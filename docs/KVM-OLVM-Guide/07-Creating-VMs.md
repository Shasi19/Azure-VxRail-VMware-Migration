# 07 — Creating Virtual Machines

> Covers all VM creation methods: virt-install (CLI), virt-manager (GUI), cloud-init (automation), OLVM web UI, and VM templates.

---

## Methods Overview

| Method | Best For | Automation | GUI |
|--------|----------|------------|-----|
| `virt-install` CLI | Scripting, automation | Yes | No |
| `virt-manager` | Interactive single VMs | No | Yes |
| Cloud-init | Automated fleet provisioning | Yes | No |
| OLVM Web UI | Enterprise managed VMs | Partial (API) | Yes |
| `virsh define` XML | Fine-grained XML control | Yes | No |
| Clone from template | Fast stamping | Yes | Via virsh |

---

## 1. virt-install — CLI VM Creation

### 1a. Basic VM from ISO

```bash
# Download OS ISO to ISO directory
mkdir -p /data/kvm/iso
wget https://releases.ubuntu.com/22.04/ubuntu-22.04.4-live-server-amd64.iso \
  -O /data/kvm/iso/ubuntu-22.04.iso

# Create VM from ISO (interactive installer)
virt-install \
  --name ubuntu-test \
  --vcpus 4 \
  --memory 8192 \
  --disk size=50,path=/data/kvm/images/ubuntu-test.qcow2,format=qcow2,bus=virtio \
  --cdrom /data/kvm/iso/ubuntu-22.04.iso \
  --os-variant ubuntu22.04 \
  --network bridge=br0,model=virtio \
  --graphics vnc,listen=0.0.0.0,port=5900 \
  --video virtio \
  --boot cdrom,hd

# Connect to VNC console: vnc://kvm-host-01:5900
# Complete Ubuntu installation interactively
```

### 1b. Production VM — Full Options

```bash
virt-install \
  --name k8s-cp-01 \
  --vcpus 8,maxvcpus=16 \
  --memory 16384,maxmemory=32768 \
  --cpu host-model \
  --disk /data/kvm/images/k8s-cp-01.qcow2,size=100,format=qcow2,bus=virtio,cache=none,io=threads \
  --network bridge=br0,model=virtio,driver.name=vhost \
  --os-variant ubuntu22.04 \
  --graphics none \
  --console pty,target_type=serial \
  --serial pty \
  --noautoconsole \
  --autostart \
  --import \
  --boot hd

# Explanation of flags:
# --vcpus 8,maxvcpus=16   : start with 8 vCPUs, can hotplug up to 16
# --memory 16384,maxmemory=32768 : 16GB start, 32GB max (balloon)
# --cpu host-model        : expose host CPU model (allows migration to similar hosts)
# --disk ... cache=none,io=threads : good for QCOW2 workloads
# --network ... driver.name=vhost  : use vhost-net for better network performance
# --graphics none         : headless VM (serial console only)
# --autostart             : start VM when host boots
# --import                : use existing disk (no installation)
```

### 1c. VM with Multiple Disks and Networks

```bash
virt-install \
  --name infra-db-01 \
  --vcpus 16 \
  --memory 65536 \
  --cpu host-passthrough \
  --disk /dev/kvm-vg/db-os,format=raw,bus=virtio,cache=none,io=native \
  --disk /dev/kvm-vg/db-data,format=raw,bus=virtio,cache=none,io=native \
  --network bridge=br0,model=virtio \
  --network bridge=br-storage,model=virtio \
  --os-variant centos-stream9 \
  --graphics none \
  --noautoconsole \
  --import \
  --autostart
# Two disks: OS disk on LVM + data disk on LVM
# Two networks: management + storage
```

### 1d. Common OS Variants

```bash
# List all supported OS variants
virt-install --os-variant list | grep -E '(ubuntu|centos|rhel|oracle|debian)'

# Common ones:
# ubuntu22.04       — Ubuntu 22.04 LTS
# centos-stream9    — CentOS Stream 9
# rhel9.0           — Red Hat Enterprise Linux 9
# ol9.0             — Oracle Linux 9
# debian11          — Debian 11
# fedora38          — Fedora 38
```

---

## 2. Cloud-Init (Automated OS Configuration)

