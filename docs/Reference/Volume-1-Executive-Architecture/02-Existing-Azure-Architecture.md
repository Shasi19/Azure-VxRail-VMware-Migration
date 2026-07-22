# Volume 1: Executive & Solution Architecture
## Chapter 2: Existing Azure Architecture

---

## Current Azure Infrastructure Overview

> **Architecture Pattern**: Hub-and-Spoke, 4 identical environments, West Europe region.
> Each environment has the **same 5-service stack**: AKS + Storage + Cosmos DB + ACR + PostgreSQL.

### Azure Services Inventory

```
┌─────────────────────────────────────────────────────────────────────────┐
│   AZURE CLOUD INFRASTRUCTURE  (Hub-and-Spoke, West Europe)              │
│   4 ENVIRONMENTS — Dev, QA, Pre-Prod, Production                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   Sub-AFRPS-AF-INT  ─  Hub Subscription (Centralised Connectivity)      │
│   UDR Route Tables on all environment VNets -> Hub                      │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  rg-ae-prod-we-001   DEV Environment                             │   │
│  │  ├─ Azure Kubernetes Service (AKS) + UDR                        │   │
│  │  ├─ Azure Storage Account + UDR                                 │   │
│  │  ├─ Azure Cosmos DB + UDR                                       │   │
│  │  ├─ Azure Container Registry (ACR) + UDR                        │   │
│  │  └─ Azure Database for PostgreSQL + UDR                         │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  rg-cv-preprod-we-001   QA Environment                           │   │
│  │  ├─ Azure Kubernetes Service (AKS) + UDR                        │   │
│  │  ├─ Azure Storage Account + UDR                                 │   │
│  │  ├─ Azure Cosmos DB + UDR                                       │   │
│  │  ├─ Azure Container Registry (ACR) + UDR                        │   │
│  │  └─ Azure Database for PostgreSQL + UDR                         │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  rg-as-las-we-001   Pre-Production Environment                   │   │
│  │  ├─ Azure Kubernetes Service (AKS) + UDR                        │   │
│  │  ├─ Azure Storage Account + UDR                                 │   │
│  │  ├─ Azure Cosmos DB + UDR                                       │   │
│  │  ├─ Azure Container Registry (ACR) + UDR                        │   │
│  │  └─ Azure Database for PostgreSQL + UDR                         │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  rg-dls-coe-we-001   Production Environment + Shared Monitoring  │   │
│  │  ├─ Azure Kubernetes Service (AKS) + UDR                        │   │
│  │  ├─ Azure Storage Account + UDR                                 │   │
│  │  ├─ Azure Cosmos DB + UDR                                       │   │
│  │  ├─ Azure Container Registry (ACR) + UDR                        │   │
│  │  ├─ Azure Database for PostgreSQL + UDR                         │   │
│  │  ├─ Azure Monitor (centralised telemetry from all envs)         │   │
│  │  └─ Application Insights                                        │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Component Details

### 1. Compute Layer — Azure Kubernetes Service (AKS)

Each of the three workload VNets (rg-ae-prod-we-001, rg-cv-prod-we-001, rg-as-las-we-001) runs a dedicated AKS cluster.

#### Azure Kubernetes Service (per workload VNet)

```
Configuration:
├─ Kubernetes Version: 1.28+
├─ Node Pool: System + User node pools
├─ VM SKU: Standard_D4s_v3 (typical)
├─ Auto-scaling: Enabled (Min: 2, Max: 5 nodes)
├─ Networking: Azure CNI + UDR routing to hub
├─ Managed Identity: Enabled (pod identity)
├─ Container Registry: Linked ACR per VNet
└─ RBAC: Azure AD integrated

Workloads:
├─ Application Pods (web-facing, auto-scaled)
├─ CronJob Pods (batch / ETL)
└─ Internal services / sidecars
```

#### Azure Container Instances (Batch / ETL)

```
Usage (rg-ae-prod-we-001, rg-as-las-we-001):
├─ Purpose: Ad-hoc batch jobs and ETL pipelines
├─ Frequency: Daily scheduled tasks
├─ Typical Duration: 5-30 minutes
├─ Memory: 1-4 GB per container
├─ CPU: 1-4 cores per container
├─ Storage: Ephemeral (temporary)
└─ Network: Virtual Network integrated (UDR)

Current Workloads:
├─ Report Generation (daily)
├─ Data Export (hourly)
├─ Cache Warming (on-demand)
└─ ETL Processes (nightly)
```

#### Azure Container Registry (ACR)

```
One ACR per workload VNet:
├─ SKU: Standard / Premium
├─ Geo-replication: Not enabled (single region)
├─ Image scanning: Microsoft Defender for Containers
├─ Private endpoint: VNet-integrated
├─ Admin account: Disabled (Managed Identity access)
└─ Webhook: Enabled for CD triggers
```

### 2. Networking — Hub and Spoke

#### Hub Subscription: Sub-AFRPS-AF-INT

```
Role: Centralised network connectivity hub
├─ UDR (User Defined Routes) pushed to all spoke VNets
├─ Forces egress traffic through hub (inspect / log)
├─ Provides shared connectivity services
└─ Peering with each workload VNet (Spoke)

