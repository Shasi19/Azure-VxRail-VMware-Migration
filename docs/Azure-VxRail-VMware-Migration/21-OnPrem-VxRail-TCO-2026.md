# On-Premises Dell VxRail TCO, 35-VM Capacity, and Operations (V4)

**Prepared:** 2026-09-09  
**Document version:** V4 - 35-VM capacity and existing-cluster expansion model
**Audience:** CTO, directors, finance, infrastructure, and migration steering committee

## Executive Decision

For the requested **35-VM target**, on-premises is not automatically cheaper than the current Azure bill. A realistic model must distinguish expanding the existing six-node VxRail from buying a new capacity block:

- **Expand existing VxRail:** **$180k-$510k one time**, primarily memory, support, and capacity additions.
- **Buy a new six-node VxRail cluster:** **$1.04M-$2.39M initial approval envelope**.
- **Annual operating cost:** **$390k-$930k/year**, including support, facilities, software, staffing, and maintenance.
- **Migration program:** **$180k-$420k** one time.
- **Three-year expanded-existing-cluster TCO:** **$1.50M-$3.45M**, including operations and migration.
- **Three-year new-cluster TCO:** **$2.39M-$5.75M**, including operations and migration.
- **Three-year Azure baseline:** **$855,144** at the workbook's current `$23,754/month`, before Azure growth or optimization.

On-premises becomes financially attractive only when the VxRail hardware is already owned or heavily discounted, facilities and staff are already funded, utilization is high, and data sovereignty or latency has business value. With a new cluster purchase and new operating capacity, **staying on Azure and optimizing the current architecture is the lower-risk financial decision**. A new VxRail purchase should be justified by sovereignty, control, predictable high utilization, or an existing datacenter strategy, not by an assumed cloud-cost saving.

## 1. 35-VM Target On-Premises Architecture

```mermaid
flowchart TB
    Users[Users and partners] --> FW[Redundant firewall / VPN]
    FW --> TOR[Redundant 25/100 GbE TOR switches]
    TOR --> VX[Dell VxRail 6-node cluster]
    VX --> VC[vCenter + VxRail Manager]
    VX --> K8S[18 Kubernetes VMs: 3 control-plane + 15 workers]
    VX --> DB[PostgreSQL Patroni HA: QA 1 + PREPROD 3 + PROD 3]
    VX --> NOSQL[Mongo-compatible service / replica set]
    VX --> OPS[Harbor + ArgoCD + Prometheus + Grafana + logging]
    VX --> VEEAM[Veeam backup proxy and repository]
    VEEAM --> NAS[Dedicated 40-60 TB usable NAS]
    NAS --> OFFSITE[Immutable offsite / second site copy]
```

### 35-VM sizing schedule

| VM group | Count | Per-VM sizing | Total vCPU | Total RAM | Logical storage |
|---|---:|---|---:|---:|---:|
| Kubernetes control plane | 3 | 8 vCPU / 32 GB / 150 GB | 24 | 96 GB | 450 GB |
| QA workers | 3 | 12 vCPU / 48 GB / 200 GB | 36 | 144 GB | 600 GB |
| PREPROD workers | 9 | 16 vCPU / 64 GB / 250 GB | 144 | 576 GB | 2,250 GB |
| PROD workers | 12 | 24 vCPU / 96 GB / 300 GB | 288 | 1,152 GB | 3,600 GB |
| QA PostgreSQL | 1 | 8 vCPU / 32 GB / 600 GB | 8 | 32 GB | 600 GB |
| PREPROD PostgreSQL Patroni | 3 | 16 vCPU / 64 GB / 700 GB | 48 | 192 GB | 2,100 GB |
| PROD PostgreSQL Patroni | 3 | 32 vCPU / 128 GB / 1.5 TB | 96 | 384 GB | 4,500 GB |
| Platform and operations VMs | 10 | 8 vCPU / 32 GB / 250 GB | 80 | 320 GB | 2,500 GB |
| **Total** | **35 VMs** | **35 VM instances** | **724 vCPU** | **2,896 GB** | **16.6 TB** |

The platform/operations group assumes two Harbor/registry VMs, two GitOps/automation VMs, three monitoring/logging VMs, two ingress/VPN/bastion VMs, and one Veeam proxy. This produces the requested **35 VM instances**.

### Capacity gap against the current VxRail

The repository reports **1.38 TB free memory** and **90.86 TB free storage**. The 35-VM design requires approximately **2.90 TB assigned RAM** and **16.6 TB logical storage**, before vSphere/vSAN overhead, N+1 reserve, snapshots, and growth. The immediate gap is approximately **1.52 TB RAM**. Storage is sufficient; memory is the binding constraint.

### Compute and storage design

