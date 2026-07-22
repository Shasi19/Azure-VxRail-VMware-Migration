# Azure → On-Premises Migration
## Dell VxRail HCI + VMware vSphere

> **Your Infrastructure:** 6-node Dell VxRail HCI cluster running VMware vSphere  
> **Migration:** Azure (AKS + Cosmos DB + ACR + PostgreSQL + Storage) → On-Premises Kubernetes on VxRail  
> **VM OS:** Oracle Linux 9 | **Backup:** Veeam Backup and Replication | **Phase 1:** Dev + QA | **Phase 2:** PreProd + Prod

---

## Start Here → [VxRail Migration Guide](docs/VxRail-VMware-Migration/00-Index.md)

Everything you need for this migration is inside `docs/VxRail-VMware-Migration/`.  
Follow the numbered steps below **in order**.

---

## Step-by-Step Migration Flow

```
BEFORE YOU START
  Step 1 → Audit your current VxRail hardware           [09-Current-Infra-Inventory.md]
  Step 2 → Identify what to procure (switches, VPN..)   [10-Procurement-Guide.md]
  Step 3 → Set up foundations (DNS, NTP, CA, VPN)       [11-Initial-Setup-Before-Migration.md]

INFRASTRUCTURE BUILD  
  Step 4 → Assess vSphere resources and vSAN capacity    [01-Infrastructure-Assessment.md]
  Step 5 → Create Oracle Linux 9 VM template + all VMs   [02-VM-Provisioning-vSphere.md]
            ↳ Oracle Linux 9 reference guide              [13-Oracle-Linux-VMs.md]
  Step 6 → Configure DVS networking, VLANs, firewalld    [03-Network-vSphere.md]
  Step 7 → Configure vSAN storage + CSI driver           [04-Storage-vSAN.md]
  Step 8 → Build HA Kubernetes cluster on vSphere        [07-Kubernetes-vSphere.md]

PHASE 1 — DEV + QA (Weeks 1–8)
  Step 9 → Execute Phase 1 migration                     [05-Phase1-Dev-QA.md]
            ↳ Master execution reference                  [12-Migration-Execution.md]

PHASE 2 — PREPROD + PROD (Weeks 9–18)
  Step 10 → Execute Phase 2 migration                    [06-Phase2-PreProd-Prod.md]
  Step 11 → DNS cutover + rollback runbook               [08-Cutover-Runbook.md]

ONGOING OPERATIONS
  Step 12 → Configure Veeam Backup for all VMs + K8s    [14-Veeam-Backup.md]
  Step 13 → Follow patch cycles (monthly/quarterly)     [15-Patching-Cycles.md]
```

---

## All VxRail Migration Files

| # | File | What It Covers | When to Read |
|---|------|---------------|-------------|
| 00 | [**Index and Overview**](docs/VxRail-VMware-Migration/00-Index.md) | VM allocation plan, architecture overview, Azure-to-OnPrem service mapping | Day 0 |
| — | **── BEFORE YOU START ──** | | |
| 09 | [**Current Infra Inventory**](docs/VxRail-VMware-Migration/09-Current-Infra-Inventory.md) | How to audit your VxRail cluster — model identification, hardware worksheet, audit scripts | Day 0 |
| 10 | [**Procurement Guide**](docs/VxRail-VMware-Migration/10-Procurement-Guide.md) | What to buy — switches with prices, Azure VPN SKU, certs, licenses, backup NAS | Day 0 |
| 11 | [**Initial Setup (Pre-Migration)**](docs/VxRail-VMware-Migration/11-Initial-Setup-Before-Migration.md) | 15-step foundation: DNS/BIND9, NTP, internal CA, Azure VPN, jump host, Ansible, readiness gate | Days 1–14 |
| — | **── INFRASTRUCTURE BUILD ──** | | |
| 01 | [Infrastructure Assessment](docs/VxRail-VMware-Migration/01-Infrastructure-Assessment.md) | vSphere CPU/RAM/vSAN audit, cluster readiness checklist, capacity planning | Pre-work |
| 02 | [VM Provisioning (vSphere)](docs/VxRail-VMware-Migration/02-VM-Provisioning-vSphere.md) | govc CLI bulk VM creation, cloud-init for OL9, all 26 VMs scripted | Pre-work |
| 13 | [**Oracle Linux 9 VM Guide**](docs/VxRail-VMware-Migration/13-Oracle-Linux-VMs.md) | OL9 template creation, dnf vs apt command reference, K8s on OL9, SELinux, firewalld, PostgreSQL/MongoDB on OL9, troubleshooting | Pre-work |
| 03 | [Network (DVS + firewalld)](docs/VxRail-VMware-Migration/03-Network-vSphere.md) | DVS port groups, VLANs, MetalLB L2 mode, keepalived VIP, firewalld rules for K8s | Pre-work |
| 04 | [Storage (vSAN + CSI)](docs/VxRail-VMware-Migration/04-Storage-vSAN.md) | vSAN storage policies, vSphere CSI driver, StorageClasses per env, MinIO on vSAN | Pre-work |
| 07 | [Kubernetes on vSphere](docs/VxRail-VMware-Migration/07-Kubernetes-vSphere.md) | kubeadm HA 3-master cluster, vSphere CCM, Calico CNI v3.27, MetalLB, verification | Pre-work |
| — | **── MIGRATION EXECUTION ──** | | |
| 12 | [**Master Migration Execution**](docs/VxRail-VMware-Migration/12-Migration-Execution.md) | Full step-by-step: K8s build → Harbor → ArgoCD → PostgreSQL migration → MongoDB migration → app deploy → DNS cutover → Azure decommission | Both phases |
| 05 | [Phase 1 — Dev + QA](docs/VxRail-VMware-Migration/05-Phase1-Dev-QA.md) | Week-by-week plan: infra → DB migration → app deploy → validation → sign-off. Go/no-go gates. | Phase 1 |
| 06 | [Phase 2 — PreProd + Prod](docs/VxRail-VMware-Migration/06-Phase2-PreProd-Prod.md) | Live pglogical replication for Prod, maintenance window cutover, Azure decommission | Phase 2 |
| 08 | [Cutover Runbook](docs/VxRail-VMware-Migration/08-Cutover-Runbook.md) | DNS cutover scripts, smoke tests, rollback triggers, 72h post-cutover monitoring | Both phases |
| — | **── ONGOING OPERATIONS ──** | | |
| 14 | [**Veeam Backup Guide**](docs/VxRail-VMware-Migration/14-Veeam-Backup.md) | Veeam B&R v12 on VxRail: VBR install, hotadd transport, VM backup jobs for all 26 VMs, pre/post-freeze for PostgreSQL+MongoDB, Veeam Agent on OL9, Kasten K10 for K8s, restore procedures | During setup |
| 15 | [**Patching Cycles**](docs/VxRail-VMware-Migration/15-Patching-Cycles.md) | Full patch calendar: Monthly (OS security), Quarterly (OS+K8s+DB), Semi-annual (VxRail ESXi+vCenter), Annual (major upgrades); rolling drain/patch/uncordon scripts, rollback procedures | Ongoing |

