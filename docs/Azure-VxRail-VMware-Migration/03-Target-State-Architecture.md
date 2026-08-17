# On-Premises Target State Architecture

**Complete Design for VxRail VMware vSphere Kubernetes Infrastructure**

---

## On-Prem Architecture + Data Flow

```
┌─────────────┐   ┌──────────────┐   ┌───────────────┐
│ Users / DNS │──▶│ MetalLB / In │──▶│ K8s Workloads │
└─────────────┘   └──────────────┘   └──────┬────────┘
                                            │
                  ┌─────────────────────────▼─────────────────────────┐
                  │ Patroni PostgreSQL + vSAN 247.66 TB / 90.86 TB free│
                  └────────────────────────────────────────────────────┘
```


## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Physical Infrastructure](#physical-infrastructure)
3. [Virtual Infrastructure](#virtual-infrastructure)
4. [Kubernetes Architecture](#kubernetes-architecture)
5. [Database Architecture](#database-architecture)
6. [Storage Architecture](#storage-architecture)
7. [Networking Architecture](#networking-architecture)
8. [Backup & Disaster Recovery](#backup--disaster-recovery)
9. [Monitoring & Observability](#monitoring--observability)
10. [Security Architecture](#security-architecture)

---

## Architecture Overview

### Target Infrastructure Summary

```
On-Premises VxRail HCI Cluster
├── 6 Dell PowerEdge Servers (2-socket, 32-core each)
├── 3 vSphere Master Nodes (Kubernetes control plane)
├── 15 Worker Nodes (across QA/PREPROD/PROD)
├── vSAN Storage (247.66 TB total, 90.86 TB free)
├── 10GbE Network (redundant, converged)
└── Veeam Backup to local NAS

Workloads:
├── QA Environment (3 workers)
├── PREPROD Environment (9 workers)
└── PROD Environment (12 workers) [3 are shared masters]

Total Capacity:
- CPUs: 192 vCPUs (64% for workers, 12% for masters, 24% overhead)
- RAM: 768 GB (60% for workloads, 20% for vSAN, 20% overhead)
- Storage: 247.66 TB total (156.8 TB used, 90.86 TB free)
```

### Environment Separation

```
QA ENVIRONMENT (Weeks 1-3)
├── Kubernetes Cluster: k8s-qa
├── Nodes: 3M + 3W = 6 total VMs
├── Isolation: Network namespace, separate VLAN 100
├── Networking: 10.50.0.0/16
├── Storage: 50 GB vSAN allocation
└── Capacity: 8 vCPU, 32 GB RAM allocated

PREPROD ENVIRONMENT (Weeks 4-8)
├── Kubernetes Cluster: k8s-preprod
├── Nodes: 3M + 9W = 12 total VMs
├── Isolation: Separate namespace, VLAN 110
├── Networking: 10.51.0.0/16
├── Storage: 150 GB vSAN allocation
└── Capacity: 24 vCPU, 96 GB RAM allocated

PROD ENVIRONMENT (Weeks 9-16)
├── Kubernetes Cluster: k8s-prod
├── Nodes: 3M + 12W = 15 total VMs (includes QA/PREPROD masters)
├── Isolation: Separate namespace, VLAN 120
├── Networking: 10.52.0.0/16
├── Storage: 200 GB vSAN allocation
└── Capacity: 64 vCPU, 256 GB RAM allocated
```

---

## Physical Infrastructure

### Dell VxRail HCI Cluster

```
Model: Dell VxRail E560F (Flex Edition)
Node Count: 6 nodes
Chassis: 2U form factor per node
Redundancy: N+1 (can survive 1 node failure)

Per-Node Specifications:
├── Processor: 2x Intel Xeon Platinum 8360Y (32 cores, 2.4 GHz)
├── Memory: 512 GB DDR4 (8x 64 GB RDIMM)
├── Storage:
│   ├── 2x 480 GB SSD (boot disk, RAID 1)
│   ├── 6x 7.68 TB NVMe (vSAN capacity tier)
│   └── 12x 18 TB HDD (vSAN capacity tier, RAID 6)
├── Network:
│   ├── 4x 10 GbE ports (converged)
│   └── 1x 1 GbE management port
└── Out-of-Band Management: iDRAC9 with secure boot

Cluster Specifications:
├── Total CPU Capacity: 871.58 GHz (149.84 GHz used, 721.75 GHz free)
├── Total Memory: 4.5 TB (3.11 TB used, 1.38 TB free)
├── vSAN Total Capacity: 247.66 TB (9 datastores)
├── vSAN Used: 156.8 TB | Free: 90.86 TB
├── Network Throughput: 240 Gbps aggregate (6 × 40 Gbps)
└── Power Consumption: ~18 kW per node, ~108 kW total
```

### Network Infrastructure

```
Physical Network Design:
┌─────────────────────────────────────┐
│  Core Network Switch               │
│  (10GbE, L3 routing)               │
└─────────────┬───────────────────────┘
              │
    ┌─────────┴─────────┐
    │                   │
┌───────┐           ┌───────┐
│ Leaf  │           │ Leaf  │
│ Sw 1  │           │ Sw 2  │
│(LACP) │           │(LACP) │
└───────┘           └───────┘
    │                   │
    └─────────┬─────────┘
              │
    ┌─────────────────────────┐
    │ VxRail Cluster          │
    │ Node 1 │ Node 2         │
    │ Node 3 │ Node 4         │
    │ Node 5 │ Node 6         │
    └─────────────────────────┘

Physical Links:
- Each node: 4x 10GbE ports
- Link 1-2: vSAN traffic (redundant pair)
- Link 3-4: VM/management traffic (LACP bonded)
- All links: VLAN tagging enabled
- Jumbo frames: 9000 MTU for vSAN
```

---

## Virtual Infrastructure

### vSphere Cluster Configuration

```
vCenter Server: vcs.internal.domain
vSphere Version: 8.0 U1
Datacenter: DC-OnPrem
Cluster: Cluster-VxRail

Host Configuration:
├── 6 ESXi hosts (fully meshed)
├── Network Time Protocol: Enabled (to NTP server)
├── vSphere HA: Enabled (4-node quorum)
├── vSphere DRS: Enabled (balanced mode)
├── vSAN: Enabled (2-node fault tolerance)
└── Multipathing: ROUND-ROBIN

vSAN Configuration:
├── Fault Tolerance Level: FTT = 1 (can lose 1 node)
├── Stripe Width: 1 (single stripe)
├── Object Space Reservation: 10%
├── Compression: Enabled (25-40% reduction)
├── Deduplication: Enabled (depends on workload)
├── Encryption: Enabled (AES-256)
├── Health Check: Daily
└── Rebuild Priority: Low priority (not to impact workloads)
```

### Virtual Machine Specifications

#### Kubernetes Master Nodes (3 VMs — shared across all environments)

```
VM Configuration (per master node):
├── CPU:     8 vCPUs  (+25% buffer vs minimum 4 vCPU)
├── Memory:  32 GB RAM (+60% buffer vs minimum 16 GB; handles etcd + API server growth)
├── Storage: 150 GB   (OS 50 GB + etcd 50 GB + logs/buffers 50 GB — thin provisioned)
├── Network: 2x vNICs (VMXNET3; 1 cluster/pod network, 1 storage/vSAN)
├── OS:      Oracle Linux 9 (minimal install)
└── Runtime: containerd 1.7+

WHY these master specs:
  - 8 vCPUs: API server, scheduler, controller-manager all run here; 8 leaves headroom
    for bursts and future K8s upgrades adding new controllers
  - 32 GB RAM: etcd alone uses 2–4 GB; API server 4–8 GB; 32 GB gives 50%+ free buffer
    for unexpected load (e.g., large kubectl list operations, admission webhooks)
  - 150 GB disk: etcd data grows ~1 GB/month; logs accumulate; 150 GB = 3+ years buffer

Static IPs:
  k8s-master-01: 10.50.0.10 (QA) / 10.51.0.10 (PREPROD) / 10.52.0.10 (PROD)
  k8s-master-02: 10.50.0.11 (QA) / 10.51.0.11 (PREPROD) / 10.52.0.11 (PROD)
  k8s-master-03: 10.50.0.12 (QA) / 10.51.0.12 (PREPROD) / 10.52.0.12 (PROD)
  VIP (HAProxy): 10.50.0.100 (QA) / 10.51.0.100 (PREPROD) / 10.52.0.100 (PROD)

HA:
  ├── Anti-affinity rule: each master on a different VxRail physical host
  ├── vSphere HA: restart priority = HIGH
  ├── kubeadm HA: stacked etcd (etcd co-located with master)
  └── HAProxy VIP: routes kubectl + API traffic to any healthy master
```

#### Kubernetes Worker Nodes — Sizing with Buffer

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                   WORKER NODE VM SIZING (with growth buffer)                     │
├──────────────┬────────────┬───────────┬──────────────┬────────────────────────── │
│ Environment  │ Count      │ vCPU      │ RAM          │ Storage (vSAN thin prov.) │
├──────────────┼────────────┼───────────┼──────────────┼─────────────────────────  │
│ QA           │ 3 workers  │ 12 vCPU   │ 48 GB        │ 200 GB per node           │
│              │            │ (+50% buf)│ (+50% buf)   │ (+100% vs 100GB baseline) │
├──────────────┼────────────┼───────────┼──────────────┼─────────────────────────  │
│ PREPROD      │ 9 workers  │ 16 vCPU   │ 64 GB        │ 250 GB per node           │
│              │            │ (+100% vs │ (+100% buf)  │ (+150% vs baseline)       │
│              │            │  QA min.) │              │                           │
├──────────────┼────────────┼───────────┼──────────────┼─────────────────────────  │
│ PROD         │ 12 workers │ 24 vCPU   │ 96 GB        │ 300 GB per node           │
│              │            │ (+50% vs  │ (+50% vs     │ (persistent vol headroom) │
│              │            │  PREPROD) │  PREPROD)    │                           │
└──────────────┴────────────┴───────────┴──────────────┴─────────────────────────  ┘

WHY these worker specs:
  QA (12vCPU / 48GB / 200GB):
  - 12 vCPU: runs ~10-15 pods; 12 vCPU allows pod bursts without OOMKiller
  - 48 GB: each Java pod = 1-2 GB; Node.js = 200-500 MB; 48 GB = room for 30+ pods
  - 200 GB: PersistentVolumes, image layers, emptyDir, logs; 200 GB = 2yr+ headroom

  PREPROD (16vCPU / 64GB / 250GB):
  - Matches production sizing more closely → performance tests are representative
  - 64 GB handles 3K concurrent-user load without memory pressure
  - 250 GB: more PVs, larger database staging areas

  PROD (24vCPU / 96GB / 300GB):
  - 30% OVER current load as headroom for traffic growth
  - 96 GB: peak load + 40% = ~67 GB; 96 GB = 40%+ buffer before needing new nodes
  - 300 GB: accommodates future StatefulSet PVs, log volumes, growing datasets

Total New VM Footprint:
  ├── QA:      3W × (12vCPU, 48GB, 200GB) + 3M × (8vCPU, 32GB, 150GB)
  │            = 60 vCPU, 240 GB RAM, 1.05 TB storage
  ├── PREPROD: 9W × (16vCPU, 64GB, 250GB) + 3M × (8vCPU, 32GB, 150GB)
  │            = 168 vCPU, 672 GB RAM, 2.7 TB storage
  └── PROD:    12W × (24vCPU, 96GB, 300GB) + 3M × (8vCPU, 32GB, 150GB)
               = 312 vCPU, 1,248 GB RAM, 4.05 TB storage

  Grand Total VMs: 30 VMs
  Grand Total: ~540 vCPU | ~2.1 TB RAM | ~7.8 TB storage
  Available on VxRail: 721.75 GHz free | 1.38 TB RAM free | 90.86 TB storage free
  ⚠️  Memory: Plan in phases — 2.1 TB > 1.38 TB free
     Mitigation: Migrate QA first, validate, then PREPROD, then PROD.
                 Each phase decommissions Azure = releases cost, not capacity.
                 Memory is the constraint to monitor.
```

#### PostgreSQL Database Node Sizing

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                 DATABASE VM SIZING (3 nodes per environment)                 │
├──────────────┬────────────┬─────────────────┬──────────────────────────────  │
│ Environment  │ Count      │ vCPU / RAM      │ Storage                       │
├──────────────┼────────────┼─────────────────┼──────────────────────────────  │
│ QA (single)  │ 1 VM       │ 8 vCPU / 32 GB  │ 500 GB data + 100 GB OS/log  │
│              │            │                 │ = 600 GB total                │
├──────────────┼────────────┼─────────────────┼──────────────────────────────  │
│ PREPROD HA   │ 3 VMs      │ 16 vCPU / 64 GB │ 500 GB data + 200 GB WAL/log │
│ (Patroni)    │ per node   │ per node        │ = 700 GB per node             │
├──────────────┼────────────┼─────────────────┼──────────────────────────────  │
│ PROD HA      │ 3 VMs      │ 32 vCPU / 128 GB│ 1 TB data + 500 GB WAL/log   │
│ (Patroni)    │ per node   │ per node        │ = 1.5 TB per node             │
└──────────────┴────────────┴─────────────────┴──────────────────────────────  ┘

WHY these DB specs:
  PROD 128GB RAM: shared_buffers = 32 GB (25% of RAM) — PostgreSQL caches most
  of the working dataset in RAM. Current DB ~650 GB; 128 GB RAM caches hot pages
  and dramatically reduces disk I/O.
  
  PROD 1.5 TB storage: 1 TB data × 1.5x growth buffer = immediate headroom,
  500 GB WAL = 7+ days of WAL retention for PITR, log shipping, and debugging.

IPs (VLAN 30 — Database network, isolated):
  QA:      pg-qa-01:       10.30.0.100 (pgBouncer VIP: 10.30.0.50)
  PREPROD: pg-preprod-01:  10.30.0.110, -02: .111, -03: .112 (VIP: 10.30.0.100)
  PROD:    pg-prod-01:     10.30.0.120, -02: .121, -03: .122 (VIP: 10.30.0.200)
```

---

## Kubernetes Architecture

### Cluster Design (Per Environment)

```
KUBERNETES CLUSTER TOPOLOGY:

┌─────────────────────────────┐
│   Kubernetes Master Nodes   │ (3 replicas)
│   (etcd, API, Scheduler)    │
│   HA Enabled via Patroni    │
└──────────────┬──────────────┘
               │
        ┌──────┴──────┐
        │             │
    ┌───────┐    ┌───────┐
    │Worker │    │Worker │  (Multiple, environment dependent)
    │Nodes  │    │Nodes  │
    └───────┘    └───────┘

Network Overlay: Calico v3.27.0 (BGP-based)
├── Pod CIDR: 10.x.0.0/16 (x varies by environment)
├── Service CIDR: 10.96.0.0/12
├── Node IP Range: 10.5x.0.0/24 (x varies by environment)
└── Load Balancer: MetalLB v0.13.12

Persistent Volume Storage:
├── Default SC: vSAN-SC (vSphere CSI driver)
├── Storage Policy: vSAN-Platinum (for stateful apps)
├── Snapshot Support: Enabled
└── Reclaim Policy: Delete (production: manual review)
```

### Critical Kubernetes Settings

```yaml
Kubernetes Version: 1.34.x
Container Runtime: containerd v1.7.x
CRI Socket: unix:///run/containerd/containerd.sock

kubeadm init parameters:
  --kubernetes-version=v1.34.0
  --pod-network-cidr=10.5x.0.0/16
  --service-cidr=10.96.0.0/12
  --cri-socket=unix:///run/containerd/containerd.sock
  --upload-certs
  --certificate-key=<random-key>

CNI Configuration:
  calico_backend: vxlan
  mtu: 1500
  cross_subnet: true

Kubelet Configuration:
  max-pods: 110
  image-gc-high-threshold: 85
  image-gc-low-threshold: 80
  eviction-hard:
    - memory.available<100Mi
    - nodefs.available<10%
    - nodefs.inodesFree<5%
```

---

## Database Architecture

### PostgreSQL Patroni HA Cluster

```
QA Database (Single Instance - Week 1-3):
├── Single PostgreSQL 14 VM
├── Backup: Daily snapshots
└── HA: Not required (test environment)

PREPROD Database (Patroni HA - Weeks 4-8):
├── 3 PostgreSQL 14 nodes (Patroni)
├── Patroni Cluster Name: preprod-postgres
├── VIP/Endpoint: postgres.preprod.internal (10.51.10.10)
├── Automatic Failover: Enabled
├── Replication: Streaming replication (synchronous)
├── Backup: Daily (pg_basebackup)
└── WAL Archiving: To vSAN NFS storage

PROD Database (Patroni HA - Weeks 9-16):
├── 3 PostgreSQL 14 nodes (Patroni)
├── Patroni Cluster Name: prod-postgres
├── VIP/Endpoint: postgres.prod.internal (10.52.10.10)
├── Automatic Failover: Enabled (< 30 seconds)
├── Replication: Streaming replication (synchronous)
├── pglogical Replication: From Azure (during Week 12-15)
├── Backup: Hourly (pg_basebackup)
├── WAL Archiving: To vSAN NFS storage
└── PITR Retention: 7 days

Patroni Configuration:
├── etcd Cluster: 3 nodes (same VMs as PostgreSQL)
├── Quorum: 2/3 nodes required for decisions
├── Leader Election TTL: 30 seconds
├── Loop Wait: 10 seconds
├── Maximum Lag Bytes: 1 MB
└── Retry Timeout: 30 seconds
```

### MongoDB/Cosmos DB Alternative

```
MongoDB Replicaset (Alternative to Cosmos DB):
├── 3 replica nodes
├── Replicaset Name: rs0
├── Primary Node: mongo-prod-01
├── Secondary Nodes: mongo-prod-02, mongo-prod-03
├── Arbiter: (optional, could be 4-node)
├── Oplog Size: 10 GB
├── Replication Lag Target: < 1 second
└── Backup: Hourly snapshots via Veeam

Collections (from Cosmos DB):
├── users: Indexed on _id, email
├── sessions: TTL index (24 hours)
├── events: Sharded by date (if >1 TB)
└── cache: TTL index (auto-cleanup)
```

---

## Storage Architecture

### vSAN Storage Pools

```
vSAN Datastore Configuration:
├── Total Capacity: 247.66 TB total capacity, 90.86 TB free (after FTT=1 + overhead)
├── Allocated to Kubernetes: 200 TB
├── Reserved for System/Buffer: 50 TB

Storage Allocation by Environment:
├── QA: 50 TB (persistent volumes + snapshots)
├── PREPROD: 75 TB (load testing data + archives)
├── PROD: 150 TB (production data + WAL files)
└── Buffer/Snapshots: 20 TB for all environments

Storage Classes:

1. vsan-platinum (for PROD stateful apps)
   ├── RAID: 1 (mirrored)
   ├── Failure Tolerance: 1 node
   ├── Stripe Width: 1
   ├── Cache Reservation: 25%
   ├── Object Space Res: 30%
   └── Forceprovisioning: true

2. vsan-gold (for PREPROD, resilient)
   ├── RAID: 1
   ├── Failure Tolerance: 1 node
   ├── Stripe Width: 1
   ├── Cache Reservation: 15%
   └── Object Space Res: 20%

3. vsan-silver (for QA, cost-optimized)
   ├── RAID: 5
   ├── Failure Tolerance: 2 disks
   ├── Stripe Width: 4
   ├── Cache Reservation: 10%
   └── Object Space Res: 10%
```

### Persistent Volume Strategy

```
Oracle Linux VMs (Masters/Workers):
├── Boot Disk: 100 GB (vSAN-backed RAID-1)
├── Container Storage: /var/lib/containers (thin provisioned)
└── kubelet Storage: /var/lib/kubelet (vSAN CSI mounted)

PostgreSQL Data:
├── WAL Storage: 50 GB (fast vSAN NVMe tier)
├── Data Directory: 200 GB (vSAN capacity tier)
├── Backup Storage: 100 GB (vSAN, compressed)
└── Snapshot Storage: 50 GB (vSAN retention)

Application Persistent Volumes:
├── Database PVCs: 150 GB (PROD)
├── File Storage PVCs: 100 GB (PROD)
├── Log Storage PVCs: 50 GB (7-day retention)
└── Cache Storage PVCs: 30 GB (local node SSD preference)
```

---

## Networking Architecture

### VLAN Segmentation

```
VLAN Layout:
├── VLAN 10: vSAN Network (10.5.0.0/24)
│   └── Gateway: 10.5.0.1 (management cluster router)
│
├── VLAN 20: vSphere Management (10.20.0.0/24)
│   ├── vCenter: 10.20.0.10
│   ├── ESXi Hosts: 10.20.0.100 - 10.20.0.105
│   └── Gateway: 10.20.0.1
│
├── VLAN 100: QA Kubernetes Cluster (10.50.0.0/16)
│   ├── Node IP Range: 10.50.0.0/24
│   ├── Service IP Range: 10.96.0.0/12 (overlapping across all clusters)
│   ├── Pod CIDR: 10.200.0.0/16
│   └── Gateway: 10.50.0.1
│
├── VLAN 110: PREPROD Kubernetes Cluster (10.51.0.0/16)
│   ├── Node IP Range: 10.51.0.0/24
│   ├── Pod CIDR: 10.201.0.0/16
│   └── Gateway: 10.51.0.1
│
├── VLAN 120: PROD Kubernetes Cluster (10.52.0.0/16)
│   ├── Node IP Range: 10.52.0.0/24
│   ├── Pod CIDR: 10.202.0.0/16
│   └── Gateway: 10.52.0.1
│
├── VLAN 30: Database Servers (10.30.0.0/24)
│   ├── PostgreSQL VIP: 10.30.0.10
│   └── MongoDB Replicas: 10.30.0.20 - 10.30.0.22
│
├── VLAN 40: Backup & Monitoring (10.40.0.0/24)
│   ├── Veeam Backup Server: 10.40.0.10
│   ├── NAS Backup Storage: 10.40.0.20
│   ├── Prometheus/Grafana: 10.40.0.30
│   └── ELK Stack: 10.40.0.40 - 10.40.0.42
│
└── VLAN 1: Out-of-Band Management
    ├── iDRAC Interfaces: 192.168.1.100 - 192.168.1.105 (all nodes)
    ├── vCenter vMotion: VLAN 1
    └── Gateway: 192.168.1.1
```

### Firewall Rules (Between Zones)

```
Ingress to PROD Cluster (10.52.0.0/16):
├── From On-Premises (10.200.0.0/8): All traffic allowed
├── From Azure VPN: Restricted (API server 6443, app traffic 443)
├── From Internet: HTTPS (443) only, blocked (no direct public IPs)
└── From Other Clusters: DENY (network isolation)

PROD to External:
├── To Azure (via VPN): PostgreSQL/Cosmos replication (5432, 27017)
├── To Internet: HTTPS (443) only (for OS patches, container pulls)
└── To Backup Storage (VLAN 40): All traffic allowed

Between Clusters (QA↔PREPROD↔PROD):
├── DENY all (network isolation for separation)
└── Exception: Shared monitoring (Vlan 40) allowed from all

Database VLAN (10.30.0.0/24):
├── Allowed from Kubernetes clusters: PostgreSQL (5432), MongoDB (27017)
├── Allowed from backup VLAN: Backup traffic
└── Denied from internet: All traffic blocked (internally only)
```

### Load Balancing

```
MetalLB Configuration:
├── Mode: BGP (announcing routes to upstream router)
├── Address Pool: 10.50.100.0/24 (QA), 10.51.100.0/24 (PREPROD), 10.52.100.0/24 (PROD)
├── AS Number: 65000 (internal)
└── Peer Router AS: 65001 (network infrastructure)

Service Ingress Design:
├── External LoadBalancer Service (API ingress)
│   └── Assigned IP: From MetalLB pool
├── ClusterIP Services (internal service-to-service)
│   └── Internal DNS: service.namespace.svc.cluster.local
└── NodePort Services (for legacy apps, if needed)
    └── Ports: 30000-32767 range

DNS Configuration:
├── In-cluster DNS: CoreDNS (10.96.0.10)
├── External DNS: Route upstream to on-premises DNS
├── Service Discovery: kubernetes.default.svc.cluster.local
└── Pod DNS: pod-ip.namespace.pod.cluster.local (if required)
```

---

## Backup & Disaster Recovery

### Backup Strategy

```
Veeam Backup Configuration (on-premises):
├── Backup Server: Veeam VM (8 vCPU, 32 GB RAM)
├── Backup Repository: 500 GB local NAS (separate from vSAN)
├── Deduplication: Enabled (30-50% reduction)
└── Encryption: AES-256

Backup Schedules:

PostgreSQL Backups:
├── Frequency: Hourly (incremental WAL)
├── Full Backup: Daily (Sunday midnight)
├── Retention: 30 days
├── Method: pg_basebackup + WAL archiving
└── RPO: 1 hour

Kubernetes PVCs:
├── Frequency: Daily
├── Full Backup: Weekly
├── Retention: 14 days
├── Method: vSAN snapshots + Veeam integration
└── RPO: 24 hours

VM Snapshots:
├── Frequency: Hourly
├── Retention: 6 hours (quick restore)
├── Cold Snapshots: Weekly (archived to NAS)
└── RPO: 1 hour

Application Data:
├── Database: See PostgreSQL above
├── Files: Daily backup to NAS
├── Configs: Git-based (version controlled)
└── Secrets: Encrypted backup to Air-gapped storage

Backup Verification:
├── Restore Test: Weekly (one random database)
├── Backup Integrity Check: Daily
├── Backup Log Review: Daily by ops team
└── Audit Log: All backups logged for compliance
```

### Disaster Recovery Architecture

```
Primary Site (On-Premises VxRail):
├── Kubernetes Clusters: k8s-qa, k8s-preprod, k8s-prod
├── Databases: PostgreSQL Patroni HA (3-node)
├── Storage: vSAN (247.66 TB total, 90.86 TB free)
├── Backup: Veeam (local NAS)
└── Objective: Normal operations

Secondary Site (Azure or Cold Standby):
├── Option A: Azure VMs (standby, periodic sync)
├── Option B: Local NAS (DR copies only, no live VMs)
├── Option C: Stretched vSAN cluster (same 6 nodes, different sites)
├── Database Replica: PostgreSQL read-only replica (Azure)
└── Objective: Recover within RTO/RPO targets

RTO/RPO Targets:
├── Database: RTO 2 hours, RPO 1 hour
├── Kubernetes Workloads: RTO 4 hours, RPO 24 hours
├── File Storage: RTO 24 hours, RPO 24 hours
└── Configuration: RTO 1 hour, RPO near-zero (Git-based)

Failover Procedure:
1. Detect primary site failure
2. Promote standby site (database promotion)
3. Update DNS to point to secondary
4. Start VMs on secondary from backups
5. Validate application health
6. Notify users of failover
```

---

## Monitoring & Observability

### Prometheus + Grafana Stack

```
Prometheus Configuration:
├── Instances: 2 (for redundancy, no HA cluster)
├── Storage: 500 GB (vSAN-backed)
├── Retention: 15 days
├── Scrape Interval: 30 seconds
├── Evaluation Interval: 1 minute
└── Data Redundancy: Snapshots every 6 hours

Dashboards (50+ custom):
├── Cluster Health (nodes, pods, resources)
├── Application Performance (latency, throughput, errors)
├── Database Metrics (queries, replication, connections)
├── Network Performance (bandwidth, latency, packet loss)
├── Storage Metrics (capacity, IOPS, latency)
├── Backup Status (backup duration, success rate)
└── Business Metrics (user count, transactions, revenue)

Alerting Rules:
├── High: CPU > 80%, Memory > 85%, Disk > 90%
├── High: Pod restart rate > 5/hour
├── High: Database replication lag > 5 seconds
├── High: Backup failure (on-call alert)
├── Medium: Network latency > 100ms
├── Medium: Query time p95 > 500ms
└── Low: Disk forecast filled in < 7 days

Alert Routing:
├── Critical → PagerDuty (on-call engineer)
├── High → Email + Slack + SMS
├── Medium → Slack + Email
└── Low → Slack only
```

### ELK Stack (Elasticsearch, Logstash, Kibana)

```
Elasticsearch Cluster:
├── Nodes: 3 (master + data)
├── Shards: 3 (per index)
├── Replicas: 1
├── Index Rotation: Daily
├── Retention: 30 days (cold storage: archived)
└── Storage: 1.5 TB (vSAN-backed)

Log Sources:
├── Kubernetes Events: kubelet logs, pod events
├── Container Logs: application stdout/stderr
├── System Logs: kernel, systemd, syslog
├── Database Logs: PostgreSQL query log, slow query log
├── Application Logs: custom application logging
├── Backup Logs: Veeam backup status
└── Firewall Logs: Network device logs (syslog)

Logstash Pipeline:
├── Input: Fluentd (collecting from containers)
├── Filter: Parse, enrich, tag by source
├── Output: Elasticsearch (index per environment)
└── Performance: 10K events/sec capacity

Kibana Dashboards:
├── Log Analysis: Search, filter, aggregate logs
├── Performance Analysis: Query time, throughput
├── Error Tracking: Error rate, stack traces
├── User Activity: Login, actions, behavior
└── Compliance: Audit trails, security events
```

---

## Security Architecture

### Network Security

```
Firewall Zones:
├── Zone 1: On-Premises Network (trusted)
├── Zone 2: VxRail Cluster (internal, semi-trusted)
├── Zone 3: Kubernetes Pods (isolated, untrusted)
└── Zone 4: Internet (untrusted)

Network Policies (Kubernetes):
├── Default: DENY all traffic
├── Ingress: Only allow API gateway traffic
├── Egress: Only allow to databases, internet APIs
└── DNS: Allow only to CoreDNS (10.96.0.10)

Encryption:
├── Data at Rest: AES-256 (vSAN encryption)
├── Data in Transit: TLS 1.3 (all services)
├── Database Encryption: PostgreSQL pgcrypto
└── Backup Encryption: AES-256 (Veeam)
```

### RBAC & Access Control

```
Kubernetes RBAC:
├── ServiceAccounts: One per microservice
├── Roles: Defined by namespace (least privilege)
├── ClusterRoles: For cluster-wide operations
├── RoleBindings: Bind roles to ServiceAccounts
└── Audit Logging: All API requests logged

SSH Access:
├── Bastion Host: Jump server for cluster access
├── SSH Keys: Stored in secure vault (HashiCorp Vault)
├── Session Recording: All sessions recorded for audit
├── Multi-Factor Auth: Required for bastion access
└── Account Lockout: After 3 failed attempts

Container Registry Access:
├── Harbor Registry: Private, on-premises
├── Authentication: LDAP + OIDC
├── Image Signing: Cosign for image verification
├── Vulnerability Scanning: Trivy integration
└── Pull Secrets: Kubernetes imagePullSecrets
```

---

## Capacity Planning Summary

| Environment | Masters | Workers | Total Nodes | CPU | Memory | Storage |
|-------------|---------|---------|-------------|-----|--------|---------|
| QA | 3 | 3 | 6 | 24 | 96 GB | 50 GB |
| PREPROD | shared | 9 | 9 | 72 | 288 GB | 75 GB |
| PROD | 3 | 12 | 15 | 120 | 480 GB | 150 GB |
| **Total** | **3** | **24** | **30** | **216** | **864 GB** | **275 GB** |

**Note**: Masters are shared across all environments but dedicated to PROD during production phase.

---

**End of Target State Architecture Document**

Reference: [02-Current-State-Architecture.md](./02-Current-State-Architecture.md), [04-Pre-Migration-Checklist.md](./04-Pre-Migration-Checklist.md), [05-QA-Detailed-Implementation.md](./05-QA-Detailed-Implementation.md)

