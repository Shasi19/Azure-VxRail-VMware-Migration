# 02 — VM Provisioning

> **Goal**: Create all 12 VMs (control plane, workers, infra) using cloud-init for automated OS configuration.  
> Run these commands **on the KVM host** that will own each VM.

---

## VM Inventory

| VM Name | Role | vCPU | RAM | Disk | IP | Host |
|---------|------|------|-----|------|----|------|
| k8s-cp-01 | K8s Control Plane | 8 | 16 GB | 100 GB | 10.0.1.10 | Host-1 |
| k8s-cp-02 | K8s Control Plane | 8 | 16 GB | 100 GB | 10.0.1.11 | Host-2 |
| k8s-cp-03 | K8s Control Plane | 8 | 16 GB | 100 GB | 10.0.1.12 | Host-3 |
| k8s-wk-01 | K8s Worker | 16 | 64 GB | 200 GB | 10.0.1.20 | Host-1 |
| k8s-wk-02 | K8s Worker | 16 | 64 GB | 200 GB | 10.0.1.21 | Host-1 |
| k8s-wk-03 | K8s Worker | 16 | 64 GB | 200 GB | 10.0.1.22 | Host-2 |
| k8s-wk-04 | K8s Worker | 16 | 64 GB | 200 GB | 10.0.1.23 | Host-2 |
| k8s-wk-05 | K8s Worker | 16 | 64 GB | 200 GB | 10.0.1.24 | Host-3 |
| k8s-wk-06 | K8s Worker | 16 | 64 GB | 200 GB | 10.0.1.25 | Host-3 |
| infra-db-01 | DB Primary | 16 | 64 GB | 500 GB | 10.0.1.30 | Host-1 |
| infra-db-02 | DB Replica | 16 | 64 GB | 500 GB | 10.0.1.31 | Host-2 |
| infra-db-03 | DB Replica + MongoDB | 16 | 64 GB | 500 GB | 10.0.1.32 | Host-3 |

---

## 1. Create a Reusable VM Creation Script

```bash
cat > /usr/local/bin/create-vm.sh << 'SCRIPT'
#!/bin/bash
# Usage: create-vm.sh <name> <cpus> <ram_mb> <disk_gb> <ip> <role>
set -euo pipefail

VM_NAME=$1
VCPUS=$2
RAM=$3
DISK_GB=$4
VM_IP=$5
VM_ROLE=$6
BASE_IMAGE="/data/kvm/images/ubuntu-22.04-base.qcow2"
IMG_DIR="/data/kvm/images"
GATEWAY="10.0.1.1"
DNS="192.168.10.1"
SSH_KEY=$(cat /root/.ssh/id_rsa.pub 2>/dev/null || cat /home/admin/.ssh/id_rsa.pub)

echo "Creating VM: $VM_NAME  IP: $VM_IP  vCPU: $VCPUS  RAM: ${RAM}MB  Disk: ${DISK_GB}GB"

# Create disk image from base template
qemu-img create -f qcow2 -F qcow2 -b "$BASE_IMAGE" "$IMG_DIR/${VM_NAME}.qcow2" "${DISK_GB}G"

# Create cloud-init user-data
cat > /tmp/${VM_NAME}-user-data.yaml << EOF
#cloud-config
hostname: ${VM_NAME}
fqdn: ${VM_NAME}.internal
users:
  - name: admin
    groups: sudo
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    ssh_authorized_keys:
      - ${SSH_KEY}
package_update: true
packages:
  - curl
  - wget
  - vim
  - htop
  - net-tools
  - nfs-common
  - open-iscsi
  - socat
  - conntrack
  - ipset
runcmd:
  - echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
  - echo "net.bridge.bridge-nf-call-iptables = 1" >> /etc/sysctl.conf
  - sysctl -p
  - swapoff -a
  - sed -i '/ swap / s/^/#/' /etc/fstab
  - echo never > /sys/kernel/mm/transparent_hugepage/enabled
  - modprobe br_netfilter
  - modprobe overlay
  - echo "br_netfilter" >> /etc/modules-load.d/k8s.conf
  - echo "overlay" >> /etc/modules-load.d/k8s.conf
  - timedatectl set-timezone UTC
  - systemctl enable --now chrony
write_files:
  - path: /etc/role
    content: "${VM_ROLE}\n"
EOF

# Create cloud-init network-config
cat > /tmp/${VM_NAME}-network.yaml << EOF
version: 2
ethernets:
  enp1s0:
    addresses: [${VM_IP}/24]
    gateway4: ${GATEWAY}
    nameservers:
      addresses: [${DNS}]
EOF

# Create cloud-init ISO
cloud-localds /tmp/${VM_NAME}-cidata.iso \
  /tmp/${VM_NAME}-user-data.yaml \
  --network-config /tmp/${VM_NAME}-network.yaml

# Install the VM
virt-install \
  --name "$VM_NAME" \
  --vcpus "$VCPUS" \
  --memory "$RAM" \
  --disk path="$IMG_DIR/${VM_NAME}.qcow2",format=qcow2,bus=virtio,cache=writeback \
  --disk path="/tmp/${VM_NAME}-cidata.iso",device=cdrom \
  --os-variant ubuntu22.04 \
  --network bridge=br-vm,model=virtio \
  --graphics none \
  --console pty,target_type=serial \
  --import \
  --noautoconsole \
  --autostart

echo "VM $VM_NAME created. Waiting for network..."
sleep 30
ping -c 3 "$VM_IP" && echo "$VM_NAME is reachable at $VM_IP" || echo "WARNING: $VM_IP not yet reachable (may still be booting)"
SCRIPT

chmod +x /usr/local/bin/create-vm.sh
```

