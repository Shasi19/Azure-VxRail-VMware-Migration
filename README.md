# Azure → On-Premises Migration
## Dell VxRail HCI + VMware vSphere

> **Your Infrastructure:** 6-node Dell VxRail HCI cluster running VMware vSphere  
> **Source:** Azure (AKS + Cosmos DB + ACR + PostgreSQL + Storage) — Dev / QA / PreProd / Prod  
> **Target:** Kubernetes on Oracle Linux 9 VMs on VxRail + vSAN  
> **Backup:** Veeam Backup and Replication (existing)  
> **Timeline:** 32 weeks including procurement buffers and approval gates

---

## Repository Structure

```
Migration/
│
├── docs/
│   │
│   ├── VxRail-VMware-Migration/     ← YOUR PRIMARY MIGRATION GUIDE (18 files)
│   │   ├── 00-Index.md              ← Start here — master flow and 32-week timeline
│   │   ├── 01-Architecture-Overview.md
│   │   ├── 02 through 17 ...
│   │
│   ├── Presentation/                ← HLD / LLD / Executive slides (4 files)
│   │   ├── 00-Index.md
│   │   ├── 01-Executive-Presentation.md
│   │   ├── 02-HLD-High-Level-Design.md
│   │   └── 03-LLD-Low-Level-Design.md
│   │
│   └── Reference/                   ← Optional reference guides (57 files)
│       ├── 00-Reference-Index.md
│       ├── KVM-OLVM-Guide/          ← KVM + OLVM deep dive (13 files)
│       ├── OnPrem-KVM/              ← Migration guide for KVM infra (10 files)
│       ├── OnPrem-BareMetal/        ← Migration guide for bare-metal (9 files)
│       ├── Volume-1-Executive-Architecture/
│       ├── Volume-2-Migration-Strategy/
│       ├── Volume-3-Infrastructure-Setup/
│       ├── Volume-4-Kubernetes-Platform/
│       ├── Volume-5-Database-Migration/
│       ├── Volume-6-Application-Migration/
│       ├── Volume-7-Monitoring-Security/
│       └── Volume-8-GoLive-Operations/
│
└── README.md                        ← This file
```

---

## Start Here

### → [VxRail Migration Master Index](docs/VxRail-VMware-Migration/00-Index.md)

---

## VxRail Migration — All 18 Files in Order

| # | File | What It Covers | When |
|---|------|---------------|------|
| 00 | [Index + 32-Week Timeline](docs/VxRail-VMware-Migration/00-Index.md) | Master flow, VM allocation, IP plan, Azure mapping | Day 0 |
| 01 | [**Architecture Overview**](docs/VxRail-VMware-Migration/01-Architecture-Overview.md) | **Current Azure** + **Current VxRail on-prem** + **Target architecture** + Procurement list + Why every tool is used | Day 0 — Read First |
| 02 | [Current Infra Inventory](docs/VxRail-VMware-Migration/02-Current-Infra-Inventory.md) | Audit your VxRail cluster — model, resources, audit scripts | Week 1–2 |
| 03 | [Procurement Guide](docs/VxRail-VMware-Migration/03-Procurement-Guide.md) | What to order — switch, NAS, VPN, licenses with prices + lead times | Week 1–3 |
| 04 | [Initial Setup (Pre-Migration)](docs/VxRail-VMware-Migration/04-Initial-Setup-Before-Migration.md) | 15-step foundation — DNS, NTP, CA, VPN, jump host, Ansible | Weeks 5–8 |
| 05 | [Infrastructure Assessment](docs/VxRail-VMware-Migration/05-Infrastructure-Assessment.md) | vSphere + vSAN capacity audit, readiness checklist | Week 8 |
| 06 | [Oracle Linux 9 VMs](docs/VxRail-VMware-Migration/06-Oracle-Linux-VMs.md) | OL9 template, dnf commands, cloud-init, SELinux, firewalld | Weeks 9–10 |
| 07 | [VM Provisioning (vSphere)](docs/VxRail-VMware-Migration/07-VM-Provisioning-vSphere.md) | Create all 27 VMs with govc, bulk clone script, DRS rules | Week 10 |
| 08 | [Network (DVS + firewalld)](docs/VxRail-VMware-Migration/08-Network-vSphere.md) | DVS VLANs, MetalLB, keepalived VIP, firewalld rules | Weeks 10–11 |
| 09 | [Storage (vSAN + CSI)](docs/VxRail-VMware-Migration/09-Storage-vSAN.md) | vSAN policies, vSphere CSI driver, StorageClasses, MinIO | Week 11 |
| 10 | [Kubernetes on vSphere](docs/VxRail-VMware-Migration/10-Kubernetes-vSphere.md) | kubeadm 3-master HA, Calico CNI, MetalLB, vSphere CCM | Weeks 11–12 |
| 11 | [Veeam Backup](docs/VxRail-VMware-Migration/11-Veeam-Backup.md) | Veeam B&R v12, VM jobs, Veeam Agent on OL9, Kasten K10, restore | Week 12 |
| 12 | [**Migration Execution**](docs/VxRail-VMware-Migration/12-Migration-Execution.md) | **Master commands** — Harbor, ArgoCD, PostgreSQL, MongoDB, app deploy, cutover | Weeks 13–28 |
| 13 | [Phase 1 — Dev + QA](docs/VxRail-VMware-Migration/13-Phase1-Dev-QA.md) | Week-by-week plan — DB migrate → app deploy → validate → sign-off | Weeks 13–22 |
| 14 | [Phase 2 — PreProd + Prod](docs/VxRail-VMware-Migration/14-Phase2-PreProd-Prod.md) | Patroni HA, pglogical live replication, maintenance window cutover | Weeks 21–30 |
| 15 | [Cutover Runbook](docs/VxRail-VMware-Migration/15-Cutover-Runbook.md) | DNS cutover scripts, smoke tests, rollback decision tree, 72h monitoring | Weeks 22 + 31 |
| 16 | [Patching Cycles](docs/VxRail-VMware-Migration/16-Patching-Cycles.md) | Monthly / Quarterly / Semi-annual / Annual patch cycles | Ongoing |
| 17 | [**Troubleshooting Errors**](docs/VxRail-VMware-Migration/17-Troubleshooting-Errors.md) | **Every likely error** at every stage — vSphere, K8s, DB, Veeam, DNS, VPN — with fixes | Reference |

