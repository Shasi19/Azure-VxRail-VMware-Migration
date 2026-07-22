# VxRail VMware Migration Guide

## Azure → On-Premises (Dell VxRail HCI + VMware vSphere)

> **Current On-Prem Infrastructure:** 6-node Dell VxRail HCI cluster running VMware vSphere  
> **Source:** Azure (AKS + Cosmos DB + ACR + PostgreSQL + Storage Account) — 4 environments  
> **Target:** Kubernetes on VMware VMs + vSAN storage — same 4 environments  
> **Migration Order:** Phase 1 → Dev + QA | Phase 2 → PreProd + Prod

---

## Infrastructure Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    DELL VxRail HCI CLUSTER (6 Nodes)                        │
│                                                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐ │
│  │ VxRail-1 │  │ VxRail-2 │  │ VxRail-3 │  │ VxRail-4 │  │ VxRail-5 │  │ VxRail-6 │ │
│  │ ESXi 8.x │  │ ESXi 8.x │  │ ESXi 8.x │  │ ESXi 8.x │  │ ESXi 8.x │  │ ESXi 8.x │ │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘ │
│       └──────────────┴──────────────┴──────────────┴──────────────┴───────────┘       │
│                                    vSAN Datastore                                       │
│                              vCenter Server (management)                                │
│                        Distributed Virtual Switch (DVS)                                 │
└─────────────────────────────────────────────────────────────────────────────┘
```

**What VxRail provides:**
- **VMware vSphere (ESXi)** — hypervisor on each node → create/manage VMs
- **VMware vSAN** — distributed storage pooled from all 6 nodes → persistent volumes for Kubernetes
- **vCenter Server** — central management for all 6 ESXi hosts (built into VxRail)
- **VxRail Manager** — Dell's lifecycle manager (firmware, software upgrades)
- **vSphere HA + DRS** — automatic VM restart on host failure + workload balancing

---

## Migration Phases

```
PHASE 1 — Weeks 1-8                    PHASE 2 — Weeks 9-18
Dev + QA Environments                  PreProd + Prod Environments
─────────────────────────────          ─────────────────────────────
Week 1-2: Infra Prep + K8s Setup       Week 9-10: PreProd Migration
Week 3-4: Dev Migration                Week 11-12: PreProd Validation (2 weeks)
Week 5-6: QA Migration                 Week 13-15: Prod Migration (parallel)
Week 7-8: Dev+QA Validation            Week 16-17: Prod Go-Live + Stabilize
                                       Week 18: Azure Decommission
```

---

## VM Allocation Plan (6 VxRail Nodes)

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│  VxRail Node → VM Placement (DRS managed, pinned for critical VMs)              │
├──────────────┬───────────────────────────────────────────────────────────────────┤
│ VxRail-1     │ k8s-master-1, db-dev-01 (PostgreSQL primary Dev)                 │
│ VxRail-2     │ k8s-master-2, db-qa-01 (PostgreSQL primary QA)                   │
│ VxRail-3     │ k8s-master-3, db-preprod-01 (PostgreSQL primary PreProd)         │
│ VxRail-4     │ k8s-worker-1, k8s-worker-2, db-prod-01 (PostgreSQL primary Prod) │
│ VxRail-5     │ k8s-worker-3, k8s-worker-4, mongo-prod-01, minio-01              │
│ VxRail-6     │ k8s-worker-5, k8s-worker-6, harbor-01, monitoring-01             │
└──────────────┴───────────────────────────────────────────────────────────────────┘
```

### VM Inventory

