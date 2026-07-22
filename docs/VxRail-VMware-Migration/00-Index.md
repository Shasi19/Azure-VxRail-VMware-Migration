# VxRail VMware Migration Guide — Master Index

> **Infrastructure:** 6-node Dell VxRail HCI running VMware vSphere  
> **VM OS:** Oracle Linux 9 (OL9) | **Backup:** Veeam Backup and Replication  
> **Source:** Azure (AKS + Cosmos DB + ACR + PostgreSQL + Storage) — Dev/QA/PreProd/Prod  
> **Target:** Kubernetes on VMware OL9 VMs + vSAN storage — same 4 environments  
> **Phase 1 (Weeks 1–8):** Dev + QA | **Phase 2 (Weeks 9–18):** PreProd + Prod

---

## Step-by-Step Flow (Follow This Order)

```
╔══════════════════════════════════════════════════════════════════╗
║               VXRAIL MIGRATION — STEP BY STEP                   ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  STAGE 0 — ASSESSMENT AND PROCUREMENT (Day 0)                   ║
║  ┌────────────────────────────────────────────────────────────┐ ║
║  │ Step 1. Audit current VxRail cluster hardware              │ ║
║  │         → 09-Current-Infra-Inventory.md                   │ ║
║  │ Step 2. Identify what to order (switches, VPN, storage)    │ ║
║  │         → 10-Procurement-Guide.md                         │ ║
║  └────────────────────────────────────────────────────────────┘ ║
║                            │                                     ║
║                            ▼                                     ║
║  STAGE 1 — FOUNDATION SETUP (Days 1–14, before any migration)   ║
║  ┌────────────────────────────────────────────────────────────┐ ║
║  │ Step 3. Set up DNS, NTP, internal CA, Azure VPN, Ansible   │ ║
║  │         → 11-Initial-Setup-Before-Migration.md (15 steps)  │ ║
║  └────────────────────────────────────────────────────────────┘ ║
║                            │                                     ║
║                            ▼                                     ║
║  STAGE 2 — INFRASTRUCTURE BUILD (Week 1–2)                      ║
║  ┌────────────────────────────────────────────────────────────┐ ║
║  │ Step 4. Check vSphere + vSAN capacity and readiness        │ ║
║  │         → 01-Infrastructure-Assessment.md                  │ ║
║  │ Step 5. Create Oracle Linux 9 VM template                  │ ║
║  │         → 13-Oracle-Linux-VMs.md (Section 1–2)             │ ║
║  │ Step 6. Clone all 26 VMs via govc                          │ ║
║  │         → 02-VM-Provisioning-vSphere.md                    │ ║
║  │ Step 7. Configure DVS VLANs, firewalld, MetalLB, VIP       │ ║
║  │         → 03-Network-vSphere.md                            │ ║
║  │ Step 8. Configure vSAN StorageClasses + CSI driver         │ ║
║  │         → 04-Storage-vSAN.md                               │ ║
║  │ Step 9. Build Kubernetes HA cluster (kubeadm 3-master)     │ ║
║  │         → 07-Kubernetes-vSphere.md                         │ ║
║  └────────────────────────────────────────────────────────────┘ ║
║                            │                                     ║
║                            ▼                                     ║
║  STAGE 3 — PHASE 1: DEV + QA MIGRATION (Weeks 3–8)             ║
║  ┌────────────────────────────────────────────────────────────┐ ║
║  │ Step 10. Set up Veeam Backup before data migration         │ ║
║  │          → 14-Veeam-Backup.md (Sections 1–3)               │ ║
║  │ Step 11. Follow week-by-week Phase 1 plan                  │ ║
║  │          → 05-Phase1-Dev-QA.md                             │ ║
║  │          → 12-Migration-Execution.md (detailed commands)   │ ║
║  │ Step 12. DNS cutover for Dev + QA                          │ ║
║  │          → 08-Cutover-Runbook.md                           │ ║
║  └────────────────────────────────────────────────────────────┘ ║
║                            │                                     ║
║                            ▼                                     ║
║  STAGE 4 — PHASE 2: PREPROD + PROD MIGRATION (Weeks 9–18)      ║
║  ┌────────────────────────────────────────────────────────────┐ ║
║  │ Step 13. Follow Phase 2 plan (pglogical live replication)  │ ║
║  │          → 06-Phase2-PreProd-Prod.md                       │ ║
║  │          → 12-Migration-Execution.md (Prod sections)       │ ║
║  │ Step 14. Production DNS cutover + rollback gate            │ ║
║  │          → 08-Cutover-Runbook.md                           │ ║
║  └────────────────────────────────────────────────────────────┘ ║
║                            │                                     ║
║                            ▼                                     ║
║  STAGE 5 — ONGOING OPERATIONS (Post Go-Live)                    ║
║  ┌────────────────────────────────────────────────────────────┐ ║
║  │ Step 15. Veeam Backup — all VM jobs + K8s Kasten K10       │ ║
║  │          → 14-Veeam-Backup.md                              │ ║
║  │ Step 16. Monthly/Quarterly/Semi-annual patching cycles     │ ║
║  │          → 15-Patching-Cycles.md                           │ ║
║  └────────────────────────────────────────────────────────────┘ ║
╚══════════════════════════════════════════════════════════════════╝
```

