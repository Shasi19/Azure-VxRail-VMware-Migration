# 01 — KVM Installation

> **Goal**: Install KVM hypervisor on Oracle Linux 8/9, RHEL 8/9, or Ubuntu 22.04. By the end, the server runs as a bare-metal hypervisor ready to host virtual machines.

---

## What Gets Installed

```
┌─────────────────────────────────────────────────────┐
│  qemu-kvm        — the virtualisation engine         │
│  libvirt         — API daemon that manages VMs       │
│  virt-install    — CLI to create VMs                 │
│  virt-manager    — optional desktop GUI              │
│  libguestfs-tools— inspect/modify VM disk images    │
│  bridge-utils    — manage Linux bridge networks      │
└─────────────────────────────────────────────────────┘
```

---

## 1. Hardware Verification

```bash
# Check CPU supports hardware virtualisation
# vmx = Intel VT-x   |   svm = AMD-V
grep -Ec '(vmx|svm)' /proc/cpuinfo
# Must return > 0

# Check KVM module availability
lsmod | grep kvm
# Expected: kvm_intel (Intel) or kvm_amd (AMD) + kvm base module

# Full system info
dmidecode -t processor | grep -E '(Manufacturer|Version|Core Count)'

# RAM available
free -gh

# Disk space
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
```

**BIOS/UEFI settings to verify (requires physical console or IPMI):**

| Setting | Required Value | Path (varies by vendor) |
|---------|---------------|------------------------|
| Intel VT-x / AMD-V | Enabled | Advanced > CPU Config |
| Intel VT-d / AMD-Vi | Enabled | Advanced > CPU Config (for SR-IOV, PCI passthrough) |
| Hyper-Threading | Enabled | Advanced > CPU Config |
| C-States | Disabled | Advanced > Power Management |
| Secure Boot | Disabled (or enroll MOK) | Boot > Secure Boot |

---

## 2. Installation on Oracle Linux 8/9 and RHEL 8/9

```bash
# Install KVM and virtualisation group
dnf install -y @virt

# Install additional useful tools
dnf install -y \
  virt-install \
  virt-manager \
  libguestfs-tools \
  guestfs-tools \
  virt-top \
  libvirt-devel \
  python3-libvirt \
  cloud-init \
  cloud-utils-growpart \
  qemu-img \
  bridge-utils \
  net-tools \
  bind-utils \
  nfs-utils \
  iscsi-initiator-utils \
  device-mapper-multipath \
  tuned

# Enable and start libvirt
systemctl enable --now libvirtd

# Verify KVM is functional
virt-host-validate
# Look for:  QEMU: Checking for hardware virt support  : PASS
#            QEMU: Checking for device /dev/kvm          : PASS
#            QEMU: Checking for cgroup 'cpu' controller  : PASS

# Check libvirt version
virsh version
# Expected: libvirt 8.x or higher, QEMU 6.x or higher
```

---

## 3. Installation on Ubuntu 22.04 LTS

```bash
# Install KVM and virtualisation tools
apt update && apt install -y \
  qemu-kvm \
  libvirt-daemon-system \
  libvirt-clients \
  virtinst \
  virt-manager \
  libguestfs-tools \
  guestfs-tools \
  cpu-checker \
  bridge-utils \
  cloud-image-utils \
  ovmf \
  qemu-utils \
  virt-top

# Enable libvirt
systemctl enable --now libvirtd

# Add admin user to libvirt and kvm groups
usermod -aG libvirt,kvm $USER
newgrp libvirt

# Verify KVM is ready
kvm-ok
# Expected: INFO: /dev/kvm exists
#           KVM acceleration can be used
```

---

## 4. Configure libvirt Daemon

```bash
# Edit libvirt daemon config
vi /etc/libvirt/libvirtd.conf

# Recommended settings:
# listen_tls = 0
# listen_tcp = 1
# tcp_port = "16509"
# auth_tcp = "none"            # WARNING: only for internal trusted networks
# max_clients = 20
# max_workers = 20
# log_level = 2
# log_outputs = "2:file:/var/log/libvirt/libvirtd.log"

# OR for TLS (production):
# listen_tls = 1
# tls_port = "16514"
# ca_file = "/etc/pki/libvirt/cacert.pem"
# cert_file = "/etc/pki/libvirt/servercert.pem"
# key_file = "/etc/pki/libvirt/private/serverkey.pem"

systemctl restart libvirtd

# Check libvirt socket is active
virsh list --all
# Should return empty list without error
```

---

## 5. Configure Default Storage Pool

```bash
# By default libvirt stores images in /var/lib/libvirt/images
# For production: point to a fast NVMe partition

# Create dedicated directory for VM images
mkdir -p /data/kvm/images

# If /data is a separate NVMe disk, mount it:
# mkfs.xfs /dev/nvme1n1
# echo '/dev/nvme1n1 /data xfs defaults,noatime 0 0' >> /etc/fstab
# mount -a

# Redefine default pool to use the new location
virsh pool-destroy default 2>/dev/null
virsh pool-undefine default 2>/dev/null

virsh pool-define-as default dir --target /data/kvm/images
virsh pool-build default
virsh pool-start default
virsh pool-autostart default

# Verify
virsh pool-list --all
virsh pool-info default
```

---

## 6. Configure Default Network

```bash
# Check default NAT network (libvirt creates this automatically)
virsh net-list --all
# Expected:
#  Name      State    Autostart   Persistent
#  default   active   yes         yes

# Inspect default network
virsh net-dumpxml default
# Note: 192.168.122.0/24 with NAT — good for test VMs

# For production: create a bridged network (VMs get real network IPs)
# See 03-KVM-Networking.md for full network setup

# Enable IP forwarding (needed for NAT network)
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.d/99-kvm.conf
sysctl --system
```