Cloud-init eliminates manual OS installation. Start from a pre-installed cloud image and inject configuration.

### 2a. Download Cloud Images

```bash
# Ubuntu 22.04 cloud image
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img \
  -O /data/kvm/images/ubuntu-22.04-cloud.img

# Oracle Linux 9 cloud image
wget https://yum.oracle.com/templates/OracleLinux/OL9/u4/x86_64/OL9U4_x86_64-kvm-b234.qcow \
  -O /data/kvm/images/oracle-linux-9-cloud.qcow2

# CentOS Stream 9
wget https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-9-latest-x86_64-NoCloud.x86_64.qcow2 \
  -O /data/kvm/images/centos-stream9-cloud.qcow2

# Convert to QCOW2 if needed
qemu-img convert -f qcow2 -O qcow2 ubuntu-22.04-cloud.img ubuntu-22.04-base.qcow2
```

### 2b. Create Cloud-Init Config Files

```bash
VM_NAME="k8s-wk-01"
VM_IP="10.0.1.20"

# user-data: cloud-init instance configuration
cat > /tmp/${VM_NAME}-userdata.yaml << EOF
#cloud-config
hostname: ${VM_NAME}
fqdn: ${VM_NAME}.internal

users:
  - name: admin
    groups: [sudo, wheel]
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    lock_passwd: false
    passwd: \$6\$salt\$hashedpassword   # generate: openssl passwd -6 mypassword
    ssh_authorized_keys:
      - $(cat /root/.ssh/id_rsa.pub)

# Update and install packages
package_update: true
package_upgrade: true
packages:
  - curl
  - wget
  - vim
  - htop
  - git
  - net-tools
  - nfs-common
  - socat
  - conntrack
  - ipset
  - qemu-guest-agent

# Run commands after first boot
runcmd:
  # Disable swap (required for Kubernetes)
  - swapoff -a
  - sed -i '/ swap / s/^/#/' /etc/fstab
  # Load kernel modules for K8s
  - modprobe br_netfilter
  - modprobe overlay
  - echo "br_netfilter" >> /etc/modules-load.d/k8s.conf
  - echo "overlay" >> /etc/modules-load.d/k8s.conf
  # K8s sysctl settings
  - echo "net.bridge.bridge-nf-call-iptables=1" >> /etc/sysctl.d/k8s.conf
  - echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/k8s.conf
  - sysctl --system
  # Enable and start qemu-guest-agent
  - systemctl enable --now qemu-guest-agent

write_files:
  - path: /etc/role
    content: "kubernetes-worker\n"
    permissions: '0644'

final_message: "Cloud-init complete for ${VM_NAME}"
EOF

# network-config: static IP assignment
cat > /tmp/${VM_NAME}-network.yaml << EOF
version: 2
ethernets:
  enp1s0:
    addresses: [${VM_IP}/24]
    gateway4: 10.0.1.1
    nameservers:
      addresses: [10.0.1.1, 8.8.8.8]
    dhcp4: false
EOF

# Create cloud-init ISO (combines user-data + network-config)
cloud-localds \
  /tmp/${VM_NAME}-cidata.iso \
  /tmp/${VM_NAME}-userdata.yaml \
  --network-config /tmp/${VM_NAME}-network.yaml

echo "Cloud-init ISO created: /tmp/${VM_NAME}-cidata.iso"
```

### 2c. Create VM Using Cloud-Init

```bash
# Create a new QCOW2 based on the cloud base image
qemu-img create -f qcow2 \
  -b /data/kvm/images/ubuntu-22.04-base.qcow2 \
  -F qcow2 \
  /data/kvm/images/${VM_NAME}.qcow2 200G

# Launch VM with cloud-init ISO
virt-install \
  --name ${VM_NAME} \
  --vcpus 16 \
  --memory 65536 \
  --disk /data/kvm/images/${VM_NAME}.qcow2,format=qcow2,bus=virtio \
  --disk /tmp/${VM_NAME}-cidata.iso,device=cdrom \
  --os-variant ubuntu22.04 \
  --network bridge=br0,model=virtio \
  --graphics none \
  --noautoconsole \
  --import \
  --autostart

# Cloud-init runs on first boot (~60 seconds)
# Watch cloud-init progress
sleep 60
virsh console ${VM_NAME}
# Or: ssh admin@${VM_IP}  (SSH available after cloud-init completes)
```

