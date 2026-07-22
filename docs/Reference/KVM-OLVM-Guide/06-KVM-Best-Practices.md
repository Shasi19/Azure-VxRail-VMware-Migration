# 06 — KVM Best Practices

> Performance tuning, NUMA topology, hugepages, CPU pinning, live migration, and a production-readiness checklist.

---

## 1. CPU Pinning

Pinning a VM's vCPUs to specific physical CPUs eliminates scheduler jitter and reduces latency. Critical for database VMs.

```bash
# First: understand your NUMA topology
numactl --hardware
# Example output:
# available: 2 nodes (0-1)
# node 0 cpus: 0 1 2 3 4 5 6 7 32 33 34 35 36 37 38 39
# node 1 cpus: 8 9 10 11 12 13 14 15 40 41 42 43 44 45 46 47
# node 0 size: 256 GB    node 1 size: 256 GB

# Check per-CPU topology
lscpu --extended
# Shows SOCKET, CORE, THREAD for each logical CPU

# Pin a running VM's vCPUs
# VM with 4 vCPUs pinned to physical CPUs 0-3 (NUMA node 0)
virsh vcpupin k8s-cp-01 0 0   # vCPU 0 → pCPU 0
virsh vcpupin k8s-cp-01 1 1   # vCPU 1 → pCPU 1
virsh vcpupin k8s-cp-01 2 2   # vCPU 2 → pCPU 2
virsh vcpupin k8s-cp-01 3 3   # vCPU 3 → pCPU 3

# Or pin all vCPUs to a CPU range at once
virsh vcpupin k8s-cp-01 0 0-3
virsh vcpupin k8s-cp-01 --all 0-7

# Verify pinning
virsh vcpuinfo k8s-cp-01
virsh vcpupin k8s-cp-01   # shows current mapping

# Make pinning persistent (add to VM XML)
virsh edit k8s-cp-01
# Add inside <vcpu> section:
# <cputune>
#   <vcpupin vcpu='0' cpuset='0'/>
#   <vcpupin vcpu='1' cpuset='1'/>
#   <vcpupin vcpu='2' cpuset='2'/>
#   <vcpupin vcpu='3' cpuset='3'/>
#   <emulatorpin cpuset='0-3'/>   <!-- pin QEMU emulator threads too -->
# </cputune>
```

---

## 2. NUMA Topology

For large VMs (>8 vCPUs, >64GB RAM), incorrect NUMA configuration causes cross-NUMA memory access (latency doubles).

```bash
# Check NUMA stats on host
numastat
# Shows NUMA hits vs misses (high miss rate = cross-NUMA problem)

# Check current VM NUMA placement
numastat -p $(pgrep -f "guest=k8s-cp-01")

# Proper NUMA-aware VM configuration in libvirt XML:
# virsh edit k8s-cp-01 — add this section inside <domain>:

# <cpu>
#   <topology sockets='1' cores='8' threads='2'/>
#   <numa>
#     <cell id='0' cpus='0-7' memory='32768' unit='MiB'/>
#   </numa>
# </cpu>
# <numatune>
#   <memory mode='strict' nodeset='0'/>   <!-- all memory from NUMA node 0 -->
# </numatune>
# <cputune>
#   <vcpupin vcpu='0' cpuset='0'/>
#   ... (pin to NUMA node 0 cpus only)
# </cputune>

# Pin a VM to a specific NUMA node when starting
virsh numatune k8s-cp-01 --nodeset 0 --mode strict

# Verify NUMA binding
virsh numatune k8s-cp-01
```

---

## 3. Hugepages

Hugepages reduce TLB misses (translation lookaside buffer) for large VMs. Significant benefit for PostgreSQL and MongoDB VMs.

```bash
# --- 2MB Hugepages ---
# Calculate: for a 64GB VM, need 64*1024/2 = 32768 hugepages
echo 32768 > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages

# Make persistent
echo "vm.nr_hugepages = 32768" >> /etc/sysctl.d/99-hugepages.conf
sysctl -p /etc/sysctl.d/99-hugepages.conf

# Verify allocation
cat /proc/meminfo | grep -i huge
# HugePages_Total:   32768
# HugePages_Free:    32768   (decreases as VMs use them)
# Hugepagesize:       2048 kB

# --- 1GB Hugepages (best for DBs, requires BIOS support) ---
# Allocate at boot (cannot be allocated dynamically)
# Add to kernel cmdline: hugepagesz=1G hugepages=64
grubby --args="hugepagesz=1G hugepages=64" --update-kernel=DEFAULT
reboot

# Verify 1GB hugepages
cat /proc/meminfo | grep -i "Huge"

# --- Configure VM to use hugepages ---
# virsh edit k8s-cp-01 — add inside <domain><memoryBacking>:
# <memoryBacking>
#   <hugepages>
#     <page size='2' unit='M'/>   <!-- or size='1' unit='G' for 1GB -->
#   </hugepages>
#   <nosharepages/>    <!-- disable KSM for this VM -->
# </memoryBacking>

# --- Mount hugepages filesystem (required for some VMs) ---
mkdir -p /dev/hugepages
mount -t hugetlbfs -o pagesize=2M hugetlbfs /dev/hugepages
echo "hugetlbfs /dev/hugepages hugetlbfs pagesize=2M 0 0" >> /etc/fstab
```

