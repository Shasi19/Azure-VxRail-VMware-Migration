# Azure vs Existing VxRail vs Kubernetes Platforms

**Date:** 2026-09-09  
**Audience:** CTO, directors, finance, infrastructure, and steering committee  
**Scope:** Current architecture resources, 35-VM on-premises target, and Kubernetes platform choices

## Executive summary

The current Azure workbook provides a **$23,754/month** or **$285,048/year** subscription control total. Only **$6,352/month** is directly mapped to named architecture resources in the visible workbook rows. The remaining **$17,402/month** must be reconciled by Azure resource ID before it is allocated to networking, ACR, monitoring, backup, WAF, database, or shared services.

For the 35-VM target on the existing VxRail cluster, the common operating cost is **$39,500-$106,700/month** or **$474,000-$1,280,000/year**, before Kubernetes platform support. Adding platform support gives:

| Kubernetes option | Monthly total | Annual total |
|---|---:|---:|
| OpenShift | **$47,000-$121,700** | **$564,000-$1,460,000** |
| SUSE Rancher Prime | **$42,400-$114,200** | **$509,000-$1,370,000** |
| Canonical Kubernetes | **$41,000-$111,300** | **$492,000-$1,335,000** |

These are budgetary ranges. Azure values come from the supplied workbook; on-premises and platform values require Dell/Broadcom/vendor quotes.

## 1. Azure current architecture cost

| Azure resource in architecture | Monthly low | Monthly high | Annual low | Annual high | Cost basis |
|---|---:|---:|---:|---:|---|
| AKS node pools | $2,370 | $2,370 | $28,440 | $28,440 | Workbook AKS rows: QA, PREPROD, and two PROD rows |
| PostgreSQL Flexible Server | $719 visible | $719 visible | $8,628 visible | $8,628 visible | Only PREPROD row is visible; QA/PROD require export |
| Cosmos DB MongoDB API | $396 | $396 | $4,752 | $4,752 | QA, PREPROD, PROD visible rows |
| Mapped Storage Accounts | $2,298 | $2,298 | $27,576 | $27,576 | Application and backup storage rows mapped to architecture |
| Mapped managed disk | $330 | $330 | $3,960 | $3,960 | 2 TB named disk; ownership still requires confirmation |
| Bastion | $239 | $239 | $2,868 | $2,868 | Visible Bastion row |
| ACR Premium | Not identifiable | Not identifiable | Not identifiable | Not identifiable | Architecture service; no dedicated visible workbook row |
| Azure Monitor/App Insights/Log Analytics/ELK | Not identifiable | Not identifiable | Not identifiable | Not identifiable | Architecture service; reconcile by resource ID |
| Firewall/VPN/ExpressRoute/WAF/DNS/Key Vault | $17,402 residual | $17,402 residual | $208,824 residual | $208,824 residual | Residual full subscription amount, not allocated to individual services |
| **Full Azure subscription control total** | **$23,754** | **$23,754** | **$285,048** | **$285,048** | Workbook Cost Summary sheet |

> The residual `$17,402/month` is not a claim that networking alone costs that amount. It is the unreconciled difference between the full subscription total and named architecture-mapped rows.

### Azure environment view

| Environment | Monthly visible cost | Annual visible cost |
|---|---:|---:|
| QA | $526 | $6,312 |
| PREPROD | $1,040 | $12,480 |
| PROD | $2,029 | $24,348 |
| **Visible environment subtotal** | **$3,595** | **$43,140** |

## 2. On-premises target-state expense

Target: **35 VMs** comprising 18 Kubernetes VMs, 7 PostgreSQL VMs, and 10 platform/operations VMs. Sizing is approximately 556 vCPU, 2.22 TB RAM, and 14.2 TB logical storage.

### One-time existing-cluster expansion

| Expense | Low | High | Treatment |
|---|---:|---:|---|
| Certified RAM expansion | $80,000 | $250,000 | Main requirement; current free RAM is approximately 1.38 TB |
| Licensing uplift | $25,000 | $100,000 | vSphere/vSAN entitlement and support |
| Backup/network/power additions | $20,000 | $70,000 | Repository, optics, ports, UPS/PDU allocation |
| Validation and implementation | $15,000 | $40,000 | Rebalance, burn-in, acceptance |
| **Expansion total** | **$140,000** | **$460,000** |
| **Approval envelope with contingency** | **$155,000** | **$510,000** |

