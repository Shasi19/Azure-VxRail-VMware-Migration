# Azure to VxRail On-Premises Migration
## Migration Presentation — Full Story

> **Audience:** Management, architects, project sponsors  
> **Purpose:** Complete picture — why migrate, current state, target state, plan, risks, ROI

---

## 1. Why Are We Migrating?

```
┌──────────────────────────────────────────────────────────────────┐
│                    THE PROBLEM WITH AZURE TODAY                  │
├──────────────────────────────────────────────────────────────────┤
│  💰 Cost:           ~$7,945/month → ~$95,000/year on Azure       │
│  🔒 Lock-in:        Proprietary services (Cosmos, ACR, AKS)      │
│  📍 Data residency: Data stored in Microsoft data centres        │
│  🚀 Performance:    Network latency to Azure adds overhead       │
│  📋 Compliance:     Upcoming regulatory requirements for on-prem │
└──────────────────────────────────────────────────────────────────┘

WHY VXRAIL SPECIFICALLY?
  ✅ Already own the hardware (6-node Dell VxRail HCI cluster)
  ✅ Already have VMware vSphere licences (included with VxRail)
  ✅ Already have Veeam Backup deployed
  ✅ Team already uses Oracle Linux VMs
  ✅ Zero new hardware capex required (migration uses existing cluster)
  ✅ Estimated savings: $70,000–85,000/year after migration costs
```

---

## 2. Current State — Azure Architecture

```
                         AZURE CLOUD (Today)
┌─────────────────────────────────────────────────────────────────────┐
│              Hub Subscription (Sub-AFRPS-AF-INT)                    │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  Azure VPN Gateway  │  Azure Firewall  │  Azure DNS Zones    │   │
│  └─────────────────────────────────────────────────────────────┘    │
│                     Hub VNet — 10.0.0.0/16                          │
└────────────────┬──────────────┬──────────────┬──────────────────────┘
                 │              │              │
    ┌────────────▼──┐  ┌────────▼──────┐  ┌───▼────────────┐  ┌──────────────────┐
    │  DEV VNet      │  │  QA VNet      │  │ PREPROD VNet   │  │  PROD VNet        │
    │                │  │               │  │                │  │                   │
    │  AKS Cluster   │  │  AKS Cluster  │  │  AKS Cluster   │  │  AKS Cluster      │
    │                │  │               │  │                │  │  (Spot + Sys pool)│
    │  Cosmos DB     │  │  Cosmos DB    │  │  Cosmos DB     │  │  Cosmos DB        │
    │  (Mongo API)   │  │  (Mongo API)  │  │  (Mongo API)   │  │  (Multi-region)   │
    │                │  │               │  │                │  │                   │
    │  PostgreSQL    │  │  PostgreSQL   │  │  PostgreSQL    │  │  PostgreSQL HA    │
    │  Flexible      │  │  Flexible     │  │  Flexible      │  │  + Read Replica   │
    │                │  │               │  │                │  │                   │
    │  ACR           │  │  ACR          │  │  ACR           │  │  ACR (Geo-rep)    │
    │  Storage Acct  │  │  Storage Acct │  │  Storage Acct  │  │  Storage (RA-GRS) │
    └────────────────┘  └───────────────┘  └────────────────┘  └───────────────────┘

MONTHLY COST BREAKDOWN:
  AKS (all envs):       $3,200 / month
  Cosmos DB (all envs): $1,800 / month
  PostgreSQL (all envs):$1,900 / month
  ACR + Storage:        $  345 / month
  Networking + VPN:     $  700 / month
  ─────────────────────────────────────
  TOTAL:               ~$7,945 / month  →  ~$95,340 / year
```

### Azure Services in Use

| Service | Purpose | Limitation on Azure |
|---------|---------|-------------------|
| AKS | Container orchestration | $3,200/mo; version upgrade complexity |
| Azure Cosmos DB (MongoDB API) | Document database | Expensive at scale; RU/s billing unpredictable |
| Azure PostgreSQL Flexible | Relational database | Managed but costly; limited tuning |
| Azure Container Registry | Docker image storage | Per-environment ACR = 4× cost |
| Azure Storage Account | Blob / file storage | Egress costs; data residency concern |
| Azure VNet | Network isolation | Cannot extend to on-prem natively |

---

## 3. What We Have On-Premises Today

