# Azure to On-Premises VxRail HCI Migration

> **Objective:** Migrate Azure workloads (AKS, PostgreSQL, Cosmos DB, Storage, Monitoring) to on-premises Dell VxRail 6-node HCI cluster running VMware vSphere  
> **Total Timeline:** 28 weeks (with buffers for approvals, meetings, troubleshooting)  
> **Target Environments:** QA, PREPROD, PROD (separate timelines, sequential migration)

---

## 📋 Migration Overview

### Current State (Azure)
- **Compute:** Azure Kubernetes Service (AKS)
- **Database:** PostgreSQL, Azure Cosmos DB
- **Storage:** Azure Storage Accounts
- **Registry:** Azure Container Registry
- **Backup:** Veeam Backup and Replication
- **Monitoring:** Log Analytics, Application Insights

### Target State (On-Premises)
- **Hypervisor:** VMware vSphere on Dell VxRail 6-node HCI cluster
- **Kubernetes:** Kubernetes on Oracle Linux 9 VMs (kubeadm, 3-master HA)
- **Database:** PostgreSQL with Patroni HA, MongoDB (Cosmos DB alternative)
- **Storage:** vSAN (vSphere Virtual SAN)
- **Registry:** Harbor (self-hosted container registry)
- **Backup:** Veeam Backup and Replication (existing, integrated)
- **Monitoring:** Prometheus + Grafana + ELK Stack

---

## 📅 Timeline Summary

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     MIGRATION TIMELINE — 28 WEEKS                       │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  QA ENVIRONMENT         → Weeks 1–7   (6 weeks work + 1 week buffer)   │
│  PREPROD ENVIRONMENT    → Weeks 8–16  (8 weeks work + 1 week buffer)   │
│  PROD ENVIRONMENT       → Weeks 17–28 (10 weeks work + 2 week buffer)  │
│                                                                         │
│  Total: 28 weeks                                                        │
│  Includes: Approvals, meetings, troubleshooting, testing, validation    │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 🗂️ Repository Structure

```
Migration/
│
├── docs/
│   │
│   ├── 00-README.md                              ← YOU ARE HERE
│   │
│   ├── QA-Environment/                           ← 6-week testing phase
│   │   ├── 00-QA-Timeline.md
│   │   ├── 01-QA-Architecture.md
│   │   ├── 02-QA-Prerequisites.md
│   │   ├── 03-QA-Infrastructure-Setup.md
│   │   ├── 04-QA-Kubernetes-Deployment.md
│   │   ├── 05-QA-Database-Migration.md
│   │   ├── 06-QA-Application-Migration.md
│   │   ├── 07-QA-Veeam-Backup.md
│   │   ├── 08-QA-Cutover-Plan.md
│   │   ├── 09-QA-Validation-Testing.md
│   │   └── 10-QA-Troubleshooting.md
│   │
│   ├── PREPROD-Environment/                      ← 8-week load testing phase
│   │   ├── 00-PREPROD-Timeline.md
│   │   ├── 01-PREPROD-Architecture.md
│   │   ├── 02-PREPROD-Prerequisites.md
│   │   ├── 03-PREPROD-Infrastructure-Setup.md
│   │   ├── 04-PREPROD-Kubernetes-Deployment.md
│   │   ├── 05-PREPROD-Database-Migration.md
│   │   ├── 06-PREPROD-Application-Migration.md
│   │   ├── 07-PREPROD-Veeam-Backup.md
│   │   ├── 08-PREPROD-Cutover-Plan.md
│   │   ├── 09-PREPROD-Performance-Testing.md
│   │   └── 10-PREPROD-Troubleshooting.md
│   │
│   ├── PROD-Environment/                         ← 10-week production migration
│   │   ├── 00-PROD-Timeline.md
│   │   ├── 01-PROD-Architecture.md
│   │   ├── 02-PROD-Prerequisites.md
│   │   ├── 03-PROD-Infrastructure-Setup.md
│   │   ├── 04-PROD-Kubernetes-Deployment.md
│   │   ├── 05-PROD-Database-Migration.md
│   │   ├── 06-PROD-Application-Migration.md
│   │   ├── 07-PROD-Veeam-Backup.md
│   │   ├── 08-PROD-DR-Strategy.md
│   │   ├── 09-PROD-Cutover-Plan.md
│   │   ├── 10-PROD-Troubleshooting.md
│   │   └── 11-PROD-Post-Migration-Operations.md
│   │
│   ├── Shared-Infrastructure/                    ← Common foundation docs
│   │   ├── 00-Shared-Index.md
│   │   ├── 01-VxRail-6Node-Cluster-Setup.md
│   │   ├── 02-Oracle-Linux-9-Template.md
│   │   ├── 03-vSphere-Network-Configuration.md
│   │   ├── 04-vSAN-Storage-Configuration.md
│   │   ├── 05-Kubernetes-HA-Cluster-Setup.md
│   │   ├── 06-PostgreSQL-Patroni-HA.md
│   │   ├── 07-Cosmos-DB-Migration-Strategy.md
│   │   ├── 08-Harbor-Container-Registry.md
│   │   ├── 09-Monitoring-Stack-Setup.md
│   │   ├── 10-Security-VPN-DNS-Configuration.md
│   │   └── 11-Common-Troubleshooting-Guide.md
│   │
│   └── VxRail-VMware-Migration/                  ← Legacy reference (optional)
│       └── (Keep original files for detailed reference)
│
└── README.md                                      ← Repo root README

```

