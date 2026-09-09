# Azure vs On-Premises Cost Comparison - 2026 (V2)

**Prepared:** 2026-09-09  
**Document version:** V2 - AKS environment costing and Kubernetes platform comparison
**Source workbook:** `DI_Cost_Optimization_2026.xlsx` (provided separately)  
**Scope:** Azure resources represented in the workbook and the repository's existing six-node Dell VxRail target

## Executive Summary

The workbook's authoritative last-month Azure total is **$23,754/month** or **$285,048/year**. This is the total on the `Cost Summary` sheet, not the larger illustrative figures in older repository documents. The workbook is a real usage/cost snapshot; the repository's older `$60,500/month` table should be treated as a planning scenario until reconciled against Azure Cost Management exports.

The workbook's resource-detail rows total only **$9,011/month**. They are an optimization worklist, not a complete invoice reconciliation: several subscription totals have no corresponding detail rows. This report therefore uses **$23,754/month** for the Azure baseline and uses the detail rows only to identify right-sizing and cleanup actions.

For on-premises, the repository says the six-node VxRail cluster, vSphere/vCenter, existing Veeam deployment, and TOR switching are already present. The migration does not require buying a second compute platform. The common incremental procurement estimate is **$20,000-$45,000 one time**, plus **$3,600-$19,300/year** for backup, OS, and certificate items, excluding migration labor, taxes, and facility costs. If the existing Veeam and OS entitlements cover the migrated workloads, the common incremental annual software cost can be close to **$0**.

## 1. Current Azure Cost from the Workbook

### AKS and directly related resources by environment

The table below is restricted to Kubernetes and directly adjacent application-platform rows visible in the workbook. It excludes shared subscription costs, networking, storage, backup, monitoring, and resources that are not explicitly attributable to an environment.

| Environment | AKS entries and sizing | AKS cost/month | Directly related rows visible | Related cost/month | Visible platform subtotal/month | Annualized |
|---|---|---:|---|---:|---:|---:|
| QA | 3 x Standard D2s v4 (6 vCPU, 24 GiB total) | $284 | Cosmos DB $132; Container Instance $110 (marked for removal) | $242 | **$526** | $6,312 |
| PREPROD | 2 x Standard D2s v4 (4 vCPU, 16 GiB total) | $189 | PostgreSQL $719; Cosmos DB $132 | $851 | **$1,040** | $12,480 |
| PROD | 4 x Standard D4s v4 plus 7 x Standard D4as v6 (44 vCPU, 176 GiB total) | **$1,897** | Cosmos DB $132 | $132 | **$2,029** | $24,348 |
| **Total visible** | **16 AKS nodes** | **$2,370** | **AKS-adjacent rows** | **$1,225** | **$3,595** | **$43,140** |

The `Directly related rows visible` total is **$1,225/month** ($242 + $851 + $132), and the visible platform subtotal is **$3,595/month**. These are not complete environment costs because the workbook detail sheet does not enumerate all shared networking, storage, backup, monitoring, ingress, or subscription-level charges. The workbook's AKS-only total is **$2,370/month** or **$28,440/year**.

The PROD AKS count is the most important reconciliation point: the workbook shows 11 PROD nodes across two AKS rows, while the repository target design uses 12 PROD worker nodes plus 3 shared control-plane nodes. Obtain the AKS export and confirm whether one node is omitted from the workbook detail or whether the on-prem target is intentionally over-sized.

### Subscription totals

| Subscription | Last month cost | Annualized |
|---|---:|---:|
| Sub-APP-ServerLess-WE | $49 | $588 |
| Sub-ACRPS-AE-WE | $5,593 | $67,116 |
| Sub-ACRPS-DRU-WE | $5,817 | $69,804 |
| Sub-DI-Backup-WE | $3,121 | $37,452 |
| Sub-DI-DR-WE | $4,302 | $51,624 |
| Sub-DI-HUB-WE | $4,475 | $53,700 |
| Sub-DI-VLAB-WE | $397 | $4,764 |
| **Total** | **$23,754** | **$285,048** |

### Resource-detail items visible in the workbook

