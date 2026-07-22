# Azure to On-Premises Migration

> **Complete migration guide** — from current Azure architecture through every phase of on-premises deployment, including HLD/LLD diagrams, detailed commands, and go-live runbook.

---

## 📋 Project Overview

| Item | Detail |
|------|--------|
| **Objective** | Migrate Azure-hosted apps to on-premises Kubernetes |
| **Duration** | 26 Weeks (6.5 Months) |
| **Investment** | $2.6M Year 1 (CapEx + OpEx) |
| **Expected ROI** | 18–24 months |
| **Annual Savings** | ~$400,000–$528,000 |
| **Target Availability** | 99.99% (four nines) |

---

## 🏗️ Current Azure Architecture

| Component | Azure Service | On-Prem Replacement |
|-----------|--------------|---------------------|
| App Hosting | App Service (3x P1V2) | Kubernetes Pods + HPA |
| Database | Azure PostgreSQL Managed | PostgreSQL HA + Patroni |
| Cache | Azure Redis Cache (Premium) | Redis Cluster (3+3 nodes) |
| Object Storage | Azure Blob Storage | MinIO Distributed |
| Load Balancer | Azure Application Gateway | F5 BIG-IP (Active/Passive) |
| Firewall/WAF | Azure Front Door + WAF | Palo Alto PA-5250 NGFW |
| Monitoring | Azure Monitor + App Insights | Prometheus + Grafana + Jaeger |
| Logging | Azure Log Analytics | Elasticsearch + Logstash + Kibana |
| Secrets | Azure Key Vault | HashiCorp Vault |
| CI/CD | Azure DevOps | GitLab CI + ArgoCD |
| DR / Backup | Azure Site Recovery + Backup | Bacula + Velero |

---

## 📚 Documentation Structure

### 🎨 [Presentation](docs/Presentation/) — Start Here for Overviews
| Doc | Audience | Description |
|-----|----------|-------------|
| [00 Index](docs/Presentation/00-Index.md) | All | Navigation and quick stats |
| [01 Executive Presentation](docs/Presentation/01-Executive-Presentation.md) | CTO, Board | Business case, ROI, timeline, risk summary |
| [02 HLD — High Level Design](docs/Presentation/02-HLD-High-Level-Design.md) | Architects | Architecture, traffic flow, security, CI/CD design |
| [03 LLD — Low Level Design](docs/Presentation/03-LLD-Low-Level-Design.md) | Engineers | IP plan, hardware specs, K8s resources, DNS, backup |

---

### Volume 1: Executive & Solution Architecture
| Doc | Description |
|-----|-------------|
| [01 Executive Summary](docs/Volume-1-Executive-Architecture/01-Executive-Summary.md) | Business case, ROI, project overview |
| [02 Existing Azure Architecture](docs/Volume-1-Executive-Architecture/02-Existing-Azure-Architecture.md) | Current state: components, costs, limitations |
| [03 Target On-Premises Architecture](docs/Volume-1-Executive-Architecture/03-Target-Architecture.md) | Target state: K8s, PostgreSQL HA, F5, Palo Alto |
| [04 Azure Architecture Visual](docs/Volume-1-Executive-Architecture/04-Azure-Architecture-Visual.md) | Full Mermaid diagram of current Azure stack (4-VNet hub-spoke) |
| [05 On-Prem Architecture Visual](docs/Volume-1-Executive-Architecture/05-OnPrem-Architecture-Visual.md) | Full Mermaid diagram of target on-prem stack + VLAN map |
| [06 Component Purpose Guide](docs/Volume-1-Executive-Architecture/06-Component-Purpose-Guide.md) | NEW — What every tool does, why chosen, Azure equivalent |
| [07 Per-Environment Architecture](docs/Volume-1-Executive-Architecture/07-Per-Environment-Architecture.md) | NEW — Dev/QA/PreProd/Prod on-prem stack with MongoDB per env |

### Volume 2: Migration Strategy
| Doc | Description |
|-----|-------------|
| [01 Migration Overview & Service Mapping](docs/Volume-2-Migration-Strategy/01-Migration-Overview.md) | Azure→OnPrem service map, flowcharts, risk register |
| [02 Phase Implementation Guide](docs/Volume-2-Migration-Strategy/02-Phase-Implementation-Guide.md) | Gantt chart, step-by-step per phase, cutover sequence |
| [03 Timeline & Milestones](docs/Volume-2-Migration-Strategy/03-Timeline-And-Milestones.md) | 26-week timeline, RACI, Go/No-Go gates, budget burn-down |
| [04 Multi-Environment Migration Plan](docs/Volume-2-Migration-Strategy/04-Multi-Environment-Migration-Plan.md) | NEW — Dev, QA, Pre-Prod, Prod timelines with go/no-go gates |