---

## All Files — Quick Reference

| Step | File | Description |
|------|------|-------------|
| 1 | [09-Current-Infra-Inventory.md](09-Current-Infra-Inventory.md) | Audit VxRail cluster — model ID, resource inventory, audit scripts |
| 2 | [10-Procurement-Guide.md](10-Procurement-Guide.md) | What to buy — switches, VPN appliance, licenses, backup NAS |
| 3 | [11-Initial-Setup-Before-Migration.md](11-Initial-Setup-Before-Migration.md) | 15-step on-prem foundation: DNS, NTP, CA, VPN, Ansible, templates |
| 4 | [01-Infrastructure-Assessment.md](01-Infrastructure-Assessment.md) | vSphere/vSAN capacity audit, VM sizing, readiness gate checklist |
| 5+6 | [02-VM-Provisioning-vSphere.md](02-VM-Provisioning-vSphere.md) | Create all 26 OL9 VMs via govc, cloud-init, DRS anti-affinity rules |
| 5 | [13-Oracle-Linux-VMs.md](13-Oracle-Linux-VMs.md) | OL9 VM template, dnf commands, K8s on OL9, firewalld, SELinux |
| 7 | [03-Network-vSphere.md](03-Network-vSphere.md) | DVS port groups, VLANs, MetalLB, keepalived VIP, firewalld rules |
| 8 | [04-Storage-vSAN.md](04-Storage-vSAN.md) | vSAN policies (FTT-0/1/RAID-5), CSI driver, StorageClasses, MinIO |
| 9 | [07-Kubernetes-vSphere.md](07-Kubernetes-vSphere.md) | kubeadm 3-master HA, vSphere CCM, Calico CNI, MetalLB, validation |
| 10 | [14-Veeam-Backup.md](14-Veeam-Backup.md) | Veeam B&R v12: install, VM jobs, Veeam Agent on OL9, Kasten K10, restore |
| 11 | [05-Phase1-Dev-QA.md](05-Phase1-Dev-QA.md) | Phase 1 week-by-week: Dev+QA infra → DB migrate → app deploy → sign-off |
| 11 | [12-Migration-Execution.md](12-Migration-Execution.md) | Master execution commands: Harbor, ArgoCD, PostgreSQL, MongoDB, cutover |
| 12 | [08-Cutover-Runbook.md](08-Cutover-Runbook.md) | DNS cutover scripts, smoke tests, rollback decision tree, 72h monitoring |
| 13 | [06-Phase2-PreProd-Prod.md](06-Phase2-PreProd-Prod.md) | Phase 2: Patroni HA, pglogical live replication for Prod, decommission |
| 15 | [15-Patching-Cycles.md](15-Patching-Cycles.md) | Patch calendar: Monthly/Quarterly/Semi-annual/Annual cycles and scripts |

---

## Infrastructure Overview

