# Volume 1: Azure Cloud Architecture — Enhanced Design

> **Updated Azure Target Architecture** — Multi-region deployment with global distribution, high availability, and comprehensive integration with on-premises Kubernetes migration strategy.

---

## Overview

This document provides an **enhanced multi-region Azure architecture** aligned with the migration project's target infrastructure. The architecture supports seamless transition from on-premises to cloud-native services while maintaining compatibility with the Kubernetes-first approach.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Regional Architecture](#regional-architecture)
3. [Core Components](#core-components)
4. [Multi-Region Deployment](#multi-region-deployment)
5. [Data Consistency Strategy](#data-consistency-strategy)
6. [Security & Networking](#security--networking)
7. [Monitoring & Observability](#monitoring--observability)
8. [Cost Optimization](#cost-optimization)
9. [Disaster Recovery](#disaster-recovery)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    AZURE MULTI-REGION ARCHITECTURE                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  Azure Front Door (Global Load Balancer & WAF)                  │  │
│  │  ├─ DDoS Protection: Standard                                   │  │
│  │  ├─ WAF Policies: OWASP Top 10 + Custom Rules                 │  │
│  │  ├─ SSL/TLS Termination                                        │  │
│  │  └─ Geo-redundancy: Automatic failover                         │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│         │                    │                    │                     │
│  ┌──────▼──────┐     ┌───────▼─────┐     ┌──────▼──────┐             │
│  │   Region 1  │     │   Region 2  │     │   Region 3  │             │
│  │   (Primary) │     │ (Secondary) │     │  (Tertiary) │             │
│  └─────────────┘     └─────────────┘     └─────────────┘             │
│         │                    │                    │                     │
│  ┌──────▼──────────────────▼────────────────────▼──────┐              │
│  │              AZURE COSMOS DB (Global)               │              │
│  │  ├─ Multi-region replication                       │              │
│  │  ├─ Automatic failover                             │              │
│  │  ├─ Consistency: Strong (Single-region)            │              │
│  │  └─ RU/s: Auto-scale 4K–100K                       │              │
│  └──────────────────────────────────────────────────────┘              │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │         Azure Backup & Site Recovery (Central)                  │  │
│  │  ├─ Backup vault: GRS (Geo-redundant storage)                  │  │
│  │  ├─ RPO: 1 hour | RTO: 4 hours                                 │  │
│  │  └─ Replication policies: Region-to-region                      │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Regional Architecture

### Tier 1: Entry & Security

```
┌──────────────────────────────────────────────┐
│  Azure Front Door (Global)                   │
├──────────────────────────────────────────────┤
│  ├─ HTTPS/TLS 1.2+                          │
│  ├─ DDoS Protection Standard                 │
│  ├─ WAF with managed rule sets              │
│  ├─ Geo-routing based on latency            │
│  └─ Cache optimization: 1hr TTL             │
└──────────────────────────────────────────────┘
           │              │              │
    ┌──────▼───┐   ┌─────▼────┐   ┌────▼──────┐
    │ Region 1 │   │ Region 2 │   │ Region 3  │
    └──────────┘   └──────────┘   └───────────┘
```

### Tier 2: Container Orchestration (Per Region)

**Azure Kubernetes Service (AKS)**

```
Cluster Configuration:
├─ K8s Version: 1.28.x (auto-upgrade enabled)
├─ Node Pools:
│  ├─ System Pool: 3 nodes (Standard_D4s_v3)
│  ├─ App Pool: 6–12 nodes (auto-scale)
│  ├─ Data Pool: 4 nodes (memory-optimized)
│  └─ GPU Pool: 2 nodes (ML workloads, optional)
├─ Networking:
│  ├─ CNI: Azure CNI (native VNet integration)
│  ├─ Network Policy: Calico
│  ├─ Service CIDR: 10.0.0.0/16
│  ├─ Pod CIDR: 10.244.0.0/16
│  └─ LoadBalancer: Azure LB (managed)
├─ Add-ons:
│  ├─ Azure Monitor Container Insights
│  ├─ KEDA (event-driven autoscaling)
│  ├─ Azure Policy
│  ├─ Secrets Store CSI Driver
│  └─ Istio Service Mesh (optional)
├─ RBAC:
│  ├─ Azure AD Integration
│  ├─ Role-Based Access Control
│  └─ Pod Identity (workload authentication)
└─ Security:
   ├─ Network Policies enforced
   ├─ Pod Security Policies
   ├─ Container registry scanning
   └─ Image signing (Notation)
```

### Tier 3: Storage & Data (Per Region)

#### Azure Container Registry (ACR)

```
Configuration:
├─ SKU: Premium (geo-replication)
├─ Geo-replication: All regions
├─ Registries per region: 3+
├─ Image retention: 90 days (build artifacts)
├─ Scanning: Defender for container registries
├─ Webhooks: Push notifications to CI/CD
├─ Bandwidth: Unlimited (Premium)
└─ Authentication: Service principals + Managed Identity
```

#### Storage Account

```
Configuration:
├─ Replication: GRS (Geo-redundant storage)
├─ Tier: Hot (frequent access), Archive (backup)
├─ Containers:
│  ├─ app-artifacts: Container images (backup)
│  ├─ logs: Application & system logs
│  ├─ backups: Database & configuration backups
│  ├─ metrics: Exported Prometheus metrics
│  └─ configs: Configuration files & secrets
├─ Lifecycle policies:
│  ├─ Hot→Cool: 30 days
│  ├─ Cool→Archive: 90 days
│  └─ Delete: 180 days
├─ Access tier: Premium (low latency)
└─ Encryption:
   ├─ At-rest: AES-256 (customer-managed keys)
   ├─ In-transit: HTTPS only
   └─ Key rotation: Annual
```

### Tier 4: Databases (Per Region)

#### Azure Database for PostgreSQL

```
Configuration:
├─ Deployment: Flexible Server (HA enabled)
├─ Compute: Standard_B4ms (4 vCore, 16 GB RAM)
├─ Storage: 512 GB SSD (auto-grow)
├─ Backup:
│  ├─ Retention: 7 days (full backups daily)
│  ├─ PITR: 7 days
│  ├─ Geo-redundant: Enabled
│  └─ Cross-region restore: Available
├─ HA Setup:
│  ├─ Standby replica: Same zone or cross-zone
│  ├─ Failover time: <1 minute
│  ├─ RPO: Near-zero (synchronous)
│  └─ Auto-failover: Enabled
├─ Security:
│  ├─ Firewall rules: Service + custom IPs
│  ├─ Private Link: VNet service endpoint
│  ├─ SSL/TLS: Enforced (1.2+)
│  ├─ Encryption: Customer-managed keys
│  └─ Authentication: AD + password
├─ Performance:
│  ├─ Query Store: Enabled
│  ├─ Connection pooling: PgBouncer
│  ├─ Max connections: 250 (default)
│  └─ Slow query logs: <1s threshold
└─ Monitoring:
   ├─ Metrics: CPU, storage, connections
   ├─ Query Performance Insights: Top 5 queries
   └─ Alerts: Auto-triggered on thresholds
```

#### Azure Cosmos DB (NoSQL — Global)

```
Configuration:
├─ API: Core (SQL)
├─ Consistency Level: Strong (single-region read-write)
├─ Throughput:
│  ├─ Provisioned: Auto-scale 4K–100K RU/s
│  ├─ Per-partition key: Configurable
│  └─ Burst capacity: Available
├─ Global Distribution:
│  ├─ Write regions: 1 (Region 1) + failover
│  ├─ Read regions: All 3 regions
│  ├─ Replication: <30ms P99 latency
│  └─ RPO: <100ms
├─ Storage:
│  ├─ Partition key strategy: By tenant/org
│  ├─ Retention: Unlimited (TTL per document)
│  ├─ Indexing: Automatic
│  └─ Backups: Continuous (7-day retention)
├─ Security:
│  ├─ RBAC: Azure AD integration
│  ├─ Network: Private endpoints + firewall
│  ├─ Encryption: CMK + transparent
│  └─ Compliance: SOC 2, ISO 27001
└─ Monitoring:
   ├─ RU consumption: Real-time dashboard
   ├─ Query latency: P50/P95/P99
   ├─ Partition key health: Load distribution
   └─ Replication lag: Cross-region metrics
```

#### Azure Cache for Redis

```
Configuration:
├─ SKU: Premium (enterprise-grade)
├─ Capacity: 6–12 GB (geo-replication)
├─ Replication:
│  ├─ Zone-redundant (within region)
│  ├─ Geo-replication (across regions)
│  ├─ Persistence: RDB + AOF
│  └─ RPO: <1 second
├─ Eviction Policy: allkeys-lru (LRU eviction)
├─ Security:
│  ├─ Private Link: VNet endpoints
│  ├─ SSL/TLS: Enforced (1.2+)
│  ├─ Auth: Access keys + Azure AD
│  └─ Encryption: Customer-managed keys
├─ Clustering:
│  ├─ Slot distribution: 16,384 slots
│  ├─ Hash algorithm: CRC16
│  └─ Sharding: 3–12 shards (auto)
└─ Monitoring:
   ├─ Memory usage: High/low watermark
   ├─ Hit/miss ratio: Cache effectiveness
   ├─ Connection count: Active clients
   └─ Eviction rate: Key pressure indicator
```

### Tier 5: Monitoring & Observability (Centralized)

```
┌──────────────────────────────────────────────┐
│  Azure Monitor (Central hub)                 │
├──────────────────────────────────────────────┤
│  
│  Metrics Collection:
│  ├─ Application Insights (APM)
│  │  ├─ Request tracing (end-to-end)
│  │  ├─ Dependency mapping
│  │  ├─ Performance counters
│  │  ├─ Custom events/metrics
│  │  └─ Sampling: 100% (first region)
│  │
│  ├─ Container Insights (AKS)
│  │  ├─ Node metrics (CPU, memory, disk)
│  │  ├─ Pod-level visibility
│  │  ├─ Kubelet metrics
│  │  └─ Cluster health dashboard
│  │
│  └─ Azure Diagnostics
│      ├─ Storage account metrics
│      ├─ Database performance insights
│      ├─ Network flow logs
│      └─ Application logs (stderr/stdout)
│
│  Log Aggregation:
│  ├─ Log Analytics Workspace (single, multi-region)
│  │  ├─ Query language: KQL (Kusto)
│  │  ├─ Retention: 30–730 days (configurable)
│  │  ├─ Data ingestion: 10+ GB/day
│  │  └─ Workbooks: Custom dashboards
│  │
│  ├─ Application Logs:
│  │  ├─ Format: JSON (structured)
│  │  ├─ Severity levels: DEBUG, INFO, WARN, ERROR
│  │  ├─ Correlation IDs: Request tracing
│  │  └─ Egress: 50+ MB/s
│  │
│  └─ Audit Logs:
│      ├─ API calls (control plane)
│      ├─ Resource changes
│      ├─ Authentication events
│      └─ Compliance-critical events
│
│  Alerting:
│  ├─ Alert rules: 50+ rules (scaled by thresholds)
│  ├─ Notification channels: Email, PagerDuty, Teams
│  ├─ Smart detection: Anomaly-based alerts
│  ├─ Action groups: Automated remediation webhooks
│  └─ SLA: 1-minute evaluation interval
│
└──────────────────────────────────────────────┘
```

---

## Multi-Region Deployment

### Failover Strategy

```
Primary Region (East US 2):
├─ AKS Cluster (active)
├─ PostgreSQL (primary write)
├─ Redis (master)
├─ Cosmos DB (write region)
└─ ACR (primary registry)

Secondary Region (West US 2):
├─ AKS Cluster (warm standby / active-active)
├─ PostgreSQL (read replica)
├─ Redis (replica)
├─ Cosmos DB (read region)
└─ ACR (geo-replicated)

Tertiary Region (North Europe):
├─ AKS Cluster (active-active for read-heavy)
├─ PostgreSQL (read replica)
├─ Redis (replica)
├─ Cosmos DB (read region)
└─ ACR (geo-replicated)

Failover Logic:
├─ Detection: 30-second health check interval
├─ Failover time: 60 seconds (DNS propagation)
├─ Trigger: 3 consecutive failures
├─ Automatic: Azure Front Door + Cosmos DB
└─ Manual override: Available via ARM template
```

### Data Synchronization

```
PostgreSQL:
├─ Primary (Region 1): Read-write
├─ Standby (Region 1): Streaming replication (sync)
├─ Read Replicas (Region 2, 3): Async replication (RPO: 15min)
├─ Replication lag: <100ms
└─ Failover: Promote read replica (manual approval)

Redis:
├─ Primary (Region 1): Write operations
├─ Zone Replica (Region 1): Sync replication
├─ Geo-replicas (Region 2, 3): Async (15-min sync)
└─ Failover: Automatic (2-minute window)

Cosmos DB:
├─ Write region: Region 1 (primary)
├─ Read regions: Region 2, 3
├─ Replication: 4-region write (optional)
├─ Consistency: Strong (single-write region)
└─ Failover: Automatic (1-second detect + switch)
```

---

## Data Consistency Strategy

### Event-Driven Consistency

```
Write Operation Flow:
┌─────────────────────────────────┐
│ Application Write (Region 1)    │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ PostgreSQL Primary (Write)      │
│ ├─ Commit: ACID guarantee       │
│ └─ Emit: Change Data Capture    │
└────────────┬────────────────────┘
             │
    ┌────────┴─────────┐
    │                  │
    ▼                  ▼
┌──────────────┐  ┌──────────────────────┐
│ Cosmos DB    │  │ Service Bus / Event  │
│ (write)      │  │ Hub (event stream)   │
└──────────────┘  └──────────────────────┘
    │                  │
    │          ┌───────┴────────┐
    │          ▼                ▼
    │      ┌────────────┐  ┌─────────────┐
    │      │ Redis      │  │ Change Feed │
    │      │ (cache)    │  │ (audit log) │
    │      └────────────┘  └─────────────┘
    │
    └─► Replicate to Region 2, 3

Consistency Level: Eventual (99% within 5 seconds)
```

---

## Security & Networking

### Network Architecture (Per Region)

```
┌────────────────────────────────────────────┐
│  Azure Virtual Network (VNet)              │
├────────────────────────────────────────────┤
│  
│  Subnets:
│  ├─ AKS-Subnet (10.0.1.0/24)
│  │  ├─ NSG: Ingress from App Gateway
│  │  ├─ Service endpoints: Storage, SQL
│  │  └─ Pod IP range: 10.244.0.0/16
│  │
│  ├─ Database-Subnet (10.0.2.0/24)
│  │  ├─ NSG: Ingress from AKS only
│  │  ├─ Private link endpoint
│  │  └─ No public IP
│  │
│  ├─ Gateway-Subnet (10.0.3.0/24)
│  │  ├─ Application Gateway (Layer 7)
│  │  ├─ WAF policies
│  │  └─ Public IP assigned
│  │
│  └─ Management-Subnet (10.0.4.0/24)
│     ├─ Bastion host (RDP/SSH)
│     ├─ VPN gateway (site-to-site)
│     └─ NSG: Restricted access
│
│  Network Security Groups (NSG):
│  ├─ Inbound rules: App Gateway only (80, 443)
│  ├─ Outbound rules: Egress to internet + DNS
│  ├─ Flow logs: Enabled (traffic analysis)
│  └─ Threat intelligence: Azure DDoS Standard
│
│  Private Connectivity:
│  ├─ Private endpoints: PostgreSQL, Cosmos DB, Redis
│  ├─ Service endpoints: Azure Storage, Key Vault
│  ├─ VNet link: DNS private zones
│  └─ Peering: Cross-region VNet peering (optional)
│
└────────────────────────────────────────────┘
```

### Identity & Access Management

```
Azure Active Directory (AAD) Integration:
├─ Service Principals:
│  ├─ AKS identity (kubelet)
│  ├─ Application identity (workload)
│  ├─ CI/CD identity (GitHub Actions)
│  └─ Admin service principal (ops)
│
├─ Pod Identity (Workload Identity):
│  ├─ Federated credentials (OIDC)
│  ├─ No secrets stored in pods
│  ├─ Time-limited tokens (1 hour default)
│  └─ Per-pod role assignments
│
├─ RBAC (Role-Based Access Control):
│  ├─ Owner: Subscription management
│  ├─ Contributor: Resource creation
│  ├─ Reader: View-only access
│  └─ Custom roles: Application-specific
│
└─ Azure Key Vault Integration:
   ├─ Secrets: Database passwords, API keys
   ├─ Keys: Encryption keys (CMK)
   ├─ Certificates: TLS/SSL
   ├─ Access policies: Per service principal
   ├─ Audit logging: All access events
   └─ Soft delete: 90-day recovery window
```

---

## Monitoring & Observability

### KPIs & Metrics

```
Application Performance:
├─ Request latency (P50/P95/P99): <100ms / <500ms / <1s
├─ Error rate: <0.1% (4 nines SLA)
├─ Throughput: 10K+ req/sec per region
├─ Dependency latency: Database <50ms, API <200ms
└─ User satisfaction (APDEX): >0.95

Infrastructure Health:
├─ CPU utilization: 40–60% (under-provisioned alert: >80%)
├─ Memory utilization: 50–70% (critical: >90%)
├─ Disk I/O: <500 IOPS per node
├─ Network throughput: <80% of max
└─ Pod restart count: <5/day (anomaly: >10)

Business Metrics:
├─ Active users (DAU/MAU)
├─ Session duration
├─ Feature usage (top 10)
├─ Conversion rate (if applicable)
└─ Revenue impact (infrastructure cost/feature)

Database Metrics:
├─ Connection pool utilization: 60–75%
├─ Query execution time (P99): <1s
├─ Replication lag: <100ms
├─ Backup completion time: <15 minutes
└─ Storage growth rate: Monitor for scaling
```

---

## Cost Optimization

### Reserved Instances & Savings Plans

```
Compute (AKS):
├─ Reserved Instances: 1-year (40% savings)
│  ├─ System pool: Reserved (predictable)
│  ├─ App pool: Spot instances (70% savings, interruptible)
│  └─ Data pool: Reserved (critical workloads)
│
├─ Hybrid Benefit: Windows/SQL Server (if applicable)
└─ Savings Plan: 3-year compute commitment (35% savings)

Storage:
├─ GRS replication: Premium tier for hot data
├─ Lifecycle policies: Cool/Archive for historical data
├─ Blob storage: $0.018/GB/month (GRS)
└─ Database: Reserved capacity (30% savings)

Networking:
├─ Data transfer: Minimize inter-region egress
├─ Azure Content Delivery Network (CDN): For static assets
├─ Traffic Manager: Free
└─ Public IP: $0.045/hour (optimize usage)

Monthly Cost Estimate (Regional):
├─ AKS: ~$3K–5K (3x D4s nodes + auto-scale)
├─ PostgreSQL: ~$500–800 (managed HA)
├─ Redis: ~$300–500 (6GB premium)
├─ Cosmos DB: ~$400–600 (auto-scale)
├─ Storage: ~$200–300 (GRS)
├─ Monitor/Logs: ~$300–500 (ingestion)
└─ Total per region: ~$5.5K–8K (~$16.5K–24K for 3 regions)
```

---

## Disaster Recovery

### RTO/RPO Targets

```
Tier 1 (Critical):
├─ RTO: <15 minutes
├─ RPO: <5 minutes (near-zero data loss)
├─ Components: AKS, PostgreSQL primary
└─ Strategy: Active-active + automatic failover

Tier 2 (Important):
├─ RTO: <1 hour
├─ RPO: <30 minutes (acceptable loss)
├─ Components: Cosmos DB, Redis
└─ Strategy: Geo-replication + manual failover

Tier 3 (Standard):
├─ RTO: <4 hours
├─ RPO: <1 hour
├─ Components: ACR, Backups
└─ Strategy: Cross-region restore

Tier 4 (Non-critical):
├─ RTO: <24 hours
├─ RPO: <4 hours
├─ Components: Archived data
└─ Strategy: On-demand restore from backup
```

### Backup & Recovery Plan

```
Daily Schedule:
├─ 00:00 UTC: PostgreSQL full backup (GRS)
├─ 06:00 UTC: Cosmos DB snapshot export
├─ 12:00 UTC: Application configuration backup
├─ 18:00 UTC: Incremental PostgreSQL backup
└─ Hourly: Continuous transaction log backup

Recovery Procedures:
├─ AKS: Redeploy from Helm charts (manifest)
├─ PostgreSQL: Point-in-time restore (7 days)
├─ Cosmos DB: Latest snapshot + replay journal
├─ Redis: Data loss acceptable (rebuild cache)
└─ ACR images: Retained 90 days (re-pull as needed)

Disaster Recovery Drill:
├─ Quarterly full region failover test
├─ Monthly application restart from backups
├─ Weekly backup restoration validation
└─ RTO/RPO verification after each drill
```

---

## Integration with On-Premises Kubernetes

### Hybrid Architecture

For organizations maintaining on-premises infrastructure:

```
┌──────────────────────────────────────────────┐
│  Azure Arc (Hybrid Management)               │
├──────────────────────────────────────────────┤
│
│  On-Premises Kubernetes:
│  ├─ Register cluster with Azure Arc
│  ├─ Unified monitoring from Azure Monitor
│  ├─ GitOps via Arc-enabled GitOps
│  ├─ Azure Policies applied across both
│  └─ Role-based access control (RBAC)
│
│  Sync Mechanisms:
│  ├─ Azure ExpressRoute (dedicated network)
│  ├─ Site-to-Site VPN (backup connectivity)
│  ├─ Application Gateway for hybrid load balancing
│  └─ Azure Data Factory for data sync (ETL)
│
│  Benefits:
│  ├─ Consistent management platform
│  ├─ Unified security policies
│  ├─ Shared monitoring & alerting
│  ├─ Disaster recovery across on-prem/cloud
│  └─ Cost optimization insights
│
└──────────────────────────────────────────────┘
```

---

## Migration Mapping: Azure Services → Target Services

| Current Azure Service | Target On-Prem Service | Target Azure Service |
|----------------------|----------------------|----------------------|
| App Service | Kubernetes Pods | AKS (this doc) |
| PostgreSQL Managed | PostgreSQL HA (Patroni) | Azure Database PostgreSQL |
| Redis Cache | Redis Cluster | Azure Cache for Redis |
| Blob Storage | MinIO S3 | Storage Account |
| Application Gateway | F5 BIG-IP | Azure Application Gateway |
| Front Door | N/A | Azure Front Door |
| Cosmos DB | PostgreSQL/MongoDB | Azure Cosmos DB |
| Application Insights | Prometheus + Grafana | App Insights (this doc) |
| Log Analytics | ELK Stack | Log Analytics Workspace |
| Key Vault | HashiCorp Vault | Azure Key Vault |
| DevOps Pipelines | GitLab CI + ArgoCD | Azure DevOps / GitHub Actions |

---

## Deployment Checklist

- [ ] Resource group created (per region)
- [ ] VNet + Subnets provisioned (address space planned)
- [ ] NSG + firewall rules configured
- [ ] AKS cluster deployed (version 1.28+)
- [ ] ACR provisioned with geo-replication
- [ ] PostgreSQL instance created (HA enabled)
- [ ] Cosmos DB account provisioned
- [ ] Redis cache deployed
- [ ] Storage Account created (GRS)
- [ ] Application Gateway configured (WAF enabled)
- [ ] Azure Front Door setup (global load balancing)
- [ ] Application Insights enabled
- [ ] Log Analytics Workspace created
- [ ] Azure Monitor alerts configured
- [ ] Backup vault setup (cross-region replication)
- [ ] Private endpoints configured (database/storage)
- [ ] Service principals created (for workloads)
- [ ] RBAC roles assigned
- [ ] Key Vault policies configured
- [ ] Disaster recovery test completed

---

## References

- [Azure Kubernetes Service (AKS)](https://docs.microsoft.com/azure/aks/)
- [Azure Database for PostgreSQL](https://docs.microsoft.com/azure/postgresql/)
- [Azure Cosmos DB](https://docs.microsoft.com/azure/cosmos-db/)
- [Azure Container Registry](https://docs.microsoft.com/azure/container-registry/)
- [Azure Cache for Redis](https://docs.microsoft.com/azure/azure-cache-for-redis/)
- [Azure Monitor & Application Insights](https://docs.microsoft.com/azure/azure-monitor/)
- [Azure Front Door](https://docs.microsoft.com/azure/frontdoor/)

---

**Classification**: Internal Use Only  
**Version**: 1.0  
**Created**: July 2026  
**Author**: Migration Architecture Team  
**Status**: Published