### Volume 3: Infrastructure Setup
| Doc | Description |
|-----|-------------|
| [01 Network & Compute Configuration](docs/Volume-3-Infrastructure-Setup/01-Network-Compute-Configuration.md) | Rack layout, Palo Alto + F5 config, VMware vSphere, NetApp ONTAP |

### Volume 4: Kubernetes Platform 🆕
| Doc | Description |
|-----|-------------|
| [01 Kubernetes Setup Guide](docs/Volume-4-Kubernetes-Platform/01-Kubernetes-Setup-Guide.md) | Step-by-step K8s install: preflight → control plane → workers → CNI → ArgoCD → Vault |
| [02 Detailed Commands Reference](docs/Volume-4-Kubernetes-Platform/02-Detailed-Commands-Reference.md) | **Build, deploy, ops, DB, Redis, monitoring, Vault, troubleshooting, end-user commands** |

### Volume 5: Database Migration
| Doc | Description |
|-----|-------------|
| [01 PostgreSQL HA Migration](docs/Volume-5-Database-Migration/01-PostgreSQL-HA-Migration.md) | Patroni cluster, pglogical live replication, PgBouncer, HAProxy, backup |

### Volume 6: Application Migration
| Doc | Description |
|-----|-------------|
| [01 App Containerization & Deployment](docs/Volume-6-Application-Migration/01-App-Containerization-And-Deployment.md) | Dockerfile, Helm chart, ArgoCD GitOps, GitLab CI/CD pipeline |

### Volume 7: Monitoring & Security
| Doc | Description |
|-----|-------------|
| [01 Monitoring & Alerting Setup](docs/Volume-7-Monitoring-Security/01-Monitoring-And-Alerting-Setup.md) | Prometheus, Grafana, ELK Stack, HashiCorp Vault, 15+ alert rules |

### Volume 8: Go-Live & Operations
| Doc | Description |
|-----|-------------|
| [01 Go-Live Runbook & Operations](docs/Volume-8-GoLive-Operations/01-GoLive-Runbook-And-Operations.md) | Cutover decision tree, rollback plan, daily ops checklist, SLAs, Azure decommission |

---

## Deployment Guides

Three complete deployment paths — choose based on your on-prem infrastructure:

### VxRail VMware Migration (Dell VxRail HCI + vSphere) ⭐ Current Infra
> **6-node Dell VxRail HCI cluster running VMware vSphere** — phased migration: Dev+QA first, then PreProd+Prod

| # | File | Description |
|---|------|-------------|
| 00 | [Index](docs/VxRail-VMware-Migration/00-Index.md) | VxRail overview, VM allocation plan, phase timeline, Azure mapping |
| 09 | [**Current Infra Inventory**](docs/VxRail-VMware-Migration/09-Current-Infra-Inventory.md) | **What you have now** — VxRail model guide, audit commands, hardware worksheet |
| 10 | [**Procurement Guide**](docs/VxRail-VMware-Migration/10-Procurement-Guide.md) | **What to buy** — switches with specs/prices, VPN, certs, licenses, backup storage |
| 11 | [**Initial Setup (Before Migration)**](docs/VxRail-VMware-Migration/11-Initial-Setup-Before-Migration.md) | **15-step foundation** — DNS, NTP, CA, Azure VPN, templates, Ansible, readiness gate |
| 01 | [Infrastructure Assessment](docs/VxRail-VMware-Migration/01-Infrastructure-Assessment.md) | vSphere resource audit, vSAN capacity planning, readiness checklist |
| 02 | [VM Provisioning (vSphere)](docs/VxRail-VMware-Migration/02-VM-Provisioning-vSphere.md) | govc CLI, cloud-init on VMware, bulk VM creation script, DRS rules |
| 03 | [Network (vSphere DVS)](docs/VxRail-VMware-Migration/03-Network-vSphere.md) | DVS port groups, VLANs, MetalLB config, keepalived VIP, firewall |
| 04 | [Storage (vSAN + CSI)](docs/VxRail-VMware-Migration/04-Storage-vSAN.md) | vSAN policies, vSphere CSI driver, StorageClasses, MinIO on vSAN |
| 07 | [Kubernetes on vSphere](docs/VxRail-VMware-Migration/07-Kubernetes-vSphere.md) | kubeadm HA with vSphere CCM, Calico CNI, CSI, MetalLB end-to-end |
| 12 | [**Migration Execution**](docs/VxRail-VMware-Migration/12-Migration-Execution.md) | **Master guide** — K8s build, Harbor, ArgoCD, DB migrate, app deploy, DNS cutover |
| 05 | [Phase 1 — Dev + QA](docs/VxRail-VMware-Migration/05-Phase1-Dev-QA.md) | Week-by-week: infra → DB migration → app deploy → validation → sign-off |
| 06 | [Phase 2 — PreProd + Prod](docs/VxRail-VMware-Migration/06-Phase2-PreProd-Prod.md) | Live pglogical replication → maintenance window cutover → decommission |
| 08 | [Cutover Runbook](docs/VxRail-VMware-Migration/08-Cutover-Runbook.md) | DNS cutover scripts, rollback procedures, 72h post-cutover monitoring |

