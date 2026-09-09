# GCP Executive Decision Brief (Standalone)

**Version:** GCP V1  
**Audience:** CTO, CIO, directors, finance, and architecture board

## Decision

Keep Azure as the immediate platform while optimizing the measured `$23,754/month` bill. Do not authorize a GCP production migration for cost savings alone. Authorize a limited GCP discovery and proof of concept only if GKE, Google analytics, networking, or an existing commercial commitment is strategically important.

## Budget

- GCP steady-state planning range: **$14,000-$36,000/month** including a contingency envelope.
- GCP one-time migration planning range: **$80,000-$195,000**.
- Largest uncertainty: replacing Cosmos DB and validating application compatibility.

## Comparison

| Option | Best use | Main concern |
|---|---|---|
| Azure existing | Lowest immediate risk; optimize before moving | Current bill remains high until rightsizing is completed |
| On-premises VxRail | Reuse owned infrastructure and sovereignty | Memory headroom, staffing, facilities, and self-managed operations |
| GCP | GKE, analytics, global services, or negotiated strategic value | Cloud-to-cloud migration cost and Cosmos replacement |

## Approval Gates

1. Azure Cost Management export reconciled to the workbook.
2. GCP pricing calculator model completed with actual region, traffic, log, backup, and database assumptions.
3. Cosmos compatibility proof completed.
4. GKE POC meets application latency, availability, security, and restore requirements.
5. Three-year TCO and migration business case approved.