---

## 4. CPU Models

```bash
# List available CPU models
virsh cpu-models x86_64 | head -20

# Check host CPU capabilities
virsh capabilities | grep -A5 "<cpu>"

# CPU model options:
# host-passthrough — expose exact host CPU to VM (best performance, cannot live migrate to different CPU)
# host-model       — expose host CPU model with tweaks (good balance, can migrate to similar CPUs)
# Specific model   — e.g., "Skylake-Server" (most portable, slightly lower performance)

# For K8s node VMs (need to migrate between hosts with same CPU family):
# Use host-model

# For DB VMs (pinned to one host, max performance):
# Use host-passthrough

# Set in VM XML:
# <cpu mode='host-passthrough' check='none'>
#   <topology sockets='1' cores='8' threads='2'/>
# </cpu>
```

---

## 5. Memory Ballooning

The virtio-balloon driver allows the host to reclaim memory from VMs without shutting them down.

```bash
# Check balloon stats for a running VM
virsh domstats k8s-wk-01 --balloon
# Shows: available, rss, usable, unused, disk.caches

# Set current memory target (host reclaims some RAM)
virsh setmem k8s-wk-01 32G --live   # Reduce VM RAM to 32GB

# Set back to full allocation
virsh setmem k8s-wk-01 64G --live

# Check memory balloon in VM XML
virsh dumpxml k8s-wk-01 | grep -A5 memballoon
# <memballoon model='virtio'>
#   <stats period='10'/>    <!-- report stats every 10s -->
# </memballoon>

# Disable ballooning for production DB VMs (lock memory)
# In VM XML:
# <memballoon model='none'/>     <!-- disable completely -->
# OR
# <memoryBacking>
#   <locked/>                    <!-- pin VM memory, prevent swap -->
# </memoryBacking>
```

---

## 6. Kernel Same-Page Merging (KSM)

KSM lets the kernel merge identical memory pages from multiple VMs — useful when running many similar VMs.

```bash
# Check KSM status
cat /sys/kernel/mm/ksm/run
# 1 = running

# Enable KSM
echo 1 > /sys/kernel/mm/ksm/run

# Tune KSM aggressiveness
echo 1000 > /sys/kernel/mm/ksm/pages_to_scan    # pages scanned per interval
echo 20 > /sys/kernel/mm/ksm/sleep_millisecs     # interval in ms

# KSM stats
cat /sys/kernel/mm/ksm/pages_shared   # pages shared (good)
cat /sys/kernel/mm/ksm/pages_sharing  # VMs using shared pages
cat /sys/kernel/mm/ksm/pages_unshared # pages scanned but not shared

# Automate KSM tuning
systemctl enable --now ksmtuned

# For production DB VMs: disable KSM (security: Rowhammer attack mitigations)
# In VM XML:
# <memoryBacking><nosharepages/></memoryBacking>
```

---

## 7. Live Migration

Live migration moves a running VM from one KVM host to another with minimal downtime (seconds).

```bash
# --- Prerequisites ---
# 1. Shared storage (NFS/iSCSI/Ceph) or --copy-storage-all for local
# 2. Same libvirt version on source and destination
# 3. Compatible CPU model (use host-model, not host-passthrough for migrations)
# 4. Network connectivity between hosts on migration network

# Basic live migration
virsh migrate --live k8s-wk-01 qemu+ssh://kvm-host-02.internal/system

# Migration with specified target name (rename on destination)
virsh migrate --live k8s-wk-01 \
  qemu+ssh://kvm-host-02.internal/system \
  --name k8s-wk-01

# Bandwidth limit (MB/s) — prevent migration from saturating network
virsh migrate --live k8s-wk-01 \
  qemu+ssh://kvm-host-02.internal/system \
  --bandwidth 1000    # 1000 MB/s

# Post-copy migration (VM starts on destination, remaining pages copied on-demand)
# Lower downtime, higher risk of failure
virsh migrate --live --postcopy k8s-wk-01 \
  qemu+ssh://kvm-host-02.internal/system

# Migration with local storage (no shared storage — copies all disk data)
virsh migrate --live k8s-wk-01 \
  qemu+ssh://kvm-host-02.internal/system \
  --copy-storage-all

# Monitor migration progress
virsh domjobinfo k8s-wk-01
# Shows: Data Remaining, Data Total, Memory Remaining, Time Elapsed

# Cancel migration if needed
virsh migrate-compcache k8s-wk-01  # check
virsh domjobabort k8s-wk-01        # cancel

# Verify VM is running on destination
virsh -c qemu+ssh://kvm-host-02.internal/system list
```