### OnPrem-KVM (Kubernetes inside KVM Virtual Machines)
> Best for: VM-level isolation, snapshot-based DR, lab/multi-tenant environments.  
> KVM hypervisor runs on bare-metal hosts; K8s runs inside guest VMs.

| # | Doc | Contents |
|---|-----|----------|
| 00 | [Index](docs/OnPrem-KVM/00-Index.md) | Architecture overview, hardware requirements, IP plan |
| 01 | [KVM Host Setup](docs/OnPrem-KVM/01-KVM-Host-Setup.md) | Install KVM, libvirt, bridge networking, storage pool |
| 02 | [VM Provisioning](docs/OnPrem-KVM/02-VM-Provisioning.md) | Cloud-init VM creation for all 12 VMs, snapshots |
| 03 | [Network Configuration](docs/OnPrem-KVM/03-Network-Configuration.md) | VM networking, MetalLB, firewall, NTP |
| 04 | [Kubernetes Setup](docs/OnPrem-KVM/04-Kubernetes-Setup.md) | kubeadm HA cluster, Calico CNI, namespaces, Ingress |
| 05 | [Storage Setup](docs/OnPrem-KVM/05-Storage-Setup.md) | MinIO distributed, NetApp NFS StorageClass |
| 06 | [Database Setup](docs/OnPrem-KVM/06-Database-Setup.md) | PostgreSQL+Patroni HA, MongoDB ReplicaSet, PgBouncer |
| 07 | [Platform Services](docs/OnPrem-KVM/07-Platform-Services.md) | Harbor, ArgoCD, GitLab CI, Vault, Redis |
| 08 | [Observability and Security](docs/OnPrem-KVM/08-Observability-Security.md) | Prometheus, Grafana, ELK, Jaeger, NetworkPolicy |
| 09 | [Backup and DR](docs/OnPrem-KVM/09-Backup-DR.md) | Velero, Bacula, KVM VM snapshots, etcd backup |

### OnPrem-BareMetal (Kubernetes directly on physical servers)
> Best for: Maximum performance, simpler architecture, dedicated hardware.  
> No hypervisor — K8s runs directly on physical server OS.

| # | Doc | Contents |
|---|-----|----------|
| 00 | [Index](docs/OnPrem-BareMetal/00-Index.md) | Architecture overview, hardware requirements, KVM vs BareMetal comparison |
| 01 | [Server Preparation](docs/OnPrem-BareMetal/01-Server-Preparation.md) | OS install, BIOS tuning, kernel modules, containerd |
| 02 | [Network Configuration](docs/OnPrem-BareMetal/02-Network-Configuration.md) | NIC bonding, VLANs, static IPs, firewall, MetalLB |
| 03 | [Kubernetes Setup](docs/OnPrem-BareMetal/03-Kubernetes-Setup.md) | kubeadm with keepalived VIP, Calico CNI, node labels |
| 04 | [Storage Setup](docs/OnPrem-BareMetal/04-Storage-Setup.md) | MinIO on NVMe, NetApp NFS StorageClass, performance tuning |
| 05 | [Database Setup](docs/OnPrem-BareMetal/05-Database-Setup.md) | PostgreSQL+Patroni, MongoDB ReplicaSet, K8s secrets |
| 06 | [Platform Services](docs/OnPrem-BareMetal/06-Platform-Services.md) | Harbor, ArgoCD, GitLab CI, Vault, Redis |
| 07 | [Observability and Security](docs/OnPrem-BareMetal/07-Observability-Security.md) | Prometheus, Grafana, ELK, Jaeger, NetworkPolicy |
| 08 | [Backup and DR](docs/OnPrem-BareMetal/08-Backup-DR.md) | Velero, Bacula, etcd backup, node recovery runbook |

---

### KVM and OLVM Complete Guide
> Deep-dive reference for KVM hypervisor and OLVM (Oracle Linux Virtualization Manager). Covers installation, networking, storage, security, best practices, VM creation, Kubernetes, monitoring, HTTPS certs, and backup.

