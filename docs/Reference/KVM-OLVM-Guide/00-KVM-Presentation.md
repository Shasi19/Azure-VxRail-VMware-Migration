# Azure to KVM + OLVM On-Premises Migration
## Migration Presentation — KVM Option

> **This guide covers the KVM/OLVM alternative.** If your on-prem infrastructure uses KVM as the hypervisor (instead of VMware VxRail), this is your migration path.  
> **Your actual infra is VxRail** → see [../../VxRail-VMware-Migration/00-VxRail-Presentation.md](../../VxRail-VMware-Migration/00-VxRail-Presentation.md)

---

## 1. Why KVM as an Alternative to VxRail?

```
┌──────────────────────────────────────────────────────────────────┐
│              WHEN TO CHOOSE KVM OVER VxRail/VMware               │
├──────────────────────────────────────────────────────────────────┤
│  💰 No VMware licence cost (KVM is open source — built into OL9) │
│  🐧 100% open source stack (no vendor lock-in to Dell/VMware)    │
│  🔧 Full control over hypervisor internals                       │
│  🏢 Already have generic x86 servers (not VxRail)               │
│  📦 OLVM provides vCenter-equivalent management (Oracle-supported)│
│                                                                  │
│  Trade-offs vs VxRail:                                           │
│  ⚠️  No vSAN — need separate shared storage (NFS, iSCSI, Ceph)   │
│  ⚠️  No Dell hardware integration (manual firmware/patching)     │
│  ⚠️  Less mature HA automation (vs vSphere HA + DRS)             │
└──────────────────────────────────────────────────────────────────┘
```

---

## 2. Current Azure Architecture (Same as VxRail Scenario)

```
                    AZURE CLOUD (Source — Same for All Options)
┌─────────────────────────────────────────────────────────────────────┐
│              Hub Subscription (Sub-AFRPS-AF-INT)                    │
│  Azure VPN Gateway  │  Azure Firewall  │  Azure DNS Zones           │
│                     Hub VNet — 10.0.0.0/16                          │
└────────────┬──────────────┬──────────────┬──────────────────────────┘
             │              │              │
  ┌──────────▼──┐  ┌────────▼──────┐  ┌───▼───────────┐  ┌──────────────────┐
  │  DEV VNet   │  │  QA VNet      │  │ PREPROD VNet  │  │  PROD VNet        │
  │  AKS        │  │  AKS          │  │  AKS           │  │  AKS (HA)         │
  │  Cosmos DB  │  │  Cosmos DB    │  │  Cosmos DB     │  │  Cosmos DB (MR)   │
  │  PostgreSQL │  │  PostgreSQL   │  │  PostgreSQL    │  │  PostgreSQL HA    │
  │  ACR        │  │  ACR          │  │  ACR           │  │  ACR (Geo-rep)    │
  │  Storage    │  │  Storage      │  │  Storage       │  │  Storage (RA-GRS) │
  └─────────────┘  └───────────────┘  └────────────────┘  └───────────────────┘
  Monthly cost: ~$7,945 / month | Annual: ~$95,340
```

---

## 3. Target Architecture — KVM + OLVM On-Premises

```
YOUR DATA CENTRE — KVM OPTION (After Migration)
──────────────────────────────────────────────────────────────────────────

  ┌──────────────────────────────────────────────────────────────────┐
  │          PHYSICAL SERVERS (x86, your existing hardware)          │
  │                                                                  │
  │  Server-1  Server-2  Server-3  Server-4  Server-5  Server-6     │
  │  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐   │
  │  │ KVM  │  │ KVM  │  │ KVM  │  │ KVM  │  │ KVM  │  │ KVM  │   │
  │  │(OL9) │  │(OL9) │  │(OL9) │  │(OL9) │  │(OL9) │  │(OL9) │   │
  │  └──┬───┘  └──┬───┘  └──┬───┘  └──┬───┘  └──┬───┘  └──┬───┘   │
  │     └─────────┴──────────┴──────────┴──────────┴─────────┘       │
  │                    libvirt + QEMU (hypervisor layer)              │
  │                                                                  │
  │  ┌────────────────────────────────────────────────────────────┐  │
  │  │           OLVM (Oracle Linux Virtualization Manager)        │  │
  │  │           = Management plane (equivalent to vCenter)        │  │
  │  │           Manages all KVM hosts, VMs, networks, storage     │  │
  │  └────────────────────────────────────────────────────────────┘  │
  │                                                                  │
  │  Shared Storage (one of):                                        │
  │  ┌─────────────────────────────────────────────────────────┐    │
  │  │  NFS Server  OR  iSCSI Target  OR  Ceph (GlusterFS)    │    │
  │  │  (not included in KVM — must be provisioned separately)  │    │
  │  └─────────────────────────────────────────────────────────┘    │
  │                                                                  │
  │  VM LAYER (Oracle Linux 9 guest VMs — same as VxRail option):   │
  │  ┌───────────────────────────────────────────────────────────┐  │
  │  │ K8s Masters (3x OL9) | K8s Workers (6x OL9)              │  │
  │  │ PostgreSQL VMs (OL9) | MongoDB VMs (OL9)                  │  │
  │  │ Harbor | MinIO | Monitoring | Veeam Agent                  │  │
  │  └───────────────────────────────────────────────────────────┘  │
  └──────────────────────────────────────────────────────────────────┘
```