```
DELL VxRail HCI CLUSTER — 6 Nodes (VMware vSphere)
────────────────────────────────────────────────────────────────────

VxRail-1  ┌─────────────────────────────────────────────────────┐
          │  k8s-master-1 (OL9, 4vCPU/8GB)                     │
          │  db-dev-01    (OL9, 4vCPU/8GB, PostgreSQL Dev)      │
          │  mongo-dev-01 (OL9, 2vCPU/4GB, MongoDB Dev)        │
          └─────────────────────────────────────────────────────┘

VxRail-2  ┌─────────────────────────────────────────────────────┐
          │  k8s-master-2 (OL9, 4vCPU/8GB)                     │
          │  db-qa-01     (OL9, 4vCPU/8GB, PostgreSQL QA)      │
          │  mongo-qa-01  (OL9, 2vCPU/4GB, MongoDB QA)        │
          └─────────────────────────────────────────────────────┘

VxRail-3  ┌─────────────────────────────────────────────────────┐
          │  k8s-master-3  (OL9, 4vCPU/8GB)                    │
          │  db-preprod-01 (OL9, 4vCPU/16GB, PostgreSQL PProd) │
          │  mongo-preprod-01 (OL9, 4vCPU/8GB, Mongo PProd)   │
          └─────────────────────────────────────────────────────┘

VxRail-4  ┌─────────────────────────────────────────────────────┐
          │  k8s-worker-1  (OL9, 8vCPU/16GB, Dev+QA workloads) │
          │  k8s-worker-2  (OL9, 8vCPU/16GB, Dev+QA workloads) │
          │  db-preprod-02 (OL9, 4vCPU/16GB, PG PProd replica) │
          │  db-prod-01    (OL9, 8vCPU/32GB, PostgreSQL Prod)  │
          │  mongo-prod-01 (OL9, 4vCPU/16GB, MongoDB Prod RS)  │
          └─────────────────────────────────────────────────────┘

VxRail-5  ┌─────────────────────────────────────────────────────┐
          │  k8s-worker-3  (OL9, 12vCPU/32GB, PreProd loads)   │
          │  k8s-worker-4  (OL9, 12vCPU/32GB, PreProd loads)   │
          │  db-prod-02    (OL9, 8vCPU/32GB, PG Prod replica)  │
          │  minio-01      (OL9, 4vCPU/8GB, MinIO storage)     │
          │  mongo-prod-02 (OL9, 4vCPU/16GB, MongoDB Prod RS)  │
          └─────────────────────────────────────────────────────┘

VxRail-6  ┌─────────────────────────────────────────────────────┐
          │  k8s-worker-5  (OL9, 16vCPU/64GB, Prod workloads)  │
          │  k8s-worker-6  (OL9, 16vCPU/64GB, Prod workloads)  │
          │  db-prod-03    (OL9, 8vCPU/32GB, PG Prod replica)  │
          │  harbor-01     (OL9, 4vCPU/8GB, Container Registry)│
          │  monitoring-01 (OL9, 4vCPU/16GB, Prometheus+Grafana)│
          │  mongo-prod-03 (OL9, 4vCPU/16GB, MongoDB Prod RS)  │
          │  vxrail-vbr-01 (Win2022, 8vCPU/16GB, Veeam B&R)   │
          └─────────────────────────────────────────────────────┘

              Shared by all nodes:
              vSAN Datastore (pooled NVMe, all 6 nodes)
              DVS — Distributed Virtual Switch
              vCenter + VxRail Manager (management)
              vSphere HA + DRS (auto failover + balancing)
```

---

## VM Allocation Table

