# 01 — Server Preparation (Bare-Metal)

> **Goal**: Install and configure Ubuntu 22.04 LTS on every physical server, apply firmware updates, kernel tuning, and make each server production-ready before Kubernetes installation.  
> Repeat on **all servers**: 3 control planes + 6 workers + 3 DB servers.

---

## 1. OS Installation

### 1a. Boot from Ubuntu 22.04 Server ISO

```
1. Download Ubuntu Server 22.04 LTS from ubuntu.com
2. Write to USB: dd if=ubuntu-22.04-live-server-amd64.iso of=/dev/sdX bs=4M status=progress
3. Boot each server from USB
4. During installation:
   - Language: English
   - Keyboard: English (US)
   - Network: Skip (configure after install)
   - Storage: Use entire disk, LVM off (bare-metal performance)
   - Partition:
       /boot/efi    512 MB   FAT32
       /boot        2 GB     ext4
       /            200 GB   xfs
       /var         100 GB   xfs   (for container images)
       /data        ALL      xfs   (for databases, MinIO)
   - Username: admin
   - Password: (set strong password)
   - OpenSSH: Install yes, import SSH keys from GitHub if available
5. Reboot
```

### 1b. Post-Install Configuration

```bash
# Run immediately after first login
sudo -i

# Set hostname (change per server)
hostnamectl set-hostname server-cp-01

# Update all packages
apt update && apt upgrade -y && apt autoremove -y

# Install essential tools
apt install -y \
  curl wget vim htop iotop dstat \
  net-tools nfs-common open-iscsi \
  socat conntrack ipset \
  chrony ntp \
  jq unzip tar gzip \
  iptables iptables-persistent \
  sysstat lvm2 smartmontools \
  build-essential git \
  gpg apt-transport-https ca-certificates

# Reboot to apply kernel updates
reboot
```

---

## 2. Firmware and BIOS Tuning

```bash
# Check CPU features
grep -m1 -E '(vmx|svm|sse4|avx|aes)' /proc/cpuinfo | tr ' ' '\n' | sort | uniq

# Check BIOS settings via dmidecode
dmidecode -t bios | grep -E '(Version|Date|Vendor)'

# Install firmware update tool (Dell servers)
# apt install -y fwupd
# fwupdmgr get-updates
# fwupdmgr update

# Check storage device health
for DISK in $(lsblk -d -o NAME | tail -n +2); do
  echo "=== $DISK ==="
  smartctl -H /dev/$DISK 2>/dev/null || echo "No SMART data"
done
```

**BIOS settings to verify manually:**
- Hyperthreading: Enabled
- Turbo Boost: Enabled
- C-States: Disabled (for consistent low-latency)
- NUMA: Enabled
- SR-IOV: Enabled (for network performance)
- Secure Boot: Disabled (or configure with MOK for custom kernels)
- PXE Boot: Disabled on production servers

---

## 3. Kernel Tuning for Kubernetes

```bash
# Load required kernel modules
modprobe br_netfilter
modprobe overlay
modprobe nf_conntrack
modprobe ip_vs
modprobe ip_vs_rr
modprobe ip_vs_wrr
modprobe ip_vs_sh

# Make modules persist across reboots
cat > /etc/modules-load.d/k8s.conf << 'EOF'
br_netfilter
overlay
nf_conntrack
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
EOF

# Kubernetes-required sysctl settings
cat > /etc/sysctl.d/99-k8s.conf << 'EOF'
# Networking
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1

# Connection tracking
net.netfilter.nf_conntrack_max = 1000000
net.netfilter.nf_conntrack_tcp_timeout_established = 86400

# Socket buffers (for high-throughput services)
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.netdev_max_backlog = 65536
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535

# File descriptors
fs.file-max = 2097152
fs.inotify.max_user_watches = 1048576
fs.inotify.max_user_instances = 8192

# Memory
vm.swappiness = 0
vm.overcommit_memory = 1
vm.panic_on_oom = 0
vm.max_map_count = 262144

# Huge pages (beneficial for PostgreSQL)
vm.nr_hugepages = 512
EOF

sysctl --system
```

---

## 4. Disable Swap

```bash
# Disable swap now
swapoff -a

# Comment out swap entries in fstab
sed -i '/ swap / s/^\(.*\)$/#\1/' /etc/fstab

# Verify
free -h
# Swap line should show 0B
```

---

## 5. Disable Transparent Hugepages

