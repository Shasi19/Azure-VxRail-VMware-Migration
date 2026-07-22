# Infrastructure Assessment — Dell VxRail HCI + vSphere

## 1. VxRail Cluster Audit

Before provisioning VMs, audit the existing cluster to confirm available resources.

### 1.1 Connect to vCenter and Collect Host Facts

```bash
# Install govc (VMware vSphere CLI)
curl -L -o - "https://github.com/vmware/govmomi/releases/latest/download/govc_Linux_x86_64.tar.gz" \
  | sudo tar -C /usr/local/bin -xvzf - govc

# Set environment variables
export GOVC_URL=https://vcenter.internal.company.com
export GOVC_USERNAME=administrator@vsphere.local
export GOVC_PASSWORD='YourVcenterPassword'
export GOVC_INSECURE=0   # set 1 only for self-signed certs in lab
export GOVC_DATACENTER="Datacenter"
export GOVC_CLUSTER="VxRail-Cluster"

# Verify connectivity
govc about

# List all ESXi hosts in the cluster
govc host.info -dc="Datacenter" '*'
```

### 1.2 Cluster Resource Summary

```bash
# Total compute resources across all 6 nodes
govc cluster.usage -dc="Datacenter" VxRail-Cluster

# Per-host CPU and memory
govc host.info -json '*' | python3 -c "
import json, sys
data = json.load(sys.stdin)
for h in data['HostSystems']:
    name = h['Self']['Value']
    cpu_total = h['Hardware']['CpuInfo']['NumCpuCores']
    mem_gb = h['Hardware']['MemorySize'] // (1024**3)
    print(f'{name}: {cpu_total} cores, {mem_gb} GB RAM')
"

# List all VMs currently running (to understand existing load)
govc find . -type m -runtime.powerState poweredOn | head -50

# vSAN datastore capacity
govc datastore.info -dc="Datacenter" vsanDatastore
```

### 1.3 Expected Minimums for This Migration

| Resource | Required | Notes |
|----------|----------|-------|
| Free vCPU | 160+ cores total across cluster | See VM inventory in 00-Index.md |
| Free RAM | 600+ GB total | Phase 1 needs ~200 GB |
| vSAN free space | 8+ TB usable | After FTT=1 policy overhead |
| Network | 25 GbE or 10 GbE uplinks | For vSAN and VM traffic |

> **Typical VxRail E-series 6-node:** Each node has dual Intel Xeon (32-64 cores), 256-512 GB RAM, 2-6 NVMe drives for vSAN. A 6-node cluster provides 1,500+ vCPU capacity and 1.5-3 TB RAM.

---

## 2. vSAN Capacity Planning

### 2.1 Check Current vSAN Health and Capacity

```bash
# Via govc
govc datastore.info vsanDatastore

# Via vSphere web client: vSAN > Capacity Overview
# Or via ESXCLI on any host
ssh root@vxrail-1.internal.company.com \
  "esxcli vsan storage stats get"

# Check vSAN disk groups per host
govc host.esxcli -host vxrail-1.internal.company.com \
  vsan storage list
```

### 2.2 vSAN Storage Policy for K8s Workloads

Create policies in vCenter: **Policies and Profiles > VM Storage Policies**

```
Policy: k8s-production
  - Failures to Tolerate (FTT): 1   (survives 1 node failure)
  - RAID: RAID-1 (mirroring)
  - Disk striping: 1
  - Use: prod/preprod Kubernetes PVs, production databases

Policy: k8s-dev-qa
  - Failures to Tolerate (FTT): 0   (no redundancy — dev/qa only)
  - Use: dev and qa Kubernetes PVs, dev/qa databases
  - Saves 2x storage compared to FTT=1

Policy: k8s-databases
  - Failures to Tolerate (FTT): 1
  - RAID: RAID-5/6 (erasure coding) — requires 4+ nodes
  - Use: All database VMs — gives good protection with less overhead
```

