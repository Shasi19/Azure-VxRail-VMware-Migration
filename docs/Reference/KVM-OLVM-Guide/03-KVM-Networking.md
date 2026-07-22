# 03 — KVM Networking

> Covers all KVM networking modes: Linux bridge, VLAN-aware bridges, NIC bonding, macvtap, Open vSwitch, SR-IOV, and firewall configuration.

---

## Networking Concepts

```
GUEST VM
  │
  │ virtio-net (virtual NIC inside VM)
  │
  ▼
TAP Device (tap0, tap1...)   ← kernel virtual interface; one per VM NIC
  │
  ├── Linux Bridge (br0)     ← acts like a software L2 switch
  │     │
  │     └── Physical NIC (bond0, eno1...)  ← connects to real network
  │
  OR
  │
  ├── macvtap                ← bypasses bridge; VM directly on NIC
  │
  OR
  │
  └── OVS Bridge             ← Open vSwitch; advanced SDN features
```

| Mode | Use Case | Performance | Features |
|------|----------|-------------|----------|
| **Linux Bridge** | General production | Good | VLAN, firewalling, simple |
| **macvtap** | Single VM, max throughput | Excellent | No filtering, no host-to-VM comms |
| **Open vSwitch** | SDN, complex VLAN | Good | VXLAN, flow control, OpenFlow |
| **SR-IOV** | Low-latency, HPC | Best (near-native) | Dedicated NIC partition per VM |
| **Isolated (no NIC)** | Security testing | N/A | VM has no external connectivity |

---

## 1. Linux Bridge (Standard Production Setup)

### 1a. Create a Bridge Manually (ip commands)

```bash
# Create bridge
ip link add name br0 type bridge

# Add physical NIC to bridge
ip link set eno1 master br0

# Move the IP from eno1 to bridge
ip addr del 10.0.1.11/24 dev eno1
ip addr add 10.0.1.11/24 dev br0
ip link set br0 up
ip link set eno1 up

# Add default route
ip route add default via 10.0.1.1 dev br0

# Verify
ip link show type bridge
bridge link show
```

### 1b. Permanent Bridge via Netplan (Ubuntu)

```yaml
# /etc/netplan/01-kvm-bridge.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eno1:
      dhcp4: false
  bridges:
    br0:
      interfaces: [eno1]
      addresses: [10.0.1.11/24]
      gateway4: 10.0.1.1
      nameservers:
        addresses: [10.0.1.1, 8.8.8.8]
      parameters:
        stp: false
        forward-delay: 0
      dhcp4: false
```

```bash
netplan apply
ip addr show br0
```

### 1c. Permanent Bridge via nmcli (RHEL / Oracle Linux)

```bash
# Create bridge
nmcli connection add type bridge con-name br0 ifname br0

# Set static IP on bridge
nmcli connection modify br0 \
  ipv4.addresses 10.0.1.11/24 \
  ipv4.gateway 10.0.1.1 \
  ipv4.dns 10.0.1.1 \
  ipv4.method manual

# Disable STP (speeds up port coming up)
nmcli connection modify br0 bridge.stp no
nmcli connection modify br0 bridge.forward-delay 0

# Add physical NIC as a bridge slave
nmcli connection add type bridge-slave \
  con-name br0-slave ifname eno1 master br0

# Activate
nmcli connection up br0
nmcli connection up br0-slave

# Verify
nmcli device status
bridge link
```

### 1d. Define the Bridge Network in libvirt

```xml
<!-- /tmp/bridge-network.xml -->
<network>
  <name>br0-net</name>
  <forward mode="bridge"/>
  <bridge name="br0"/>
</network>
```

```bash
virsh net-define /tmp/bridge-network.xml
virsh net-start br0-net
virsh net-autostart br0-net
virsh net-list --all
```

---

## 2. NIC Bonding

Bonds two physical NICs together for redundancy or throughput.

### Bond Modes

