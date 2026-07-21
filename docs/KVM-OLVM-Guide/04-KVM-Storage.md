# 04 — KVM Storage

> Complete reference for KVM storage: disk formats, LVM, NFS, iSCSI, snapshots, backup, and performance tuning.

---

## Storage Format Comparison

| Format | Extension | Performance | Features | Best For |
|--------|-----------|-------------|----------|----------|
| **RAW** | .img | Best (no overhead) | None (no snapshot, no compress) | Production DB VMs on LVM |
| **QCOW2** | .qcow2 | Good (5-10% overhead) | Snapshots, compression, encryption | General VMs, dev/test |
| **VMDK** | .vmdk | Moderate | VMware compatible | VM migration from VMware |
| **LVM LV** | (block device) | Excellent | Thin provisioning, VG snapshots | Production performance VMs |
| **RBD (Ceph)** | (network block) | Good over 10GbE | Live migration without shared FS | Multi-host clusters |

**Recommendation**: Use LVM thin-provisioned volumes for production K8s node VMs. Use QCOW2 for dev/test and VMs that need snapshots.

---

## 1. libvirt Storage Pools

A storage pool is how libvirt tracks where VM disks live.

```bash
# Pool types:
# dir       — directory of QCOW2/RAW files
# logical   — LVM volume group
# netfs     — NFS mount
# iscsi     — iSCSI target
# rbd       — Ceph RBD pool

# List existing pools
virsh pool-list --all --details

# --- Directory Pool ---
virsh pool-define-as datapool dir --target /data/kvm/images
virsh pool-build datapool
virsh pool-start datapool
virsh pool-autostart datapool

# --- LVM Pool ---
# First create the LVM VG on your NVMe disk
pvcreate /dev/nvme1n1
vgcreate kvm-vg /dev/nvme1n1

virsh pool-define-as lvm-pool logical \
  --source-name kvm-vg \
  --target /dev/kvm-vg
virsh pool-start lvm-pool
virsh pool-autostart lvm-pool

# --- NFS Pool ---
virsh pool-define-as nfs-pool netfs \
  --source-host 10.0.3.10 \
  --source-path /vol/kvm_images \
  --target /mnt/kvm-nfs
virsh pool-build nfs-pool
virsh pool-start nfs-pool
virsh pool-autostart nfs-pool

# Show all pool details
virsh pool-list --all
virsh pool-info datapool
```

---

## 2. QCOW2 Deep Dive

QCOW2 (QEMU Copy-On-Write version 2) is the most versatile KVM disk format.

```bash
# Create a QCOW2 image
qemu-img create -f qcow2 /data/kvm/images/my-vm.qcow2 100G

# Create with preallocation (better performance, slower create)
qemu-img create -f qcow2 -o preallocation=metadata \
  /data/kvm/images/my-vm-fast.qcow2 100G

# Inspect image info
qemu-img info /data/kvm/images/my-vm.qcow2
# Shows: virtual size, disk size, cluster size, backing file, snapshots

# Resize a QCOW2 image
qemu-img resize /data/kvm/images/my-vm.qcow2 +50G
# Then inside the VM: sudo growpart /dev/vda 1 && sudo resize2fs /dev/vda1
# Or for XFS: sudo xfs_growfs /

# Convert RAW to QCOW2
qemu-img convert -f raw -O qcow2 vm.raw vm.qcow2

# Convert QCOW2 to RAW (for LVM block device)
qemu-img convert -f qcow2 -O raw vm.qcow2 /dev/kvm-vg/vm-lv

# Convert VMDK (from VMware) to QCOW2
qemu-img convert -f vmdk -O qcow2 vm.vmdk vm.qcow2

# Compress a QCOW2 (reduce size at rest — slower reads)
qemu-img convert -c -O qcow2 vm.qcow2 vm-compressed.qcow2

# Check image consistency
qemu-img check /data/kvm/images/my-vm.qcow2

# View the full snapshot chain (backing files)
qemu-img info --backing-chain /data/kvm/images/my-vm.qcow2
```

### QCOW2 Backing Files (Templates)

```bash
# Create a base template image
qemu-img create -f qcow2 /data/kvm/images/ubuntu-22.04-base.qcow2 30G

# Create child images that use the base as backing file
# The child only stores DIFFERENCES from the base — saves disk space
qemu-img create -f qcow2 \
  -b /data/kvm/images/ubuntu-22.04-base.qcow2 \
  -F qcow2 \
  /data/kvm/images/vm-worker-01.qcow2 100G

# The base must not be modified while children exist
# To detach from backing file (merge base + child into one standalone image):
qemu-img rebase -b '' -f qcow2 /data/kvm/images/vm-worker-01.qcow2
```

---

## 3. LVM Storage (Best Performance)

LVM Logical Volumes are block devices — no QCOW2 overhead.

