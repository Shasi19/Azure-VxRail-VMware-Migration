# Azure to Bare-Metal On-Premises Migration
## Migration Presentation — Bare-Metal Option

> **This guide covers the bare-metal alternative** — running Kubernetes directly on physical servers with no hypervisor layer.  
> **Your actual infra is VxRail** → see [../../VxRail-VMware-Migration/00-VxRail-Presentation.md](../../VxRail-VMware-Migration/00-VxRail-Presentation.md)

---

## 1. Why Bare-Metal?

```
┌──────────────────────────────────────────────────────────────────┐
│              WHEN TO CHOOSE BARE-METAL OVER VxRail/KVM           │
├──────────────────────────────────────────────────────────────────┤
│  🚀 Maximum performance (no hypervisor overhead — 5–15% gain)    │
│  💰 Zero hypervisor licence cost                                 │
│  🔧 Simplest architecture (fewer layers = fewer failure points)  │
│  🧮 Dedicated hardware per workload (no noisy neighbour)         │
│  📊 Best for CPU/GPU-intensive workloads                         │
│                                                                  │
│  Trade-offs:                                                     │
│  ⚠️  No VM snapshots — backups must be at OS/app level           │
│  ⚠️  Node failure = K8s must reschedule (no VM live migration)   │
│  ⚠️  Hardware provisioning is manual and slow                    │
│  ⚠️  Harder to right-size resources post-deployment              │
└──────────────────────────────────────────────────────────────────┘
```

---

## 2. Current Azure Architecture (Same Source)

```
                    AZURE CLOUD (Source)
┌─────────────────────────────────────────────────────────────────────┐
│              Hub Subscription (Sub-AFRPS-AF-INT)                    │
│  Azure VPN Gateway  │  Azure Firewall  │  Azure DNS Zones           │
└────────────┬──────────────┬──────────────┬──────────────────────────┘
             │              │              │
  ┌──────────▼──┐  ┌────────▼──────┐  ┌───▼───────────┐  ┌──────────────────┐
  │  DEV VNet   │  │  QA VNet      │  │ PREPROD VNet  │  │  PROD VNet        │
  │  AKS        │  │  AKS          │  │  AKS           │  │  AKS (HA)         │
  │  Cosmos DB  │  │  Cosmos DB    │  │  Cosmos DB     │  │  Cosmos DB        │
  │  PostgreSQL │  │  PostgreSQL   │  │  PostgreSQL    │  │  PostgreSQL HA    │
  │  ACR        │  │  ACR          │  │  ACR           │  │  ACR              │
  │  Storage    │  │  Storage      │  │  Storage       │  │  Storage          │
  └─────────────┘  └───────────────┘  └────────────────┘  └───────────────────┘
  Monthly cost: ~$7,945/month | Annual: ~$95,340
```

---

## 3. Target Architecture — Bare-Metal On-Premises

```
YOUR DATA CENTRE — BARE-METAL OPTION (After Migration)
──────────────────────────────────────────────────────────────────────

  NO HYPERVISOR LAYER — Kubernetes runs directly on physical OS

  ┌──────────────────────────────────────────────────────────────────┐
  │            PHYSICAL SERVERS (x86 — Oracle Linux 9 installed)     │
  │                                                                  │
  │  CONTROL PLANE SERVERS (3 physical machines)                    │
  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │
  │  │  master-1    │  │  master-2    │  │  master-3    │  VIP:     │
  │  │  OL9 (bare) │  │  OL9 (bare) │  │  OL9 (bare) │  10.0.3.100│
  │  │  kubeadm    │  │  kubeadm    │  │  kubeadm    │  keepalived│
  │  └──────────────┘  └──────────────┘  └──────────────┘           │
  │                                                                  │
  │  WORKER SERVERS (6 physical machines)                           │
  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
  │  │ worker-1/2      │  │ worker-3/4      │  │ worker-5/6      │ │
  │  │ Dev + QA loads  │  │ PreProd loads   │  │ Prod loads      │ │
  │  │ OL9 (bare)      │  │ OL9 (bare)      │  │ OL9 (bare)      │ │
  │  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
  │  MetalLB: 10.0.4.200–220 (LoadBalancer IPs)                    │
  │                                                                  │
  │  DATABASE SERVERS (dedicated physical machines)                 │
  │  ┌────────────────────────┐  ┌────────────────────────────────┐ │
  │  │  PostgreSQL servers    │  │  MongoDB servers               │ │
  │  │  OL9 + Patroni HA      │  │  OL9 + ReplicaSet             │ │
  │  │  (Prod: 3 servers)     │  │  (Prod: 3 servers)            │ │
  │  └────────────────────────┘  └────────────────────────────────┘ │
  │                                                                  │
  │  SERVICE SERVERS                                                │
  │  Harbor | MinIO | Prometheus+Grafana | Jump Host               │
  │  (dedicated physical servers or co-hosted with workers)        │
  │                                                                  │
  │  SHARED STORAGE (for K8s PVs)                                  │
  │  ┌────────────────────────────────────────────────────────────┐ │
  │  │  NAS / NFS Server   OR   Local NVMe (non-shared)          │ │
  │  │  NFS CSI Driver for Kubernetes PVs                        │ │
  │  └────────────────────────────────────────────────────────────┘ │
  └──────────────────────────────────────────────────────────────────┘
```

