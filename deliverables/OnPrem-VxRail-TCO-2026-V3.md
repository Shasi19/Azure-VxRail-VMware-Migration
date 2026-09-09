# On-Premises Dell VxRail TCO and Operations (V3)

**Audience:** CTO, directors, finance, infrastructure, and migration steering committee

## Executive decision

If a new six-node Dell VxRail cluster must be purchased:

- Initial purchase and implementation: **$1.04M-$2.39M**.
- Annual operations: **$390k-$980k**.
- Migration program: **$180k-$420k**.
- Three-year on-premises TCO: **$2.39M-$5.75M**.
- Three-year Azure baseline: **$855,144** at the current `$23,754/month` bill.

![Three-year cost comparison](../docs/Azure-VxRail-VMware-Migration/assets/onprem-tco-bars.svg)

## Architecture

```mermaid
flowchart TB
    Users[Users] --> FW[Redundant firewall and VPN]
    FW --> TOR[25/100 GbE TOR switching]
    TOR --> VX[Dell VxRail six-node cluster]
    VX --> K8S[Kubernetes: control plane and workers]
    VX --> DB[PostgreSQL Patroni HA]
    VX --> OPS[Harbor, ArgoCD, monitoring, logging]
    VX --> VEEAM[Veeam backup]
    VEEAM --> NAS[40-60 TB backup repository]
    NAS --> OFFSITE[Immutable offsite copy]
```

## Full acquisition budget

| Category | Low | High |
|---|---:|---:|
| Six VxRail nodes | $600,000 | $1,200,000 |
| VMware/vSphere licensing | $150,000 | $400,000 |
| TOR switches, optics, cabling | $50,000 | $120,000 |
| Backup repository | $25,000 | $80,000 |
| Firewall/VPN/load balancing | $30,000 | $100,000 |
| Rack, UPS, PDUs, power | $50,000 | $150,000 |
| Commissioning and spares | $40,000 | $120,000 |
| Approval envelope with contingency | **$1,040,000** | **$2,390,000** |

## Annual operating cost

| Category | Low/year | High/year |
|---|---:|---:|
| Hardware support | $60,000 | $150,000 |
| VMware support | $50,000 | $150,000 |
| Power and cooling | $35,000 | $90,000 |
| Backup and offsite DR | $25,000 | $75,000 |
| OS/security/platform support | $25,000 | $75,000 |
| Operations staffing | $180,000 | $400,000 |
| Refresh reserve | $15,000 | $40,000 |
| **Total** | **$390,000** | **$980,000** |

![On-premises operating responsibilities](../docs/Azure-VxRail-VMware-Migration/assets/onprem-operating-model.svg)

## Operational effort

- OS patching: 3-6 engineer-days/month.
- Kubernetes upgrades: 5-10 engineer-days/quarter.
- VxRail/vSphere lifecycle: 3-8 engineer-days per maintenance window.
- Database patching, failover, PITR, backup checks, restore tests, certificate rotation, vulnerability remediation, capacity reviews, incidents, and on-call are continuous.
- Two FTE is a minimum shared model; 3-4 FTE is more realistic for 24x7 production ownership.

## Migration effort

| Workstream | Cost |
|---|---:|
| Discovery and design | $25,000-$50,000 |
| Platform and network build | $45,000-$100,000 |
| QA migration | $20,000-$45,000 |
| PREPROD rehearsal | $30,000-$65,000 |
| PROD replication, cutover, hypercare | $50,000-$120,000 |
| Governance and security | $10,000-$40,000 |
| **Total** | **$180,000-$420,000** |

## Recommendation

Remain on Azure and optimize first. Buy a new VxRail cluster only when sovereignty, latency, regulation, or an already-funded datacenter strategy justifies the additional capital and operating burden. Require Dell/Broadcom quotes, facilities approval, 2-4 FTE ownership, capacity validation, database compatibility, and immutable offsite DR before purchase approval.

Full source report: [21-OnPrem-VxRail-TCO-2026.md](../docs/Azure-VxRail-VMware-Migration/21-OnPrem-VxRail-TCO-2026.md)
