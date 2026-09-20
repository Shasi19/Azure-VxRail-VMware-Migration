# Clean Deliverables - 2026

This folder contains the four authoritative decision reports. Each report has a matching Markdown file for GitHub viewing and Word file for formal distribution.

| Decision area | Markdown | Word |
|---|---|---|
| Azure current architecture and cost | 01-Azure-Current-Architecture-and-Cost-2026.md | 01-Azure-Current-Architecture-and-Cost-2026.docx |
| Existing six-node VxRail expansion | 02-Existing-VxRail-Expansion-2026.md | 02-Existing-VxRail-Expansion-2026.docx |
| New Dell VxRail cluster | 03-New-Dell-VxRail-Cluster-2026.md | 03-New-Dell-VxRail-Cluster-2026.docx |
| GCP architecture and cost | 04-GCP-Architecture-and-Cost-2026.md | 04-GCP-Architecture-and-Cost-2026.docx |

## Decision summary

- **Azure:** best immediate choice because the current bill is measured and migration risk is zero.
- **Existing VxRail:** best on-premises route when sovereignty or latency is required, after memory/N+1 validation.
- **New Dell cluster:** only when existing capacity cannot be expanded or a separate lifecycle boundary is required.
- **GCP:** choose for strategic GKE, analytics, networking, or commercial reasons, not cost alone.

The reports include architecture diagrams, resource purpose, servers and VM sizing, disks and storage, Kubernetes, databases, backup/DR, people, operations, migration, and three-year cost analysis.