```bash
# --- Setup LVM VG on dedicated NVMe ---
pvcreate /dev/nvme1n1
vgcreate kvm-vg /dev/nvme1n1
# Check
pvs && vgs

# --- Create LV per VM ---
lvcreate -L 100G -n k8s-cp-01 kvm-vg
lvcreate -L 200G -n k8s-wk-01 kvm-vg
lvcreate -L 500G -n infra-db-01 kvm-vg

# List all LVs
lvs

# --- LVM Thin Provisioning (allocate on write, overcommit disk) ---
# Create a thin pool (e.g., 2TB thin pool in a 2TB VG)
lvcreate -L 2T -T kvm-vg/thin-pool --poolmetadatasize 20G

# Create thin volumes (appear as 200G but only use real space when written)
lvcreate -V 200G -T kvm-vg/thin-pool -n k8s-wk-02
lvcreate -V 200G -T kvm-vg/thin-pool -n k8s-wk-03

# Check thin pool usage
lvs -a kvm-vg
# DATA% column shows how full the thin pool is

# --- Use LV as VM disk ---
virt-install \
  --name k8s-cp-01 \
  --disk /dev/kvm-vg/k8s-cp-01,format=raw,bus=virtio,cache=none,io=native \
  ...
```

---

## 4. NFS Storage (NetApp AFF A250)

```bash
# Mount NFS from NetApp
apt install -y nfs-common   # Ubuntu
dnf install -y nfs-utils    # RHEL/OL

# Mount with performance options
echo "10.0.3.10:/vol/kvm_images  /mnt/nfs-kvm  nfs4  \
  rw,hard,intr,rsize=131072,wsize=131072,timeo=600,nfsvers=4.1,_netdev  0 0" \
  >> /etc/fstab
mount -a

# Check mount performance
dd if=/dev/zero of=/mnt/nfs-kvm/test bs=4M count=1000 oflag=direct
# Should see ~1 GB/s on 10GbE to NetApp

# Define NFS pool in libvirt
virsh pool-define-as nfs-pool netfs \
  --source-host 10.0.3.10 \
  --source-path /vol/kvm_images \
  --target /mnt/nfs-kvm
virsh pool-start nfs-pool
virsh pool-autostart nfs-pool

# Create a volume in the NFS pool
virsh vol-create-as nfs-pool k8s-cp-01.qcow2 100G --format qcow2
virsh vol-list nfs-pool
```

---

## 5. iSCSI Storage

```bash
# Install iSCSI initiator
dnf install -y iscsi-initiator-utils   # RHEL/OL
apt install -y open-iscsi              # Ubuntu

# Set initiator name (unique per host)
echo "InitiatorName=iqn.2026-01.internal.kvm:kvm-host-01" \
  > /etc/iscsi/initiatorname.iscsi

systemctl enable --now iscsid

# Discover iSCSI targets
iscsiadm -m discovery -t sendtargets -p 10.0.3.20
# Example output:
# 10.0.3.20:3260,1 iqn.2026-01.com.storage:kvm-lun-01

# Login to target
iscsiadm -m node \
  -T iqn.2026-01.com.storage:kvm-lun-01 \
  -p 10.0.3.20 \
  --login

# Find the new block device
lsblk
# New disk appears as /dev/sdb

# Format for use
mkfs.xfs /dev/sdb
mkdir -p /mnt/iscsi
echo "/dev/sdb /mnt/iscsi xfs defaults,_netdev 0 0" >> /etc/fstab

# Enable automatic login at boot
iscsiadm -m node \
  -T iqn.2026-01.com.storage:kvm-lun-01 \
  -p 10.0.3.20 \
  --op update -n node.startup -v automatic

# Define iSCSI pool in libvirt
virsh pool-define-as iscsi-pool iscsi \
  --source-host 10.0.3.20 \
  --source-dev iqn.2026-01.com.storage:kvm-lun-01 \
  --target /dev/disk/by-path
virsh pool-start iscsi-pool
virsh pool-autostart iscsi-pool
```

---

## 6. Disk Performance Tuning

```bash
# --- virtio vs IDE comparison ---
# Always use virtio (or virtio-scsi for multiple disks)
# In virt-install: --disk bus=virtio

# --- Cache modes ---
# cache=none         Best for production DB (bypasses host page cache, O_DIRECT)
# cache=writeback    Best throughput (writes cached in RAM — risk of data loss on crash)
# cache=writethrough Safe (write confirmed only after disk write) — slow
# cache=directsync   Like none + writeback combined

# Recommended:
# Production DB VMs:  cache=none,io=native (raw block)
# K8s worker VMs:     cache=none,io=threads (QCOW2)
# Dev/Test VMs:       cache=writeback       (QCOW2, fast)

# Set in VM XML:
# <driver name='qemu' type='qcow2' cache='none' io='threads' discard='unmap'/>

# --- I/O mode ---
# io=native  — uses Linux native AIO (requires cache=none)
# io=threads — uses QEMU thread pool
# io=io_uring — modern, fastest (Linux 5.1+)

# Check I/O scheduler on host NVMe
cat /sys/block/nvme0n1/queue/scheduler
# [none] mq-deadline

# For NVMe: scheduler=none or mq-deadline
echo mq-deadline > /sys/block/nvme0n1/queue/scheduler

# --- TRIM/Discard passthrough ---
# Allows the VM to TRIM (free) space back to the host
# For LVM thin pools:
# <driver name='qemu' type='raw' discard='unmap'/>
# In VM: fstrim -v /

# Check VM disk performance
virt-top    # shows per-VM disk throughput
virsh domblkstat <vm> vda  # per-disk IOPS and bytes
```