| Layer | Required design |
|---|---|
| Physical cluster | Six Dell VxRail nodes, N+1 failure tolerance, dual power, dual network paths |
| Virtualization | VMware vSphere/vCenter and VxRail Manager; quote licensing separately from hardware |
| Kubernetes | Three control-plane VMs, QA 3 workers, PREPROD 9 workers, PROD 12 workers; reconcile against workbook's 16 AKS nodes |
| Databases | QA single PostgreSQL VM; three-node PREPROD Patroni; three-node PROD Patroni; Mongo-compatible production replica set |
| Storage | vSAN for VM/PVC data; separate backup repository; MinIO or equivalent for object semantics |
| Network | Management, vMotion, vSAN, Kubernetes, database, backup, ingress, and migration VLANs |
| Backup/DR | Veeam VM backup, Kasten or equivalent namespace backup, PostgreSQL WAL/PITR, immutable offsite copy |

## 2. Expansion of Existing Six-Node Cluster

| Expansion item | Low | High | Basis |
|---|---:|---:|---|
| 1.5-2.0 TB certified RAM kits and installation | $120,000 | $300,000 | Dell-supported DIMMs, firmware, burn-in, and labor |
| vSphere/vSAN entitlement uplift | $25,000 | $100,000 | Confirm core and capacity licensing with Dell/Broadcom |
| Backup, network, and power additions | $20,000 | $70,000 | Extra ports, repository, optics, UPS/PDU allocation |
| Capacity validation and implementation | $15,000 | $40,000 | Rebalance, evacuate, test, and acceptance |
| **One-time expansion total** | **$180,000** | **$510,000** | Existing cluster retained |

Annual operating cost for the expanded cluster is **$390,000-$1,020,000/year**, including an estimated $15,000-$40,000/year incremental support and maintenance uplift. Three-year expanded-cluster TCO is therefore approximately **$1.50M-$3.45M**, including the $180,000-$420,000 migration program.

## 3. Full New-Cluster Acquisition Budget

These are **budgetary 2026 USD ranges**, not Dell, Broadcom, reseller, or facilities quotes. Configuration, region, support tier, contract term, and discounts can change them substantially.

| Purchase category | Low | High | What it includes |
|---|---:|---:|---|
| Six Dell VxRail nodes | $600,000 | $1,200,000 | Six production-class nodes with CPU, 4-5 TB RAM total, NVMe/vSAN capacity, rails, and warranties |
| VMware/vSphere and management licensing | $150,000 | $400,000 | Three-year planning allowance; obtain a Broadcom/Dell quote for exact core entitlement |
| 25/100 GbE TOR switching, optics, cabling | $50,000 | $120,000 | Redundant switches, optics, DACs/fiber, installation, and port expansion |
| Dedicated backup repository | $25,000 | $80,000 | 40-60 TB usable NAS or hardened repository, disks, spare capacity |
| Firewall, VPN, load-balancing additions | $30,000 | $100,000 | Redundant security edge, VPN, certificates, and optional hardware load balancer |
| Rack, UPS, PDUs, power distribution | $50,000 | $150,000 | Rack work, dual PDUs, UPS allocation, cabling, and installation |
| Datacenter commissioning and spares | $40,000 | $120,000 | Hardware installation, burn-in, spare disks/PSUs, acceptance testing |
| **Initial acquisition subtotal** | **$945,000** | **$2,170,000** | Before tax and contingency |
| **Recommended approval envelope with 10% contingency** | **$1,040,000** | **$2,390,000** | Use for early capital planning |

## 4. Annual Operating Cost

| Operating category | Low/year | High/year | Activities covered |
|---|---:|---:|---|
| Dell VxRail hardware support | $60,000 | $150,000 | 24x7 support, parts replacement, firmware lifecycle, onsite response |
| VMware/vSphere subscription/support | $50,000 | $150,000 | Renewal/subscription, support, and management components |
| Datacenter power and cooling | $35,000 | $90,000 | Six-node load, UPS losses, cooling, rack, and facility allocation |
| Backup, DR, and offsite storage | $25,000 | $75,000 | NAS refresh, immutable/offsite copy, Veeam/Kasten support and media |
| OS, security, certificates, and platform support | $25,000 | $75,000 | Oracle Linux/Ubuntu support, security tools, certificates, vendor support |
| Platform operations staffing | $180,000 | $400,000 | 2-4 FTE allocation across VMware, Linux/Kubernetes, DBA, backup, and on-call |
| Hardware/software refresh reserve | $15,000 | $40,000 | Spares, lifecycle refresh, testing, and replacement reserve |
| **Annual operating total** | **$390,000** | **$980,000** | Fully loaded planning range |

The lower end assumes existing staff absorb the platform and facilities are already funded. The upper end is more appropriate when 24x7 coverage, dedicated engineers, and external support are required.

## 5. Operational Effort and Maintenance

| Activity | Typical cadence | Effort planning | Owner |
|---|---|---:|---|
| OS patching for Kubernetes, DB, and utility VMs | Monthly; emergency CVEs as needed | 3-6 engineer-days/month | Linux/platform |
| Kubernetes version and add-on upgrades | Quarterly | 5-10 engineer-days/quarter | Kubernetes platform |
| vSphere/VxRail firmware and lifecycle | Quarterly planning; maintenance windows 2-4 times/year | 3-8 engineer-days/window | VMware/VxRail |
| PostgreSQL patching, failover, and PITR test | Monthly; quarterly failover | 2-5 engineer-days/month | DBA |
| Backup monitoring and restore tests | Daily checks; monthly sample restore; quarterly full restore | 2-5 engineer-days/month | Backup/platform |
| Vulnerability, certificate, and secret rotation | Monthly / expiry-driven | 2-4 engineer-days/month | Security/platform |
| Capacity, performance, and cost review | Monthly | 1-3 engineer-days/month | Architecture/finance |
| Incident response and on-call | Continuous | 0.5-1.5 FTE equivalent | Operations |

