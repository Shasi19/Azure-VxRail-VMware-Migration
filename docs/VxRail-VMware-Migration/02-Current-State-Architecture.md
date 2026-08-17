# Azure Current State Architecture

**Comprehensive Documentation of Existing Azure Workloads & Infrastructure**

---

## Table of Contents
1. [Executive Summary](#executive-summary)
2. [Current Azure Infrastructure](#current-azure-infrastructure)
3. [Application Architecture](#application-architecture)
4. [Database Architecture](#database-architecture)
5. [Storage & Backup](#storage--backup)
6. [Networking](#networking)
7. [Monitoring & Logging](#monitoring--logging)
8. [Capacity & Performance](#capacity--performance)
9. [Cost Analysis](#cost-analysis)
10. [Dependencies & Integrations](#dependencies--integrations)

---

## Executive Summary

### Current State Overview
- **3 AKS Clusters**: QA (dev), PREPROD (staging), PROD (production)
- **Database**: Azure Database for PostgreSQL (managed service, ver. 13)
- **NoSQL**: Azure Cosmos DB (SQL API, multi-region)
- **Storage**: Azure Storage Accounts (blob, file shares, queues)
- **Backup**: Veeam Backup & Replication (backup to Azure Storage)
- **Registry**: Azure Container Registry (ACR) with premium tier
- **Monitoring**: Azure Monitor, Application Insights, Log Analytics
- **Networking**: Virtual Networks (VNets) with ExpressRoute/VPN hybrid connectivity
- **Total Workload**: ~25 containerized microservices across all environments

### Key Numbers
- **AKS Node Count**: 6 + 8 + 12 = 26 total nodes (QA + PREPROD + PROD)
- **Compute**: ~52 vCPUs, ~156 GB RAM allocated
- **Storage**: ~2 TB database + 1 TB object storage + 500 GB logs
- **Monthly Cost**: ~$45,000 (compute) + $12,000 (storage) + $8,000 (backup) = $65,000/month
- **Total Users**: 3,000+ (PROD), 500 (PREPROD), 200 (QA)
- **Data Tier**: Single-region primary + DR replica in paired region

---

## Current Azure Infrastructure

### Azure Kubernetes Service (AKS) Clusters

#### QA Cluster (Development)
```
Cluster: aks-qa-001
Region: East US 2
Kubernetes Version: 1.29.x
Node Count: 6 nodes
Node Type: Standard_D4s_v3 (4 vCPU, 16 GB RAM per node)
Container Runtime: containerd
Networking: Kubenet (simple networking model)
Storage: Azure Managed Disks (Premium SSD)
DNS: Azure DNS
Load Balancer: Azure Load Balancer (Basic)

Namespaces:
  - default
  - kube-system
  - kube-public
  - monitoring (Prometheus + Grafana)
  - applications
  - database (PostgreSQL operator)
```

#### PREPROD Cluster (Staging)
```
Cluster: aks-preprod-001
Region: East US 2
Kubernetes Version: 1.29.x
Node Count: 8 nodes
Node Type: Standard_D8s_v3 (8 vCPU, 32 GB RAM per node)
Container Runtime: containerd
Networking: Azure CNI (advanced networking)
Storage: Azure Managed Disks (Premium SSD)
DNS: Azure DNS
Load Balancer: Azure Load Balancer (Standard)

Namespaces:
  - default
  - kube-system
  - kube-public
  - monitoring
  - applications
  - database
  - testing (load testing tools)
```

#### PROD Cluster (Production)
```
Cluster: aks-prod-001
Region: East US 2
Kubernetes Version: 1.29.x
Node Count: 12 nodes
Node Type: Standard_D16s_v3 (16 vCPU, 64 GB RAM per node)
Container Runtime: containerd
Networking: Azure CNI (advanced networking)
Storage: Azure Managed Disks (Premium SSD, ZRS - Zone Redundant Storage)
DNS: Azure DNS
Load Balancer: Azure Load Balancer (Standard)
Auto-scaling: Enabled (8-16 nodes)

Namespaces:
  - default
  - kube-system
  - kube-public
  - monitoring
  - applications
  - database
```

### Virtual Networks (VNets) & Networking

```
VNet: vnet-primary (10.0.0.0/16)
├── Subnet: aks-qa (10.0.1.0/24) → aks-qa-001 cluster
├── Subnet: aks-preprod (10.0.2.0/24) → aks-preprod-001 cluster
├── Subnet: aks-prod (10.0.3.0/24) → aks-prod-001 cluster
├── Subnet: database (10.0.4.0/24) → PostgreSQL, Cosmos DB
├── Subnet: storage (10.0.5.0/24) → Storage accounts, backups
└── Subnet: monitoring (10.0.6.0/24) → Log Analytics agents

VNet Peering: vnet-primary ↔ vnet-dr (10.1.0.0/16) [East US]

Connectivity:
- ExpressRoute Circuit (2 Gbps) → On-premises datacenter
- Azure VPN Gateway (Site-to-Site) → Backup connectivity
- Azure Bastion → Secure shell access to VMs
```

### Network Security Groups (NSGs)

```
NSG: aks-qa-nsg
  Inbound Rules:
    - Allow TCP 443 (HTTPS) from 0.0.0.0/0 (internet)
    - Allow TCP 6443 (Kubernetes API) from on-prem (10.200.0.0/8)
    - Allow TCP 22 (SSH) from on-prem only
  
NSG: aks-prod-nsg
  Inbound Rules:
    - Allow TCP 443 (HTTPS) from 0.0.0.0/0 (internet)
    - Allow TCP 6443 (Kubernetes API) from on-prem (10.200.0.0/8)
    - Allow TCP 22 (SSH) from on-prem only
    - Allow UDP 500, 4500 (IPSec) from on-prem
  Outbound Rules:
    - Allow all traffic to 0.0.0.0/0 (default)

NSG: database-nsg
  Inbound Rules:
    - Allow TCP 5432 (PostgreSQL) from AKS subnets only
    - Allow TCP 27017 (MongoDB) from AKS subnets only
  Outbound Rules:
    - Allow TCP 443 (HTTPS) to internet (backup, updates)
```

---

## Application Architecture

### Microservices Breakdown (PROD)

| Service | Language | Replicas | CPU | Memory | Status |
|---------|----------|----------|-----|--------|--------|
| API Gateway | Go | 3 | 500m | 512Mi | Running |
| Authentication Service | Python | 3 | 500m | 512Mi | Running |
| User Service | Go | 2 | 250m | 256Mi | Running |
| Product Service | Python | 2 | 250m | 256Mi | Running |
| Order Service | Java | 3 | 1000m | 1Gi | Running |
| Payment Service | Node.js | 2 | 500m | 512Mi | Running |
| Notification Service | Python | 2 | 250m | 256Mi | Running |
| Analytics Service | Python | 1 | 500m | 1Gi | Running |
| Admin Dashboard | React (SPA) | 2 | 100m | 128Mi | Running |
| Mobile Backend | Go | 2 | 250m | 256Mi | Running |
| File Service | Python | 2 | 500m | 512Mi | Running |
| Cache Layer | Redis | 1 | 250m | 1Gi | Running |
| Message Queue | RabbitMQ | 1 | 500m | 1Gi | Running |
| Logging Agent | Fluentd | DaemonSet | 100m | 256Mi | Running |

### Ingress Architecture

```
Internet Traffic
    ↓
Azure Traffic Manager (DNS-based load balancing)
    ↓
Ingress Controller (NGINX - 3 replicas in PROD)
    ├── api.company.com → API Gateway Service
    ├── admin.company.com → Admin Dashboard Service
    ├── auth.company.com → Authentication Service
    └── *.api.company.com → Internal API routing

SSL/TLS: Azure Application Gateway (WAF enabled)
- Certificate: Managed via Azure Key Vault
- WAF Rules: OWASP Top 10 enabled
- Rate Limiting: 1000 req/min per IP
```

### Service Discovery & Configuration

- **DNS**: CoreDNS (in-cluster DNS)
- **Service Mesh**: None (direct service-to-service calls)
- **Configuration Management**: ConfigMaps + Secrets (Azure Key Vault CSI driver)
- **Service Accounts**: Separate RBAC for each microservice

---

## Database Architecture

### PostgreSQL Managed Database

```
Service: Azure Database for PostgreSQL
Tier: Premium (Burstable: B_Standard_B2s, General Purpose: GP_Standard_D2s_v3)
Version: PostgreSQL 13
High Availability: Zone-redundant (automatic failover)
Storage: 1 TB (auto-scaling enabled, up to 10 TB)
Backup: 35-day retention, geo-redundant backup
Replica: Read replica in West US 2 (for DR)

Databases:
  - production_db (PROD workloads)
  - staging_db (PREPROD workloads)
  - dev_db (QA workloads)

Connection Pooling: Azure Database for PostgreSQL connection pooling (PgBouncer)
- Pool size: 100 connections max
- Connection timeout: 30 seconds
- Idle timeout: 600 seconds

Performance Metrics:
  - Avg Query Time: 45ms
  - Max Connections: 512
  - Avg Transactions/sec: 1,200
  - Storage Used: 650 GB (avg)
  - Backup Size: ~200 GB (compressed)

Maintenance Windows: Sundays 2-4 AM UTC (auto-patching enabled)
```

### Azure Cosmos DB (MongoDB API)

```
Service: Azure Cosmos DB - MongoDB API
Account Name: cosmos-prod-001
Tier: Standard (provisioned throughput)
Regions: Primary (East US 2) + Secondary (West US 2)
API: MongoDB 4.0 compatible

Collections:
  - users: 50K documents, ~200 MB
  - sessions: 1M documents (TTL: 24 hours), ~800 MB
  - events: Time-series, ~2B documents, auto-partitioned, ~50 GB
  - cache: Temporary data, TTL: 1 hour, ~5 GB

Throughput Configuration:
  - Production: 5,000 RUs (request units)
  - PREPROD: 1,000 RUs
  - QA: 400 RUs
  - Auto-scale enabled (max 15,000 RUs during load)

Consistency: Session consistency
Backup: Continuous (7-day retention), geo-redundant
Geo-replication: Multi-master enabled (eventual consistency)
```

---

## Storage & Backup

### Azure Storage Accounts

```
Storage Account: stgprod001 (Premium Tier)
Regions: East US 2 (LRS + GRS backup)
Containers:
  - app-data/: 450 GB (user uploads, documents)
  - app-logs/: 200 GB (7-day rolling logs)
  - app-backups/: 300 GB (database backups)
  - app-artifacts/: 150 GB (build artifacts, Docker layers)

Tiers:
  - Hot (80% of data): Frequently accessed
  - Cool (15% of data): Infrequently accessed, 30-day minimum
  - Archive (5% of data): Long-term retention, 90-day minimum

Access: Shared Key + Azure AD Service Principal
Encryption: Microsoft-managed keys (CMK available)
Redundancy: Geo-redundant Storage (GRS) - 3x replication
```

### Veeam Backup Configuration

```
Backup Server: Veeam Backup & Replication (Azure VM)
- VM Size: Standard_D8s_v3 (8 vCPU, 32 GB RAM)
- OS: Windows Server 2022
- Version: Veeam v12

Backup Repository: Azure Storage Account
- Blob Storage: stg-backups-001
- Container: veeam-backups (2 TB allocated)
- Redundancy: LRS to Azure (then GRS to paired region)

Backup Policy:
  PostgreSQL Database:
    - Frequency: Daily incremental
    - Full backup: Weekly (Sundays)
    - Retention: 30 days
    - Method: pg_basebackup + WAL archiving

  Application VMs:
    - Frequency: Daily
    - Full backup: Weekly
    - Retention: 30 days
    - Deduplication: Enabled (40% reduction)

  Container Registry (ACR):
    - Frequency: Weekly
    - Method: Blob snapshot
    - Retention: 12 weeks

RPO Target: 4 hours (backup every 4 hours for critical data)
RTO Target: 2 hours (restore from backup within 2 hours)
```

---

## Networking

### Hybrid Connectivity Architecture

```
On-Premises Datacenter (10.200.0.0/8)
         ↓
    [VPN Gateway]
         ↓
  ┌─────────────────┐
  │ Azure Hybrid    │
  │ Connectivity    │
  │ - ExpressRoute  │
  │ - VPN (backup)  │
  └─────────────────┘
         ↓
  ┌─────────────────┐
  │ Azure Gateway   │
  │ Subnet          │
  │ (10.0.7.0/24)   │
  └─────────────────┘
         ↓
  ┌─────────────────┐
  │ AKS Clusters    │
  │ & Databases     │
  └─────────────────┘
```

### DNS Resolution

```
Public DNS: company.com → Azure Traffic Manager
Internal DNS: *.internal.company.com → Azure DNS (10.0.0.1)

DNS Records:
  api.company.com A 40.x.x.x (Azure Public IP)
  *.api.company.com CNAME api.company.com
  kubernetes.default.svc.cluster.local A 10.0.1.1 (in-cluster)
  database.internal CNAME postgres.database.azure.com
```

---

## Monitoring & Logging

### Azure Monitor Setup

```
Log Analytics Workspace: law-prod-001
Retention: 30 days (default), 90 days (custom tables)

Data Sources:
  - AKS Cluster Logs (diagnostic settings enabled)
  - Application Insights (SDK instrumentation)
  - Database Metrics (Azure Database for PostgreSQL)
  - Storage Metrics (blob read/write/delete)
  - Veeam Backup Logs (syslog integration)
  - Network Flow Logs (NSG diagnostics)

Monitoring Tools:
  - Azure Monitor Metrics
  - Application Insights (APM)
  - Log Analytics (KQL queries)
  - Alerts (action groups, email/SMS/Teams)
```

### In-Cluster Monitoring

```
Prometheus + Grafana (deployed in monitoring namespace)
- Prometheus Data Retention: 15 days
- Grafana Dashboards: 20+ custom dashboards
- Alert Manager: Integrated with Azure Monitor

Key Metrics Collected:
  - Kubernetes cluster health (node/pod count)
  - Pod CPU/Memory usage
  - Container restart rates
  - Network I/O
  - Database connection pool stats
  - Application response times
  - Error rates (5xx responses)
```

### ELK Stack

```
Elasticsearch Cluster: 3 data nodes (Azure VMs)
Logstash: 3 instances (log parsing & enrichment)
Kibana: Web UI for log analysis

Log Sources:
  - Application logs (stdout/stderr)
  - Nginx access logs
  - PostgreSQL query logs
  - Azure Storage diagnostics
  - Kubernetes events

Index Pattern: logs-{year}.{month}.{day}
Retention Policy: 30 days
Disk Usage: ~1.2 TB
Daily Log Volume: ~500 GB
```

---

## Capacity & Performance

### Current Resource Utilization (PROD)

| Resource | Allocated | Used | Utilization |
|----------|-----------|------|-------------|
| CPU (vCPU) | 192 | 96 | 50% |
| Memory (GB) | 768 | 384 | 50% |
| Storage (TB) | 3 | 1.8 | 60% |
| Network (Gbps) | 40 | 4 | 10% |
| Database Connections | 512 | 280 | 55% |

### Performance Baselines

```
API Response Time (p95): 200ms
Database Query Time (p95): 50ms
Page Load Time (p95): 1.2s
Error Rate (5xx): 0.05%
Uptime: 99.95%
Deployment Frequency: 10x/week
Mean Time to Recovery (MTTR): 15 minutes
```

### Peak Load Characteristics

```
Peak Load Timing: Weekdays 9 AM - 5 PM EST
Concurrent Users: 3,000+ during peak
Transactions/sec (PROD): 2,500 TPS
Database connections: 450+ connections
Memory usage: ~600 GB during peak
CPU utilization: 70-80% during peak
```

---

## Cost Analysis

### Monthly Cost Breakdown

| Component | Cost | Notes |
|-----------|------|-------|
| AKS Compute | $28,000 | 26 total nodes (6+8+12) |
| Azure Database PostgreSQL | $12,000 | Premium tier, HA enabled |
| Cosmos DB | $3,500 | 5K RU provisioned |
| Storage Accounts | $8,000 | 2 TB average usage |
| Veeam Backup | $5,000 | Backup storage + licenses |
| Azure Monitor/AppInsights | $2,000 | Logs, metrics, APM |
| Virtual Network | $1,200 | VPN Gateway, traffic |
| Load Balancer | $800 | Azure LB (standard) |
| **Total Monthly** | **$60,500** | |
| **Annual Cost** | **$726,000** | |

### Cost Optimization Opportunities

1. **Reserved Instances**: 3-year commitment = 30% savings (~$18k/month)
2. **Spot Instances for non-critical**: 60% savings on test environments (~$3k/month)
3. **Storage Tiering**: Move 40% to cool tier = 50% storage savings (~$1.5k/month)
4. **On-premises Migration**: Expected $15-20k/month savings (vs. current $60.5k)

---

## Dependencies & Integrations

### External Integrations

```
Email Service:
  - SendGrid API (SMTP integration)
  - Rate limit: 100k emails/day
  - Monthly cost: $800

Payment Gateway:
  - Stripe API (PCI-DSS compliant)
  - 2.2% + $0.30 per transaction
  - ~50k transactions/month

Analytics:
  - Google Analytics (embedded in SPA)
  - Amplitude (custom events)
  - Cost: $1,200/month

Logging:
  - Datadog (third-party APM - optional)
  - Currently using Azure Monitor only

CDN:
  - Azure CDN (Azure Front Door)
  - Static assets cached (images, JS, CSS)
  - Edge locations: 200+ worldwide
```

### Critical Dependencies

1. **Database**: All microservices depend on PostgreSQL (single point of failure if not HA)
2. **Message Queue**: Notification service depends on RabbitMQ
3. **Cache**: Payment Service depends on Redis for session data
4. **Authentication**: All services depend on Auth Service

---

## Migration Readiness Assessment

### Risks from Current Architecture
- **Single PostgreSQL Instance**: No automatic failover
- **No Multi-AZ Redundancy**: All AKS clusters in single availability zone
- **Dependent on Azure Services**: Cosmos DB, Azure Storage require connectivity

### Advantages of Current Setup
- **Managed Services**: Database backups, patching automated
- **Built-in Monitoring**: Azure Monitor deeply integrated
- **Hybrid Connectivity**: ExpressRoute for on-premises integration
- **Mature Backup Strategy**: Veeam provides point-in-time recovery

---

## Key Artifacts for Migration Planning

**Documents to gather before migration:**
- [ ] Complete application inventory (all microservices)
- [ ] Database schema export (pg_dump)
- [ ] PostgreSQL user accounts & permissions
- [ ] Cosmos DB collection definitions & indexes
- [ ] ACR container image manifests (helm charts)
- [ ] Azure Key Vault secrets inventory
- [ ] Network firewall rules & NSG configurations
- [ ] Monitoring dashboard definitions (Grafana JSON)
- [ ] Backup retention policies & RPO/RTO SLAs
- [ ] Cost allocation & chargeback model

---

## Next Steps

1. **Week -2**: Export current state configurations
2. **Week -1**: Target architecture design review
3. **Week 0**: Pre-migration checklist validation
4. **Week 1-3**: QA phase implementation
5. **Week 4-8**: PREPROD phase implementation
6. **Week 9-16**: PROD phase implementation

---

**End of Current State Architecture Document**

Reference: [03-Target-State-Architecture.md](#), [04-Pre-Migration-Checklist.md](#)