| Mode | Name | Description | Switch Requirement |
|------|------|-------------|-------------------|
| 0 | balance-rr | Round-robin across NICs | None |
| 1 | active-backup | One NIC active, failover on failure | None |
| 2 | balance-xor | XOR hash for load balance | None |
| 4 | 802.3ad (LACP) | Both NICs active via LACP | Switch LACP config |
| 5 | balance-tlb | Adaptive TX load balance | None |
| 6 | balance-alb | Adaptive TX+RX load balance | None |

### Configure Bonding via Netplan

```yaml
# /etc/netplan/01-bond.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eno1:
      dhcp4: false
    eno2:
      dhcp4: false
  bonds:
    bond0:
      interfaces: [eno1, eno2]
      parameters:
        mode: 802.3ad          # LACP (requires switch config)
        # mode: active-backup  # Use this if switch doesn't support LACP
        lacp-rate: fast
        mii-monitor-interval: 100
        transmit-hash-policy: layer3+4
      dhcp4: false
  bridges:
    br0:
      interfaces: [bond0]
      addresses: [10.0.1.11/24]
      gateway4: 10.0.1.1
      parameters:
        stp: false
        forward-delay: 0
      dhcp4: false
```

```bash
netplan apply

# Verify bond status
cat /proc/net/bonding/bond0
# Check: Bonding Mode, Active Slave, Speed of each slave

# Live check
watch -n1 'cat /proc/net/bonding/bond0 | grep -E "(Bonding|MII|Link|Speed|Slave)"'
```

### Bond via nmcli (RHEL/OL)

```bash
# Create bond
nmcli connection add type bond con-name bond0 ifname bond0 \
  bond.options "mode=active-backup,miimon=100"

# Add slaves
nmcli connection add type ethernet con-name bond0-slave1 ifname eno1 master bond0
nmcli connection add type ethernet con-name bond0-slave2 ifname eno2 master bond0

# Add bridge on top
nmcli connection add type bridge con-name br0 ifname br0
nmcli connection modify br0 ipv4.addresses 10.0.1.11/24 \
  ipv4.gateway 10.0.1.1 ipv4.method manual bridge.stp no
nmcli connection add type bridge-slave con-name br0-bond ifname bond0 master br0

nmcli connection up bond0
nmcli connection up br0
```

---

## 3. VLAN-Aware Bridges

One physical NIC carries multiple VLANs. Each VM connects to a specific VLAN.

```bash
# Enable VLAN filtering on bridge
ip link set br0 type bridge vlan_filtering 1

# Assign VLAN 100 to the uplink port (eno1/bond0)
bridge vlan add dev bond0 vid 100 trunk   # trunk = allows tagged frames

# Assign VLAN to a specific VM tap interface (e.g., tap0 belongs to VLAN 100)
bridge vlan add dev tap0 vid 100 pvid untagged

# Check VLAN assignments
bridge vlan show

# The VM connected to tap0 will be on VLAN 100 without knowing it (untagged inside VM)
```

### Netplan VLAN config for host management:

```yaml
vlans:
  bond0.100:
    id: 100
    link: bond0
    addresses: [10.0.1.11/24]
    gateway4: 10.0.1.1
  bond0.200:
    id: 200
    link: bond0
    addresses: [10.0.3.11/24]   # Storage VLAN
```

### libvirt network with VLAN tag:

```xml
<!-- VM's network interface will be tagged on VLAN 100 -->
<interface type='bridge'>
  <source bridge='br0'/>
  <vlan>
    <tag id='100'/>
  </vlan>
  <model type='virtio'/>
</interface>
```

---

## 4. macvtap (Direct NIC Connection)

macvtap bypasses the bridge — the VM gets a sub-interface directly on the physical NIC. High performance, but the host cannot communicate with VMs on macvtap (limitation).

```bash
# Create a macvtap manually
ip link add link eno1 name macvtap0 type macvtap mode bridge
ip link set macvtap0 up
```

### In libvirt VM XML:

```xml
<interface type='direct'>
  <source dev='eno1' mode='bridge'/>
  <model type='virtio'/>
</interface>
```

```bash
# Define VM using macvtap
virt-install \
  --name my-vm \
  --network type=direct,source=eno1,source.mode=bridge,model=virtio \
  ...
```

