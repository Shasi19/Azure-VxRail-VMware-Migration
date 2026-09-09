# Azure vs On-Premises Cost Comparison (V1)

**Audience:** Finance, infrastructure, and architecture review  
**Source:** `DI_Cost_Optimization_2026.xlsx` and repository architecture documents

## Headline numbers

- Azure subscription control total: **$23,754/month**, **$285,048/year**.
- Architecture-mapped visible floor: **$6,352/month**.
- Existing-cluster incremental on-premises procurement: **$20,000-$45,000 one time** plus **$3,600-$19,300/year**.
- New VxRail purchase is not included in this V1 baseline. See [V3 full TCO](./OnPrem-VxRail-TCO-2026-V3.md).

## Environment view

| Environment | AKS cost/month | Directly related visible rows | Partial platform total |
|---|---:|---:|---:|
| QA | $284 | Cosmos $132 + QA Container Instance $110 | **$526** |
| PREPROD | $189 | PostgreSQL $719 + Cosmos $132 | **$1,040** |
| PROD | $1,897 | Cosmos $132 | **$2,029** |
| **Total visible** | **$2,370** | **$1,225** | **$3,595** |

These are partial resource-detail values. Shared networking, storage, backup, monitoring, ingress, ACR, and unallocated subscription charges require Azure Cost Management reconciliation.

## Recommendation

Remain on Azure for the immediate term and apply rightsizing, autoscaling, storage lifecycle, and unused-resource cleanup. Consider on-premises for sovereignty, latency, or strategic datacenter reasons, not on an incomplete incremental-cost assumption.

## Supporting analysis

- [Architecture-scoped Azure report](../docs/Azure-VxRail-VMware-Migration/19-Cost-Comparison-2026.md)
- [Full VxRail purchase and operations TCO V3](./OnPrem-VxRail-TCO-2026-V3.md)
- [GCP standalone comparison](./GCP-Azure-OnPrem-Comparison-2026.md)