```
YOUR EXISTING DATA CENTRE — BEFORE MIGRATION
──────────────────────────────────────────────────────────────────────

  ┌─────────────────────────────────────────────────────────────┐
  │            DELL VxRail HCI CLUSTER (6 Nodes)                │
  │         Already owned, already running, already paid for    │
  │                                                             │
  │  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌──────────┐ ┌────────┐ │
  │  │VxRail-1│ │VxRail-2│ │VxRail-3│ │VxRail-4│ │VxRail-5 │ │VxRail-6│ │
  │  │ESXi 8.x│ │ESXi 8.x│ │ESXi 8.x│ │ESXi 8.x│ │ESXi 8.x │ │ESXi 8.x│ │
  │  │NVMe    │ │NVMe    │ │NVMe    │ │NVMe    │ │NVMe     │ │NVMe    │ │
  │  └────────┘ └────────┘ └────────┘ └────────┘ └──────────┘ └────────┘ │
  │                     vSAN Datastore (pooled NVMe)                    │
  │               ~15–30 TB usable (after FTT=1 redundancy)             │
  │                                                                     │
  │  Already Running:                                                   │
  │  ✅ Oracle Linux VMs (existing workloads)                           │
  │  ✅ Veeam Backup and Replication (backing up existing VMs)          │
  │  ✅ vCenter Server (central management)                             │
  │  ✅ VxRail Manager (Dell lifecycle management)                      │
  │  ✅ vSphere HA + DRS (auto failover + load balancing)               │
  └─────────────────────────────────────────────────────────────────────┘

CURRENT RESOURCES AVAILABLE FOR MIGRATION:
  CPU:     ~110 cores free (after existing workloads)
  RAM:     ~1.2 TB free
  Storage: ~15 TB vSAN free
  These are sufficient for all 27 migration VMs
```

---

## 4. Target State — On-Premises Architecture After Migration

```
YOUR DATA CENTRE — AFTER MIGRATION
──────────────────────────────────────────────────────────────────────────────

  ┌──────────────────────────────────────────────────────────────────────┐
  │                  DELL VxRail HCI CLUSTER (Same 6 Nodes)              │
  │                                                                      │
  │   MANAGEMENT VLAN 10 (10.0.1.0/24)                                  │
  │   ┌──────────┐  ┌─────────────┐  ┌────────────┐  ┌──────────────┐  │
  │   │ vCenter  │  │  VxRail Mgr │  │  Jump Host │  │  DNS (BIND9) │  │
  │   │ (exists) │  │  (exists)   │  │  Ansible   │  │  NTP, CA     │  │
  │   └──────────┘  └─────────────┘  └────────────┘  └──────────────┘  │
  │                                                                      │
  │   KUBERNETES CONTROL PLANE — VLAN 30 (10.0.3.0/24)                 │
  │   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  VIP:          │
  │   │ k8s-master-1│  │ k8s-master-2│  │ k8s-master-3│  10.0.3.100   │
  │   │  OL9 VM     │  │  OL9 VM     │  │  OL9 VM     │  (keepalived) │
  │   └─────────────┘  └─────────────┘  └─────────────┘                │
  │                                                                      │
  │   KUBERNETES WORKERS — VLAN 40 (10.0.4.0/24)                       │
  │   ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐ │
  │   │ worker-1/2       │  │ worker-3/4       │  │ worker-5/6       │ │
  │   │ Dev + QA         │  │ PreProd          │  │ Prod             │ │
  │   │ OL9 VMs 8vCPU   │  │ OL9 VMs 12vCPU  │  │ OL9 VMs 16vCPU  │ │
  │   └──────────────────┘  └──────────────────┘  └──────────────────┘ │
  │   MetalLB Pool: 10.0.4.200–220 (LoadBalancer IPs for K8s services) │
  │                                                                      │
  │   DATABASES — VLAN 50 (10.0.5.0/24)                                │
  │   PostgreSQL 15:                    MongoDB 7.0:                    │
  │   ┌──────────────────────────┐      ┌────────────────────────────┐  │
  │   │ dev-01  (standalone)     │      │ dev-01  (standalone) OL9   │  │
  │   │ qa-01   (standalone)     │      │ qa-01   (standalone) OL9   │  │
  │   │ preprod-01/02 Patroni HA │      │ preprod RS (2 nodes) OL9   │  │
  │   │ prod-01/02/03 Patroni HA │      │ prod RS  (3 nodes)   OL9   │  │
  │   └──────────────────────────┘      └────────────────────────────┘  │
  │                                                                      │
  │   SERVICES — VLAN 60 (10.0.6.0/24)                                 │
  │   ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐ │
  │   │ Harbor       │  │  MinIO       │  │  Prometheus + Grafana     │ │
  │   │ (Container   │  │  (S3-compat  │  │  (monitoring-01 OL9)     │ │
  │   │  Registry)   │  │   Storage)   │  │                          │ │
  │   └──────────────┘  └──────────────┘  └──────────────────────────┘ │
  │   ┌──────────────────────────────────────────────────┐              │
  │   │ vxrail-vbr-01 (Veeam B&R Server — Windows 2022) │              │
  │   │ Backs up ALL 27 VMs via VMware APIs              │              │
  │   └──────────────────────────────────────────────────┘              │
  │                      vSAN Datastore                                  │
  └──────────────────────────────────────────────────────────────────────┘
          │
          │ Site-to-site VPN (during migration only — decommissioned at end)
          ▼
    Azure Cloud (source — decommissioned at Week 32)
```