Migration program is separate: **$180,000-$420,000** one time over approximately 20-28 weeks.

### Common on-premises monthly and annual expenses

| Expense | Monthly low | Monthly high | Annual low | Annual high |
|---|---:|---:|---:|---:|
| VxRail hardware support | $5,000 | $12,500 | $60,000 | $150,000 |
| VMware/vSphere/vSAN | $4,200 | $12,500 | $50,000 | $150,000 |
| PostgreSQL HA and DBA | $3,000 | $10,000 | $36,000 | $120,000 |
| Mongo-compatible database | $1,000 | $4,000 | $12,000 | $48,000 |
| Storage/PVC/object storage | $500 | $2,000 | $6,000 | $24,000 |
| Backup and offsite DR | $2,100 | $6,250 | $25,000 | $75,000 |
| Network/security/DNS/VPN | $1,000 | $4,000 | $12,000 | $48,000 |
| Monitoring/logging | $1,500 | $5,000 | $18,000 | $60,000 |
| OS/security/platform support | $2,100 | $6,250 | $25,000 | $75,000 |
| Operations staffing | $15,000 | $33,333 | $180,000 | $400,000 |
| Refresh/spare reserve | $1,250 | $3,333 | $15,000 | $40,000 |
| **Common operating total** | **$39,500** | **$106,700** | **$474,000** | **$1,280,000** |

Operational work includes monthly OS patching, quarterly Kubernetes upgrades, VxRail/vSphere maintenance, PostgreSQL failover/PITR testing, backup restores, certificate rotation, vulnerability remediation, capacity reviews, incidents, and on-call. Two FTE is a minimum shared model; 3-4 FTE is more realistic for 24x7 production ownership.

## 3. Kubernetes platform cost side by side

| Platform | License/support monthly | License/support annual | Common monthly | **Total monthly** | **Total annual** | Why choose it |
|---|---:|---:|---:|---:|---:|---|
| OpenShift | $7,500-$15,000 | $90,000-$180,000 | $39,500-$106,700 | **$47,000-$121,700** | **$564,000-$1,460,000** | Red Hat support, certified operators, compliance, existing Red Hat agreement |
| SUSE Rancher Prime | $2,917-$7,500 | $35,000-$90,000 | $39,500-$106,700 | **$42,400-$114,200** | **$509,000-$1,370,000** | Multi-cluster governance and distribution flexibility |
| Canonical Kubernetes | $1,500-$4,583 | $18,000-$55,000 | $39,500-$106,700 | **$41,000-$111,300** | **$492,000-$1,335,000** | Lowest commercial platform cost; more internal lifecycle responsibility |

## 4. Three-way decision

| Option | Monthly / annual run rate | One-time cost | Three-year planning view | Recommendation |
|---|---:|---:|---:|---|
| Azure existing | $23,754 / $285,048 measured | Low migration | $855,144 current bill | **Best immediate choice** |
| Existing VxRail + Canonical | $41,000-$111,300 / $492,000-$1,335,000 | $155,000-$510,000 + migration | Approximately $1.30M-$3.39M | Best on-premises value |
| Existing VxRail + Rancher | $42,400-$114,200 / $509,000-$1,370,000 | $155,000-$510,000 + migration | Higher than Canonical | Best governance middle option |
| Existing VxRail + OpenShift | $47,000-$121,700 / $564,000-$1,460,000 | $155,000-$510,000 + migration | Highest platform premium | Only with Red Hat justification |
| GCP | $14,000-$36,000 / $168,000-$432,000 planning | $80,000-$195,000 migration | $584,000-$1.49M planning | POC only with strategic value |

## Final justification

Choose **Azure now** because it is running, measurable, and has the lowest transition risk. Choose **existing VxRail expansion** if sovereignty, latency, or regulation requires on-premises; it is preferable to buying a new cluster. Choose **Canonical Kubernetes** when cost and upstream alignment matter, **Rancher Prime** when centralized governance matters, and **OpenShift** when Red Hat enterprise support/compliance outweighs its premium. Choose **GCP** only after a pricing calculator model and Cosmos compatibility proof demonstrate strategic value.
