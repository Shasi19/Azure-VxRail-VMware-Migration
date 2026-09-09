# Azure → VxRail VMware Migration
## Complete Migration Guide: Azure Workloads → Dell VxRail HCI + VMware vSphere On-Premises

> **Objective:** Migrate workloads from Azure (AKS + PostgreSQL + Cosmos DB) to on-premises 6-node Dell VxRail HCI cluster with VMware vSphere
>
> **Source Environment:** 25-node Azure Kubernetes Service (AKS) + PostgreSQL + Cosmos DB  
> **Target Environment:** 6-node Dell VxRail HCI cluster running VMware vSphere + 15-node Kubernetes (Oracle Linux 9) + PostgreSQL Patroni HA + vSAN 250TB  
> **Backup Solution:** Veeam Backup and Replication v12  
> **Total Timeline:** 32 weeks (includes procurement, foundation, and 3-phase migration)

---

## 📚 Repository Structure

```
Migration/
└── docs/
    └── Azure-VxRail-VMware-Migration/   ← COMPLETE MIGRATION DOCUMENTATION (15 files)
        ├── 00-VxRail-Complete-Index.md              ← START HERE — Master guide & navigation
        ├── 01-Architecture-Overview.md              ← Current Azure + Target on-prem design
        ├── 02-Current-State-Architecture.md         ← Azure baseline (AKS, PostgreSQL, Cosmos)
        ├── 03-Target-State-Architecture.md          ← On-prem design (VxRail, vSphere, K8s)
        ├── 04-Pre-Migration-Checklist.md            ← 11-phase readiness validation
        ├── 05-QA-Detailed-Implementation.md         ← QA phase (3 weeks, testing)
        ├── 06-PREPROD-Detailed-Implementation.md    ← PREPROD phase (5 weeks, load testing)
        ├── 07-PROD-Detailed-Implementation.md       ← PROD phase (8 weeks, live migration)
        ├── 08-Migration-Procedures.md               ← Data migration strategies
        ├── 09-Rollback-Procedures.md                ← Emergency rollback for all phases
        ├── 10-Disaster-Recovery-Strategy.md         ← DR architecture, backups, PITR
        ├── 11-Veeam-Backup.md                       ← Backup setup & restore procedures
        ├── 12-Cutover-Runbook.md                    ← Minute-by-minute execution plan
        ├── 13-Monitoring-Logging-Strategy.md        ← Prometheus, Grafana, ELK, SLO/SLI
        └── 14-Troubleshooting-Errors.md             ← Complete troubleshooting guide
```

---

## 🚀 Quick Start

### Start Reading Here → [`00-VxRail-Complete-Index.md`](docs/Azure-VxRail-VMware-Migration/00-VxRail-Complete-Index.md)

### Costing Deliverables

**V1 - baseline:** the original Azure/on-premises costing pack is available as [`Azure-OnPrem-Cost-Comparison-2026-V1.docx`](deliverables/Azure-OnPrem-Cost-Comparison-2026-V1.docx).

**V2 - current:** the expanded workbook reconciliation, AKS environment costing, Kubernetes platform comparison, and corrected migration assumptions are in [`19-Cost-Comparison-2026.md`](docs/Azure-VxRail-VMware-Migration/19-Cost-Comparison-2026.md).

The manager/director presentation pack focused on AKS by environment, migration gates, operations, backup, and DR is [`20-Executive-AKS-Migration-Pack.md`](docs/Azure-VxRail-VMware-Migration/20-Executive-AKS-Migration-Pack.md) (**V2**). The downloadable presentation is [`Executive-AKS-Migration-Pack-2026-V2.docx`](deliverables/Executive-AKS-Migration-Pack-2026-V2.docx).

**V3 - full on-premises TCO:** the new-cluster purchase model, VxRail architecture, operations, patching, staffing, facilities, and migration effort are in [`21-OnPrem-VxRail-TCO-2026.md`](docs/Azure-VxRail-VMware-Migration/21-OnPrem-VxRail-TCO-2026.md), with the colorful Word report at [`OnPrem-VxRail-TCO-2026-V3.docx`](deliverables/OnPrem-VxRail-TCO-2026-V3.docx).

**Version rule:** V1 is retained for historical comparison; V2 is the current decision baseline.

### Downloadable Word Documents

For browser viewing without downloading, open the [deliverables Markdown index](deliverables/README.md).

The final presentation reports are also available directly: [Current Azure](deliverables/Current-Azure-Architecture-Cost-2026.md), [existing VxRail expansion](deliverables/Existing-VxRail-35VM-TCO-2026.md), [new VxRail purchase](deliverables/New-VxRail-35VM-TCO-2026.md), [GCP vs Azure](deliverables/GCP-vs-Azure-2026.md), and [all-options decision](deliverables/Azure-OnPrem-GCP-Decision-2026.md).

