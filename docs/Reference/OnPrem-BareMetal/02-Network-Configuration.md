# 02 — Network Configuration (Bare-Metal)

> **Goal**: Configure physical network interfaces with bonding for redundancy, VLANs for traffic separation, static IPs, firewall rules, and MetalLB for Kubernetes LoadBalancer support.

---

## 1. NIC Bonding (Active-Backup Redundancy)

Each server has dual 10/25 GbE NICs. Bond them so one NIC failure doesn't cause downtime.

### 1a. Identify Physical Interfaces

```bash
# List all network interfaces
ip link show | grep -E '^[0-9]+:'
# Example: eno1, eno2 (or enp3s0, enp4s0)

# Check interface speeds
ethtool eno1 | grep Speed
ethtool eno2 | grep Speed
```

### 1b. Configure Bond with Netplan

```bash
cat > /etc/netplan/01-network.yaml << 'EOF'
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
        mode: active-backup         # or 802.3ad for LACP (requires switch config)
        primary: eno1
        mii-monitor-interval: 100
        fail-over-mac-policy: active
      dhcp4: false

  vlans:
    bond0.100:                       # VLAN 100: management
      id: 100
      link: bond0
      addresses: [10.0.1.10/24]      # Change per server
      gateway4: 10.0.1.1
      nameservers:
        addresses: [10.0.1.1, 8.8.8.8]
    bond0.200:                       # VLAN 200: storage (NetApp)
      id: 200
      link: bond0
      addresses: [10.0.3.10/24]      # Change per server
    bond0.300:                       # VLAN 300: MetalLB external
      id: 300
      link: bond0
      addresses: [10.0.2.10/24]      # Only on LB-designated servers

EOF

# Apply
netplan apply

# Verify bonding
cat /proc/net/bonding/bond0
ip addr show bond0.100
```

---

## 2. Firewall Rules (iptables)

Bare-metal servers need explicit firewall rules since there's no hypervisor-layer security.

```bash
# Flush existing rules
iptables -F INPUT
iptables -F FORWARD
iptables -F OUTPUT

# Default policy
iptables -P INPUT DROP
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT

# Allow established connections
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# SSH (restrict to management subnet only)
iptables -A INPUT -p tcp --dport 22 -s 192.168.10.0/24 -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -s 10.0.1.0/24 -j ACCEPT

# Kubernetes API server (control planes only)
iptables -A INPUT -p tcp --dport 6443 -s 10.0.1.0/24 -j ACCEPT

# etcd (control planes only)
iptables -A INPUT -p tcp --dport 2379:2380 -s 10.0.1.0/24 -j ACCEPT

# kubelet API
iptables -A INPUT -p tcp --dport 10250 -s 10.0.1.0/24 -j ACCEPT

# Pod and service CIDR (Kubernetes internal)
iptables -A INPUT -s 10.244.0.0/16 -j ACCEPT   # Pod CIDR
iptables -A INPUT -s 10.96.0.0/12 -j ACCEPT    # Service CIDR

# NodePort range
iptables -A INPUT -p tcp --dport 30000:32767 -j ACCEPT
iptables -A INPUT -p udp --dport 30000:32767 -j ACCEPT

# Database ports (infra servers only — restrict to cluster subnet)
# Uncomment on DB servers:
# iptables -A INPUT -p tcp --dport 5432 -s 10.0.1.0/24 -j ACCEPT
# iptables -A INPUT -p tcp --dport 27017 -s 10.0.1.0/24 -j ACCEPT
# iptables -A INPUT -p tcp --dport 6432 -s 10.0.1.0/24 -j ACCEPT

# ICMP (ping)
iptables -A INPUT -p icmp -j ACCEPT

# NFS (worker nodes)
iptables -A INPUT -p tcp --dport 2049 -s 10.0.1.0/24 -j ACCEPT
iptables -A INPUT -p udp --dport 2049 -s 10.0.1.0/24 -j ACCEPT

# Save rules
iptables-save > /etc/iptables/rules.v4
systemctl enable --now netfilter-persistent
```

---

## 3. Static Routes

```bash
# Add route to MetalLB pool (only on nodes that need to reach LB IPs externally)
ip route add 10.0.2.0/24 via 10.0.1.1

# Persist via Netplan
# Add to /etc/netplan/01-network.yaml under the bond0.100 section:
# routes:
#   - to: 10.0.2.0/24
#     via: 10.0.1.1
netplan apply
```

---

## 4. Install MetalLB (After Kubernetes is Up)

```bash
# Apply MetalLB manifests
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=180s

# Define IP pool — must be routable on the physical network
cat > /tmp/metallb-config.yaml << 'EOF'
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: baremetal-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.0.2.10-10.0.2.50
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: baremetal-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - baremetal-pool
  interfaces:
  - bond0.300
EOF

kubectl apply -f /tmp/metallb-config.yaml

# Verify
kubectl get ipaddresspool -n metallb-system
```

---

## 5. NFS Mount Configuration

```bash
# Mount NetApp shared storage
mkdir -p /mnt/netapp

echo "10.0.3.10:/vol/k8s_data  /mnt/netapp  nfs4  rw,hard,intr,rsize=131072,wsize=131072,timeo=600,_netdev  0 0" \
  >> /etc/fstab

mount -a
df -h /mnt/netapp
```

---

## 6. Network Verification

```bash
# Check bonding status
cat /proc/net/bonding/bond0 | grep -E '(Mode|Currently Active|MII|Speed)'

# Check VLAN interfaces
ip addr show bond0.100
ip addr show bond0.200

# Test inter-node connectivity
for IP in 10.0.1.{10..12} 10.0.1.{20..25} 10.0.1.{30..32}; do
  ping -c 1 -W 1 $IP > /dev/null && echo "$IP REACHABLE" || echo "$IP UNREACHABLE"
done

# Test NFS
showmount -e 10.0.3.10

# Test DNS
nslookup harbor.internal
nslookup google.com

echo "Network check complete"
```

---

## 7. Troubleshooting Network Issues

| Symptom | Check | Fix |
|---------|-------|-----|
| Bond shows link down | `cat /proc/net/bonding/bond0` | Check cable, switch port speed |
| VLAN not getting IP | `ip addr show bond0.100` | Check VLAN ID matches switch trunk port |
| Cannot reach other nodes | `ping 10.0.1.11` | Check switch ACL, gateway route |
| NFS mount hangs | `showmount -e 10.0.3.10` | Check NetApp export policy, firewall |
| MetalLB IP not reachable | `kubectl get svc` | Check L2Advertisement interface name |

---

*Next: [03-Kubernetes-Setup.md](03-Kubernetes-Setup.md)*