---

## 5. Open vSwitch (OVS) with KVM

OVS enables advanced SDN features like VXLAN tunnels, OpenFlow, and precise flow control.

```bash
# Install OVS
dnf install -y openvswitch    # RHEL/OL
# apt install -y openvswitch-switch  # Ubuntu

systemctl enable --now openvswitch

# Create OVS bridge
ovs-vsctl add-br ovsbr0

# Add physical NIC to OVS bridge
ovs-vsctl add-port ovsbr0 bond0

# Add internal port with IP for host management
ovs-vsctl add-port ovsbr0 ovsbr0-mgmt -- set Interface ovsbr0-mgmt type=internal
ip addr add 10.0.1.11/24 dev ovsbr0-mgmt
ip link set ovsbr0-mgmt up

# Add VLAN on OVS
ovs-vsctl add-port ovsbr0 vlan100 tag=100 -- set Interface vlan100 type=internal
ip addr add 10.0.100.1/24 dev vlan100
ip link set vlan100 up

# Show OVS configuration
ovs-vsctl show

# Create VXLAN tunnel between two KVM hosts
ovs-vsctl add-port ovsbr0 vxlan0 \
  -- set interface vxlan0 type=vxlan \
     options:remote_ip=10.0.1.12 \
     options:key=1000

# libvirt with OVS bridge
# In VM XML: <interface type='bridge'><source bridge='ovsbr0'/>...
```

---

## 6. SR-IOV (Hardware NIC Virtualisation)

SR-IOV splits a single physical NIC into multiple **Virtual Functions (VFs)**. Each VF is assigned directly to a VM — near-native hardware performance.

```bash
# Check if NIC supports SR-IOV
lspci | grep -i ethernet
lspci -v -s 0000:01:00.0 | grep -i "SR-IOV"

# Check current VF count
cat /sys/class/net/eno1/device/sriov_numvfs

# Enable VFs (Intel X710 example — creates 4 VFs)
echo 4 > /sys/class/net/eno1/device/sriov_numvfs

# Verify VFs created
ip link show eno1
# Should show: vf 0 ... vf 1 ... vf 2 ... vf 3 ...

# Make permanent
cat > /etc/udev/rules.d/99-sriov.rules << 'EOF'
SUBSYSTEM=="net", ACTION=="add", ATTR{phys_port_name}!="*vf*",\
  KERNELS=="0000:01:00.0", ATTR{device/sriov_numvfs}="4"
EOF

# Get VF PCI addresses
lspci | grep "Virtual Function"
# e.g.: 0000:01:10.0 Ethernet: Intel VF

# Attach VF directly to VM (PCI passthrough)
virsh nodedev-list | grep pci
virsh nodedev-dumpxml pci_0000_01_10_0

# Add to VM XML:
# <hostdev mode='subsystem' type='pci' managed='yes'>
#   <source>
#     <address domain='0x0000' bus='0x01' slot='0x10' function='0x0'/>
#   </source>
# </hostdev>
```

---

## 7. VM Network XML Reference

### Bridged (most common)

```xml
<interface type='bridge'>
  <source bridge='br0'/>
  <model type='virtio'/>
  <driver name='vhost'/>      <!-- vhost offloads to kernel for better performance -->
</interface>
```

### Private isolated network (VMs can talk to each other, not outside)

```xml
<!-- Define isolated network -->
<!-- /tmp/isolated-net.xml -->
<network>
  <name>isolated</name>
  <bridge name='virbr-iso' stp='on' delay='0'/>
</network>
```

```bash
virsh net-define /tmp/isolated-net.xml
virsh net-start isolated
virsh net-autostart isolated
```

### NAT network (VMs can reach internet via host NAT)

```xml
<network>
  <name>nat-net</name>
  <forward mode='nat'/>
  <bridge name='virbr1' stp='on' delay='0'/>
  <ip address='192.168.200.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.200.10' end='192.168.200.100'/>
      <!-- Static DHCP binding by MAC -->
      <host mac='52:54:00:11:22:33' name='my-vm' ip='192.168.200.20'/>
    </dhcp>
  </ip>
</network>
```