| VM Name | OS | Role | vCPU | RAM | Disk | VxRail Node |
|---------|-----|------|------|-----|------|-------------|
| k8s-master-1 | OL9 | K8s Control Plane | 4 | 8 GB | 80 GB | VxRail-1 |
| k8s-master-2 | OL9 | K8s Control Plane | 4 | 8 GB | 80 GB | VxRail-2 |
| k8s-master-3 | OL9 | K8s Control Plane | 4 | 8 GB | 80 GB | VxRail-3 |
| k8s-worker-1 | OL9 | K8s Worker (Dev/QA) | 8 | 16 GB | 100 GB | VxRail-4 |
| k8s-worker-2 | OL9 | K8s Worker (Dev/QA) | 8 | 16 GB | 100 GB | VxRail-4 |
| k8s-worker-3 | OL9 | K8s Worker (PreProd) | 12 | 32 GB | 150 GB | VxRail-5 |
| k8s-worker-4 | OL9 | K8s Worker (PreProd) | 12 | 32 GB | 150 GB | VxRail-5 |
| k8s-worker-5 | OL9 | K8s Worker (Prod) | 16 | 64 GB | 200 GB | VxRail-6 |
| k8s-worker-6 | OL9 | K8s Worker (Prod) | 16 | 64 GB | 200 GB | VxRail-6 |
| db-dev-01 | OL9 | PostgreSQL Dev | 4 | 8 GB | 200 GB | VxRail-1 |
| db-qa-01 | OL9 | PostgreSQL QA | 4 | 8 GB | 200 GB | VxRail-2 |
| db-preprod-01 | OL9 | PostgreSQL PreProd | 4 | 16 GB | 500 GB | VxRail-3 |
| db-preprod-02 | OL9 | PostgreSQL PreProd replica | 4 | 16 GB | 500 GB | VxRail-4 |
| db-prod-01 | OL9 | PostgreSQL Prod primary | 8 | 32 GB | 1 TB | VxRail-4 |
| db-prod-02 | OL9 | PostgreSQL Prod replica | 8 | 32 GB | 1 TB | VxRail-5 |
| db-prod-03 | OL9 | PostgreSQL Prod replica | 8 | 32 GB | 1 TB | VxRail-6 |
| mongo-dev-01 | OL9 | MongoDB Dev (standalone) | 2 | 4 GB | 100 GB | VxRail-1 |
| mongo-qa-01 | OL9 | MongoDB QA (standalone) | 2 | 4 GB | 100 GB | VxRail-2 |
| mongo-preprod-01 | OL9 | MongoDB PreProd RS | 4 | 8 GB | 300 GB | VxRail-3 |
| mongo-preprod-02 | OL9 | MongoDB PreProd RS | 4 | 8 GB | 300 GB | VxRail-5 |
| mongo-prod-01 | OL9 | MongoDB Prod RS | 4 | 16 GB | 500 GB | VxRail-4 |
| mongo-prod-02 | OL9 | MongoDB Prod RS | 4 | 16 GB | 500 GB | VxRail-5 |
| mongo-prod-03 | OL9 | MongoDB Prod RS | 4 | 16 GB | 500 GB | VxRail-6 |
| minio-01 | OL9 | MinIO Object Storage | 4 | 8 GB | 2 TB | VxRail-5 |
| harbor-01 | OL9 | Harbor Registry | 4 | 8 GB | 500 GB | VxRail-6 |
| monitoring-01 | OL9 | Prometheus + Grafana | 4 | 16 GB | 500 GB | VxRail-6 |
| vxrail-vbr-01 | Win2022 | Veeam B&R Server | 8 | 16 GB | 600 GB | VxRail-6 |

**Total: 27 VMs** (26 Oracle Linux 9 + 1 Windows Server 2022 for Veeam)

---

## Network / IP Plan

| Subnet | VLAN | Purpose | IP Range |
|--------|------|---------|----------|
| Management | VLAN 10 | vCenter, ESXi, jump host, DNS, Veeam | 10.0.1.0/24 |
| K8s Control Plane | VLAN 30 | 3 masters + VIP | 10.0.3.0/24 |
| K8s Workers | VLAN 40 | 6 workers + MetalLB LB range | 10.0.4.0/24 |
| Databases | VLAN 50 | PostgreSQL + MongoDB VMs | 10.0.5.0/24 |
| Services | VLAN 60 | Harbor, MinIO, Monitoring | 10.0.6.0/24 |