Topology:
├─ VNet Peering: Hub ↔ rg-ae-prod-we-001
├─ VNet Peering: Hub ↔ rg-cv-prod-we-001
├─ VNet Peering: Hub ↔ rg-as-las-we-001
└─ VNet Peering: Hub ↔ rg-dls-coe-we-001
```

#### Virtual Networks (Workload Spokes)

```
Each workload VNet:
├─ Region: West Europe
├─ UDR: Applied to all subnets (route to hub)
├─ NSG: Applied to AKS, Storage, DB subnets
├─ Private Endpoints: PostgreSQL + Storage
├─ DNS: Private DNS zones
└─ Network Watcher: Enabled
```

### 3. Data Layer

#### Azure Cosmos DB (NoSQL — per environment)

```
One Cosmos DB account per environment (4 total):
├─ API: Core (SQL/NoSQL) — document-oriented
├─ Consistency: Session consistency (default)
├─ Replication: Single-region (West Europe)
├─ Throughput: Autoscale (400–4000 RU/s)
├─ Partition key: Per-collection design
├─ Indexing: Automatic (all fields)
├─ TTL: Enabled for session/cache collections
└─ Private Endpoint: VNet-integrated

Collections / Containers (typical):
├─ sessions       — User session documents (TTL: 24h)
├─ audit_logs     — Immutable audit trail
├─ notifications  — Event/notification queue
├─ config         — Dynamic application configuration
└─ analytics      — Aggregated analytics snapshots

Cost per environment: ~$2,500/month (autoscale)
Total (4 environments):  ~$10,000/month
```

#### Azure Database for PostgreSQL (per environment)

```
Configuration:
├─ Version: PostgreSQL 11
├─ Compute: 4 vCore, Memory-optimized
├─ Storage: 1 TB
├─ Backup: Geo-redundant
├─ Retention: 7 days (default)
├─ Replication: Read replicas (2)
├─ Scaling: Vertical only
└─ High Availability: Zone redundant

Performance:
├─ Database Size: 500 GB
├─ Tables: 250+
├─ Indexes: 1,500+
├─ Connections: 400 max
├─ Transactions/min: 10,000
├─ Query Response: 50-200ms (P95)
└─ Storage I/O: 2,000 IOPS

Security:
├─ Firewall: Enabled
├─ SSL: Required
├─ Authentication: Password + AD
├─ Encryption: At-rest (default)
├─ Audit logging: Enabled
└─ Backup encryption: AES-256

Backup & Recovery:
├─ Automatic Backup: Daily
├─ Backup Window: 2 AM UTC
├─ Retention: 7 days
├─ Geo-redundancy: Enabled
├─ PITR Window: 7 days
└─ Recovery Time: <15 minutes
```

#### Azure Storage Accounts

```
Account 1: Application Data
├─ Type: General Purpose v2
├─ Replication: RA-GRS (Geo-redundant)
├─ Access Tier: Hot
├─ Capacity: 1 TB
├─ Containers: 10+
├─ Blobs: 5,000+
└─ Uses: Application uploads, exports

Account 2: Backup Storage
├─ Type: General Purpose v2
├─ Replication: RA-GRS
├─ Access Tier: Cool
├─ Capacity: 2 TB
├─ Archives: 100+
└─ Uses: Daily backups, archives

Account 3: Logs
├─ Type: Blob Storage
├─ Replication: GRS
├─ Access Tier: Hot
├─ Capacity: 500 GB
└─ Uses: Diagnostics, audit logs

Security:
├─ Encryption: AES-256
├─ HTTPS: Enforced
├─ Firewall: Enabled
├─ Service Endpoints: Virtual Network
├─ Access Keys: Rotated quarterly
└─ SAS Tokens: Short-lived (1 hour)
```

#### Azure Cache for Redis

```
Configuration:
├─ SKU: Premium
├─ Capacity: 6 GB
├─ Clustering: Enabled
├─ Replication: Automatic
├─ Persistence: AOF enabled
├─ Virtual Network: Integrated
├─ TLS: Enabled
└─ Port: 6379 (encrypted)

Usage:
├─ Session Storage: 1 GB
├─ Cache: 3 GB
├─ Queue: 1 GB
├─ Temporary Data: 1 GB
└─ Hit Rate: 85-90%
```

### 4. Networking

#### Azure Virtual Network

```
Four VNets, all in West Europe region:

VNet 1 — rg-ae-prod-we-001
├─ Subnets: AKS, ACR, Storage, PostgreSQL
├─ UDR: Applied to all subnets
└─ Peered to: Sub-AFRPS-AF-INT hub

VNet 2 — rg-cv-prod-we-001
├─ Subnets: AKS, ACR, Storage, PostgreSQL
├─ UDR: Applied
└─ Peered to: Sub-AFRPS-AF-INT hub

VNet 3 — rg-as-las-we-001
├─ Subnets: AKS, ACR, Storage, PostgreSQL
├─ UDR: Applied to all subnets
└─ Peered to: Sub-AFRPS-AF-INT hub

VNet 4 — rg-dls-coe-we-001 (Shared Services)
├─ Subnets: PostgreSQL, Monitoring
├─ UDR: Applied
└─ Peered to: Sub-AFRPS-AF-INT hub

Security (all VNets):
├─ Network Security Groups: Per subnet
├─ Route Tables (UDR): Force-tunnel to hub
├─ Private Endpoints: PostgreSQL + Storage
├─ Network Watchers: Enabled
└─ Flow Logs: Enabled
```

### 5. Monitoring & Management

#### Azure Monitor

```
Capabilities:
├─ Metrics: Collected every 1 minute
├─ Logs: 30-day retention
├─ Alert Rules: 15+ active
├─ Action Groups: 3 (Email, SMS, Webhook)
├─ Autoscale: 2 rules active
├─ Diagnostics: Enabled on all resources
└─ Custom Metrics: Application-specific

Alerts:
├─ High CPU (App Service): >80%
├─ High Memory: >85%
├─ Database Connections: >350
├─ Response Time: >500ms (P95)
├─ Error Rate: >1%
├─ Storage Quota: >80%
└─ Health Check Failures: Any
```

#### Application Insights

```
Configuration:
├─ Instrumentation: SDK-based
├─ Sampling Rate: 100% (Production)
├─ Retention: 90 days
├─ Custom Events: 50+
├─ Custom Metrics: 100+
└─ Alerts: 10 active

Metrics Tracked:
├─ Request Rate
├─ Response Time
├─ Exception Rate
├─ Dependency Duration
├─ Server Response Time
├─ User Count
├─ Session Count
└─ Page View Count
```

#### Azure Log Analytics

```
Configuration:
├─ Workspace: 1
├─ Retention: 30 days (default)
├─ Data Ingestion Rate: 50 GB/day
├─ Queries: 20+ saved
├─ Workbooks: 5+ custom
└─ Alerts: 10+ rules

Data Sources:
├─ Application Logs
├─ System Logs
├─ Performance Data
├─ Security Events
├─ Audit Logs
└─ Custom Data
```

### 6. Security & Compliance

#### Azure Key Vault

```
Configuration:
├─ Name: prod-keyvault
├─ SKU: Premium
├─ Purge Protection: Enabled
├─ Soft Delete: 90 days
├─ Access Policy: RBAC-based
├─ Network Rules: Virtual Network restricted
└─ Logging: Enabled

Secrets Stored:
├─ Database Credentials
├─ API Keys
├─ Connection Strings
├─ Encryption Keys
├─ Service Principal Credentials
└─ Third-party API Keys

Certificates:
├─ SSL/TLS Certificates: 5
├─ Certificate Authority: DigiCert
├─ Auto-renewal: Enabled
├─ Expiration Alerts: 30 days
└─ Rotation Policy: Annual
```

#### Azure Security Center

```
Configuration:
├─ Tier: Standard
├─ Auto Provisioning: Enabled
├─ Data Collection: Full
├─ Threat Detection: Enabled
├─ Regulatory Compliance: 5 standards
└─ Alerts: 50+ rules

Compliance Frameworks:
├─ PCI DSS 3.2.1
├─ ISO 27001
├─ HIPAA
├─ SOC 2
└─ GDPR

Security Posture:
├─ Overall Score: 78/100
├─ Recommendations: 15 pending
├─ Critical Issues: 2
├─ High Issues: 5
└─ Medium Issues: 8
```

#### Azure Sentinel

```
Configuration:
├─ Workspace: Connected to Log Analytics
├─ Data Connectors: 10+
├─ Analytics Rules: 20+ active
├─ Playbooks: 5 automated
├─ Incidents: 30-day history
└─ SOAR Automation: Enabled

Monitored Threats:
├─ Brute Force Attacks
├─ SQL Injection Attempts
├─ Unauthorized Access
├─ Data Exfiltration
├─ Malware Detection
└─ Compliance Violations
```

### 7. Backup & Disaster Recovery

#### Azure Backup

```
Configuration:
├─ Backup Vault: prod-backup-vault
├─ Retention Policy: 30 days
├─ Backup Frequency: Daily at 2 AM UTC
├─ Redundancy: Geo-redundant
├─ Encryption: Customer-managed keys
└─ Monitoring: Enabled