---

## 8. Monitoring KVM Performance

```bash
# virt-top (top-like tool for VMs)
virt-top
# Shows: CPU%, memory, disk R/W, network R/W per VM
# Press 1 to cycle domains, f to filter

# virsh domstats (detailed per-VM stats)
virsh domstats k8s-wk-01
virsh domstats k8s-wk-01 --balloon --cpu-total --vcpu --interface --block

# Check CPU steal time inside VM (indicates noisy neighbours)
# Inside the VM:
vmstat 1 5 | awk '{print $16}'    # st column = steal time
top | grep -i "wa\|st"
# st > 5% means the VM is waiting for CPU — host is overloaded

# Host-side KVM perf analysis
perf kvm stat record -a -- sleep 10
perf kvm stat report
# Shows: kvmexits, mmio, hlt, cpuid counts per VM

# Monitor all VM disk IO
iostat -x 1 | grep -E "(dm-|vd)"

# Monitor bridge network traffic
sar -n DEV 1 5 | grep virbr

# Check KVM exit reasons (high exits = bad performance)
cat /sys/kernel/debug/kvm/exits
```

---

## 9. Production Readiness Checklist

Before putting a KVM host into production, verify all items:

```bash
cat > /usr/local/bin/kvm-prod-check.sh << 'SCRIPT'
#!/bin/bash
echo "=== KVM Production Readiness Check: $(hostname) ==="

checks_passed=0
checks_failed=0

check() {
  local desc=$1; local cmd=$2
  if eval "$cmd" &>/dev/null; then
    echo "  [PASS] $desc"
    ((checks_passed++))
  else
    echo "  [FAIL] $desc"
    ((checks_failed++))
  fi
}

echo "--- Hardware ---"
check "VT-x/AMD-V enabled" "grep -qE '(vmx|svm)' /proc/cpuinfo"
check "/dev/kvm exists" "test -c /dev/kvm"
check "KVM module loaded" "lsmod | grep -q kvm"
check "NUMA available" "numactl --show"

echo "--- OS Configuration ---"
check "Swap disabled" "[ $(free | awk '/Swap/{print $2}') -eq 0 ]"
check "THP disabled" "grep -q never /sys/kernel/mm/transparent_hugepage/enabled"
check "IP forwarding on" "[ $(cat /proc/sys/net/ipv4/ip_forward) -eq 1 ]"
check "CPU governor: performance" "cpupower frequency-info | grep -q performance"

echo "--- libvirt ---"
check "libvirtd running" "systemctl is-active libvirtd"
check "Default pool active" "virsh pool-info default | grep -q 'running'"
check "Default network active" "virsh net-info default | grep -q 'Active:.*yes'"
check "QEMU not running as root" "! ps aux | grep qemu | grep -qv grep | grep -q root"

echo "--- Security ---"
check "SELinux enforcing" "[ $(getenforce) = 'Enforcing' ]"
check "sVirt enabled" "ps -eZ | grep -q svirt_t"
check "Firewall active" "systemctl is-active nftables || systemctl is-active firewalld"

echo "--- Storage ---"
check "NFS mounted" "mount | grep -q nfs"
check "Data directory accessible" "test -w /data/kvm/images"

echo ""
echo "=== Results: $checks_passed passed, $checks_failed failed ==="
SCRIPT

chmod +x /usr/local/bin/kvm-prod-check.sh
kvm-prod-check.sh
```

---

## Host Sizing Guidelines

| Workload | vCPU:pCPU Ratio | RAM Overcommit | Storage |
|----------|----------------|----------------|---------|
| Dev/Test VMs | Up to 8:1 | Up to 2:1 | QCOW2 on NVMe |
| K8s worker VMs | 2:1 to 4:1 | 1.2:1 | LVM RAW or QCOW2 |
| Production DB VMs | 1:1 (pinned) | No overcommit | LVM RAW, cache=none |
| Web/App VMs | 4:1 to 6:1 | 1.5:1 | QCOW2, cache=writeback |
| Mixed general | 4:1 | 1.3:1 | QCOW2, NFS |

---

*Next: [07-Creating-VMs.md](07-Creating-VMs.md)*