---

## 2. Generate SSH Key Pair for VM Access

```bash
# Generate keypair if not already present
test -f /root/.ssh/id_rsa || ssh-keygen -t rsa -b 4096 -N '' -f /root/.ssh/id_rsa

# Copy public key to a safe location for reference
cat /root/.ssh/id_rsa.pub
```

---

## 3. Create K8s Control Plane VMs

Run on Host-1:
```bash
create-vm.sh k8s-cp-01 8 16384 100 10.0.1.10 control-plane
```

Run on Host-2:
```bash
create-vm.sh k8s-cp-02 8 16384 100 10.0.1.11 control-plane
```

Run on Host-3:
```bash
create-vm.sh k8s-cp-03 8 16384 100 10.0.1.12 control-plane
```

---

## 4. Create K8s Worker VMs

Run on Host-1:
```bash
create-vm.sh k8s-wk-01 16 65536 200 10.0.1.20 worker
create-vm.sh k8s-wk-02 16 65536 200 10.0.1.21 worker
```

Run on Host-2:
```bash
create-vm.sh k8s-wk-03 16 65536 200 10.0.1.22 worker
create-vm.sh k8s-wk-04 16 65536 200 10.0.1.23 worker
```

Run on Host-3:
```bash
create-vm.sh k8s-wk-05 16 65536 200 10.0.1.24 worker
create-vm.sh k8s-wk-06 16 65536 200 10.0.1.25 worker
```

---

## 5. Create Infrastructure VMs (DB / MongoDB / MinIO)

Run on Host-1:
```bash
create-vm.sh infra-db-01 16 65536 500 10.0.1.30 db-primary
```

Run on Host-2:
```bash
create-vm.sh infra-db-02 16 65536 500 10.0.1.31 db-replica
```

Run on Host-3:
```bash
create-vm.sh infra-db-03 16 65536 500 10.0.1.32 db-replica
```

---

## 6. Verify All VMs Are Running

```bash
# Check on each host
virsh list --all

# Expected output (example on Host-1):
#  Id   Name         State
#  --   k8s-cp-01    running
#  --   k8s-wk-01    running
#  --   k8s-wk-02    running
#  --   infra-db-01  running

# Test SSH to each VM
for IP in 10.0.1.{10..12} 10.0.1.{20..25} 10.0.1.{30..32}; do
  echo -n "$IP: "
  ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no admin@$IP "hostname" 2>/dev/null || echo "NOT READY"
done
```

---

## 7. Set Hostnames in /etc/hosts on Every VM

```bash
# Run this on every VM (or via Ansible)
cat >> /etc/hosts << 'EOF'
# Kubernetes Cluster Nodes
10.0.1.10   k8s-cp-01 k8s-cp-01.internal
10.0.1.11   k8s-cp-02 k8s-cp-02.internal
10.0.1.12   k8s-cp-03 k8s-cp-03.internal
10.0.1.20   k8s-wk-01 k8s-wk-01.internal
10.0.1.21   k8s-wk-02 k8s-wk-02.internal
10.0.1.22   k8s-wk-03 k8s-wk-03.internal
10.0.1.23   k8s-wk-04 k8s-wk-04.internal
10.0.1.24   k8s-wk-05 k8s-wk-05.internal
10.0.1.25   k8s-wk-06 k8s-wk-06.internal
10.0.1.30   infra-db-01 infra-db-01.internal
10.0.1.31   infra-db-02 infra-db-02.internal
10.0.1.32   infra-db-03 infra-db-03.internal
EOF

# Automate with a loop from any host that can SSH to all VMs
for IP in 10.0.1.{10..12} 10.0.1.{20..25} 10.0.1.{30..32}; do
  scp /etc/hosts admin@$IP:/tmp/hosts_append
  ssh admin@$IP "sudo bash -c 'cat /tmp/hosts_append >> /etc/hosts'"
done
```

---

## 8. VM Snapshot — Golden State

Before installing Kubernetes (take a clean snapshot to roll back if needed):

```bash
# On each KVM host, snapshot all VMs on that host
for VM in $(virsh list --name); do
  virsh snapshot-create-as --domain "$VM" \
    --name "pre-k8s-$(date +%Y%m%d)" \
    --description "Clean OS before K8s install" \
    --disk-only \
    --atomic
  echo "Snapshot created for $VM"
done

# List snapshots
virsh snapshot-list k8s-cp-01
```

---

## 9. VM Management Quick Reference

```bash
# Start a VM
virsh start k8s-wk-01

# Graceful shutdown
virsh shutdown k8s-wk-01

# Force off
virsh destroy k8s-wk-01

# Reboot
virsh reboot k8s-wk-01

# View console
virsh console k8s-cp-01
# (Ctrl+] to exit console)

# View resource usage
virsh domstats k8s-cp-01

# Live migrate VM to another host (requires shared storage)
virsh migrate --live k8s-wk-01 qemu+ssh://192.168.10.12/system --persistent

# Delete VM (remove disk too)
virsh destroy k8s-wk-01
virsh undefine k8s-wk-01 --remove-all-storage
```

---

*Next: [03-Network-Configuration.md](03-Network-Configuration.md)*
