# 03 — Network Configuration (KVM)

> **Goal**: Configure VM-level networking — static IPs, firewall rules, MetalLB IP pool, and DNS.  
> Run inside **guest VMs** unless stated otherwise.

---

## 1. Static IP Configuration Inside VMs

Cloud-init set the IP at first boot. Verify and make it permanent:

```bash
# Verify current IP
ip addr show enp1s0

# Edit netplan config (already set by cloud-init, verify it looks right)
cat /etc/netplan/50-cloud-init.yaml

# If you need to change IP manually:
cat > /etc/netplan/50-cloud-init.yaml << 'EOF'
network:
  version: 2
  ethernets:
    enp1s0:
      addresses: [10.0.1.10/24]    # Change per VM
      gateway4: 10.0.1.1
      nameservers:
        addresses: [192.168.10.1, 8.8.8.8]
      dhcp4: false
EOF

netplan apply
```

---

## 2. Firewall Rules (UFW on Guest VMs)

```bash
# Disable UFW inside VMs — Calico/NetworkPolicy handles pod-level filtering
ufw disable
systemctl disable ufw

# On infra DB VMs, use iptables to restrict DB ports
# Only allow connections from the K8s worker subnet
iptables -A INPUT -p tcp --dport 5432 -s 10.0.1.0/24 -j ACCEPT  # PostgreSQL
iptables -A INPUT -p tcp --dport 5432 -j DROP
iptables -A INPUT -p tcp --dport 27017 -s 10.0.1.0/24 -j ACCEPT  # MongoDB
iptables -A INPUT -p tcp --dport 27017 -j DROP
iptables -A INPUT -p tcp --dport 6379 -s 10.0.1.0/24 -j ACCEPT   # Redis
iptables -A INPUT -p tcp --dport 6379 -j DROP

# Save rules
iptables-save > /etc/iptables/rules.v4
```

---

## 3. Kernel Modules for Kubernetes

Must be loaded on every K8s node VM before kubeadm runs:

```bash
# Load modules now
modprobe br_netfilter
modprobe overlay
modprobe nf_conntrack

# Make persistent
cat > /etc/modules-load.d/k8s.conf << 'EOF'
br_netfilter
overlay
nf_conntrack
EOF

# Set required sysctl params
cat > /etc/sysctl.d/k8s.conf << 'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system
```

---

## 4. Install and Configure containerd (Container Runtime)

```bash
# Install containerd
apt install -y containerd

# Generate default config
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# Enable SystemdCgroup (required for K8s)
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# If using Harbor private registry (after Harbor is set up):
# Add registry mirror under [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
# in /etc/containerd/config.toml:
# [plugins."io.containerd.grpc.v1.cri".registry.mirrors."harbor.internal:443"]
#   endpoint = ["https://harbor.internal"]

systemctl restart containerd
systemctl enable containerd

# Verify
systemctl status containerd --no-pager
```

---

## 5. Disable Swap on All K8s VMs

```bash
# Disable swap immediately
swapoff -a

# Disable in fstab (comment out swap entry)
sed -i '/ swap / s/^\(.*\)$/#\1/' /etc/fstab

# Verify no swap
free -h
# Swap row should show 0
```

---

## 6. Configure MetalLB IP Pool (applied after K8s install)

MetalLB replaces Azure Load Balancer. It assigns real IP addresses from a pool to LoadBalancer services.

```bash
# After kubectl is configured, apply MetalLB:
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

# Wait for MetalLB to be ready
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=120s

# Define the IP pool (IPs routable on your br-vm network)
cat > /tmp/metallb-pool.yaml << 'EOF'
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: onprem-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.0.2.10-10.0.2.50
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: onprem-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - onprem-pool
EOF

kubectl apply -f /tmp/metallb-pool.yaml
```

---

## 7. Internal DNS (CoreDNS + /etc/hosts)

Kubernetes comes with CoreDNS. For external service names (Harbor, GitLab, etc.), use a local DNS entry or HAProxy:

```bash
# On each VM, add service hostnames to /etc/hosts
cat >> /etc/hosts << 'EOF'
# Platform Services (LoadBalancer IPs from MetalLB pool)
10.0.2.10   harbor.internal
10.0.2.11   argocd.internal
10.0.2.12   gitlab.internal
10.0.2.13   grafana.internal
10.0.2.14   kibana.internal
10.0.2.15   vault.internal
10.0.2.16   minio.internal
EOF
```

---

## 8. NTP Time Synchronisation

All VMs must be time-synced. Skewed clocks break etcd, TLS certs, and logs.

```bash
# Install chrony
apt install -y chrony

# Configure NTP server (use your internal NTP or public pool)
cat > /etc/chrony/chrony.conf << 'EOF'
server 192.168.10.1 iburst prefer
server pool.ntp.org iburst
makestep 1.0 3
rtcsync
EOF

systemctl enable --now chrony

# Verify synchronisation
chronyc tracking
chronyc sources -v
# Reference ID should not be LOCAL (unsynced)
```

---

## 9. Verify VM Network Readiness

```bash
# From any VM, ping all other VMs
for IP in 10.0.1.{10..12} 10.0.1.{20..25} 10.0.1.{30..32}; do
  ping -c 1 -W 1 $IP > /dev/null && echo "$IP OK" || echo "$IP FAILED"
done

# Check internet access (for pulling images)
curl -s https://registry.k8s.io > /dev/null && echo "Internet OK" || echo "Internet FAILED"

# Check NFS mount
mount | grep netapp || echo "NFS not mounted — check /etc/fstab"

# Check containerd
ctr version
```

---

*Next: [04-Kubernetes-Setup.md](04-Kubernetes-Setup.md)*