| Resource category | Visible monthly cost | Key observations |
|---|---:|---|
| PostgreSQL | $719 | Preprod is at 20% max CPU and 36% max memory; resize is recommended. |
| Kubernetes services | $2,370 | QA, preprod, and prod entries recommend autoscaling; a second prod entry exists in another subscription. |
| Cosmos DB | $396 | All three entries have low utilization and recommend reducing memory. |
| Container instance | $110 | QA instance is marked as a likely unused resource; validate and remove. |
| Bastion | $239 | Resize from Standard to Basic is recommended. |
| Virtual machines | $2,047 | Several VMs are at 99-100% CPU but low memory; resize only after workload validation. |
| Storage and disk | $2,628 | Includes approximately 8 TB, 4 TB, 2 TB, and 65 TB items; apply lifecycle and housekeeping policies. |
| **Visible detail subtotal** | **$9,011** | Not equal to the $23,754 subscription total; do not use as the Azure bill baseline. |

### Workbook actions to validate before migration

1. Export the same billing period from Azure Cost Management and reconcile it to the seven subscription totals.
2. Confirm whether the seven subscriptions include shared services or resources omitted from `Resource details`.
3. Apply autoscaling to the Kubernetes services after setting minimum and maximum counts with the application team.
4. Validate the unused QA container instance before removal.
5. Apply lifecycle management to the 8 TB, 4 TB, and 65 TB storage accounts, and clean the 2 TB disk after utilization review.
6. Do not reduce the high-CPU VMs solely because memory is low; confirm CPU saturation, latency, and application SLAs first.

## 2. On-Premises Resource Requirements

The following mapping preserves the repository's target design while calling out the items that must be validated against the workbook inventory.

| Azure capability | On-premises equivalent | Quantity / sizing basis | Cost treatment |
|---|---|---|---|
| AKS | Kubernetes on VMware VMs, kubeadm, Calico, shared three-node control plane | Repository target: 3 control-plane VMs plus 15 worker VMs across QA, PREPROD, and PROD; workbook shows 16 AKS worker nodes across four entries, so validate the final worker count | Uses existing VxRail compute; no new server purchase assumed |
| Azure Database for PostgreSQL | PostgreSQL 15 with Patroni, etcd, and HAProxy/Keepalived | QA: 1 VM; PREPROD: 3 VMs; PROD: 3 VMs; use the repository's documented CPU, RAM, and disk sizing as the starting point | Open source software; existing compute and vSAN |
| Cosmos DB | MongoDB-compatible database service on VMs, preferably MongoDB Community or Percona after compatibility testing | One non-prod instance per environment and a three-member production replica set, or co-locate small non-prod workloads only after performance testing | Open source option; operational effort is required |
| Azure Container Registry | Harbor registry with replication and vulnerability scanning | Two or three registry VMs or a highly available deployment on the Kubernetes platform; archive ACR images before cutover | Open source; consumes existing compute and storage |
| Storage Accounts | vSAN datastores plus MinIO for object storage and NFS/SMB where file semantics are required | Size for the workbook's data footprint and retention policy; reserve separate backup capacity | vSAN is existing; MinIO is open source |
| Azure Backup / Veeam | Existing Veeam Backup & Replication with a dedicated NAS or backup repository | 40-60 TB usable repository is the repository's stated planning range; size from retention and deduplication tests | NAS is new one-time procurement; Veeam entitlement must be checked |
| Azure Monitor / Application Insights | Prometheus, Grafana, Loki or ELK, Alertmanager, and exporters | Central monitoring stack with persistent storage and retention sized to log volume | Open source option; consumes existing compute and storage |
| Azure Load Balancer | MetalLB for Kubernetes plus existing firewall or an appliance load balancer | Redundant ingress path for QA, PREPROD, and PROD | Existing network where capacity is available |
| VNet, VPN Gateway, NSGs | VMware distributed switches, VLANs, firewall zones, and site-to-site VPN | Separate management, vMotion, vSAN, Kubernetes, database, backup, and ingress networks | Existing TOR switches if port and throughput capacity are confirmed |
| Azure Bastion | Jump host or existing privileged access platform | One hardened management path; MFA and session logging required | Existing platform or small VM |