---

## 🚀 Quick Start

### Choose Your Environment

**👉 Start with your environment:**

1. **[QA Environment (Weeks 1-7)](QA-Environment/00-QA-Timeline.md)**
   - Start here for testing and validation
   - Smaller workloads, faster iteration
   - 6 weeks of work + 1 week buffer

2. **[PREPROD Environment (Weeks 8-16)](PREPROD-Environment/00-PREPROD-Timeline.md)**
   - After QA sign-off
   - Load testing and performance validation
   - 8 weeks of work + 1 week buffer

3. **[PROD Environment (Weeks 17-28)](PROD-Environment/00-PROD-Timeline.md)**
   - Final production migration
   - Zero-downtime cutover strategy
   - 10 weeks of work + 2 week buffer

---

## 🔧 Shared Infrastructure Setup

**Before starting ANY environment, complete the shared infrastructure foundation:**

Read in this order:
1. [Shared Index](Shared-Infrastructure/00-Shared-Index.md) — Overview
2. [VxRail 6-Node Cluster](Shared-Infrastructure/01-VxRail-6Node-Cluster-Setup.md) — Physical infrastructure
3. [Oracle Linux 9 Template](Shared-Infrastructure/02-Oracle-Linux-9-Template.md) — OS setup
4. [vSphere Network](Shared-Infrastructure/03-vSphere-Network-Configuration.md) — DVS, VLANs, firewall
5. [vSAN Storage](Shared-Infrastructure/04-vSAN-Storage-Configuration.md) — Storage policies
6. [Kubernetes HA](Shared-Infrastructure/05-Kubernetes-HA-Cluster-Setup.md) — K8s foundation
7. [PostgreSQL Patroni](Shared-Infrastructure/06-PostgreSQL-Patroni-HA.md) — Database HA
8. [Harbor Registry](Shared-Infrastructure/08-Harbor-Container-Registry.md) — Container registry
9. [Monitoring Stack](Shared-Infrastructure/09-Monitoring-Stack-Setup.md) — Prometheus/Grafana/ELK
10. [Security & VPN](Shared-Infrastructure/10-Security-VPN-DNS-Configuration.md) — VPN, DNS, RBAC

---

## 📊 Key Dates & Milestones

| Phase | Start | End | Duration | Key Milestones |
|-------|-------|-----|----------|---|
| **QA** | Week 1 | Week 7 | 6 wks + buffer | Infrastructure → K8s → DB → Apps → Validation → Sign-off |
| **PREPROD** | Week 8 | Week 16 | 8 wks + buffer | Infra replication → Load testing → Performance validation → Approval gate |
| **PROD** | Week 17 | Week 28 | 10 wks + buffer | Infra → Live replication → Cutover window → Hypercare → Azure decommission |

---

## ✅ Pre-Migration Checklist

Before starting Week 1:

- [ ] **Stakeholder Alignment**
  - [ ] Executive sponsor approval
  - [ ] Change control board notification
  - [ ] Team resource allocation confirmed

- [ ] **Procurement Completed**
  - [ ] Dell VxRail 6-node cluster (already in place)
  - [ ] Network switches (ordered & delivered)
  - [ ] NAS/backup storage (if needed)
  - [ ] VMware licenses (vSphere, vSAN)
  - [ ] Veeam licenses (v12 or later)

- [ ] **Current State Documented**
  - [ ] Azure workload inventory created
  - [ ] Database schemas documented
  - [ ] Data volumes and backup sizes recorded
  - [ ] Application dependency map created

- [ ] **Infrastructure Ready**
  - [ ] VxRail cluster powered on and basic config complete
  - [ ] vSphere cluster accessible via vCenter
  - [ ] Network connectivity to on-prem facility confirmed
  - [ ] Jump host available for management access

- [ ] **Team Prepared**
  - [ ] VMware vSphere admin assigned
  - [ ] Kubernetes admin assigned
  - [ ] PostgreSQL DBA assigned
  - [ ] Network admin assigned
  - [ ] Backup admin assigned
  - [ ] Application team engaged

---

## 📞 Support & Troubleshooting

**Environment-Specific Issues:**
- QA: See [QA Troubleshooting](QA-Environment/10-QA-Troubleshooting.md)
- PREPROD: See [PREPROD Troubleshooting](PREPROD-Environment/10-PREPROD-Troubleshooting.md)
- PROD: See [PROD Troubleshooting](PROD-Environment/10-PROD-Troubleshooting.md)

**Common Issues (All Environments):**
- See [Common Troubleshooting Guide](Shared-Infrastructure/11-Common-Troubleshooting-Guide.md)

---

## 📝 Document Status

- **Created:** August 2026
- **Last Updated:** August 2026
- **Owner:** Infrastructure Team
- **Classification:** Internal Use Only

---

## Next Steps

1. **Confirm Timeline** — Review timelines with your team
2. **Assign Resources** — Allocate team members to each phase
3. **Start Shared Infrastructure** — Begin foundation setup
4. **Schedule Kickoff** — Plan QA phase kickoff meeting

**Ready to begin? Start with [QA Environment Timeline →](QA-Environment/00-QA-Timeline.md)**