---

## Presentation Docs (For Stakeholders)

| File | Audience | Contents |
|------|---------|---------|
| [00 Index](docs/Presentation/00-Index.md) | All | Navigation |
| [01 Executive Presentation](docs/Presentation/01-Executive-Presentation.md) | CTO / Board | Business case, ROI, timeline, risk summary |
| [02 HLD — High Level Design](docs/Presentation/02-HLD-High-Level-Design.md) | Architects | Architecture, traffic flow, security, CI/CD |
| [03 LLD — Low Level Design](docs/Presentation/03-LLD-Low-Level-Design.md) | Engineers | IP plan, hardware specs, K8s resources, DNS |

---

## Reference Guides (Optional)

> Not needed for VxRail migration. Useful if you work with KVM, bare-metal, or need generic K8s / DB references.

| Guide | Contents |
|-------|---------|
| [Reference Index](docs/Reference/00-Reference-Index.md) | Overview of all reference guides |
| [KVM-OLVM-Guide](docs/Reference/KVM-OLVM-Guide/00-Index.md) | KVM hypervisor + OLVM deep dive (13 files) |
| [OnPrem-KVM](docs/Reference/OnPrem-KVM/00-Index.md) | Full migration guide for KVM-based infra |
| [OnPrem-BareMetal](docs/Reference/OnPrem-BareMetal/00-Index.md) | Full migration guide for bare-metal servers |
| [Volume 1 — Executive Architecture](docs/Reference/Volume-1-Executive-Architecture/) | Executive summary, Azure + on-prem architecture visuals |
| [Volume 2 — Migration Strategy](docs/Reference/Volume-2-Migration-Strategy/) | Strategy, Gantt, risk register, multi-env plan |
| [Volume 3 — Infrastructure Setup](docs/Reference/Volume-3-Infrastructure-Setup/) | Generic network + compute config |
| [Volume 4 — Kubernetes Platform](docs/Reference/Volume-4-Kubernetes-Platform/) | K8s setup guide + detailed commands reference |
| [Volume 5 — Database Migration](docs/Reference/Volume-5-Database-Migration/) | PostgreSQL HA + Patroni generic guide |
| [Volume 6 — Application Migration](docs/Reference/Volume-6-Application-Migration/) | Containerization, Helm, ArgoCD, GitLab CI |
| [Volume 7 — Monitoring and Security](docs/Reference/Volume-7-Monitoring-Security/) | Prometheus, Grafana, ELK, Vault, NetworkPolicy |
| [Volume 8 — Go-Live and Operations](docs/Reference/Volume-8-GoLive-Operations/) | Go-live runbook, rollback plan, daily ops |

---

## 32-Week Timeline Summary

```
Weeks  1– 4  │ Discovery + Procurement order placed     │ Hardware lead time starts
Weeks  5– 8  │ Hardware delivery + Foundation setup     │ DNS, NTP, CA, VPN, Ansible
Weeks  9–12  │ Infrastructure build                     │ OL9 VMs, K8s, Veeam, Harbor
Week      13 │ Buffer — fix infra errors                │
Weeks 13–22  │ Phase 1: Dev + QA migration              │ DB migrate → app → validate
Week      22 │ Dev + QA DNS cutover                     │ PHASE 1 COMPLETE
Weeks 23–27  │ Phase 2: PreProd migration               │ Patroni HA + validate
Weeks 28–31  │ Phase 2: Prod migration + cutover        │ pglogical live replication
Weeks 31–32  │ Hypercare + Azure decommission           │ PROJECT COMPLETE
```

---

**Classification:** Internal Use Only &nbsp;|&nbsp; **Last Updated:** July 2026