| VM Name | Role | vCPU | RAM | Disk | VxRail Node |
|---------|------|------|-----|------|-------------|
| `k8s-master-1` | K8s Control Plane | 4 | 8 GB | 80 GB | VxRail-1 |
| `k8s-master-2` | K8s Control Plane | 4 | 8 GB | 80 GB | VxRail-2 |
| `k8s-master-3` | K8s Control Plane | 4 | 8 GB | 80 GB | VxRail-3 |
| `k8s-worker-1` | K8s Worker (Dev/QA) | 8 | 16 GB | 100 GB | VxRail-4 |
| `k8s-worker-2` | K8s Worker (Dev/QA) | 8 | 16 GB | 100 GB | VxRail-4 |
| `k8s-worker-3` | K8s Worker (PreProd) | 12 | 32 GB | 150 GB | VxRail-5 |
| `k8s-worker-4` | K8s Worker (PreProd) | 12 | 32 GB | 150 GB | VxRail-5 |
| `k8s-worker-5` | K8s Worker (Prod) | 16 | 64 GB | 200 GB | VxRail-6 |
| `k8s-worker-6` | K8s Worker (Prod) | 16 | 64 GB | 200 GB | VxRail-6 |
| `db-dev-01` | PostgreSQL Dev | 4 | 8 GB | 200 GB | VxRail-1 |
| `db-qa-01` | PostgreSQL QA | 4 | 8 GB | 200 GB | VxRail-2 |
| `db-preprod-01` | PostgreSQL PreProd | 4 | 16 GB | 500 GB | VxRail-3 |
| `db-preprod-02` | PostgreSQL PreProd replica | 4 | 16 GB | 500 GB | VxRail-4 |
| `db-prod-01` | PostgreSQL Prod primary | 8 | 32 GB | 1 TB | VxRail-4 |
| `db-prod-02` | PostgreSQL Prod replica | 8 | 32 GB | 1 TB | VxRail-5 |
| `db-prod-03` | PostgreSQL Prod replica | 8 | 32 GB | 1 TB | VxRail-6 |
| `mongo-dev-01` | MongoDB Dev | 2 | 4 GB | 100 GB | VxRail-1 |
| `mongo-qa-01` | MongoDB QA | 2 | 4 GB | 100 GB | VxRail-2 |
| `mongo-preprod-01` | MongoDB PreProd | 4 | 8 GB | 300 GB | VxRail-3 |
| `mongo-preprod-02` | MongoDB PreProd replica | 4 | 8 GB | 300 GB | VxRail-5 |
| `mongo-prod-01` | MongoDB Prod RS | 4 | 16 GB | 500 GB | VxRail-4 |
| `mongo-prod-02` | MongoDB Prod RS | 4 | 16 GB | 500 GB | VxRail-5 |
| `mongo-prod-03` | MongoDB Prod RS | 4 | 16 GB | 500 GB | VxRail-6 |
| `minio-01` | MinIO (all envs) | 4 | 8 GB | 2 TB | VxRail-5 |
| `harbor-01` | Harbor Registry | 4 | 8 GB | 500 GB | VxRail-6 |
| `monitoring-01` | Prometheus + Grafana | 4 | 16 GB | 500 GB | VxRail-6 |

---

## Azure to On-Prem Service Mapping (VxRail Context)

| Azure Service | VxRail/VMware Equivalent | Notes |
|---------------|--------------------------|-------|
| AKS | Kubernetes on VMware VMs (kubeadm) | vSphere CSI for PV |
| Azure Storage Account | MinIO on vSAN-backed VM | S3-compatible |
| Azure Cosmos DB (MongoDB API) | MongoDB 7.0 ReplicaSet on VMs | Wire-compatible |
| Azure Container Registry (ACR) | Harbor on VM | vSAN-backed |
| Azure PostgreSQL | PostgreSQL 15 + Patroni HA on VMs | HAProxy + PgBouncer |
| Azure VNet | VMware DVS + Port Groups | VLAN-segmented |
| Azure Load Balancer | MetalLB (K8s) + VMware NSX-T / F5 | Layer 4 LB |
| Azure Monitor | Prometheus + Grafana + ELK | On VM |
| Azure DNS | Internal DNS (bind9 or Pi-hole) | vSphere VM |

---

## Guide Contents

| File | Contents | Phase |
|------|----------|-------|
| [01-Infrastructure-Assessment.md](01-Infrastructure-Assessment.md) | VxRail resource audit, capacity planning, vSAN sizing | Pre-work |
| [02-VM-Provisioning-vSphere.md](02-VM-Provisioning-vSphere.md) | Create VMs via vCenter UI + govc CLI + cloud-init | Pre-work |
| [03-Network-vSphere.md](03-Network-vSphere.md) | DVS port groups, VLANs, MetalLB, firewall | Pre-work |
| [04-Storage-vSAN.md](04-Storage-vSAN.md) | vSAN policies, vSphere CSI, StorageClass, MinIO | Pre-work |
| [05-Phase1-Dev-QA.md](05-Phase1-Dev-QA.md) | **Phase 1: Dev + QA migration, week-by-week** | Phase 1 |
| [06-Phase2-PreProd-Prod.md](06-Phase2-PreProd-Prod.md) | **Phase 2: PreProd + Prod migration, go/no-go gates** | Phase 2 |
| [07-Kubernetes-vSphere.md](07-Kubernetes-vSphere.md) | kubeadm HA on VMware, vSphere cloud provider, CSI | Both |
| [08-Cutover-Runbook.md](08-Cutover-Runbook.md) | DNS cutover, rollback, validation checklists | Both |