| Host | IP | Role |
|------|-----|------|
| k8s-api VIP | 10.0.3.100 | K8s API Server (keepalived float) |
| k8s-master-1/2/3 | 10.0.3.11/12/13 | Control plane nodes |
| k8s-worker-1/2 | 10.0.4.21/22 | Dev+QA workers |
| k8s-worker-3/4 | 10.0.4.23/24 | PreProd workers |
| k8s-worker-5/6 | 10.0.4.25/26 | Prod workers |
| MetalLB pool | 10.0.4.200–220 | LoadBalancer service IPs |
| db-dev-01 | 10.0.5.11 | PostgreSQL Dev |
| db-qa-01 | 10.0.5.12 | PostgreSQL QA |
| db-preprod-01/02 | 10.0.5.13/14 | PostgreSQL PreProd |
| db-prod-01/02/03 | 10.0.5.15/16/17 | PostgreSQL Prod |
| mongo-dev-01 | 10.0.5.21 | MongoDB Dev |
| mongo-qa-01 | 10.0.5.22 | MongoDB QA |
| mongo-preprod-01/02 | 10.0.5.23/24 | MongoDB PreProd RS |
| mongo-prod-01/02/03 | 10.0.5.25/26/27 | MongoDB Prod RS |
| harbor-01 | 10.0.6.11 | Harbor Registry |
| minio-01 | 10.0.6.12 | MinIO |
| monitoring-01 | 10.0.6.13 | Prometheus + Grafana |
| vxrail-vbr-01 | 10.0.1.40 | Veeam B&R Server |

---

## Azure to On-Prem Service Mapping

| Azure Service | On-Prem Equivalent | Technology | Guide |
|--------------|-------------------|------------|-------|
| AKS | Kubernetes (kubeadm) on OL9 VMs | K8s 1.29, Calico, MetalLB | `07-Kubernetes-vSphere.md` |
| Azure Cosmos DB (Mongo API) | MongoDB 7.0 ReplicaSet | Wire-compatible with Cosmos | `12-Migration-Execution.md` |
| Azure Container Registry | Harbor | On vSAN-backed VM | `12-Migration-Execution.md` |
| Azure PostgreSQL | PostgreSQL 15 + Patroni HA | pglogical for live migration | `12-Migration-Execution.md` |
| Azure Storage Account | MinIO on vSAN | S3-compatible | `04-Storage-vSAN.md` |
| Azure VNet | VMware DVS Port Groups | VLANs per environment | `03-Network-vSphere.md` |
| Azure Load Balancer | MetalLB (K8s) + keepalived (VIP) | L2/L4 | `03-Network-vSphere.md` |
| Azure Monitor | Prometheus + Grafana | On OL9 VM | `12-Migration-Execution.md` |
| Azure DNS | BIND9 Internal DNS | On jump host OL9 VM | `11-Initial-Setup-Before-Migration.md` |
| Azure Backup / Velero | Veeam B&R v12 | VM + K8s workload backup | `14-Veeam-Backup.md` |
| Azure Update Management | dnf + kubeadm upgrade cycles | Monthly/Quarterly | `15-Patching-Cycles.md` |
| Azure DevOps / CI | ArgoCD + Harbor | GitOps | `12-Migration-Execution.md` |

---

## Phase Timeline

```
PHASE 1 — Dev + QA (Weeks 1–8)
───────────────────────────────────────────────────────────────────
Week 1–2  │ Foundation + vSphere infra build (Steps 3–9 above)
Week 3    │ Deploy Kubernetes + install Harbor, ArgoCD, Prometheus
Week 4    │ Migrate Dev PostgreSQL + MongoDB from Azure
Week 5    │ Deploy Dev application workloads, validate
Week 6    │ Migrate QA PostgreSQL + MongoDB from Azure
Week 7    │ Deploy QA application workloads, validate
Week 8    │ Load test + sign-off → DNS cutover Dev + QA

PHASE 2 — PreProd + Prod (Weeks 9–18)
───────────────────────────────────────────────────────────────────
Week 9–10 │ Migrate PreProd (DB + apps + validate)
Week 11   │ PreProd sign-off + DNS cutover
Week 12   │ Start pglogical live replication: Prod PostgreSQL
Week 13   │ Migrate Prod MongoDB, deploy Prod apps to K8s
Week 14   │ Parallel run: Azure + on-prem both serving Prod
Week 15   │ Performance validation + load test on on-prem
Week 16   │ Maintenance window: Prod DNS cutover (01:00–06:00)
Week 17   │ 72h hypercare monitoring + Azure on standby
Week 18   │ Azure decommission (if no rollback triggered)
```