---

## 7. Snapshots

### Internal Snapshot (QCOW2 only — includes memory state)

```bash
# Create snapshot (saves disk + RAM state — VM pauses briefly)
virsh snapshot-create-as --domain k8s-cp-01 \
  --name "pre-upgrade-20260721" \
  --description "Before Kubernetes upgrade" \
  --atomic

# List snapshots
virsh snapshot-list k8s-cp-01

# Revert to snapshot
virsh snapshot-revert k8s-cp-01 "pre-upgrade-20260721"

# Delete snapshot
virsh snapshot-delete k8s-cp-01 "pre-upgrade-20260721"
```

### External Snapshot (Disk-only — VM keeps running)

```bash
# Create external disk-only snapshot (VM keeps running)
virsh snapshot-create-as --domain k8s-cp-01 \
  --name "snap-$(date +%Y%m%d-%H%M)" \
  --description "Live snapshot" \
  --disk-only \
  --atomic

# The VM now writes to a NEW overlay file
# Original disk is frozen — copy it for backup
virsh domblklist k8s-cp-01
# Shows: vda  /data/kvm/images/k8s-cp-01.snap-20260721-1430

# After backup, merge the snapshot back (blockcommit)
virsh blockcommit k8s-cp-01 vda \
  --top /data/kvm/images/k8s-cp-01.snap-20260721-1430 \
  --wait --verbose --pivot

# Verify the VM is back to one disk file
virsh domblklist k8s-cp-01
```

---

## 8. Incremental Backup with Dirty Bitmaps (QEMU 4.2+)

Dirty bitmaps track which 64KB blocks changed since last backup — enables 90% faster incremental backups.

```bash
# Add a persistent dirty bitmap to track changes (do this once)
virsh qemu-monitor-command k8s-cp-01 --hmp \
  "block-dirty-bitmap-add drive-vda backup-bitmap --persistent"

# Run first FULL backup
qemu-img convert -f qcow2 \
  /data/kvm/images/k8s-cp-01.qcow2 \
  -O qcow2 \
  /backup/k8s-cp-01-full-$(date +%Y%m%d).qcow2

# Run INCREMENTAL backup (only changed blocks)
# (Using qemu-nbd + qemu-img -- requires QEMU 6+)
# Create external snapshot to safely read disk
virsh snapshot-create-as k8s-cp-01 snap-backup --disk-only --atomic

# Copy only dirty blocks to incremental file
# See: https://wiki.qemu.org/Features/IncrementalBackup
# For production: use Veeam Agent for Linux or Proxmox Backup Server APIs

# Cleanup snapshot after backup
virsh blockcommit k8s-cp-01 vda --top snap-backup --wait --pivot
```

---

## 9. Troubleshooting Storage

| Symptom | Cause | Fix |
|---------|-------|-----|
| VM disk very slow | Wrong cache mode | Change to `cache=none,io=native` in VM XML |
| `virsh pool-start` fails | NFS not mounted | Check `mount \| grep nfs`; verify NFS server |
| Snapshot creation failed | Not enough disk space | `df -h /data/kvm/images`; free space or use different pool |
| `blockcommit` hung | QEMU waiting for I/O | Check `virsh blockjobinfo <vm> vda`; wait or abort |
| LV not found after reboot | VG not activated | `vgchange -ay kvm-vg`; add to initramfs |
| iSCSI disconnects | Network issue / timeout | Check `iscsiadm -m session`; increase `node.conn[0].timeo.noop_out_timeout` |
| VM disk resize failed | Filesystem not resized | Run `growpart /dev/vda 1 && resize2fs /dev/vda1` inside VM |
| "No space left" on thin pool | Pool over-provisioned | `lvextend -L+500G kvm-vg/thin-pool`; monitor DATA% |
| Snapshot chain too long | Many unsquashed snapshots | Merge with `qemu-img commit`; blockcommit chain back |
| RAW image on NFS is slow | NFS rsize/wsize too small | Mount with `rsize=131072,wsize=131072,nfsvers=4.1` |
| QCOW2 not compressed | Default no compression | Use `-c` flag in `qemu-img convert` |
| SELinux blocks image access | Wrong fcontext | `restorecon -Rv /data/kvm/images` |

---

*Next: [05-KVM-Security.md](05-KVM-Security.md)*