| # | Doc | Contents |
|---|-----|----------|
| 00 | [Index](docs/KVM-OLVM-Guide/00-Index.md) | KVM vs OLVM comparison, Azure service mapping, architecture |
| 01 | [KVM Installation](docs/KVM-OLVM-Guide/01-KVM-Installation.md) | Install on OL9/RHEL9/Ubuntu22, SELinux/AppArmor, verify, quick test |
| 02 | [OLVM Installation](docs/KVM-OLVM-Guide/02-OLVM-Installation.md) | Engine setup, add KVM hosts, storage domains, logical networks, HA, REST API |
| 03 | [KVM Networking](docs/KVM-OLVM-Guide/03-KVM-Networking.md) | Linux bridge, bonding, VLANs, macvtap, OVS, SR-IOV, firewall, troubleshooting |
| 04 | [KVM Storage](docs/KVM-OLVM-Guide/04-KVM-Storage.md) | QCOW2, LVM, NFS, iSCSI, snapshots, dirty bitmap incremental, performance tuning |
| 05 | [KVM Security](docs/KVM-OLVM-Guide/05-KVM-Security.md) | sVirt, SELinux, AppArmor, TLS for libvirt, VM isolation, audit logging, secrets |
| 06 | [KVM Best Practices](docs/KVM-OLVM-Guide/06-KVM-Best-Practices.md) | CPU pinning, NUMA, hugepages, KSM, live migration, monitoring, prod checklist |
| 07 | [Creating VMs](docs/KVM-OLVM-Guide/07-Creating-VMs.md) | virt-install, cloud-init, bulk creation script, QEMU guest agent, templates, OLVM UI |
| 08 | [OLVM HTTPS Certificate](docs/KVM-OLVM-Guide/08-OLVM-HTTPS-Certificate.md) | Internal CA, Let's Encrypt, DNS challenge, auto-renewal, cert monitoring |
| 09 | [Kubernetes on KVM](docs/KVM-OLVM-Guide/09-Kubernetes-on-KVM.md) | Provision VMs in OLVM, kubeadm HA, Calico, keepalived VIP, node labels, upgrades |
| 10 | [OLVM Backup](docs/KVM-OLVM-Guide/10-OLVM-Backup.md) | engine-backup, export domain, OVA download, snapshot schedule, REST API automation |
| 11 | [Monitoring and Logging](docs/KVM-OLVM-Guide/11-Monitoring-Logging.md) | node_exporter, libvirt-exporter, OLVM DWH+Grafana, ELK, guest agent metrics, alerts |
| 12 | [Backup and Recovery](docs/KVM-OLVM-Guide/12-Backup-Recovery.md) | Cold backup, live snapshot+blockcommit, dirty bitmaps, Bacula, MinIO, DR runbook |

---

## 🗓️ High-Level Timeline

```
Week  1– 4  │ Phase 1: Procurement & Planning     │ Hardware orders, licensing, design
Week  5– 8  │ Phase 2: Infrastructure Setup        │ Rack & stack, network, VMware, storage
Week  9–12  │ Phase 3: Middleware Deployment       │ F5, Vault, Harbor, Redis, MinIO
Week 13–16  │ Phase 4: Kubernetes Platform Build   │ K8s cluster, ArgoCD, app deploy
Week 17–20  │ Phase 5: Testing & Validation        │ Functional, load, security, DR drill
Week 21–22  │ Phase 6: Go-Live & Cutover           │ DNS switch, Azure to standby
Week 23–26  │ Phase 7: Stabilization               │ Hypercare, tuning, Azure decommission
```

---

## 🔑 Key Diagrams (in docs)

All diagrams use **Mermaid** (rendered natively on GitHub):
- 📊 Migration flowchart (end-to-end)
- 🏗️ On-premises infrastructure topology
- 🗓️ Gantt chart (26-week project plan)
- 🔄 Cutover sequence diagram
- 🗺️ Network VLAN layout
- 📈 Risk quadrant matrix
- 🔐 Vault & K8s security architecture

---

## ⚡ Quick Start for Engineers

```bash
# Start at the executive overview
open docs/Volume-1-Executive-Architecture/01-Executive-Summary.md

# Then follow the migration phases
open docs/Volume-2-Migration-Strategy/02-Phase-Implementation-Guide.md

# For database engineers
open docs/Volume-5-Database-Migration/01-PostgreSQL-HA-Migration.md

# For application engineers
open docs/Volume-6-Application-Migration/01-App-Containerization-And-Deployment.md

# For go-live team
open docs/Volume-8-GoLive-Operations/01-GoLive-Runbook-And-Operations.md
```

---

**Classification**: Internal Use Only | **Version**: 2.0 | **Updated**: July 2026