Budgetary staffing implication: **2 FTE is a minimum shared-service model; 3-4 FTE is more realistic for production ownership with on-call, DBA, backup, and security responsibilities.**

## 6. Migration Effort and Cost

| Workstream | Duration | Cost range | Deliverables |
|---|---:|---:|---|
| Discovery, dependency mapping, and detailed design | 3-4 weeks | $25,000-$50,000 | Resource map, target sizing, security and cutover design |
| VxRail build, network, vSphere, and Kubernetes platform | 5-8 weeks | $45,000-$100,000 | Cluster, VLANs, Kubernetes, registry, GitOps, monitoring |
| QA migration and test | 3 weeks | $20,000-$45,000 | Restore, images, secrets, smoke and load tests |
| PREPROD migration and rehearsal | 5 weeks | $30,000-$65,000 | HA, performance, backup restore, failover, rollback rehearsal |
| PROD replication, canary, and cutover | 6-8 weeks | $50,000-$120,000 | Live replication, canary, DNS cutover, hypercare |
| Project management, security, and change governance | Throughout | $10,000-$40,000 | CAB, audit, communications, risk and acceptance evidence |
| **Migration program total** | **20-28 weeks** | **$180,000-$420,000** | Excludes application redesign and major remediation |

## 7. Azure vs Expanded VxRail vs New VxRail

| Scenario | Initial purchase | Migration | 3-year operations | Three-year total |
|---|---:|---:|---:|---:|
| Azure current bill | $0 | $0 | $855,144 | **$855,144** |
| Existing VxRail expansion, low | $180,000 | $180,000 | $1,170,000 | **$1,530,000** |
| Existing VxRail expansion, high | $510,000 | $420,000 | $3,060,000 | **$3,990,000** |
| New VxRail cluster, low | $1,040,000 | $180,000 | $1,170,000 | **$2,390,000** |
| New VxRail cluster, high | $2,390,000 | $420,000 | $2,940,000 | **$5,750,000** |

This is not an apples-to-apples accounting result: Azure's number is an observed service bill and may omit internal staff; on-premises includes capital acquisition, staffing, facilities, and migration effort. It is nevertheless the correct decision view when leadership is considering buying a new cluster.

## 8. Azure vs On-Premises vs GCP Summary

| Option | Three-year planning cost | Migration effort | Best fit | Main concern |
|---|---:|---:|---|---|
| Azure existing | $855,144 current bill | Low | Lowest immediate risk and fastest optimization | Ongoing monthly cloud spend |
| Existing VxRail expansion | $1.53M-$3.99M | $180k-$420k | Sovereignty and reuse of hardware | 1.52 TB RAM gap and operational ownership |
| New six-node VxRail | $2.39M-$5.75M | $180k-$420k | New capacity and full datacenter control | Capital, staffing, facilities, support |
| GCP | Approximately $584k-$1.49M steady-state plus $80k-$195k migration | High | GKE, analytics, Google ecosystem | Cosmos replacement, egress, cloud migration cost |

GCP figures are the separate report's `$14,000-$36,000/month` envelope over three years, excluding detailed staffing assumptions. They require a pricing-calculator model and a Cosmos compatibility proof before approval.

## 9. Recommendation

**Best immediate choice:** remain on Azure and optimize the architecture-mapped services while completing a resource-ID reconciliation. The current measured bill and zero migration disruption outweigh uncertain GCP/on-prem savings.

**Best on-premises choice:** expand the existing VxRail first, not buy a new cluster, if sovereignty or latency requires on-premises. Budget **$180k-$510k** for the initial capacity expansion and validate the **1.52 TB RAM gap**. Buy a new cluster only if the existing hardware cannot be upgraded or N+1 capacity cannot be maintained.

**Required executive gates:** obtain Dell/Broadcom quotes, confirm facilities capacity, approve 2-4 FTE operational ownership, resolve VxRail memory headroom, test all database compatibility, and approve an immutable offsite DR design.

## Assumptions

- Figures are USD budgetary ranges for 2026 and are not vendor quotations.
- Six nodes are assumed to provide N+1 capacity and enough vSAN storage; final node SKU must be sized from measured workload demand.
- The 35-VM schedule includes 18 Kubernetes VMs, 7 database VMs, and 10 platform/operations VMs.
- Expansion assumes the existing six-node cluster is retained and certified RAM is added; final DIMM and host compatibility require a Dell assessment.
- New-cluster figures are shown separately and are not used as the default on-premises recommendation.
- Azure baseline uses the supplied workbook's `$23,754/month` subscription total.
- Taxes, financing, depreciation, resale value, datacenter lease, and application remediation are excluded.