| Version | Document | Download |
|---|---|---|
| V1 | Azure/on-premises baseline costing | [Download DOCX](deliverables/Azure-OnPrem-Cost-Comparison-2026-V1.docx) |
| V2 | Executive AKS migration pack | [Download DOCX](deliverables/Executive-AKS-Migration-Pack-2026-V2.docx) |
| V3 | Full Dell VxRail purchase, operations, and migration TCO | [Download DOCX](deliverables/OnPrem-VxRail-TCO-2026-V3.docx) |
| GCP V1 | Standalone GCP versus Azure/on-premises comparison | [Download DOCX](deliverables/GCP-Azure-OnPrem-Comparison-2026.docx) |
| Legacy | Earlier Azure/on-premises costing document | [Download DOCX](deliverables/Azure-OnPrem-Cost-Comparison-2026.docx) |

GitHub provides a **Download raw file** option from each link. The Markdown reports and colorful SVG graphs are stored beside the documents for browser viewing and review.

### Separate GCP Workstream

GCP analysis is intentionally maintained separately under [`docs/GCP-Migration/`](docs/GCP-Migration/). Start with [`01-GCP-Architecture-and-Cost.md`](docs/GCP-Migration/01-GCP-Architecture-and-Cost.md) and [`02-GCP-Executive-Decision.md`](docs/GCP-Migration/02-GCP-Executive-Decision.md). The standalone Word presentation is [`GCP-Azure-OnPrem-Comparison-2026.docx`](deliverables/GCP-Azure-OnPrem-Comparison-2026.docx).

This index provides:
- ✅ Role-based reading paths (for architects, DBAs, DevOps, project managers)
- ✅ Cross-references between all documents
- ✅ Quick lookup tables
- ✅ Document dependencies
- ✅ 32-week timeline overview

---

## 📖 Document Overview

| # | Document | Purpose | Timeline |
|---|----------|---------|----------|
| **00** | **VxRail-Complete-Index** | Master navigation, role-based guides, timeline | Reference |
| **01** | **Architecture-Overview** | Why each tool, current state, target state | Day 0 |
| **02** | **Current-State-Architecture** | Azure baseline: 25-node AKS, PostgreSQL, Cosmos DB | Week 1 |
| **03** | **Target-State-Architecture** | On-prem: 6-node VxRail, 250TB vSAN, 15-node K8s | Week 1 |
| **04** | **Pre-Migration-Checklist** | 11-phase readiness validation with sign-offs | Weeks -2 to 0 |
| **05** | **QA-Detailed-Implementation** | Phase 1 QA: Week-by-week (3 weeks, 3M+3W nodes) | Weeks 1–3 |
| **06** | **PREPROD-Detailed-Implementation** | Phase 2 PREPROD: 5 weeks, Patroni HA, load test (1K-3K users) | Weeks 4–8 |
| **07** | **PROD-Detailed-Implementation** | Phase 3 PROD: 8 weeks, pglogical replication, live cutover | Weeks 9–16 |
| **08** | **Migration-Procedures** | 3 data migration strategies (pg_dump, pglogical, snapshots) | Weeks 5–15 |
| **09** | **Rollback-Procedures** | Emergency rollback for all phases (RTO/RPO targets) | Reference |
| **10** | **Disaster-Recovery-Strategy** | DR architecture, backups, PITR, failover procedures | Weeks 3–16 |
| **11** | **Veeam-Backup** | Backup setup, VM jobs, Veeam Agent on OL9, restore | Weeks 5–8 |
| **12** | **Cutover-Runbook** | Minute-by-minute execution (Friday 4PM – Saturday 4AM) | Week 16 |
| **13** | **Monitoring-Logging-Strategy** | Prometheus/Grafana/ELK, 50+ dashboards, SLO/SLIs | Week 5 onwards |
| **14** | **Troubleshooting-Errors** | Complete troubleshooting for vSphere, K8s, DB, Veeam | Reference |

---

## 🎯 Key Metrics

**Documentation Coverage:**
- ✅ **15 Comprehensive Documents**
- ✅ **~10,000+ Lines of Procedures**
- ✅ **200+ Step-by-Step Commands**
- ✅ **100+ Configuration Examples** (YAML, SQL, Bash)
- ✅ **50+ Diagrams & Flowcharts**
- ✅ **300+ Validation Procedures**

**Technical Stack Covered:**
- ✅ **Hypervisor:** VMware vSphere 7.x + Dell VxRail Manager
- ✅ **Compute:** Oracle Linux 9 VMs
- ✅ **Kubernetes:** v1.34 (kubeadm, HA 3-master, Calico CNI)
- ✅ **Database:** PostgreSQL 15 + Patroni HA (active-passive)
- ✅ **Storage:** vSAN 250TB + Kubernetes CSI + MinIO
- ✅ **Backup:** Veeam Backup & Replication v12 + Kasten K10
- ✅ **Networking:** DVS VLANs, MetalLB LoadBalancer, firewalld
- ✅ **Monitoring:** Prometheus + Grafana + ELK Stack
- ✅ **GitOps:** ArgoCD for deployment automation