```bash
# Disable THP (improves PostgreSQL and MongoDB performance)
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag

# Make permanent via systemd
cat > /etc/systemd/system/disable-thp.service << 'EOF'
[Unit]
Description=Disable Transparent Hugepages
After=sysinit.target local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c "echo never > /sys/kernel/mm/transparent_hugepage/enabled"
ExecStart=/bin/sh -c "echo never > /sys/kernel/mm/transparent_hugepage/defrag"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl enable --now disable-thp
```

---

## 6. CPU Performance Governor

```bash
# Install cpufrequtils
apt install -y cpufrequtils linux-tools-generic

# Set performance governor
cpupower frequency-set -g performance

# Make permanent
cat > /etc/systemd/system/cpu-performance.service << 'EOF'
[Unit]
Description=CPU Performance Governor

[Service]
Type=oneshot
ExecStart=/usr/bin/cpupower frequency-set -g performance
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl enable --now cpu-performance

# Verify
cpupower frequency-info | grep governor
```

---

## 7. Configure /etc/hosts on All Servers

```bash
cat >> /etc/hosts << 'EOF'
# Kubernetes Cluster Nodes
10.0.1.10   server-cp-01 server-cp-01.internal
10.0.1.11   server-cp-02 server-cp-02.internal
10.0.1.12   server-cp-03 server-cp-03.internal
10.0.1.20   server-wk-01 server-wk-01.internal
10.0.1.21   server-wk-02 server-wk-02.internal
10.0.1.22   server-wk-03 server-wk-03.internal
10.0.1.23   server-wk-04 server-wk-04.internal
10.0.1.24   server-wk-05 server-wk-05.internal
10.0.1.25   server-wk-06 server-wk-06.internal
10.0.1.30   server-db-01 server-db-01.internal
10.0.1.31   server-db-02 server-db-02.internal
10.0.1.32   server-db-03 server-db-03.internal

# Platform Services
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

## 8. Time Synchronisation (Critical for K8s + Databases)

```bash
apt install -y chrony

cat > /etc/chrony/chrony.conf << 'EOF'
server 10.0.1.1 iburst prefer    # Internal NTP server
server pool.ntp.org iburst
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
allow 10.0.0.0/8
EOF

systemctl enable --now chrony
chronyc tracking
chronyc sources -v
# Look for * (synced) next to source
```

---

## 9. SSH Hardening

```bash
cat > /etc/ssh/sshd_config.d/security.conf << 'EOF'
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
X11Forwarding no
AllowTcpForwarding no
EOF

systemctl restart sshd
```

---

## 10. Install containerd (Container Runtime)

```bash
# Install containerd
apt install -y containerd

# Configure containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# Enable systemd cgroup driver (required for Kubernetes)
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# If using Harbor (configure after Harbor install):
# vim /etc/containerd/config.toml
# Under [plugins."io.containerd.grpc.v1.cri".registry.mirrors]:
# [plugins."io.containerd.grpc.v1.cri".registry.mirrors."harbor.internal"]
#   endpoint = ["https://harbor.internal"]

systemctl enable --now containerd
systemctl status containerd --no-pager
```

---

## 11. Verify Server is Ready

```bash
cat > /usr/local/bin/precheck.sh << 'SCRIPT'
#!/bin/bash
echo "=== Preflight Check: $(hostname) ==="
echo ""

# CPU virtualisation (informational only for bare-metal)
CORES=$(nproc)
echo "CPU cores: $CORES"

# RAM
RAM=$(free -g | awk '/Mem/{print $2}')
echo "RAM: ${RAM}GB"

# Swap disabled
SWAP=$(free | awk '/Swap/{print $2}')
[[ $SWAP -eq 0 ]] && echo "Swap: DISABLED (OK)" || echo "Swap: ENABLED (FAIL)"

# Kernel modules
for MOD in br_netfilter overlay ip_vs; do
  lsmod | grep -q $MOD && echo "Module $MOD: LOADED" || echo "Module $MOD: MISSING (FAIL)"
done

# containerd
systemctl is-active containerd --quiet && echo "containerd: RUNNING" || echo "containerd: NOT RUNNING (FAIL)"

# Time sync
chronyc tracking | grep -q "Leap status     : Normal" && echo "NTP: SYNCED" || echo "NTP: NOT SYNCED (FAIL)"

# NFS
mount | grep -q nfs && echo "NFS: MOUNTED" || echo "NFS: NOT MOUNTED (check fstab)"

echo ""
echo "=== Precheck complete ==="
SCRIPT

chmod +x /usr/local/bin/precheck.sh
precheck.sh
```

---

*Next: [02-Network-Configuration.md](02-Network-Configuration.md)*