---

## 8. Firewall Rules for KVM Host

```bash
# Using nftables (modern firewall on RHEL9 / OL9 / Ubuntu 22+)
cat > /etc/nftables.conf << 'EOF'
#!/usr/sbin/nft -f
flush ruleset

table inet filter {
  chain input {
    type filter hook input priority 0; policy drop;

    # Allow loopback
    iif lo accept

    # Allow established/related
    ct state established,related accept

    # SSH from management subnet only
    ip saddr 10.0.1.0/24 tcp dport 22 accept

    # libvirt API (for remote virsh -c qemu+tcp://)
    ip saddr 10.0.1.0/24 tcp dport 16509 accept

    # libvirt TLS remote
    ip saddr 10.0.1.0/24 tcp dport 16514 accept

    # OLVM VDSM agent
    ip saddr 10.0.1.10/32 tcp dport 54321 accept

    # VNC console (OLVM opens these)
    ip saddr 10.0.1.10/32 tcp dport 5900-6923 accept

    # VM live migration
    ip saddr 10.0.1.0/24 tcp dport 49152-49216 accept

    # NFS client (to storage server)
    ip daddr 10.0.3.0/24 accept

    # ICMP
    ip protocol icmp accept

    # Drop everything else
    log prefix "DROPPED: " drop
  }

  chain forward {
    type filter hook forward priority 0;
    # Allow forwarding for VMs (bridge traffic)
    accept
  }

  chain output {
    type filter hook output priority 0; policy accept;
  }
}
EOF

systemctl enable --now nftables
nft list ruleset
```

---

## 9. DNS for VMs (libvirt dnsmasq)

```bash
# libvirt's default network uses dnsmasq for VM DNS/DHCP
# Config lives at: /var/lib/libvirt/dnsmasq/default.conf

# Check VMs registered in DNS
virsh net-dhcp-leases default
# Shows MAC, IP, hostname of all DHCP-leased VMs

# Force a static DHCP binding
virsh net-update default add ip-dhcp-host \
  '<host mac="52:54:00:ab:cd:ef" name="k8s-cp-01" ip="10.0.1.10"/>' \
  --live --config

# Verify
virsh net-dumpxml default | grep host
```

---

## 10. Troubleshooting Network Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| VM has no IP address | DHCP not reaching VM | Check `virsh net-dhcp-leases default`; verify libvirt network is active |
| Cannot ping VM from host | Bridge firewall rules | Check `nft list ruleset`; ensure bridge forward chain accepts |
| Bridge network missing after reboot | Network not persistent | `virsh net-autostart default`; check Netplan/nmcli connection is active |
| VMs can't reach internet | IP forwarding off | `echo 1 > /proc/sys/net/ipv4/ip_forward`; persist in sysctl.d |
| `brctl` command not found | bridge-utils not installed | `apt install bridge-utils` or `dnf install bridge-utils` |
| LACP bond not working | Switch not configured | Enable LACP/802.3ad on switch port; or change mode to active-backup |
| VLAN traffic not passing | VLAN filtering not set | `bridge vlan show`; verify pvid on tap interfaces |
| SR-IOV VFs not persistent | udev rule missing | Add udev rule for device (see section 6) |
| VM sees wrong VLAN | Wrong tag in VM XML | Check `virsh dumpxml <vm>` network interface vlan tag |
| OVS bridge down after reboot | OVS not autostarted | `systemctl enable openvswitch` |
| macvtap: host can't reach VM | macvtap limitation | Use bridge mode instead for host-to-VM comms |
| libvirt fails to add TAP to bridge | AppArmor blocking | Add bridge to AppArmor libvirt-qemu profile |
| Migration fails — network not found | Network not on destination host | Define same network on destination host before migrating |
| `iptables` blocking bridge traffic | bridge-nf-call-iptables | Set `net.bridge.bridge-nf-call-iptables=0` or add iptables ACCEPT rules |

---

*Next: [04-KVM-Storage.md](04-KVM-Storage.md)*