### 2d. Bulk VM Creation Script

```bash
cat > /usr/local/bin/bulk-create-vms.sh << 'SCRIPT'
#!/bin/bash
# Usage: bulk-create-vms.sh
# Creates all K8s cluster VMs

BASE_IMAGE="/data/kvm/images/ubuntu-22.04-base.qcow2"
IMAGE_DIR="/data/kvm/images"
SSH_KEY=$(cat /root/.ssh/id_rsa.pub)

declare -A VMS=(
  ["k8s-cp-01"]="8:16384:100:10.0.1.10"
  ["k8s-cp-02"]="8:16384:100:10.0.1.11"
  ["k8s-cp-03"]="8:16384:100:10.0.1.12"
  ["k8s-wk-01"]="16:65536:200:10.0.1.20"
  ["k8s-wk-02"]="16:65536:200:10.0.1.21"
  ["k8s-wk-03"]="16:65536:200:10.0.1.22"
)

for VM_NAME in "${!VMS[@]}"; do
  IFS=':' read -r VCPUS MEM DISK_GB IP <<< "${VMS[$VM_NAME]}"

  echo "Creating VM: $VM_NAME ($VCPUS vCPU, ${MEM}MB RAM, ${DISK_GB}GB, $IP)"

  # Create disk
  qemu-img create -f qcow2 -b "$BASE_IMAGE" -F qcow2 \
    "$IMAGE_DIR/${VM_NAME}.qcow2" "${DISK_GB}G"

  # Create cloud-init
  cat > /tmp/${VM_NAME}-ud.yaml << EOF
#cloud-config
hostname: ${VM_NAME}
users:
  - name: admin
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    ssh_authorized_keys:
      - ${SSH_KEY}
runcmd:
  - swapoff -a
  - sed -i '/ swap / s/^/#/' /etc/fstab
  - systemctl enable --now qemu-guest-agent
EOF

  cat > /tmp/${VM_NAME}-net.yaml << EOF
version: 2
ethernets:
  enp1s0:
    addresses: [${IP}/24]
    gateway4: 10.0.1.1
    nameservers:
      addresses: [10.0.1.1]
    dhcp4: false
EOF

  cloud-localds /tmp/${VM_NAME}-ci.iso \
    /tmp/${VM_NAME}-ud.yaml \
    --network-config /tmp/${VM_NAME}-net.yaml

  virt-install \
    --name "$VM_NAME" \
    --vcpus "$VCPUS" \
    --memory "$MEM" \
    --disk "$IMAGE_DIR/${VM_NAME}.qcow2,format=qcow2,bus=virtio" \
    --disk "/tmp/${VM_NAME}-ci.iso,device=cdrom" \
    --os-variant ubuntu22.04 \
    --network bridge=br0,model=virtio \
    --graphics none \
    --noautoconsole \
    --import \
    --autostart

  echo "VM $VM_NAME created — IP: $IP"
done

echo "All VMs created. Waiting 90s for cloud-init..."
sleep 90

for VM in "${!VMS[@]}"; do
  IP=$(echo "${VMS[$VM]}" | cut -d: -f4)
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 admin@$IP \
    "hostname && uptime" 2>/dev/null && echo "$VM ($IP): READY" || echo "$VM ($IP): NOT READY"
done
SCRIPT

chmod +x /usr/local/bin/bulk-create-vms.sh
```

---

## 3. QEMU Guest Agent

The guest agent enables the host to communicate with VM internals.

```bash
# Install inside VM
apt install -y qemu-guest-agent    # Ubuntu/Debian
dnf install -y qemu-guest-agent    # RHEL/OL

systemctl enable --now qemu-guest-agent

# Host-side: enable in libvirt VM XML
# virsh edit <vm> — add inside <devices>:
# <channel type='unix'>
#   <target type='virtio' name='org.qemu.guest_agent.0'/>
# </channel>

# Use guest agent from host
virsh qemu-agent-command <vm> '{"execute":"guest-info"}'

# Get VM's IP addresses (even without DHCP leases)
virsh domifaddr <vm> --source agent

# Get guest OS info
virsh guestinfo <vm>
# Shows: OS name, kernel, hostname, timezone

# Freeze filesystems before snapshot (ensures consistency)
virsh domfsfreeze <vm>
virsh snapshot-create-as --domain <vm> --name "consistent-snap" --disk-only --atomic
virsh domfsthaw <vm>
```

