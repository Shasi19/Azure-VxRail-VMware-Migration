# Current Infrastructure Inventory — Dell VxRail HCI

> **Purpose:** Audit your existing 6-node VxRail cluster before starting migration. Document every detail. This becomes your baseline.

---

## 1. What a VxRail HCI Cluster Is (Your Current Setup)

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                   YOUR CURRENT: 6-Node Dell VxRail HCI                          │
│                                                                                  │
│  Each VxRail node is a pre-configured, pre-cabled server with:                  │
│  ├── CPU:     Intel Xeon (varies by model)                                       │
│  ├── RAM:     DDR4 ECC (varies by model)                                         │
│  ├── Storage: NVMe SSDs (cache tier) + NVMe/SAS/SATA (capacity tier) for vSAN  │
│  ├── Network: 2x 25 GbE or 2x 10 GbE NIC (bonded for redundancy)               │
│  └── BMC:     iDRAC (Dell's out-of-band management)                             │
│                                                                                  │
│  VMware software stack (pre-installed by Dell):                                  │
│  ├── VMware ESXi 7.x or 8.x  — hypervisor on each of the 6 nodes                │
│  ├── VMware vSAN              — software-defined storage (pools all node SSDs)  │
│  ├── VMware vCenter Server    — centralized management (runs as appliance VM)   │
│  └── VxRail Manager          — Dell's lifecycle + health management plugin     │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Common VxRail Models (identify yours)

| Series | Node Type | Typical CPU | Typical RAM | Storage Profile | Best For |
|--------|-----------|------------|------------|----------------|----------|
| **VxRail E Series** | All-NVMe | 2x Xeon Silver/Gold (16-32c) | 128–384 GB | NVMe cache + NVMe capacity | General purpose, balanced |
| **VxRail P Series** | Performance | 2x Xeon Gold/Platinum (24-64c) | 256–768 GB | NVMe cache + NVMe capacity | High I/O, databases |
| **VxRail V Series** | vSAN ReadyNode | 2x Xeon Gold | 128–512 GB | NVMe + SAS hybrid | Cost-optimized |
| **VxRail G Series** | GPU | 2x Xeon + GPU | 256 GB+ | NVMe | AI/ML workloads |
| **VxRail S Series** | Storage-dense | 2x Xeon | 128–256 GB | NVMe + large capacity HDDs | High capacity |

---

## 2. Run These Commands to Document Your Current Setup

### 2.1 Connect and Audit via govc

```bash
# Install govc on your jump host (Mac/Linux)
# Mac:
brew install govc

# Linux:
curl -L -o - "https://github.com/vmware/govmomi/releases/latest/download/govc_Linux_x86_64.tar.gz" \
  | sudo tar -C /usr/local/bin -xvzf - govc

# Set up environment (get these from your vCenter admin)
export GOVC_URL=https://YOUR-VCENTER-IP
export GOVC_USERNAME=administrator@vsphere.local
export GOVC_PASSWORD='YOUR-PASSWORD'
export GOVC_INSECURE=1    # set 0 if you have a valid cert

# Test connection
govc about
```

### 2.2 Node Hardware Inventory

```bash
#!/bin/bash
# inventory-vxrail-cluster.sh — collect everything about your cluster

echo "=============================================="
echo "  VxRail Cluster Inventory Report"
echo "  Generated: $(date)"
echo "=============================================="

echo ""
echo "=== vCenter Server Info ==="
govc about

echo ""
echo "=== All ESXi Hosts ==="
govc host.info -dc="*" "*" | grep -E "Name:|Memory:|CPU|Version"

echo ""
echo "=== Per-Host Detail ==="
for HOST in $(govc find . -type h | grep -v folder); do
  echo ""
  echo "--- Host: $HOST ---"
  govc host.info "$HOST"
  echo "  Datastores:"
  govc host.datastore.info -host="$HOST" 2>/dev/null | grep -E "Name:|Type:|Capacity:|Free:"
  echo "  Network adapters:"
  govc host.esxcli -host="$HOST" network nic list 2>/dev/null | head -10
done

echo ""
echo "=== vSAN Datastore ==="
govc datastore.info -dc="*" "*" | grep -A 10 -i "vsan"

echo ""
echo "=== Cluster Resources ==="
govc cluster.usage -dc="*" "*"

echo ""
echo "=== Existing VMs ==="
govc find . -type m | sort
govc ls -l "vm/*" 2>/dev/null

echo ""
echo "=== Current Network (DVS and Port Groups) ==="
govc find . -type n | sort
govc dvs.portgroup.info -dc="*" "*" 2>/dev/null

echo ""
echo "=== Licenses ==="
govc license.ls 2>/dev/null

echo ""
echo "=============================================="
echo "  Inventory complete. Save this output!"
echo "=============================================="
```

```bash
# Run and save
bash inventory-vxrail-cluster.sh 2>&1 | tee vxrail-inventory-$(date +%Y%m%d).txt
```

### 2.3 Per-Host Hardware Detail (via iDRAC or ESXi)

SSH to each ESXi host and run:

```bash
# SSH to ESXi hosts (root password from VxRail Manager initial setup)
ssh root@10.0.1.11   # vxrail-1 management IP

# CPU info
esxcli hardware cpu global get
vsish -e get /hardware/cpu/cpuList/0 | grep -E "coreCnt|threadCnt|speed"

# Memory
esxcli hardware memory get

# Storage / Disks
esxcli storage core device list | grep -E "Display Name|Size|Device Type"
esxcli vsan storage list

# NIC info (important for planning VLANs)
esxcli network nic list
esxcli network nic get -n vmnic0
esxcli network vswitch dvs vmware list

# iDRAC / BIOS firmware versions
esxcli hardware ipmi bmc get 2>/dev/null || echo "Use iDRAC web UI for BMC info"
```

### 2.4 vSAN Detailed Inventory

```bash
# On any ESXi host in the cluster
# vSAN disk group layout
esxcli vsan storage list

# vSAN capacity and health
esxcli vsan cluster get
esxcli vsan health cluster list

# On vCenter (via govc or web UI):
# vSAN > Capacity — check total, used, available
# vSAN > Health — all green?
# vSAN > Performance — baseline I/O stats
```

### 2.5 Network Inventory

```bash
# Current DVS configuration
govc dvs.portgroup.info -dc="Datacenter" "VxRail*"

# VMkernel adapters (management, vSAN, vMotion IPs)
esxcli network ip interface list
esxcli network ip interface ipv4 get

# MTU settings (jumbo frames for vSAN?)
esxcli network vswitch dvs vmware list | grep -i mtu

# VLAN IDs currently in use
esxcli network vswitch dvs vmware portgroup list
```

---

## 3. Inventory Collection Worksheet

Fill this in from the commands above:

### 3.1 Cluster Identity

| Item | Your Value | Notes |
|------|-----------|-------|
| VxRail Model | e.g., VxRail E560F | Check label on front of each node |
| Number of Nodes | 6 | Confirmed |
| ESXi Version | e.g., ESXi 8.0 U2 | `govc about` |
| vSAN Version | e.g., vSAN 8.0 | Same as ESXi |
| vCenter Version | e.g., vCenter 8.0 U2 | `govc about` |
| VxRail Manager Version | e.g., 8.0.x | VxRail Manager web UI |
| vSphere License Type | Enterprise Plus / Standard | `govc license.ls` |
| vSAN License Type | Enterprise / Standard | `govc license.ls` |
| Datacenter Name | e.g., Datacenter | Note for govc exports |
| Cluster Name | e.g., VxRail-Cluster | Note for govc exports |

### 3.2 Per-Node Hardware

| Node | Model | CPU | Cores/Node | RAM | Cache Disk | Capacity Disk | NIC Speed |
|------|-------|-----|-----------|-----|-----------|--------------|-----------|
| VxRail-1 | | | | | | | |
| VxRail-2 | | | | | | | |
| VxRail-3 | | | | | | | |
| VxRail-4 | | | | | | | |
| VxRail-5 | | | | | | | |
| VxRail-6 | | | | | | | |
| **Total** | | | | | | | |

### 3.3 Current Network Layout

| Network | Current VLAN | Current Subnet | Used By |
|---------|-------------|---------------|---------|
| Management | | | ESXi, vCenter, VxRail Mgr |
| vSAN | | | vSAN storage traffic |
| vMotion | | | VM live migration |
| VM Network | | | Existing VMs (if any) |
| Other | | | |

### 3.4 vSAN Capacity

| Metric | Value | Notes |
|--------|-------|-------|
| Raw capacity (all disks) | | Sum of all capacity-tier disks |
| Usable capacity (FTT=1) | | ~50% of raw (RAID-1) |
| Currently used | | From vCenter > vSAN > Capacity |
| Available free | | For new K8s workloads |
| NVMe cache per node | | Cache-tier NVMe size |

### 3.5 Current VMs (if any running)

List all VMs currently on the cluster:

```bash
govc find . -type m -runtime.powerState poweredOn | while read VM; do
  INFO=$(govc vm.info "$VM")
  NAME=$(echo "$INFO" | grep "^Name:" | awk '{print $2}')
  CPU=$(echo "$INFO"  | grep "CPU:"    | awk '{print $2}')
  MEM=$(echo "$INFO"  | grep "Memory:" | awk '{print $2}')
  echo "$NAME | $CPU vCPU | $MEM"
done
```

> **Important:** Document all existing VMs before starting migration. Migration VMs will compete for resources with existing workloads.

---

## 4. What Your VxRail Does NOT Have Out-of-the-Box

Understanding what's missing helps you know what to set up or procure:

| What's Missing | Why You Need It | Solution |
|---------------|----------------|----------|
| Internal DNS server | VMs need name resolution | Deploy bind9 VM or use Windows AD DNS |
| Internal CA / TLS certs | HTTPS for Harbor, ArgoCD, MinIO | Deploy Step-CA or use Let's Encrypt |
| Jump host / bastion VM | CLI management, govc, kubectl | Deploy 1 Ubuntu VM with all tools |
| NTP server | All VMs need synchronized time (K8s, etcd) | Use existing NTP or deploy chrony VM |
| IPAM (IP management) | Track which IPs are used | Spreadsheet or phpIPAM VM |
| Azure connectivity | Transfer data during migration | Site-to-Site VPN or ExpressRoute |
| Backup target | Velero + DB backups need external storage | NFS share on NAS or MinIO |
| Monitoring baseline | Pre-migration performance data | Deploy Prometheus on vSphere |
| Load balancer | External traffic entry | MetalLB (in K8s, free) or F5 (existing?) |
| GitLab / source control | ArgoCD needs a Git repo | Use existing GitLab or GitHub Enterprise |

---

## 5. Important VxRail Facts to Know

| Fact | Detail |
|------|--------|
| **VxRail Manager is read-only for some settings** | Network changes, host additions must go through VxRail Manager, not vCenter directly — otherwise VxRail Manager loses sync |
| **NEVER add ESXi hosts to vCenter manually** | Always use VxRail Manager to add/remove nodes — direct vCenter additions break the VxRail lifecycle |
| **vSAN disk groups are per-node** | Each node contributes cache+capacity disk groups to the shared pool |
| **vSAN stretched cluster needs 2 sites** | Your 6-node single-site cluster uses standard vSAN |
| **VxRail firmware updates go through VxRail Manager** | NOT vSphere Lifecycle Manager (VUM) — use VxRail Manager > Upgrade |
| **iDRAC = Dell's IPMI** | Out-of-band management — accessible even if ESXi crashes. Get all 6 iDRAC IPs |
| **vCenter VM runs on vSAN** | The vCenter appliance (VCSA) itself runs on vSAN — don't fill vSAN to 100% |
| **VMXNET3 is the NIC type for VMs** | Ubuntu will see it as `ens192` — use this in all network configs |
| **disk.EnableUUID is NOT set by default** | Must be enabled per-VM for vSphere CSI driver to work with Kubernetes |