---

## Architecture at a Glance

```
┌─────────────────────────────────────────────────────────────────┐
│              AZURE (Current)                                    │
│  Dev VNet    QA VNet    PreProd VNet    Prod VNet               │
│  AKS + CosmosDB + ACR + PostgreSQL + Storage (x4 envs)         │
└────────────────────────┬────────────────────────────────────────┘
                         │  Migration (Phase 1 → Phase 2)
┌────────────────────────▼────────────────────────────────────────┐
│         DELL VxRail HCI CLUSTER (6 Nodes — VMware vSphere)     │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                  VMware vSAN Datastore                  │   │
│  │  (pooled NVMe from all 6 nodes — distributed storage)  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐ │
│  │  K8s Control │  │  K8s Workers  │  │   Database VMs       │ │
│  │  Plane       │  │  Dev/QA/PProd │  │   PostgreSQL 15      │ │
│  │  (3 masters) │  │  /Prod        │  │   MongoDB 7.0        │ │
│  │  OL9 VMs     │  │  OL9 VMs      │  │   OL9 VMs            │ │
│  └──────────────┘  └──────────────┘  └──────────────────────┘ │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Service VMs: Harbor | MinIO | Prometheus+Grafana        │  │
│  │              Veeam B&R Server (Windows)                  │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  vCenter + VxRail Manager + DVS Networking + vSphere HA+DRS   │
└─────────────────────────────────────────────────────────────────┘
```

| Azure Service | On-Prem Replacement | File |
|--------------|---------------------|------|
| AKS | Kubernetes (kubeadm) on Oracle Linux 9 VMs | `07-Kubernetes-vSphere.md` |
| Azure Cosmos DB (MongoDB API) | MongoDB 7.0 ReplicaSet on OL9 VMs | `12-Migration-Execution.md` |
| Azure Container Registry (ACR) | Harbor on vSAN-backed VM | `12-Migration-Execution.md` |
| Azure PostgreSQL | PostgreSQL 15 on OL9 VMs | `12-Migration-Execution.md` |
| Azure Storage Account | MinIO on vSAN | `04-Storage-vSAN.md` |
| Azure VNet | VMware DVS Port Groups (VLANs) | `03-Network-vSphere.md` |
| Azure Backup / Velero | Veeam Backup and Replication v12 | `14-Veeam-Backup.md` |
| Azure Update Management | Patch cycles (dnf + kubeadm upgrade) | `15-Patching-Cycles.md` |

---

## Environment Summary

| Environment | K8s Workers | PostgreSQL | MongoDB | Phase |
|-------------|------------|-----------|---------|-------|
| Dev | worker-1, worker-2 | db-dev-01 (standalone) | mongo-dev-01 (standalone) | Phase 1 |
| QA | worker-1, worker-2 | db-qa-01 (standalone) | mongo-qa-01 (standalone) | Phase 1 |
| PreProd | worker-3, worker-4 | db-preprod-01/02 (Patroni) | mongo-preprod-01/02 (RS) | Phase 2 |
| Prod | worker-5, worker-6 | db-prod-01/02/03 (Patroni HA) | mongo-prod-01/02/03 (RS) | Phase 2 |

---

## Other Reference Guides (Not Required for VxRail Migration)

| Guide | Purpose |
|-------|---------|
| [Presentation / HLD / LLD](docs/Presentation/) | Executive slides, high-level design, low-level design |
| [KVM + OLVM Guide](docs/KVM-OLVM-Guide/) | Deep-dive: KVM hypervisor and OLVM manager (if moving to KVM in future) |
| [OnPrem-KVM](docs/OnPrem-KVM/) | K8s migration guide for KVM-based infrastructure |
| [OnPrem-BareMetal](docs/OnPrem-BareMetal/) | K8s migration guide for bare-metal servers |
| [Volume 1–8](docs/Volume-1-Executive-Architecture/) | General Azure-to-OnPrem docs (not VxRail-specific) |

---

**Classification:** Internal Use Only &nbsp;|&nbsp; **Last Updated:** July 2026 &nbsp;|&nbsp; **Infra:** Dell VxRail HCI + VMware vSphere