```bash
# Create storage policy via PowerCLI (run on a Windows jump host with PowerCLI installed)
# Or use vCenter UI: Policies and Profiles > VM Storage Policies > Create

# Check if RAID-5 erasure coding is available (needs 4+ nodes)
esxcli vsan cluster get | grep -i "mode\|node"
```

### 2.3 Calculate Required vSAN Space

```
Dev + QA  (Phase 1):
  K8s nodes (3 masters + 2 workers): 5 × 100 GB = 500 GB
  Dev databases (PG + Mongo):        2 × 300 GB = 600 GB
  QA databases (PG + Mongo):         2 × 300 GB = 600 GB
  MinIO (Phase 1 share):             1 TB
  Harbor:                            500 GB
  Monitoring:                        500 GB
  Phase 1 total raw:                 ~3.7 TB
  With FTT=1 RAID-1 (2x overhead):  ~5 TB vSAN capacity needed

PreProd + Prod (Phase 2, additional):
  PreProd databases (PG 2-node + Mongo 2-node): 4 × 500 GB = 2 TB
  Prod databases (PG 3-node + Mongo 3-node):    6 × 1 TB   = 6 TB
  2 more K8s workers (150+200 GB each):          350 GB
  Phase 2 additional raw:            ~8.35 TB
  With FTT=1 RAID-1:                 ~12 TB additional

Total cluster vSAN needed:           ~17 TB usable capacity
```

---

## 3. Network Topology Assessment

### 3.1 VxRail Network Layout

VxRail ships with a pre-configured Distributed Virtual Switch (DVS). Typical layout:

```
Physical Uplinks (per node): 2x 25 GbE or 2x 10 GbE
  ├── vmnic0 / vmnic1 → VxRail DVS (LACP bonded)
  │     ├── Management VMkernel (vmk0) — 10.0.1.x/24
  │     ├── vSAN VMkernel (vmk1)       — 10.0.9.x/24 (dedicated)
  │     ├── vMotion VMkernel (vmk2)    — 10.0.8.x/24 (dedicated)
  │     └── VM Port Group              — 10.0.x.x (your app VLANs)
```

### 3.2 Required VLANs / Port Groups

Create these port groups on the VxRail DVS:

```bash
# Check existing port groups
govc dvs.portgroup.info -dc="Datacenter" VxRail-DVS

# Create port groups (or use vCenter UI: Networking > DVS > Add Port Group)
# Recommended structure:
#   PG-Management    VLAN 10  - ESXi mgmt, vCenter, VxRail Manager
#   PG-K8s-Nodes     VLAN 20  - K8s VM IP addresses (10.0.3.x, 10.0.4.x)
#   PG-Databases     VLAN 30  - DB VM addresses (10.0.5.x)
#   PG-Services      VLAN 40  - Harbor, MinIO, monitoring (10.0.6.x)
#   PG-LoadBalancer  VLAN 50  - MetalLB floating IPs (10.0.4.200-220)
```

### 3.3 IP Address Plan

| Subnet | VLAN | Range | Used For |
|--------|------|-------|----------|
| 10.0.1.0/24 | 10 | .1–.50 | Management (vCenter, ESXi, VxRail Mgr) |
| 10.0.3.0/24 | 20 | .11–.13 | K8s control plane VMs |
| 10.0.3.0/24 | 20 | .100 | K8s API VIP (keepalived) |
| 10.0.4.0/24 | 20 | .21–.26 | K8s worker VMs |
| 10.0.4.0/24 | 20 | .200–.220 | MetalLB floating IPs |
| 10.0.5.0/24 | 30 | .10–.50 | Database VMs |
| 10.0.6.0/24 | 40 | .10–.30 | Harbor, MinIO, monitoring |
| 10.0.9.0/24 | 90 | (existing) | vSAN traffic (dedicated) |
| 10.0.8.0/24 | 80 | (existing) | vMotion traffic (dedicated) |

---

## 4. Pre-Migration Checklist

Run this before starting either phase:

```bash
#!/bin/bash
# VxRail pre-migration readiness check
# Run from a Linux jump host with govc installed

export GOVC_URL=https://vcenter.internal.company.com
export GOVC_USERNAME=administrator@vsphere.local
export GOVC_PASSWORD="${VCENTER_PASSWORD}"
export GOVC_INSECURE=0

echo "===== VxRail Migration Readiness Check ====="
echo ""

# 1. vCenter connectivity
echo -n "[1] vCenter reachable: "
govc about 2>/dev/null | grep -q "Version" && echo "PASS" || echo "FAIL"

# 2. All 6 hosts connected
echo -n "[2] All 6 ESXi hosts connected: "
HOST_COUNT=$(govc host.info '*' 2>/dev/null | grep -c "Name:")
[ "$HOST_COUNT" -eq 6 ] && echo "PASS ($HOST_COUNT hosts)" || echo "FAIL (only $HOST_COUNT hosts)"

# 3. vSAN healthy
echo -n "[3] vSAN datastore accessible: "
govc datastore.info vsanDatastore 2>/dev/null | grep -q "Free" && echo "PASS" || echo "FAIL"

# 4. Free memory check (need 200+ GB for Phase 1)
echo -n "[4] Cluster free RAM >= 200 GB: "
FREE_MEM=$(govc cluster.usage -dc="Datacenter" VxRail-Cluster 2>/dev/null | awk '/Memory/ {print $3}')
echo "CHECK manually in vCenter (Cluster > Summary > Memory)"

# 5. DVS port groups exist
echo -n "[5] K8s port group exists: "
govc dvs.portgroup.info -dc="Datacenter" VxRail-DVS 2>/dev/null | grep -q "PG-K8s" && echo "PASS" || echo "MISSING — create port groups first"

# 6. Ubuntu template available
echo -n "[6] Ubuntu 22.04 VM template: "
govc find . -type m -name "ubuntu-22.04-template" 2>/dev/null | grep -q template && echo "PASS" || echo "MISSING — upload template"

# 7. DNS resolvable
echo -n "[7] Internal DNS working: "
nslookup vcenter.internal.company.com 2>/dev/null | grep -q "Address" && echo "PASS" || echo "FAIL"

echo ""
echo "===== Readiness check complete ====="
```

---

## 5. Phase 1 Resource Summary (Dev + QA Only)

VMs to create for Phase 1 (provision these before starting):

| VM | vCPU | RAM | Disk | Node Pin | Purpose |
|----|------|-----|------|----------|---------|
| k8s-master-1 | 4 | 8 GB | 80 GB | VxRail-1 | K8s control plane |
| k8s-master-2 | 4 | 8 GB | 80 GB | VxRail-2 | K8s control plane |
| k8s-master-3 | 4 | 8 GB | 80 GB | VxRail-3 | K8s control plane |
| k8s-worker-1 | 8 | 16 GB | 100 GB | VxRail-4 | Dev + QA workloads |
| k8s-worker-2 | 8 | 16 GB | 100 GB | VxRail-4 | Dev + QA workloads |
| db-dev-01 | 4 | 8 GB | 200 GB | VxRail-1 | Dev PostgreSQL + Patroni |
| db-qa-01 | 4 | 8 GB | 200 GB | VxRail-2 | QA PostgreSQL + Patroni |
| mongo-dev-01 | 2 | 4 GB | 100 GB | VxRail-1 | Dev MongoDB standalone |
| mongo-qa-01 | 2 | 4 GB | 100 GB | VxRail-2 | QA MongoDB standalone |
| minio-01 | 4 | 8 GB | 2 TB | VxRail-5 | MinIO (shared all envs) |
| harbor-01 | 4 | 8 GB | 500 GB | VxRail-6 | Harbor container registry |
| monitoring-01 | 4 | 16 GB | 500 GB | VxRail-6 | Prometheus + Grafana |

**Phase 1 total:** 12 VMs — 52 vCPU, 128 GB RAM, ~4.3 TB disk

**Phase 2 additional:** 14 more VMs — ~80 vCPU, 300 GB RAM, ~8 TB disk
