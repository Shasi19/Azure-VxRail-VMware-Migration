# 01 — KVM Host Setup

> **Goal**: Install KVM hypervisor and libvirt on each physical host so it can run guest VMs.  
> Repeat these steps on **all 3 physical hosts** (192.168.10.11, .12, .13).

---

## 1. Prerequisites Check

```bash
# Verify CPU supports hardware virtualisation
grep -Ec '(vmx|svm)' /proc/cpuinfo
# Must be > 0.  vmx = Intel VT-x,  svm = AMD-V

# Confirm KVM module is loadable
lsmod | grep kvm
# Expected output: kvm_intel (or kvm_amd) and kvm

# Check OS version (Ubuntu 22.04 LTS recommended)
lsb_release -a
```

---

## 2. Install KVM and Supporting Packages

```bash
# Update system
apt update && apt upgrade -y

# Install KVM hypervisor, libvirt daemon, management tools
apt install -y \
  qemu-kvm \
  libvirt-daemon-system \
  libvirt-clients \
  bridge-utils \
  virt-manager \
  virtinst \
  cpu-checker \
  guestfs-tools \
  libguestfs-tools \
  cloud-image-utils \
  nfs-common \
  ovmf

# Verify KVM is OK
kvm-ok
# Expected: "KVM acceleration can be used"

# Start and enable libvirt
systemctl enable --now libvirtd

# Add your admin user to libvirt and kvm groups
usermod -aG libvirt,kvm $USER
newgrp libvirt
```

---

## 3. Configure Bridge Networking

VMs need to appear as real machines on the network. A **Linux bridge** (br0) connects VMs directly to the physical network.

### 3a. Identify Physical Interfaces

```bash
# List network interfaces
ip link show
# Example output: eno1, eno2 (or enp3s0, enp4s0)

# Check current IPs
ip addr
```

### 3b. Configure Bridge via Netplan (Ubuntu 22.04)

```bash
cat > /etc/netplan/01-kvm-bridge.yaml << 'EOF'
network:
  version: 2
  renderer: networkd

  ethernets:
    eno1:
      dhcp4: false
      dhcp6: false
    eno2:
      dhcp4: false
      dhcp6: false

  bonds:
    bond0:
      interfaces: [eno1, eno2]
      parameters:
        mode: active-backup
        primary: eno1
        mii-monitor-interval: 100
      dhcp4: false

  bridges:
    br0:
      interfaces: [bond0]
      addresses: [192.168.10.11/24]   # Change per host: .11, .12, .13
      gateway4: 192.168.10.1
      nameservers:
        addresses: [192.168.10.1, 8.8.8.8]
      parameters:
        stp: false
        forward-delay: 0
      dhcp4: false

    br-vm:
      addresses: [10.0.1.1/24]        # VM internal network gateway
      parameters:
        stp: false
        forward-delay: 0
      dhcp4: false
EOF

# Apply network config
netplan apply

# Verify bridges are up
brctl show
ip addr show br0
ip addr show br-vm
```

### 3c. Enable IP Forwarding (for VM routing)

```bash
cat >> /etc/sysctl.conf << 'EOF'
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 0
net.bridge.bridge-nf-call-ip6tables = 0
EOF

sysctl -p
```

---

## 4. Configure libvirt Networks

```bash
# Define the VM network that maps to br-vm
cat > /tmp/vm-network.xml << 'EOF'
<network>
  <name>vm-net</name>
  <forward mode="bridge"/>
  <bridge name="br-vm"/>
</network>
EOF

virsh net-define /tmp/vm-network.xml
virsh net-start vm-net
virsh net-autostart vm-net

# Verify
virsh net-list --all
```

---

## 5. Configure KVM Storage Pool

VMs will use QCOW2 disk images. Define a storage pool pointing at fast local NVMe.

```bash
# Create directory for VM disks
mkdir -p /data/kvm/images

# Mount NVMe disk to /data if separate
# lsblk
# mkfs.xfs /dev/nvme0n1
# echo '/dev/nvme0n1 /data xfs defaults,noatime 0 0' >> /etc/fstab
# mount -a

# Define the pool in libvirt
virsh pool-define-as default dir --target /data/kvm/images
virsh pool-build default
virsh pool-start default
virsh pool-autostart default

# Verify
virsh pool-list --all
```

---

## 6. Configure NFS Mount for NetApp Storage (Shared Storage)

```bash
# Install NFS client
apt install -y nfs-common

# Create mount point
mkdir -p /mnt/netapp

# Mount NetApp NFS volume (replace with your NetApp IP and export path)
echo "10.0.3.10:/vol/k8s_data  /mnt/netapp  nfs  rw,hard,intr,rsize=65536,wsize=65536,timeo=600,_netdev  0 0" >> /etc/fstab
mount -a

# Verify
df -h /mnt/netapp
```

---

## 7. Download Ubuntu Cloud Image (VM Template)

```bash
# Download Ubuntu 22.04 cloud image (fastest way to create VMs)
cd /data/kvm/images
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img

# Verify checksum
wget https://cloud-images.ubuntu.com/jammy/current/SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing

# Convert to qcow2 for better performance
qemu-img convert -f qcow2 -O qcow2 jammy-server-cloudimg-amd64.img ubuntu-22.04-base.qcow2
qemu-img info ubuntu-22.04-base.qcow2
```

---

## 8. Performance Tuning for KVM Hosts

```bash
# Set CPU governor to performance
apt install -y cpufrequtils
echo 'GOVERNOR="performance"' > /etc/default/cpufrequtils
systemctl restart cpufrequtils

# Disable transparent hugepages (recommended for K8s and DBs)
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag

# Make permanent
cat >> /etc/rc.local << 'EOF'
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag
exit 0
EOF
chmod +x /etc/rc.local

# Increase file descriptor limits
cat >> /etc/security/limits.conf << 'EOF'
* soft nofile 65536
* hard nofile 65536
* soft nproc 32768
* hard nproc 32768
EOF

# Tune kernel for networking
cat >> /etc/sysctl.conf << 'EOF'
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65536
net.ipv4.tcp_max_syn_backlog = 65536
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
vm.swappiness = 10
vm.overcommit_memory = 1
EOF
sysctl -p
```

---

## 9. Verify Host is Ready

```bash
# Check KVM
virsh version
# Expected: libvirt 8.x, QEMU/KVM 6.x or higher

virsh capabilities | grep -i 'type'
# Should include: <type>kvm</type>

# Check bridge
brctl show
# Should show br0 and br-vm with correct interfaces

# Check storage pool
virsh pool-list --all
# default pool should be ACTIVE

# Check NFS
mount | grep netapp
# Should show NFS mount

echo "Host ready for VM provisioning"
```

---

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| `kvm-ok` fails | BIOS VT-x disabled | Enable Intel VT-d / AMD-Vi in BIOS |
| libvirtd fails to start | AppArmor conflict | `systemctl disable apparmor` or add libvirt AppArmor profile |
| Bridge has no IP | Netplan syntax error | Check `journalctl -u systemd-networkd` |
| NFS mount fails | NetApp export ACL | Add host IP to NetApp export policy |
| VM can't reach network | Missing `ip_forward` | `sysctl net.ipv4.ip_forward=1` |

---

*Next: [02-VM-Provisioning.md](02-VM-Provisioning.md)*