### Capacity checks before approval

The repository reports **90.86 TB free vSAN capacity** and **1.38 TB free memory**. Its target design also calculates about **2.1 TB RAM** for all environments, which is greater than the currently reported free memory. Memory is therefore the controlling capacity risk. Do not approve the full target VM layout until the current VxRail cluster is rebalanced, workloads are phased, or memory is added.

## 3. On-Premises Cost Estimate

These are planning ranges, not vendor quotations. They use the repository's existing procurement ranges and assume the six-node VxRail, vSphere/vCenter, Veeam base deployment, and TOR switches are already owned.

### One-time incremental procurement

| Item | Low | High | Basis |
|---|---:|---:|---|
| NAS / backup repository and disks | $5,000 | $12,000 | Repository estimate: $3,000-$8,000 NAS plus $2,000-$4,000 drives |
| Additional TOR switching, if required | $15,000 | $25,000 | 25 GbE server uplinks and 100 GbE uplinks |
| Hardware VPN appliance, optional | $0 | $8,000 | Software strongSwan baseline is $0; hardware option is optional |
| **Total one-time** | **$20,000** | **$45,000** |

The repository's individual upper bounds sum to **$45,000**. A contingency of roughly 5-10% for optics, cabling, rails, and installation would make a practical approval envelope **$47,000-$50,000**. Migration engineering labor is excluded because no rate or effort estimate was supplied.

### Annual incremental recurring cost

| Item | Low | High | Basis |
|---|---:|---:|---|
| Oracle Linux Premier subscriptions | $0 | $13,000 | $0 if the organization accepts the free distribution without Premier support; repository estimate for 26 VMs is $13,000/year |
| Veeam capacity / workload add-on | $3,600 | $6,000 | Three 10-workload packs using the repository's $1,200-$2,000 range; confirm existing VUL coverage first |
| Public TLS certificates | $0 | $300 | Let's Encrypt or a paid wildcard certificate |
| **Incremental recurring total** | **$3,600** | **$19,300** |

This is **$300-$1,608/month**, excluding the shared VxRail platform, data-center power/cooling, hardware support, staffing, and migration labor. Those costs cannot be calculated reliably from the workbook because utility rates, support contracts, staffing rates, and hardware purchase history are not provided.

### Three-year view

| Scenario | Three-year cost | Notes |
|---|---:|---|
| Low incremental | $30,800 | $20,000 one-time + 3 x $3,600 recurring |
| High incremental | $102,900 | $45,000 one-time + 3 x $19,300 recurring |
| High with 10% procurement contingency | $107,400 | Uses $49,500 one-time + 3 x $19,300 recurring |

The equivalent Azure baseline is **$855,144 over three years** at the workbook's current monthly run rate, before Azure price changes. This comparison is directional because Azure includes services that on-premises replaces with owned capacity and operational responsibility.

## 4. Kubernetes Platform Options

### Sizing and pricing method

This comparison uses the repository's target of **18 Kubernetes VMs**: 3 control-plane VMs plus 15 worker VMs across QA, PREPROD, and PROD. The workbook shows 16 AKS worker nodes across its entries, so the final node count and CPU entitlement must be confirmed before requesting quotes. Existing VxRail, vSphere, vSAN, Veeam base deployment, and TOR switching are not charged again.

The prices below are **2026 budgetary planning ranges in USD**, not published list prices or vendor quotations. OpenShift and SUSE enterprise pricing is normally quote-based. Canonical Kubernetes is open source, while enterprise security and support are purchased through Ubuntu Pro and Canonical support. A reseller quote should replace these ranges before approval.

