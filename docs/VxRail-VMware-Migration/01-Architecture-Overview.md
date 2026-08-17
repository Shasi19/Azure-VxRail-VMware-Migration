# Architecture Overview — Current Azure, Current On-Prem, and Target State

> **Read this first.** This document explains where you are today (Azure + existing VxRail),
> what the target on-prem architecture looks like, what needs to be procured, and why
> every component was chosen. Start here before any other file.

---

## Architecture Comparison Flowchart

```
┌──────────────────────────┐      ┌──────────────────────────┐
│ Current Azure Estate     │ ───▶ │ Target VxRail Estate     │
│ AKS + Azure DB services  │      │ K8s + Patroni + Harbor   │
└──────────────────────────┘      └──────────────────────────┘
          │                                      │
          └────────────── compare, size, migrate ┘
```


## Table of Contents

1. [Current Azure Architecture](#1-current-azure-architecture)
2. [Current On-Prem Infrastructure (VxRail — What You Have Now)](#2-current-on-prem-infrastructure-vxrail--what-you-have-now)
3. [What Needs to Be Procured](#3-what-needs-to-be-procured)
4. [Target On-Prem Architecture (After Migration)](#4-target-on-prem-architecture-after-migration)
5. [Azure vs On-Prem Side-by-Side](#5-azure-vs-on-prem-side-by-side)
6. [Component Purpose Guide — Why Every Tool Was Chosen](#6-component-purpose-guide--why-every-tool-was-chosen)

---

## 1. Current Azure Architecture

### 1.1 Architecture Diagram

```
                        AZURE CLOUD
┌─────────────────────────────────────────────────────────────────────┐
│                    Hub Subscription (Sub-AFRPS-AF-INT)               │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  Azure VPN Gateway  │  Azure Firewall  │  Azure DNS          │   │
│  │  (S2S Connectivity) │  (Hub Filtering) │  (Private Zones)    │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                         Hub VNet (10.0.0.0/16)                      │
└─────────────────────────┬──────────────┬────────────┬───────────────┘
          VNet Peering     │              │            │
    ┌──────────────────────┘              │            └──────────────┐
    │                           ┌─────────┘                          │
    │                           │                                    │
    ▼                           ▼                                    ▼
┌───────────────────┐  ┌────────────────────┐  ┌────────────────────┐
│  DEV VNet          │  │  QA VNet            │  │  PREPROD VNet      │
│  (10.10.0.0/16)   │  │  (10.20.0.0/16)    │  │  (10.30.0.0/16)   │
│                   │  │                    │  │                    │
│  AKS Cluster      │  │  AKS Cluster       │  │  AKS Cluster       │
│  (System+User     │  │  (System+User      │  │  (System+User      │
│   node pools)     │  │   node pools)      │  │   node pools)      │
│                   │  │                    │  │                    │
│  Azure Cosmos DB  │  │  Azure Cosmos DB   │  │  Azure Cosmos DB   │
│  (MongoDB API)    │  │  (MongoDB API)     │  │  (MongoDB API)     │
│                   │  │                    │  │                    │
│  Azure PostgreSQL │  │  Azure PostgreSQL  │  │  Azure PostgreSQL  │
│  (Flexible Server)│  │  (Flexible Server) │  │  (Flexible Server) │
│                   │  │                    │  │                    │
│  Azure Container  │  │  Azure Container   │  │  Azure Container   │
│  Registry (ACR)   │  │  Registry (ACR)    │  │  Registry (ACR)    │
│                   │  │                    │  │                    │
│  Storage Account  │  │  Storage Account   │  │  Storage Account   │
│  (Blob + Queue)   │  │  (Blob + Queue)    │  │  (Blob + Queue)    │
└───────────────────┘  └────────────────────┘  └────────────────────┘
                                                        |
                                              ┌─────────────────────┐
                                              │  PROD VNet           │
                                              │  (10.40.0.0/16)     │
                                              │                     │
                                              │  AKS Cluster        │
                                              │  (System+User+Spot  │
                                              │   node pools)       │
                                              │                     │
                                              │  Azure Cosmos DB    │
                                              │  (MongoDB API)      │
                                              │  Multi-region RS    │
                                              │                     │
                                              │  Azure PostgreSQL   │
                                              │  (Flexible Server   │
                                              │   HA + read replica)│
                                              │                     │
                                              │  Azure Container    │
                                              │  Registry (ACR)     │
                                              │  Geo-replication    │
                                              │                     │
                                              │  Storage Account    │
                                              │  (RA-GRS redundancy)│
                                              └─────────────────────┘
```

### 1.2 Azure Services — What Each Does

| Service | Environment | Purpose | Configuration |
|---------|------------|---------|--------------|
| **AKS (Azure Kubernetes Service)** | Dev/QA/PreProd/Prod | Hosts application containers. Managed K8s — no control plane to manage | System pool: Standard_D2s_v3; User pool: Standard_D4s_v3; Prod: +Spot pool |
| **Azure Cosmos DB (MongoDB API)** | Dev/QA/PreProd/Prod | Document database (NoSQL). MongoDB wire-protocol compatible. Hosts app data | Dev/QA: 400 RU/s; Prod: 10,000 RU/s autoscale; multi-region in Prod |
| **Azure PostgreSQL Flexible Server** | Dev/QA/PreProd/Prod | Relational database for structured data | Dev/QA: Standard_D2ds_v4; Prod: Standard_D8ds_v4 with HA + read replica |
| **Azure Container Registry (ACR)** | Dev/QA/PreProd/Prod | Stores Docker images for AKS. Each env has its own ACR | Standard SKU (Dev/QA), Premium SKU (Prod — geo-replication) |
| **Azure Storage Account** | Dev/QA/PreProd/Prod | Blob storage for files, queue messages, logs | Dev/QA: LRS; Prod: RA-GRS (geo-redundant) |
| **Azure VPN Gateway** | Hub | Site-to-site VPN to on-prem (used during migration) | VpnGw1 or VpnGw2 SKU |
| **Azure Firewall** | Hub | Centralized traffic inspection for all VNets | Premium SKU for threat intelligence |
| **Azure DNS Private Zones** | Hub | Internal DNS resolution for all VNets | privatelink zones for PG, Cosmos, ACR |

### 1.3 Current Azure Costs (Approximate Monthly)

| Service | Dev | QA | PreProd | Prod | Monthly Total |
|---------|-----|----|---------|------|--------------|
| AKS (node pools) | $300 | $300 | $600 | $2,000 | $3,200 |
| Cosmos DB | $50 | $50 | $200 | $1,500 | $1,800 |
| PostgreSQL | $150 | $150 | $400 | $1,200 | $1,900 |
| ACR | $10 | $10 | $10 | $25 | $55 |
| Storage Account | $20 | $20 | $50 | $200 | $290 |
| VPN Gateway | — | — | — | — | $300 (shared) |
| Networking (egress) | — | — | — | — | $400 (est.) |
| **Total** | | | | | **~$7,945/month** |

> **Why migrate?** Azure costs ~$95,000/year. On-prem on existing VxRail hardware has near-zero recurring cloud costs. Expected savings: $70,000–$85,000/year after migration (hardware/maintenance costs deducted).

---

## 2. Current On-Prem Infrastructure (VxRail — What You Have Now)

### 2.1 Existing Hardware Diagram

```
YOUR CURRENT ON-PREM DATA CENTER
──────────────────────────────────────────────────────────────────────

  ┌─────────────────────────────────────────────────────────────┐
  │              DELL VxRail HCI CLUSTER                        │
  │           (6-Node Hyper-Converged Infrastructure)           │
  │                                                             │
  │  Node 1     Node 2     Node 3     Node 4     Node 5  Node 6│
  │  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐ ┌─────┐│
  │  │ESXi8 │  │ESXi8 │  │ESXi8 │  │ESXi8 │  │ESXi8 │ │ESXi8││
  │  │      │  │      │  │      │  │      │  │      │ │     ││
  │  │NVMe  │  │NVMe  │  │NVMe  │  │NVMe  │  │NVMe  │ │NVMe ││
  │  │(HDD) │  │(HDD) │  │(HDD) │  │(HDD) │  │(HDD) │ │(HDD)││
  │  └──┬───┘  └──┬───┘  └──┬───┘  └──┬───┘  └──┬───┘ └──┬──┘│
  │     └─────────┴──────────┴──────────┴──────────┴────────┘  │
  │                       vSAN Datastore                        │
  │              (pooled NVMe/HDD across all 6 nodes)           │
  │                                                             │
  │  VxRail Manager  │  vCenter Server  │  vSphere HA + DRS    │
  │  (Dell lifecycle)│  (VM management) │  (auto failover)     │
  └─────────────────────────────────────────────────────────────┘
           │
           │ Currently running Oracle Linux VMs (existing workloads)
           │ Veeam B&R already installed (backing up existing VMs)
           │
  ┌────────┴──────────────────────────────────────────┐
  │        EXISTING NETWORK (approximate)              │
  │  TOR Switch (Top of Rack) — existing               │
  │  Management VLAN (existing)                        │
  │  ESXi management IPs on existing switch            │
  └───────────────────────────────────────────────────┘
```

### 2.2 What VxRail Provides Today

| Component | What It Is | What It Does |
|-----------|-----------|-------------|
| **Dell VxRail Node (x6)** | Physical server with CPU, RAM, NVMe SSDs | Each node runs ESXi hypervisor. Contributes storage to vSAN pool |
| **VMware ESXi 8.x** | Bare-metal hypervisor on each node | Runs virtual machines. Provides CPU/RAM isolation between VMs |
| **VMware vSAN** | Software-defined storage | Pools the NVMe drives from all 6 nodes into one distributed datastore. 6-node cluster gives N+2 fault tolerance |
| **VMware vCenter Server** | Centralized management appliance | Single pane of glass to manage all 6 ESXi hosts, create VMs, configure networking, storage policies |
| **VxRail Manager** | Dell-specific lifecycle manager | Handles firmware updates, ESXi patches, hardware monitoring. Always use VxRail Manager for patches — never patch ESXi directly |
| **vSphere HA** | High availability for VMs | If a physical node fails, all VMs on it auto-restart on other healthy nodes within minutes |
| **vSphere DRS** | Distributed Resource Scheduler | Automatically balances VM workloads across all 6 nodes for optimal performance |
| **DVS (Distributed Virtual Switch)** | Software-defined networking | Centrally managed switch shared across all 6 hosts. Provides VLANs, port groups, traffic shaping |
| **VMware VMXNET3** | Virtual NIC driver | All VMs see `ens192` network adapter. High-performance paravirtual NIC |

### 2.3 Current VxRail Resources (Typical Per-Node)

| Resource | Per Node | 6-Node Total | Usable (after HA) |
|----------|----------|-------------|-------------------|
| CPU | 24-40 cores | 144-240 cores | ~110 cores |
| RAM | 256-512 GB | 1.5–3 TB | ~1.2 TB |
| NVMe | 3.8–7.6 TB | 22–45 TB vSAN | ~15–30 TB (FTT=1) |
| 10GbE NICs | 2x10GbE | — | Uplinks to TOR switch |

### 2.4 What's Already Running on VxRail

- **Oracle Linux VMs** — existing workloads (non-migration VMs)
- **Veeam Backup and Replication** — already deployed, backing up existing VMs
- vCenter, VxRail Manager (management VMs, usually run on cluster itself)

---

## 3. What Needs to Be Procured

### 3.1 What You Already Have (No Purchase Needed)

| Item | Status | Notes |
|------|--------|-------|
| 6-node Dell VxRail cluster | Have | Sufficient for migration workloads |
| VMware vSphere licenses | Have | Included with VxRail |
| vCenter Server | Have | Included with VxRail |
| Veeam B&R license | Have | Already deployed — verify seat count covers new VMs |
| Oracle Linux subscriptions | Check | Verify OL9 licenses for ~26 new VMs |
| Existing TOR switches | Have | May need port expansion or additional switch |

### 3.2 New Items to Procure

```
PROCUREMENT CHECKLIST
──────────────────────────────────────────────────────────────────────

NETWORKING
┌─────────────────────────────────────────────────────────────────┐
│ Item: Top-of-Rack Switch (if existing switch lacks capacity)    │
│ Recommended: Dell PowerSwitch S5248F-ON or Cisco Nexus 9300    │
│ Ports needed: 48x 25GbE for server uplinks + 4x 100GbE uplinks │
│ Approx cost: $15,000–25,000                                     │
│ Lead time: 4–8 weeks                                            │
├─────────────────────────────────────────────────────────────────┤
│ Item: VPN Appliance (for Azure-to-OnPrem connectivity)          │
│ Option A: Software VPN on existing VM (strongSwan — free)       │
│ Option B: Cisco ASA 5506-X or Palo Alto PA-220 (hardware)      │
│ Approx cost: $0 (SW) or $2,000–8,000 (HW)                     │
│ Lead time: 1–4 weeks (HW) or immediate (SW)                    │
└─────────────────────────────────────────────────────────────────┘

STORAGE (for Veeam Backup Repository)
┌─────────────────────────────────────────────────────────────────┐
│ Item: NAS / Backup Repository                                   │
│ Recommended: Synology RS1221+ (8-bay NAS) with 8x 10TB HDDs   │
│ OR: Synology RS3621xs+ for larger capacity                      │
│ Capacity needed: 2x total VM data (all 26 VMs) = ~40–60 TB    │
│ Approx cost: $3,000–8,000 (NAS) + $2,000–4,000 (drives)       │
│ Lead time: 2–4 weeks                                            │
└─────────────────────────────────────────────────────────────────┘

LICENSES (verify seat counts)
┌─────────────────────────────────────────────────────────────────┤
│ Oracle Linux 9 subscriptions: 26 VMs × Premier = ~$13,000/year │
│   OR: Use free Oracle Linux (basic, no Oracle support) = $0    │
│ Veeam Universal License (VUL): Check if existing covers +27 VMs│
│   Add-on if needed: ~$1,200–2,000 per 10 workloads            │
│ PostgreSQL: Open source — FREE                                  │
│ MongoDB Community: Open source — FREE                           │
│ Harbor: Open source (CNCF) — FREE                              │
│ ArgoCD: Open source — FREE                                      │
│ Prometheus/Grafana: Open source — FREE                          │
└─────────────────────────────────────────────────────────────────┘

CERTIFICATES
┌─────────────────────────────────────────────────────────────────┐
│ Internal CA: step-ca (open source) — FREE                       │
│ Public TLS cert (for any externally exposed endpoints):         │
│   Let's Encrypt (free) or purchase wildcard cert (~$300/year)  │
└─────────────────────────────────────────────────────────────────┘
```

### 3.3 Procurement Decision Tree

```
Do you have spare switch ports for 26+ new VMs?
  YES → No switch procurement needed
  NO  → Order: Dell PowerSwitch S5248F-ON (8-week lead time)
           ↓ Start this ORDER FIRST on Day 0

Do you have Azure site-to-site VPN already?
  YES → Reconfigure for migration (use existing)
  NO  → Deploy strongSwan VPN on jump host VM (free, 1 day)

Is your Veeam license count sufficient for +27 VMs?
  YES → No action needed
  NO  → Purchase Veeam VUL add-on sockets

Do you have a backup repository target (NAS or disk)?
  YES (existing NAS) → Configure as Veeam repo
  NO  → Order Synology NAS + drives (4-week lead time)
```

---

## 4. Target On-Prem Architecture (After Migration)

### 4.1 Target Architecture Diagram

```
YOUR ON-PREM DATA CENTER — AFTER MIGRATION
──────────────────────────────────────────────────────────────────────────

  ┌──────────────────────────────────────────────────────────────────┐
  │                 DELL VxRail HCI CLUSTER (6 Nodes)                │
  │                                                                  │
  │  MANAGEMENT LAYER (VLAN 10 — 10.0.1.0/24)                      │
  │  ┌──────────┐  ┌──────────┐  ┌────────────┐  ┌──────────────┐  │
  │  │ vCenter  │  │  VxRail  │  │  Jump Host │  │  DNS Server  │  │
  │  │ Server   │  │ Manager  │  │  (Ansible) │  │  (BIND9)     │  │
  │  │10.0.1.10 │  │10.0.1.11 │  │  10.0.1.20 │  │  10.0.1.5   │  │
  │  └──────────┘  └──────────┘  └────────────┘  └──────────────┘  │
  │                                                                  │
  │  K8s CONTROL PLANE (VLAN 30 — 10.0.3.0/24)                     │
  │  ┌────────────┐  ┌────────────┐  ┌────────────┐                 │
  │  │k8s-master-1│  │k8s-master-2│  │k8s-master-3│  VIP:10.0.3.100│
  │  │10.0.3.11   │  │10.0.3.12   │  │10.0.3.13   │  (keepalived)  │
  │  │OL9 VM      │  │OL9 VM      │  │OL9 VM      │                 │
  │  └────────────┘  └────────────┘  └────────────┘                 │
  │                                                                  │
  │  K8s WORKERS (VLAN 40 — 10.0.4.0/24)                           │
  │  ┌───────────────────┐  ┌───────────────────┐  ┌─────────────┐ │
  │  │ worker-1/2        │  │ worker-3/4        │  │ worker-5/6  │ │
  │  │ Dev + QA          │  │ PreProd           │  │ Prod        │ │
  │  │ 10.0.4.21-22      │  │ 10.0.4.23-24      │  │10.0.4.25-26 │ │
  │  │ OL9 VMs (8vCPU)   │  │ OL9 VMs (12vCPU)  │  │OL9 (16vCPU) │ │
  │  └───────────────────┘  └───────────────────┘  └─────────────┘ │
  │       MetalLB LB IPs: 10.0.4.200–220 (LoadBalancer services)   │
  │                                                                  │
  │  DATABASES (VLAN 50 — 10.0.5.0/24)                             │
  │  PostgreSQL:                           MongoDB:                  │
  │  ┌──────────────────────────────┐     ┌──────────────────────┐  │
  │  │ db-dev-01  (10.0.5.11) OL9  │     │ mongo-dev-01 OL9     │  │
  │  │ db-qa-01   (10.0.5.12) OL9  │     │ mongo-qa-01  OL9     │  │
  │  │ db-preprod-01/02 Patroni HA  │     │ mongo-preprod RS (2) │  │
  │  │ db-prod-01/02/03 Patroni HA  │     │ mongo-prod RS (3)    │  │
  │  │ (PgBouncer + HAProxy VIP)    │     │ (rs-prod ReplicaSet) │  │
  │  └──────────────────────────────┘     └──────────────────────┘  │
  │                                                                  │
  │  SERVICES (VLAN 60 — 10.0.6.0/24)                              │
  │  ┌────────────┐  ┌────────────┐  ┌────────────────────────────┐ │
  │  │  Harbor    │  │   MinIO    │  │  Prometheus + Grafana      │ │
  │  │  Registry  │  │  S3-compat │  │  (monitoring-01)           │ │
  │  │ 10.0.6.11  │  │ 10.0.6.12  │  │  10.0.6.13                │ │
  │  │  OL9 VM    │  │  OL9 VM    │  │  OL9 VM                    │ │
  │  └────────────┘  └────────────┘  └────────────────────────────┘ │
  │  ┌──────────────────────────────────────────┐                   │
  │  │  vxrail-vbr-01 — Veeam B&R Server        │                   │
  │  │  Windows Server 2022 — 10.0.1.40          │                   │
  │  │  Backs up ALL VMs daily via VMware APIs   │                   │
  │  └──────────────────────────────────────────┘                   │
  │                                                                  │
  │              vSAN Datastore (pooled NVMe — all 6 nodes)         │
  │              DVS — VLANs 10/30/40/50/60                         │
  └──────────────────────────────────────────────────────────────────┘
        │                                          │
        │ Azure VPN (site-to-site, during migration)│
        ▼                                          ▼
  Azure Cloud (source)                     NAS / Backup Repository
  (decommissioned at end)                  (Synology / existing NAS)
                                           Veeam backup target
```

### 4.2 How Each Environment Maps to K8s

```
KUBERNETES CLUSTER — NAMESPACE AND NODE MAPPING
───────────────────────────────────────────────────────────────

API Server VIP: 10.0.3.100 (keepalived, floats across 3 masters)

  namespace: dev        → scheduled on worker-1, worker-2
  namespace: qa         → scheduled on worker-1, worker-2
  namespace: preprod    → scheduled on worker-3, worker-4 (tainted: env=preprod)
  namespace: prod       → scheduled on worker-5, worker-6 (tainted: env=prod)

Each namespace contains:
  Deployment:     application pods (replicated)
  Service:        ClusterIP + LoadBalancer (MetalLB assigns external IP)
  PVC:            persistent storage via vSphere CSI → vSAN
  ConfigMap:      environment-specific config (DB hosts, endpoints)
  Secret:         DB passwords, API keys (sealed-secrets or Vault)

Container images pulled from: harbor.internal.company.com (10.0.6.11)
Deployment managed by:         ArgoCD (GitOps — watches your Git repo)
Metrics collected by:          Prometheus → Grafana dashboards
```

### 4.3 Data Flow (Production Request Path)

```
User/Client Request
       │
       ▼
MetalLB (10.0.4.200–220)        ← assigns external IP to K8s Service
       │
       ▼
K8s Ingress Controller           ← routes by hostname/path
       │
       ▼
Application Pod (Prod namespace)  ← your containerized app
       │
       ├──► PostgreSQL (10.0.5.15 via HAProxy VIP)  ← relational data
       │    (Patroni HA — auto failover between db-prod-01/02/03)
       │
       ├──► MongoDB (10.0.5.25 rs-prod ReplicaSet)  ← document data
       │    (3-node RS — primary + 2 secondaries)
       │
       └──► MinIO (10.0.6.12)                        ← file/object storage
            (S3-compatible — same API as Azure Blob)
```

---

## 5. Azure vs On-Prem Side-by-Side

```
AZURE (Current)                    ON-PREM TARGET (VxRail)
────────────────────────────────   ────────────────────────────────────────
AKS (managed Kubernetes)       →   kubeadm K8s 1.29 on Oracle Linux 9 VMs
                                   (3 masters + 6 workers on vSAN-backed VMs)

Azure Cosmos DB (Mongo API)    →   MongoDB 7.0 Community ReplicaSet
                                   (wire-protocol compatible — apps change
                                    only the connection string, not code)

Azure PostgreSQL Flexible       →   PostgreSQL 15 + Patroni HA + PgBouncer
                                   (Patroni handles auto-failover, same
                                    SQL — apps need only conn string change)

Azure Container Registry (ACR) →   Harbor (open source registry)
                                   (helm charts, Docker images, vulnerability
                                    scanning — same push/pull interface)

Azure Storage Account (Blob)   →   MinIO
                                   (S3-compatible API — apps using Azure SDK
                                    switch to MinIO with endpoint change only)

Azure VNet                     →   VMware DVS Port Groups (VLANs)
                                   (same isolation model, different technology)

Azure Load Balancer            →   MetalLB (K8s services)
                                   + keepalived (PostgreSQL HA VIP)

Azure Monitor + App Insights   →   Prometheus + Grafana + AlertManager
                                   (equivalent dashboards, alerting)

Azure DevOps (CI/CD)           →   ArgoCD (GitOps, continuous deployment)
                                   + Harbor (image registry)

Azure Backup / Site Recovery   →   Veeam Backup and Replication v12
                                   (already deployed on VxRail)

Azure Key Vault                →   Kubernetes Secrets (sealed-secrets)
                                   or HashiCorp Vault (if needed later)

Azure DNS                      →   BIND9 internal DNS on OL9 VM
                                   (custom zones for internal resolution)
```

---

## 6. Component Purpose Guide — Why Every Tool Was Chosen

| Component | What It Does | Why This Tool | Azure Equivalent |
|-----------|-------------|--------------|-----------------|
| **Oracle Linux 9** | OS for all VMs | Your team already uses OL9. RHEL-compatible. Oracle Unbreakable Kernel (UEK). Full support lifecycle. SELinux hardening. | Azure VM (Ubuntu/Windows) |
| **VMware ESXi + vSAN** | Hypervisor + storage | Already on VxRail. Mature, enterprise-grade. vSAN eliminates SAN dependency. vSphere HA auto-restarts VMs on node failure. | Azure VMs + Azure Disks |
| **vCenter + DVS** | VM and network management | Centralized management for all 6 nodes. DVS provides consistent VLANs across cluster. | Azure Portal / ARM |
| **kubeadm** | Kubernetes installer | Standard K8s install tool. Full control over config. Supports vSphere CCM/CSI integration. | AKS (managed) |
| **Kubernetes 1.29** | Container orchestration | Same K8s API as AKS. Apps run unchanged (same YAML manifests). Calico CNI. | AKS |
| **Calico CNI** | K8s pod networking | High-performance CNI. Supports NetworkPolicy for microsegmentation. Works well on VMware. | Azure CNI (AKS) |
| **MetalLB** | K8s load balancer | Provides LoadBalancer service type in bare-metal/VMware K8s clusters (missing in kubeadm). L2 mode works without BGP. | Azure Load Balancer |
| **keepalived + HAProxy** | Control plane VIP | Makes 3 K8s API servers appear as one VIP (10.0.3.100). HA for the control plane. | AKS managed control plane |
| **vSphere CSI Driver** | Persistent storage for K8s | Provisions PVs directly from vSAN. Supports RWO volumes. Works with vSAN storage policies (FTT levels). | Azure Disk CSI (AKS) |
| **PostgreSQL 15** | Relational database | Open source. Compatible with Azure PostgreSQL (Flexible Server is also PG-based). `pg_dump`/`pg_restore` for migration. | Azure PostgreSQL Flexible |
| **Patroni** | PostgreSQL HA | Automatic PostgreSQL failover using etcd. Industry standard for PG HA on VMs. | Azure PostgreSQL HA (built-in) |
| **pglogical** | Live DB replication | PostgreSQL logical replication plugin. Used for zero-downtime migration from Azure. Replicates changes in real-time. | Azure DMS |
| **PgBouncer** | Connection pooler | Reduces connection overhead for PostgreSQL. Sits between apps and PG. | Azure PG connection pooling |
| **MongoDB 7.0** | Document database | Wire-protocol compatible with Azure Cosmos DB MongoDB API. Apps need only connection string change. | Azure Cosmos DB (MongoDB API) |
| **Harbor** | Container registry | Open source CNCF project. Docker/Helm compatible. Vulnerability scanning built-in. Geo-replication optional. | Azure Container Registry |
| **MinIO** | Object storage | S3-compatible API — apps using Azure Blob SDK work with minor endpoint change. Open source. Runs on vSAN disk. | Azure Storage Account |
| **ArgoCD** | GitOps CD | Watches Git repo. Applies K8s manifests automatically on push. Provides deployment history + rollback. | Azure DevOps CD pipelines |
| **Prometheus + Grafana** | Monitoring | Industry standard for K8s metrics. Grafana dashboards equivalent to Azure Monitor. AlertManager for notifications. | Azure Monitor + App Insights |
| **Veeam B&R v12** | Backup | Already deployed on VxRail. VM-level agentless backup via VMware APIs. Hotadd transport for vSAN (fastest). | Azure Backup + Site Recovery |
| **Kasten K10 (Veeam)** | K8s backup | Kubernetes-native backup for PVCs, Secrets, ConfigMaps. Integrates with Veeam VBR. | Azure Backup for AKS |
| **BIND9** | Internal DNS | Authoritative DNS for `internal.company.com` zone. Required for service discovery across VLANs. | Azure DNS Private Zones |
| **step-ca** | Internal CA | Issues TLS certs for internal services (Harbor, MinIO, Prometheus). Open source. Supports ACME protocol. | Azure Key Vault CA |
| **strongSwan / OpenVPN** | Site-to-site VPN | Secure tunnel between on-prem and Azure during migration period. Allows pg_dump, data sync. | Azure VPN Gateway |
| **Ansible** | Configuration management | Idempotent automation for OS config, K8s prep, app deployment across all VMs. | ARM templates / Bicep |
| **firewalld** | Host firewall | Default firewall on OL9 (replaces iptables). `firewall-cmd` for rule management. | Azure NSG |

---

## 7. Pre-Migration Checklist

Before starting any migration work, verify:

```
HARDWARE
[ ] VxRail cluster health: all 6 nodes green in VxRail Manager
[ ] vSAN health: no warnings in vCenter vSAN monitor
[ ] Sufficient vSAN capacity for 27 new VMs (see sizing in 05-Infrastructure-Assessment.md)
[ ] Switch ports available for new VMs (or switch ordered)
[ ] NAS / backup repo ready or ordered

LICENSING
[ ] Oracle Linux subscriptions confirmed for OL9 (or free OL confirmed OK)
[ ] Veeam license seat count covers +27 VMs
[ ] VMware vSphere license includes vSAN (check with Dell)

ACCESS
[ ] vCenter admin credentials available
[ ] VxRail Manager credentials available
[ ] Jump host VM created with Ansible, govc, kubectl installed
[ ] Azure VPN established (or strongSwan configured)
[ ] SSH key pair generated for all VM access

AZURE
[ ] Azure PostgreSQL backup taken before migration start
[ ] Azure Cosmos DB export completed and verified
[ ] Azure VPN Gateway provisioned and tested
[ ] All Azure resource tags documented (for decommission tracking)

APPROVALS
[ ] Change request approved for Dev+QA migration (Phase 1)
[ ] Network VLAN plan approved by network team
[ ] DNS change authority confirmed (who approves DNS cutover)
[ ] Maintenance window agreed for Prod cutover (Phase 2)
[ ] Rollback criteria defined and documented
```