Backup Items:
├─ Virtual Machines: 10+
├─ Databases: PostgreSQL (nightly)
├─ Storage Accounts: Daily snapshot
├─ App Configuration: Weekly
└─ Total Backup Size: 1.5 TB

Recovery Options:
├─ PITR: Point-in-time recovery
├─ Cross-Region: Geo-redundant restore
├─ Instant Restore: Backup cache
└─ Backup Report: Monthly
```

#### Azure Site Recovery

```
Configuration:
├─ Primary Region: US East
├─ Secondary Region: US West 2
├─ Failover RTO: <1 hour
├─ Failover RPO: 15 minutes
├─ Replication Policy: Every 5 minutes
└─ Test Failover: Monthly

Protected Resources:
├─ Virtual Machines: 10
├─ Databases: 2 (read replicas)
├─ Storage: Geo-redundant
└─ Network Configuration: Pre-configured
```

---

## Current Performance Baseline

### Application Performance

```
Metric                      Value           Target
────────────────────────────────────────────────────
Response Time (P50)         120 ms          <100ms
Response Time (P95)         180 ms          <200ms
Response Time (P99)         500 ms          <1000ms
Error Rate                  0.1%            <0.5%
Availability                99.95%          99.9%+
Throughput                  5,000 req/sec   5,000 req/sec
Avg Concurrent Users        3,000           10,000
Page Load Time              2.5 sec         <3 sec
```

### Infrastructure Performance

```
Component          CPU Avg    Memory Avg    Disk I/O    Network
──────────────────────────────────────────────────────────────
App Service        45%        60%           500 IOPS    400 Mbps
Database           35%        65%           1,500 IOPS  200 Mbps
Storage            10%        40%           200 IOPS    100 Mbps
Cache              25%        70%           100 IOPS    150 Mbps
```

---

## Cost Analysis - Current State

### Monthly Costs

```
Compute Services:
├─ App Service (3x P1V2):        $15,000
├─ Container Instances:           $2,000
└─ Subtotal Compute:            $17,000

Data Services:
├─ PostgreSQL Database:           $8,000
├─ Storage Accounts:              $5,000
├─ Redis Cache:                   $3,000
└─ Subtotal Data:               $16,000

Networking:
├─ VPN Gateway:                   $2,000
├─ Load Balancer:                 $1,000
└─ Subtotal Networking:           $3,000

Management & Monitoring:
├─ Azure Monitor:                 $2,000
├─ Log Analytics:                 $1,500
├─ Application Insights:          $1,000
└─ Subtotal Management:           $4,500

Security & Compliance:
├─ Security Center:               $1,000
├─ Key Vault:                       $500
└─ Subtotal Security:             $1,500

Backup & DR:
├─ Backup Vault:                  $1,500
├─ Site Recovery:                 $2,500
└─ Subtotal Backup:               $4,000

────────────────────────────────────────
TOTAL MONTHLY COST:              $46,000
TOTAL ANNUAL COST:              $552,000
```

---

## Limitations & Constraints

### Operational Limitations

```
1. Vendor Lock-in
   ├─ Azure-specific services
   ├─ Proprietary APIs
   ├─ Limited interoperability
   └─ Migration complexity to other clouds

2. Customization Constraints
   ├─ Limited infrastructure tuning
   ├─ No direct hardware access
   ├─ Limited OS configuration
   └─ Service throttling imposed

3. Compliance Challenges
   ├─ Data residency in Azure regions
   ├─ Limited audit capabilities
   ├─ Shared security model
   └─ Limited encryption key control

4. Cost Issues
   ├─ Growing cloud bills
   ├─ Unpredictable scaling costs
   ├─ Licensing complexity
   └─ Multi-service overhead
```

### Performance Constraints

```
1. Shared Infrastructure
   ├─ Resource contention
   ├─ Noisy neighbor effect
   ├─ Unpredictable latency spikes
   └─ Limited QoS guarantees

2. Network Latency
   ├─ Cloud region selection
   ├─ Internet routing variability
   ├─ CDN cache misses
   └─ Limited local optimization

3. Database Limitations
   ├─ Managed service constraints
   ├─ Limited scaling options
   ├─ Version lag
   └─ Configuration restrictions
```

---

## Conclusion

The current Azure architecture provides reliable cloud-based infrastructure with good availability and security. However, the ongoing costs, vendor lock-in, and operational constraints make a transition to on-premises infrastructure strategically attractive for long-term cost optimization and operational control.

The migration to on-premises will require significant upfront investment but will result in substantial long-term cost savings and operational flexibility while maintaining or exceeding current performance and availability standards.

---

**Document Version**: 1.0  
**Date**: January 2024  
**Classification**: Internal Use Only