---

## 5. Azure → On-Prem: What Replaces What

```
AZURE SERVICE              ON-PREM REPLACEMENT         KEY POINT
─────────────────────────────────────────────────────────────────────
AKS                    →   Kubernetes 1.29 (kubeadm)   Same API, same YAML
                           on Oracle Linux 9 VMs

Azure Cosmos DB        →   MongoDB 7.0 ReplicaSet      Wire-protocol compatible
(MongoDB API)              3-node RS for Prod           App code unchanged

Azure PostgreSQL        →   PostgreSQL 15 + Patroni     Same SQL, pglogical for
Flexible Server            HA on OL9 VMs               live migration

Azure Container        →   Harbor                      Same docker push/pull
Registry (ACR)                                         interface

Azure Storage Account  →   MinIO                       S3-compatible API
                                                        (minimal app changes)

Azure VNet             →   VMware DVS Port Groups       Same isolation model
                           (VLANs 10/30/40/50/60)

Azure Load Balancer    →   MetalLB (K8s)               Same LoadBalancer type
                           + keepalived (PG VIP)

Azure Monitor          →   Prometheus + Grafana         Equivalent dashboards

Azure Backup           →   Veeam B&R v12               Already deployed!
(+ Site Recovery)          + Kasten K10 for K8s

Azure DNS              →   BIND9 on OL9 VM             Internal resolution
Private Zones
```

---

## 6. Migration Approach — 32-Week Phased Plan

```
PHASE 0: PLANNING AND PROCUREMENT (Weeks 1–8)
  ├── Week 1–2:   Architecture review, team alignment, VxRail audit
  ├── Week 3:     Order switch/NAS (8-week hardware lead time)
  ├── Week 4:     Get Change Request approvals
  ├── Week 5–7:   Hardware delivery window
  └── Week 8:     Hardware racked + foundation setup (DNS, NTP, CA, VPN)

PHASE 1: INFRASTRUCTURE BUILD (Weeks 9–13)
  ├── Create Oracle Linux 9 VM template
  ├── Clone all 27 VMs via govc
  ├── Configure DVS VLANs + firewalld
  ├── Set up vSAN CSI + StorageClasses
  ├── Build Kubernetes HA cluster (3 masters + 6 workers)
  ├── Configure Veeam backup jobs for all VMs
  └── Deploy Harbor, ArgoCD, Prometheus

PHASE 2: DEV + QA MIGRATION (Weeks 13–22)  ← Phase 1
  ├── Migrate Dev PostgreSQL (pg_dump → pg_restore)
  ├── Migrate Dev MongoDB (mongodump → mongorestore)
  ├── Deploy Dev application workloads to K8s
  ├── 2-week validation + Dev sign-off
  ├── Repeat for QA environment
  └── DNS cutover: Dev + QA → on-prem

PHASE 3: PREPROD + PROD MIGRATION (Weeks 21–31)  ← Phase 2
  ├── Migrate PreProd (Patroni HA + MongoDB RS)
  ├── PreProd sign-off (2 weeks)
  ├── Start pglogical LIVE replication: Prod PostgreSQL
  ├── Deploy Prod apps to K8s (parallel with Azure)
  ├── Load test + performance validation
  └── Maintenance window: Prod DNS cutover

PHASE 4: STABILISATION (Weeks 31–32)
  ├── 72h hypercare monitoring
  ├── Azure kept as cold standby
  └── Azure decommission when stable
```

---

## 7. Technology Stack — Detailed Comparison

| Layer | Azure (Current) | On-Prem VxRail (Target) | Why This Choice |
|-------|----------------|------------------------|----------------|
| Hypervisor | Azure managed (hidden) | VMware ESXi 8.x (VxRail) | Already owned; enterprise-grade |
| Storage | Azure Managed Disks | vSAN (pooled NVMe) | Already owned; 6-node redundancy |
| Orchestration | AKS (managed) | kubeadm K8s 1.29 | Full control; same K8s API |
| CNI | Azure CNI | Calico v3.27 | NetworkPolicy support; VMware optimised |
| Load Balancer | Azure LB | MetalLB + keepalived | Open source; works without cloud LB |
| Container Registry | ACR | Harbor | CNCF; vulnerability scanning; free |
| Document DB | Cosmos DB (Mongo API) | MongoDB 7.0 Community | Wire-compatible; zero code change |
| Relational DB | Azure PostgreSQL | PostgreSQL 15 + Patroni | Open source HA; pglogical live migration |
| Object Storage | Azure Blob | MinIO | S3-compatible; minimal app change |
| CI/CD | Azure DevOps | ArgoCD + Harbor | GitOps; declarative deployments |
| Monitoring | Azure Monitor | Prometheus + Grafana | Industry standard; custom dashboards |
| Backup | Azure Backup | Veeam B&R v12 | Already deployed! |
| VM OS | Azure managed | Oracle Linux 9 | Team already uses OL9 |