---

## 4. Bare-Metal vs VxRail vs KVM Comparison

| Factor | Bare-Metal | KVM + OLVM | VxRail + VMware |
|--------|-----------|-----------|----------------|
| Performance | Best (no hypervisor) | Good (2–5% overhead) | Good (2–5% overhead) |
| HA on node failure | K8s self-heals (pods reschedule) | OLVM VM restart | vSphere HA VM restart |
| Provisioning speed | Slow (manual OS install) | Fast (clone VM) | Fast (clone VM) |
| Backup approach | Veeam Agent + etcd snapshots | Veeam Agent + QEMU snapshots | Veeam agentless (fastest) |
| Storage | Local NVMe or NFS | QCOW2 on NFS/LVM | vSAN (built-in) |
| Licence cost | Zero | OLVM (Oracle-supported, free) | VMware (included with VxRail) |
| **Best for** | Max performance, dedicated HW | No VMware budget | Your existing VxRail ← |

---

## 5. Azure → Bare-Metal Service Mapping

| Azure | Bare-Metal Replacement | Notes |
|-------|----------------------|-------|
| AKS | Kubernetes 1.29 on OL9 (bare) | kubeadm — same manifests |
| Cosmos DB (Mongo API) | MongoDB 7.0 RS on dedicated servers | Wire-compatible |
| Azure PostgreSQL | PostgreSQL 15 + Patroni on dedicated servers | pglogical for live migration |
| ACR | Harbor on OL9 server | Same push/pull |
| Azure Storage | MinIO on NVMe | S3-compatible |
| Azure VNet | VLAN on physical switch + OL9 networking | firewalld, nmcli |
| Azure LB | MetalLB + keepalived | Same as VxRail |
| Azure Monitor | Prometheus + Grafana | Same as VxRail |
| Azure Backup | Veeam Agent for Linux | Agent-based (no agentless) |

---

## 6. What to Read in This Section

| File | Contents |
|------|---------|
| [00-Index.md](00-Index.md) | Full bare-metal guide navigation |
| [01-Server-Preparation.md](01-Server-Preparation.md) | OS install, BIOS, kernel modules, containerd |
| [02-Network-Configuration.md](02-Network-Configuration.md) | NIC bonding, VLANs, static IPs, firewall, MetalLB |
| [03-Kubernetes-Setup.md](03-Kubernetes-Setup.md) | kubeadm HA, keepalived VIP, Calico CNI, node labels |
| [04-Storage-Setup.md](04-Storage-Setup.md) | MinIO on NVMe, NFS StorageClass, performance tuning |
| [05-Database-Setup.md](05-Database-Setup.md) | PostgreSQL + Patroni, MongoDB RS, K8s secrets |
| [06-Platform-Services.md](06-Platform-Services.md) | Harbor, ArgoCD, GitLab CI, Vault, Redis |
| [07-Observability-Security.md](07-Observability-Security.md) | Prometheus, Grafana, ELK, Jaeger, NetworkPolicy |
| [08-Backup-DR.md](08-Backup-DR.md) | Velero, Bacula, etcd backup, node recovery runbook |