---

## 4. Azure → KVM/OLVM Service Mapping

| Azure Service | KVM Option | Notes |
|--------------|-----------|-------|
| AKS | Kubernetes on KVM Guest VMs (kubeadm) | Same as VxRail — K8s runs in OL9 VMs |
| Azure Cosmos DB | MongoDB 7.0 ReplicaSet | Wire-compatible — no code change |
| Azure PostgreSQL | PostgreSQL 15 + Patroni HA | pglogical for live migration |
| Azure Container Registry | Harbor on KVM VM | Same Docker/Helm interface |
| Azure Storage Account | MinIO on KVM VM | S3-compatible |
| VMware DVS | Linux bridge + OVS (Open vSwitch) | Manual VLAN config vs DVS auto |
| vSphere HA | OLVM High Availability | VM auto-restart on host failure |
| vSAN | NFS / iSCSI / Ceph | Must provision separately |
| vSphere CSI | NFS CSI Driver or Ceph RBD CSI | Different CSI driver than VxRail |
| vCenter | OLVM (Oracle Linux Virtualization Manager) | Web UI management |
| Veeam (agentless) | Veeam Agent for Linux + KVM snapshots | No agentless vSphere API |

---

## 5. KVM vs VxRail — Decision Guide

| Factor | KVM + OLVM | VxRail + VMware |
|--------|-----------|----------------|
| Hypervisor licence cost | Free (OL9 built-in) | Included with VxRail |
| Management tool | OLVM (free, Oracle-supported) | vCenter (included with VxRail) |
| Shared storage | Must add separately (NFS/Ceph) | vSAN built-in (pooled NVMe) |
| HA automation | OLVM HA (good) | vSphere HA + DRS (excellent) |
| Backup (agentless) | Not available — needs agent | Veeam agentless via VMware APIs |
| Hardware integration | Generic x86 only | Dell-specific (firmware, lifecycle) |
| Migration complexity | Higher | Lower (you already own VxRail) |
| **Best for** | New hardware, VMware-free budget | Your existing VxRail cluster |

---

## 6. KVM Migration Approach

```
PHASE 1: KVM HOST SETUP (Weeks 1–6)
  Install OL9 on all physical servers
  Install KVM + libvirt + QEMU
  Deploy OLVM Engine (management plane)
  Add all KVM hosts to OLVM
  Configure shared storage (NFS or Ceph)
  Create VM networks (Linux bridge / OVS VLANs)

PHASE 2: VM PROVISIONING (Weeks 6–10)
  Create OL9 VM templates in OLVM
  Clone all VMs (cloud-init for IP assignment)
  Configure networking (bridge, VLAN tagging)
  Set up NFS/Ceph CSI for Kubernetes PVs

PHASE 3: KUBERNETES + SERVICES (Weeks 10–14)
  kubeadm HA cluster on KVM VMs
  Calico CNI, MetalLB, Ingress
  Harbor, ArgoCD, Prometheus, MinIO

PHASE 4: DATA + APP MIGRATION (Weeks 14–26)
  Same as VxRail: pg_dump → pg_restore → pglogical
  MongoDB: mongodump → mongorestore
  App deployment via ArgoCD

PHASE 5: CUTOVER + DECOMMISSION (Weeks 26–32)
  DNS cutover per environment
  Azure decommission
```

---

## 7. What to Read in This Section

| File | Contents |
|------|---------|
| [00-Index.md](00-Index.md) | Full KVM migration guide navigation |
| [01-KVM-Installation.md](01-KVM-Installation.md) | Install KVM on OL9, SELinux, verify |
| [02-OLVM-Installation.md](02-OLVM-Installation.md) | OLVM engine, add hosts, storage domains |
| [03-KVM-Networking.md](03-KVM-Networking.md) | Linux bridge, bonding, VLANs, OVS |
| [04-KVM-Storage.md](04-KVM-Storage.md) | QCOW2, LVM, NFS, iSCSI, snapshots |
| [05-KVM-Security.md](05-KVM-Security.md) | sVirt, SELinux, TLS, VM isolation |
| [06-KVM-Best-Practices.md](06-KVM-Best-Practices.md) | CPU pinning, NUMA, hugepages, migration |
| [07-Creating-VMs.md](07-Creating-VMs.md) | virt-install, cloud-init, bulk creation |
| [08-OLVM-HTTPS-Certificate.md](08-OLVM-HTTPS-Certificate.md) | Internal CA, Let's Encrypt, renewal |
| [09-Kubernetes-on-KVM.md](09-Kubernetes-on-KVM.md) | Provision in OLVM, kubeadm HA, Calico |
| [10-OLVM-Backup.md](10-OLVM-Backup.md) | engine-backup, OVA export, schedule |
| [11-Monitoring-Logging.md](11-Monitoring-Logging.md) | node_exporter, libvirt-exporter, ELK |
| [12-Backup-Recovery.md](12-Backup-Recovery.md) | Cold backup, dirty bitmaps, Bacula, DR |