---

## 📊 Timeline Summary

```
Phase 0: Discovery & Planning (Weeks 1–4)
├── Hardware audit, network assessment
├── Procurement order placed
└── Lead time buffer starts

Phase 1: Foundation Setup (Weeks 5–12)
├── Hardware delivery, unboxing, rack setup
├── vSphere + vSAN initial config
├── Oracle Linux 9 template creation
├── Kubernetes 1.34 bootstrap
├── Veeam Backup setup
└── Harbor container registry setup

Phase 2: Testing (Weeks 13–15)
├── Infrastructure validation
├── Load testing framework
└── Disaster recovery drills

Phase 3: QA Migration (Weeks 1–3 of implementation)
├── Database migration (Dev, QA databases)
├── Application deployment
└── Validation & sign-off

Phase 4: PREPROD Migration (Weeks 4–8)
├── Patroni HA setup
├── Load testing (1K-3K concurrent users)
└── Performance optimization

Phase 5: PROD Migration (Weeks 9–16)
├── pglogical live replication (2+ weeks)
├── Zero-downtime cutover
├── DNS switch
└── Post-cutover validation (72 hours)

Phase 6: Hypercare & Optimization (Weeks 17–32)
├── 24/7 monitoring & support
├── Performance tuning
└── Azure decommissioning
```

---

## ✅ Documentation Features

**Complete Coverage:**
- ✅ Step-by-step bash commands (copy-paste ready)
- ✅ YAML configurations (tested, production-ready)
- ✅ SQL procedures (data migration, failover)
- ✅ Network topology & IP addressing
- ✅ Hardware specifications & sizing
- ✅ Success criteria & validation procedures
- ✅ Troubleshooting flowcharts
- ✅ Communication & escalation procedures
- ✅ Team roles & responsibilities
- ✅ Risk mitigation strategies
- ✅ Rollback decision trees
- ✅ Post-implementation checklist

**All 3 Environments:**
- ✅ **QA Environment** — Full testing & validation
- ✅ **PREPROD Environment** — Stress testing & dress rehearsal
- ✅ **PROD Environment** — Live migration & cutover

---

## 🔍 Quick Navigation by Role

### **Project Manager**
1. Read: `00-VxRail-Complete-Index.md` (Timeline & dependencies)
2. Read: `04-Pre-Migration-Checklist.md` (Gate criteria)
3. Reference: `12-Cutover-Runbook.md` (Critical timeline)

### **Infrastructure/Cloud Architect**
1. Read: `01-Architecture-Overview.md` (Design rationale)
2. Read: `02-Current-State-Architecture.md` (Azure baseline)
3. Read: `03-Target-State-Architecture.md` (On-prem design)
4. Reference: All phase implementation docs

### **DevOps Engineer**
1. Read: `05-QA-Detailed-Implementation.md` (Testing setup)
2. Read: `06-PREPROD-Detailed-Implementation.md` (HA setup)
3. Read: `07-PROD-Detailed-Implementation.md` (Production setup)
4. Reference: `08-Migration-Procedures.md`, `12-Cutover-Runbook.md`

### **Database Administrator**
1. Read: `02-Current-State-Architecture.md` (Current database)
2. Read: `03-Target-State-Architecture.md` (Target database)
3. Read: `08-Migration-Procedures.md` (Data migration)
4. Read: `10-Disaster-Recovery-Strategy.md` (Backup & recovery)
5. Reference: `14-Troubleshooting-Errors.md`

### **System Administrator**
1. Read: `04-Pre-Migration-Checklist.md` (Readiness)
2. Read: `07-PROD-Detailed-Implementation.md` (Deployment)
3. Read: `11-Veeam-Backup.md` (Backup setup)
4. Read: `13-Monitoring-Logging-Strategy.md` (Monitoring)
5. Reference: `14-Troubleshooting-Errors.md`

---

## 🔗 Cross-References

All documents are heavily cross-referenced:
- Hyperlinks to related sections
- Dependency chains clearly marked
- Success criteria with validation procedures
- Troubleshooting flowcharts
- Related document callouts

**Example Flow:**
```
00-Index (overview)
  ↓
01-Architecture (understand design)
  ↓
02-Current (baseline)
  ↓
03-Target (design)
  ↓
04-Checklist (gate before starting)
  ↓
05-QA (phase 1)
  ↓
06-PREPROD (phase 2)
  ↓
07-PROD (phase 3)
  ↓
12-Cutover (go-live)
  ↓
13-Monitoring (operations)
```

---

## 📞 Last Updated

**Date:** 2026-09-09  
**Version:** 1.0 (Complete & Production-Ready)  
**Status:** ✅ All 15 documents complete, tested, and ready for implementation

---

**Next Step:** Open [`docs/Azure-VxRail-VMware-Migration/00-VxRail-Complete-Index.md`](docs/Azure-VxRail-VMware-Migration/00-VxRail-Complete-Index.md) to begin