---

## 8. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Hardware delivery delay | Medium | Medium | Order Week 3 (8-week lead time built into plan) |
| Change request approval delay | Medium | Low | Submit Week 4; escalate if delayed past Week 6 |
| Database migration data loss | Low | Critical | Full backup before each migration; pglogical for Prod live sync |
| App incompatibility on on-prem | Low | High | Dev environment first (2-week buffer before QA) |
| K8s version mismatch | Low | Medium | Same K8s 1.29 as AKS; validate manifests in Dev first |
| DNS propagation issues | Low | Medium | Lower TTL to 60s 48h before cutover |
| Prod performance regression | Low | High | 4-week parallel run + load test before cutover |
| Veeam backup failure | Low | High | Daily pre-migration backup jobs; test restore before Phase 1 |
| Team availability | Medium | Medium | 32-week timeline has buffer weeks; training in Weeks 1–4 |
| Azure VPN instability | Low | Medium | strongSwan on jump host as backup to hardware VPN |

---

## 9. Cost Comparison

```
AZURE (Current Annual Cost)
  AKS:             $38,400
  Cosmos DB:       $21,600
  PostgreSQL:      $22,800
  ACR + Storage:    $4,140
  Networking:       $8,400
  ─────────────────────────
  TOTAL:          ~$95,340 / year

ON-PREM VXRAIL (Annual Cost After Migration)
  Hardware:           $0   (already owned)
  VMware licences:    $0   (already owned)
  Veeam licences:  ~$2,400 (verify seat count; may need add-on)
  Oracle Linux:    ~$3,000 (verify OL9 subscription count)
  NAS storage:     ~$1,200 (amortised over 5 years)
  Power + cooling: ~$8,000 (estimated data centre cost)
  Staff (ops):    ~$15,000 (additional ops time estimate)
  ─────────────────────────
  TOTAL:          ~$29,600 / year

ANNUAL SAVING:    ~$65,740 / year
ROI BREAKEVEN:    ~8 months (after one-time migration project costs)
```

---

## 10. Success Criteria

| KPI | Target | How Measured |
|-----|--------|-------------|
| Application availability | 99.9% (Dev/QA), 99.95% (Prod) | Prometheus uptime metric |
| API response time | Within 10% of Azure baseline | Load test comparison (k6) |
| RTO (Recovery Time Objective) | < 30 min (Veeam Instant Recovery) | DR drill during hypercare |
| RPO (Recovery Point Objective) | < 24h (daily Veeam backup) | Backup log verification |
| Migration data integrity | 100% row count match | pg_dump count vs pg_restore count |
| No production incidents during cutover | 0 P1/P2 incidents | Incident log |
| Azure fully decommissioned | All resources deleted by Week 32 | Azure Cost Management = $0 |

---

## 11. Team and Responsibilities

| Role | Responsibility | Phase |
|------|---------------|-------|
| Project Manager | Timeline, approvals, stakeholder updates | All |
| Infrastructure Lead | vSphere, VMs, networking, storage | Phases 0–2 |
| Kubernetes Engineer | K8s cluster, Harbor, ArgoCD, MetalLB | Phase 2 |
| Database Engineer | PostgreSQL migration, MongoDB RS, pglogical | Phases 2–3 |
| Application Engineer | App containerisation, Helm charts, testing | Phases 2–3 |
| Security Engineer | Firewalld, SELinux, TLS certs, Veeam | All |
| Operations | Veeam backup, patching, monitoring | Phase 3 onwards |

---

## 12. What to Read Next

| If you are... | Start with |
|--------------|-----------|
| Executive / approver | This doc ← you are here |
| Infrastructure engineer | [02-Current-Infra-Inventory.md](02-Current-Infra-Inventory.md) |
| Starting the migration now | [00-Index.md](00-Index.md) → follow numbered files |
| Looking for errors / issues | [17-Troubleshooting-Errors.md](17-Troubleshooting-Errors.md) |
| Setting up Veeam | [11-Veeam-Backup.md](11-Veeam-Backup.md) |
| Patching schedule | [16-Patching-Cycles.md](16-Patching-Cycles.md) |