---

## 4. VM Templates and Cloning

```bash
# --- Prepare a Golden Template VM ---
# 1. Install OS + configure base settings
# 2. Install common tools (vim, curl, nfs-common, qemu-guest-agent)
# 3. Run cloud-init cleanup (so it reruns on next boot)
virt-sysprep -d template-vm
# virt-sysprep: removes SSH host keys, machine-id, user data, logs
# VM becomes a clean template

# --- Clone a VM ---
virt-clone \
  --original template-vm \
  --name k8s-wk-04 \
  --file /data/kvm/images/k8s-wk-04.qcow2

# Clone with new MAC address
virt-clone \
  --original template-vm \
  --name k8s-wk-04 \
  --file /data/kvm/images/k8s-wk-04.qcow2 \
  --mac RANDOM

# Edit cloned VM's hostname, IP before starting
virt-customize -d k8s-wk-04 \
  --hostname k8s-wk-04.internal \
  --run-command "sed -i 's/10.0.1.20/10.0.1.23/g' /etc/netplan/50-cloud-init.yaml" \
  --selinux-relabel   # Required if SELinux is enabled

virsh start k8s-wk-04
```

---

## 5. Creating VMs in OLVM Web UI

```
Screenshot: Navigate to Compute > Virtual Machines > New VM

Step 1 — General:
  Template: Blank (or select a custom template)
  Operating System: Red Hat Enterprise Linux 9 (or appropriate)
  Instance Type: medium (2 vCPU, 8GB) or custom
  Name: k8s-cp-01
  Description: K8s control plane — environment prod

Step 2 — System:
  Memory Size: 16384 MB
  Total Virtual CPUs: 8
  CPU Cores: 8 / Sockets: 1 / Threads: 2

Step 3 — Boot:
  Boot Sequence: Hard Disk first
  Enable: Run Once > Attach installation ISO (for fresh install)
  OR: Use existing disk for import

Step 4 — Storage:
  Click "Attach" > Create new disk:
    Size: 100 GB
    Interface: VirtIO-SCSI
    Storage Domain: netapp-data
    Disk Type: Thin (recommended) or Pre-allocated (max performance)

Step 5 — Network:
  Add network interface:
    Network: vm-network (VLAN 100)
    Type: VirtIO
  Add second interface (optional):
    Network: storage-net (VLAN 200)

Step 6 — High Availability:
  Highly Available: Yes
  Priority: High

Click OK — VM is created and appears in the VM list
Click the green Run button (▶) to start it
```

---

## 6. VM Management Quick Reference

```bash
# Start / Stop / Pause / Resume
virsh start k8s-cp-01
virsh shutdown k8s-cp-01      # graceful
virsh destroy k8s-cp-01       # force off
virsh suspend k8s-cp-01       # pause (RAM preserved)
virsh resume k8s-cp-01

# List VMs
virsh list --all
virsh list --state-running

# VM info
virsh dominfo k8s-cp-01
virsh domstats k8s-cp-01

# Edit VM XML
virsh edit k8s-cp-01

# Console access
virsh console k8s-cp-01       # serial console (Ctrl+] to exit)
virt-viewer k8s-cp-01         # VNC/SPICE graphical

# Delete VM (keep disk)
virsh undefine k8s-cp-01

# Delete VM + disk
virsh undefine k8s-cp-01 --remove-all-storage

# Rename VM
virsh domrename k8s-cp-01 k8s-cp-01-old

# Hotplug vCPU
virsh setvcpus k8s-cp-01 12 --live

# Hotplug memory
virsh setmem k8s-cp-01 32G --live

# Hotplug NIC
virsh attach-interface k8s-cp-01 bridge br0 --model virtio --live --persistent

# Hotplug disk
virsh attach-disk k8s-cp-01 /data/kvm/images/extra.qcow2 vdb \
  --driver qemu --subdriver qcow2 --live --persistent
```

---

*Next: [08-OLVM-HTTPS-Certificate.md](08-OLVM-HTTPS-Certificate.md)*