| Option | What is licensed | Annual platform subscription / support | One-time implementation | Three-year incremental TCO* | Operational profile |
|---|---|---:|---:|---:|---|
| **Red Hat OpenShift** | Self-managed OpenShift subscription and support; price depends on edition, entitled cores, and support level | **$90,000-$180,000/year** | **$60,000-$120,000** | **$300,800-$643,900** | Highest platform capability and strongest integrated enterprise controls; highest subscription and skills cost |
| **SUSE Rancher Prime** | Rancher Prime management/support subscription; downstream clusters still require supported OS/Kubernetes choices | **$35,000-$90,000/year** | **$35,000-$75,000** | **$170,800-$449,900** | Good fit when managing multiple clusters or distributions; lower platform license cost than OpenShift but more components remain the customer's responsibility |
| **Canonical Kubernetes** | Kubernetes/Charmed Kubernetes software is open source; Ubuntu Pro and Canonical support are the paid elements | **$18,000-$55,000/year** | **$25,000-$60,000** | **$155,800-$342,900** | Lowest commercial platform cost; requires stronger internal Linux, Juju/Cluster API, Kubernetes, and lifecycle skills |

\* Three-year incremental TCO includes the common **$20,000-$45,000** infrastructure procurement, the platform implementation range, three years of common recurring items (**$3,600-$19,300/year**), and three years of platform subscription/support. It excludes personnel, VxRail depreciation, facilities, migration labor outside the platform implementation range, and application remediation.

### What the ranges mean in practice

- **OpenShift:** Do not budget it as “free Kubernetes on existing VxRail.” Red Hat subscription and support are the dominant cost. Request quotes based on the licensed physical-core or virtual-core entitlement, the exact OpenShift edition, production support SLA, and whether non-production clusters are included.
- **Rancher Prime:** The community Rancher management layer can be used at no license cost, but that is not equivalent to Rancher Prime enterprise support. Budget Prime if the organization requires vendor support, curated components, security, and multi-cluster governance.
- **Canonical Kubernetes:** The Kubernetes distribution itself can be deployed without a license fee. Budget Ubuntu Pro for all production nodes and a Canonical support tier if the organization requires vendor-backed break/fix, security, and lifecycle support. The lower subscription cost shifts more responsibility to the internal platform team.

### Recommended financial decision

For this existing six-node VxRail environment, **Canonical Kubernetes is the lowest-cost supported starting point**, and **Rancher Prime is the best middle option** if centralized multi-cluster management is a priority. Choose **OpenShift** only when Red Hat support, certified operators, security/compliance controls, or an existing Red Hat enterprise agreement justify its materially higher recurring cost. Run a short proof of concept before commitment because platform migration effort and operational staffing can exceed the license difference.

## 5. Decision and Next Actions

1. Treat **$23,754/month** as the current Azure baseline until Cost Management reconciliation is complete.
2. Confirm the VxRail memory headroom and worker-node count before ordering or migrating.
3. Verify existing Veeam VUL and Oracle Linux entitlements; these are the largest variable recurring costs.
4. Obtain quotes for the NAS, switch/optics, and optional firewall/VPN appliance.
5. Obtain comparable quotes for OpenShift, Rancher Prime, and Canonical support using the same 18-node/target-core schedule.
6. Build a complete TCO with facilities, support, staffing, migration labor, and depreciation before final financial approval.

## Assumptions and Limitations

**Version history:** V1 was the original Azure versus on-premises cost baseline. V2 adds environment-level AKS costing, Kubernetes platform options, executive gates, and corrected migration/DR controls. The V1 baseline remains available as `deliverables/Azure-OnPrem-Cost-Comparison-2026-V1.docx`.

- Currency is USD and the workbook's `Last month cost` values are treated as monthly costs.
- Azure tax, credits, reservations, egress, and future price changes are not separately modeled.
- On-premises figures are planning estimates copied or derived from the repository's stated ranges, not quotations.
- Kubernetes platform ranges are budgetary 2026 estimates because enterprise prices are quote-based and vary by core entitlement, support SLA, contract term, and reseller region.
- The three-year platform comparison excludes platform-team staffing. A realistic loaded planning allowance of roughly **$75,000-$180,000 per FTE/year** should be added based on local compensation and whether 24x7 coverage is required.
- The repository contains older Azure cost scenarios that conflict with the workbook. This report intentionally uses the supplied workbook as the current billing baseline.
- The workbook's resource-detail sheet is incomplete relative to the subscription summary, so detail-row costs must not be summed as the total Azure bill.