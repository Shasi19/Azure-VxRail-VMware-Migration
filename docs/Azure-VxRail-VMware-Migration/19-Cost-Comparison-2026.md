# Azure vs On-Premises Cost Comparison - 2026 (V2)

**Prepared:** 2026-09-09  
**Document version:** V2 - AKS environment costing and Kubernetes platform comparison
**Source workbook:** `DI_Cost_Optimization_2026.xlsx` (provided separately)  
**Scope:** Only services explicitly present in the repository's current Azure architecture; unrelated workbook rows are excluded from the migration cost view.

## Executive Summary

The workbook's authoritative last-month Azure total is **$23,754/month** or **$285,048/year**. This is the total on the `Cost Summary` sheet, not the larger illustrative figures in older repository documents. The workbook is a real usage/cost snapshot; the repository's older `$60,500/month` table should be treated as a planning scenario until reconciled against Azure Cost Management exports.

The workbook's resource-detail rows total only **$9,011/month**, but that is not the migration scope. Several rows are not named in the current architecture, while several documented architecture services do not have a dedicated workbook row. This report therefore uses **$23,754/month** only as the financial control total and uses an architecture-scope view for migration decisions.

For on-premises, the repository says the six-node VxRail cluster, vSphere/vCenter, existing Veeam deployment, and TOR switching are already present. The migration does not require buying a second compute platform. The common incremental procurement estimate is **$20,000-$45,000 one time**, plus **$3,600-$19,300/year** for backup, OS, and certificate items, excluding migration labor, taxes, and facility costs. If the existing Veeam and OS entitlements cover the migrated workloads, the common incremental annual software cost can be close to **$0**.

## 1. Architecture-Scope Azure Cost from the Workbook

### Current architecture inventory used for costing

The current-state architecture explicitly contains:

- Three AKS clusters: QA, PREPROD, and PROD.
- Azure Database for PostgreSQL 13 with HA, backup, and a DR read replica.
- Azure Cosmos DB using the MongoDB API with multi-region replication.
- Azure Storage Accounts for application data, logs, backups, and artifacts.
- Azure Container Registry Premium.
- Veeam Backup & Replication and Azure backup storage.
- Azure Monitor, Application Insights, Log Analytics, Prometheus/Grafana, and an ELK stack.
- VNets, NSGs, ExpressRoute, VPN Gateway, Azure Bastion, Azure Traffic Manager, Application Gateway/WAF, Azure DNS, and Key Vault.
- Approximately 25 containerized microservices, including Redis and RabbitMQ workloads inside AKS.

Only workbook rows that map directly to this inventory are included in the architecture-scope cost view. Rows for unidentified VMs, unrelated subscriptions, or resources not described in the current architecture are excluded until an owner maps them to a named service.

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

### Architecture-scope cost mapping

| Current architecture service | Workbook rows included | Visible monthly cost | Scope treatment |
|---|---|---:|---|
| AKS QA, PREPROD, PROD | Three AKS rows plus the second PROD AKS row | **$2,370** | Included; primary Kubernetes compute |
| PostgreSQL managed service | `psql-ae-preprod-we-001` | **$719** | Included; only named PostgreSQL row visible, so QA/PROD costs require Azure export reconciliation |
| Cosmos DB MongoDB API | QA, PREPROD, PROD Cosmos rows | **$396** | Included; maps directly to the documented Cosmos service |
| Azure Storage Accounts | `druacrps1`, `paldata`, `diveeamrepository` | **$2,298** | Included; application and backup storage rows with explicit architecture relationship |
| Azure managed disk | Named 2 TB `scout2` disk | **$330** | Included only as storage capacity to be mapped; do not assume it belongs to AKS until owner confirmation |
| ACR Premium | No dedicated matching row in the visible detail list | **Not separately identifiable** | Included in architecture scope, but cost must come from Cost Management export |
| Monitoring, Application Insights, Log Analytics, ELK | No dedicated matching row in visible detail list | **Not separately identifiable** | Included in architecture scope, but cost must come from Cost Management export |
| VNet, ExpressRoute, VPN, Bastion, Traffic Manager, Application Gateway/WAF, DNS, Key Vault | Bastion row is visible; other services are not separately identified | **Bastion $239; remainder not separately identifiable** | Included in architecture scope; do not allocate unrelated networking rows without resource mapping |
| Redis, RabbitMQ, microservices | Runs inside AKS; no standalone service rows | **Included in AKS compute** | Do not add standalone compute unless billed as separate managed services |
| **Visible architecture-mapped subtotal** | **Only directly mapped rows above** | **$6,352** | **Partial scope floor, not a complete bill** |

The architecture-mapped subtotal is a planning floor: `$2,370` AKS + `$719` PostgreSQL + `$396` Cosmos DB + `$2,298` mapped storage + `$330` mapped disk + `$239` Bastion = **$6,352/month**. It is intentionally different from both the `$9,011` visible workbook-detail subtotal and the `$23,754` subscription total. The difference must be reconciled using Azure Cost Management by resource ID and tag before comparing Azure with on-premises or GCP.

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

### Workbook rows excluded from architecture-scope costing

| Workbook row/category | Cost | Why excluded from the current architecture scope |
|---|---:|---|
| Unidentified virtual machines | $2,047 | The current architecture names specific Veeam/ELK VMs, but these workbook VM names are not mapped to them. Exclude until resource ownership is confirmed. |
| QA Container Instance | $110 | Container Instance is not part of the documented current architecture; validate with the application owner before removal or inclusion. |
| Unmapped storage/disk rows | Included only where explicitly mapped above | Do not include a storage row merely because it is in the workbook; map it to application data, logs, artifacts, or backup first. |
| Full visible detail subtotal | $9,011 | Retained only as a workbook reconciliation control, not as the architecture-scope migration total. |

### Workbook actions to validate before migration

1. Export the same billing period from Azure Cost Management and map each resource ID to the current architecture inventory.
2. Confirm whether the seven subscriptions include shared services or resources omitted from `Resource details`; do not assign them to the migration scope without an owner and architecture mapping.
3. Apply autoscaling to the Kubernetes services after setting minimum and maximum counts with the application team.
4. Validate the unused QA container instance before removal.
5. Apply lifecycle management only to architecture-mapped application and backup storage, and clean the 2 TB disk after utilization review.
6. Do not reduce or migrate the high-CPU VMs until they are mapped to a named current-architecture component and their SLA is confirmed.

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