---

## 7. Performance Tuning for KVM Host

```bash
# Install and configure tuned for virtualisation workload
dnf install -y tuned        # RHEL/OL
# or: apt install -y tuned  # Ubuntu

# Use the virtual-host profile
tuned-adm profile virtual-host
tuned-adm active
# Confirms: Current active profile: virtual-host

# Disable transparent hugepages (better for DB VMs; can re-enable for compute VMs)
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag

# Make permanent
cat > /etc/systemd/system/disable-thp.service << 'EOF'
[Unit]
Description=Disable THP
After=sysinit.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c "echo never > /sys/kernel/mm/transparent_hugepage/enabled"
ExecStart=/bin/sh -c "echo never > /sys/kernel/mm/transparent_hugepage/defrag"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl enable --now disable-thp

# CPU governor: performance
# On RHEL/OL:
cpupower frequency-set -g performance
# On Ubuntu:
# apt install -y cpufrequtils
# cpupower frequency-set -g performance

# Kernel parameters for KVM hosts
cat > /etc/sysctl.d/99-kvm-host.conf << 'EOF'
# KVM host performance
kernel.sched_autogroup_enabled = 0
net.core.netdev_max_backlog = 65536
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 15
vm.swappiness = 10
vm.dirty_ratio = 20
vm.dirty_background_ratio = 5
fs.file-max = 2097152
fs.inotify.max_user_watches = 1048576
EOF
sysctl --system

# Disable NUMA balancing when using manual CPU pinning (see 06-KVM-Best-Practices.md)
# echo 0 > /proc/sys/kernel/numa_balancing
```

---

## 8. Set SELinux / AppArmor for KVM

### Oracle Linux / RHEL (SELinux):

```bash
# Check SELinux status
getenforce
sestatus

# SELinux should be Enforcing for production
# Ensure libvirt Booleans are correct
setsebool -P virt_use_nfs 1        # Allow VMs to use NFS storage
setsebool -P virt_use_execmem 1
setsebool -P virt_sandbox_use_all_caps 1
getsebool -a | grep virt

# Fix SELinux labels on custom image directories
semanage fcontext -a -t virt_image_t '/data/kvm/images(/.*)?'
restorecon -Rv /data/kvm/images
ls -Z /data/kvm/images/
# Should show system_u:object_r:virt_image_t:s0
```

### Ubuntu (AppArmor):

```bash
# Check AppArmor status
aa-status | grep libvirt

# If custom image path is used, add it to AppArmor profile
cat >> /etc/apparmor.d/abstractions/libvirt-qemu << 'EOF'
  /data/kvm/images/** rwk,
EOF

systemctl reload apparmor
aa-status | grep qemu
```

---

## 9. Verify Installation

```bash
# Full verification checklist
echo "=== KVM Installation Verification ==="

echo "1. Hardware virtualisation:"
grep -c '(vmx|svm)' /proc/cpuinfo && echo "PASS" || echo "FAIL"

echo "2. KVM module loaded:"
lsmod | grep -q kvm && echo "PASS" || echo "FAIL"

echo "3. libvirt running:"
systemctl is-active libvirtd && echo "PASS" || echo "FAIL"

echo "4. /dev/kvm exists:"
test -c /dev/kvm && echo "PASS" || echo "FAIL"

echo "5. Storage pool active:"
virsh pool-info default | grep -q "State:.*running" && echo "PASS" || echo "FAIL"

echo "6. Default network active:"
virsh net-info default | grep -q "Active:.*yes" && echo "PASS" || echo "FAIL"

echo "7. virt-host-validate:"
virt-host-validate 2>&1 | grep -v WARN

echo "=== Done ==="
```

---

## 10. Quick Test VM (Verify Everything Works)

```bash
# Download a minimal cloud image for testing
cd /data/kvm/images
wget https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-9-latest-x86_64-NoCloud.x86_64.qcow2 \
  -O centos9-test.qcow2

# Create a test VM
virt-install \
  --name test-vm \
  --vcpus 2 \
  --memory 2048 \
  --disk /data/kvm/images/centos9-test.qcow2,format=qcow2 \
  --os-variant centos-stream9 \
  --network network=default \
  --graphics none \
  --console pty,target_type=serial \
  --import \
  --noautoconsole

# Check it started
virsh list --all
virsh dominfo test-vm

# Get IP address (may take 30-60s for DHCP)
virsh domifaddr test-vm

# Destroy test VM
virsh destroy test-vm
virsh undefine test-vm --remove-all-storage
echo "KVM installation complete and verified"
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `kvm-ok` reports "KVM NOT available" | VT-x/AMD-V disabled in BIOS | Enable in BIOS; reboot |
| `libvirtd` fails to start | AppArmor/SELinux blocking | Check `journalctl -u libvirtd -n 50` |
| Permission denied on `/dev/kvm` | User not in kvm group | `usermod -aG kvm $USER; newgrp kvm` |
| VM stuck at "char device redirected" | Console not attached | Add `--console pty,target_type=serial` to virt-install |
| Pool not found | Pool not started | `virsh pool-start default; virsh pool-autostart default` |
| Network `default` not found | libvirt network not started | `virsh net-start default; virsh net-autostart default` |
| `virt-host-validate` WARN: cgroup | cgroup v2 not mounted | `systemctl restart libvirtd` or check cgroupv2 in kernel |
| SELinux AVC denial | Wrong fcontext on image dir | `restorecon -Rv /data/kvm/images` |

---

*Next: [02-OLVM-Installation.md](02-OLVM-Installation.md)*
