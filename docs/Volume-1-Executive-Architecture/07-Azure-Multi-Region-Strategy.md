# Volume 1: Azure Multi-Region Strategy & Global Architecture

> **Multi-Region Deployment Guide** — Complete strategy for deploying across Azure regions with high availability, disaster recovery, and cost optimization.

---

## Executive Summary

This document outlines the **multi-region Azure deployment architecture** for the migration project. It addresses:
- Global traffic distribution
- Cross-region data replication
- Automatic failover mechanisms
- Cost optimization across regions
- Compliance & regulatory requirements
- Disaster recovery procedures

---

## Table of Contents

1. [Region Selection Strategy](#region-selection-strategy)
2. [Multi-Region Topology](#multi-region-topology)
3. [Data Replication & Consistency](#data-replication--consistency)
4. [Traffic Management](#traffic-management)
5. [Failover Automation](#failover-automation)
6. [Cost Analysis](#cost-analysis)
7. [Operational Procedures](#operational-procedures)

---

## Region Selection Strategy

### Chosen Regions

Based on latency, compliance, and cost requirements:

```
Primary Region: East US 2
├─ Reason: Primary data center, lowest latency for US East Coast
├─ Latency: 0ms (baseline)
├─ Cost: $0.0968/hour for D4s_v3
└─ Services: Write-primary, read-hot

Secondary Region: West US 2
├─ Reason: Active-active for load balancing, geographic diversity
├─ Latency: 60–80ms from primary
├─ Cost: $0.1056/hour for D4s_v3 (9% premium)
└─ Services: Read-active, write-failover

Tertiary Region: North Europe (Optional)
├─ Reason: GDPR compliance, European user base
├─ Latency: 140–160ms from East US 2
├─ Cost: $0.1155/hour for D4s_v3 (20% premium)
└─ Services: Read-only, compliance, DR
```

### Latency Considerations

```
Acceptable Latencies:

Within-Region:
├─ AKS to Database: <5ms (same VNet)
├─ AKS to Redis: <2ms (in-memory)
└─ AKS to Storage: <10ms (managed service)

Cross-Region:
├─ Primary to Secondary: 60–80ms (acceptable)
├─ Primary to Tertiary: 140–160ms (read-only)
└─ Replication latency: <100ms (strong consistency)

User-Facing (Front Door):
├─ US East: 10–15ms
├─ US West: 20–30ms
├─ Europe: 40–60ms
└─ Global average: <50ms target
```

---

## Multi-Region Topology

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     GLOBAL ARCHITECTURE                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  Azure Front Door (Global Entry Point)                │    │
│  │  ├─ Geo-routing by latency                            │    │
│  │  ├─ WAF: OWASP Top 10                                 │    │
│  │  ├─ DDoS Protection: Standard                         │    │
│  │  └─ SSL/TLS termination                              │    │
│  └──────────┬─────────────────────┬──────────────────────┘    │
│             │                     │                           │
│      ┌──────▼──────┐      ┌──────▼──────┐     ┌────────────┐ │
│      │ Region 1    │      │ Region 2    │     │ Region 3   │ │
│      │ (Primary)   │      │ (Secondary) │     │(Tertiary)  │ │
│      │ East US 2   │      │ West US 2   │     │N. Europe   │ │
│      └──────┬──────┘      └──────┬──────┘     └────┬───────┘ │
│             │                    │                 │         │
│      ┌──────▼──────────────────────────────────────▼──┐       │
│      │  Azure Front Door Origin Group                 │       │
│      │  ├─ Health checks: 30s interval                │       │
│      │  ├─ Failover: Automatic                        │       │
│      │  └─ Routing: Latency-based                     │       │
│      └──────────────────────────────────────────────────┘       │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Azure Cosmos DB (Global Database)                     │   │
│  │  ├─ Write region: East US 2 (Region 1)               │   │
│  │  ├─ Read regions: All 3 regions                       │   │
│  │  ├─ Replication: <30ms latency                        │   │
│  │  └─ Consistency: Strong (single-write)               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Azure Recovery Services Vault (Backup)                │   │
│  │  ├─ GRS: Automatically replicated                      │   │
│  │  ├─ Retention: 7–365 days                              │   │
│  │  └─ Cross-region restore: Available                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Per-Region Architecture

```
┌──────────────────────────────────────────────────┐
│  Each Region (East US 2 / West US 2 / N. Europe)│
├──────────────────────────────────────────────────┤
│
│  ┌─ Azure VNet (10.x.0.0/16)
│  │  ├─ Subnet 1: AKS (10.x.1.0/24)
│  │  ├─ Subnet 2: Database (10.x.2.0/24)
│  │  ├─ Subnet 3: App Gateway (10.x.3.0/24)
│  │  └─ Subnet 4: Management (10.x.4.0/24)
│  │
│  ├─ Azure Kubernetes Service (AKS)
│  │  ├─ System Node Pool: 3 nodes (D4s_v3)
│  │  ├─ App Node Pool: 6–12 nodes (auto-scale)
│  │  ├─ Data Node Pool: 4 nodes (memory-optimized)
│  │  └─ Pods: 2K–5K capacity
│  │
│  ├─ Azure Container Registry (ACR)
│  │  ├─ Image storage: All application images
│  │  ├─ Geo-replication: All regions
│  │  └─ Webhook: Push notifications
│  │
│  ├─ Azure Database for PostgreSQL
│  │  ├─ Region 1: Primary (write)
│  │  ├─ Region 2, 3: Read replicas (async)
│  │  ├─ Failover: Manual promotion (60s switch)
│  │  └─ Backup: Geo-redundant storage
│  │
│  ├─ Azure Cache for Redis
│  │  ├─ Region 1: Primary master
│  │  ├─ Region 2: Geo-replica
│  │  ├─ Region 3: Geo-replica
│  │  └─ Failover: Automatic (2 minutes)
│  │
│  ├─ Azure Storage Account
│  │  ├─ Replication: GRS (geo-redundant)
│  │  ├─ Access tier: Hot (frequent access)
│  │  ├─ Containers: Logs, backups, configs
│  │  └─ Lifecycle: Cool/Archive after 30 days
│  │
│  ├─ Application Gateway (Layer 7)
│  │  ├─ Backend pool: AKS service IPs
│  │  ├─ Rules: Path-based routing
│  │  ├─ SSL/TLS: End-to-end encryption
│  │  └─ WAF: Managed rules + custom
│  │
│  └─ Application Insights (APM)
│     ├─ Instrumentation: Auto-enabled in AKS
│     ├─ Sampling: 100% ingestion
│     ├─ Retention: 90 days
│     └─ Workbooks: Custom dashboards
│
└──────────────────────────────────────────────────┘
```

---

## Data Replication & Consistency

### PostgreSQL Replication Strategy

```
Region 1 (Primary - East US 2):
└─ PostgreSQL Primary Instance (write)
   ├─ WAL Archiving: Continuous
   ├─ Streaming Replication: To Standby (sync)
   └─ Read Replicas: To Region 2, 3 (async)

Region 1 (Standby - Same VNet):
└─ PostgreSQL Standby (async from primary)
   ├─ Synchronous replication
   ├─ Automatic failover: Enabled
   ├─ RPO: <100 bytes (near-zero)
   └─ RTO: <60 seconds

Region 2 (Read Replica - West US 2):
└─ PostgreSQL Read Replica
   ├─ Async replication: 15-30 minute lag
   ├─ Failover: Manual promotion (60s switch)
   ├─ RPO: Up to 30 minutes
   └─ Use case: Analytics, read-heavy workloads

Region 3 (Read Replica - North Europe):
└─ PostgreSQL Read Replica
   ├─ Async replication: 30-60 minute lag
   ├─ Use case: GDPR compliance, backup
   ├─ RPO: Up to 60 minutes
   └─ Failover: Manual (requires DNS update)

Replication Diagram:
┌─────────────────┐
│ Region 1        │
│ Primary (write) │
└────────┬────────┘
         │ WAL Stream (sync)
         ▼
┌─────────────────────┐
│ Region 1            │
│ Standby (read)      │
└─────────────────────┘
         │ Replication stream (async)
         │
    ┌────┴─────┐
    │           │
    ▼           ▼
┌────────┐  ┌──────────┐
│Region2 │  │ Region 3 │
│Replica │  │ Replica  │
└────────┘  └──────────┘
```

### Cosmos DB Global Replication

```
Write Configuration:
├─ Write region: East US 2 (primary only)
├─ Read regions: East US 2, West US 2, North Europe
├─ Conflict resolution: Last-write-wins (LWW)
└─ Replication: 4-region synchronous

Consistency Levels (per operation):
├─ Strong: All reads after write (same region)
├─ Bounded staleness: <5 seconds
├─ Session: Per-session consistency (default)
├─ Consistent prefix: Causal ordering
└─ Eventual: Eventually consistent

Latencies:
├─ Intra-region write: <10ms
├─ Cross-region read: <50ms
├─ Replication lag: <30ms (global)
└─ P99 latency: <100ms
```

### Redis Cache Replication

```
Region 1 (Primary - Master):
├─ In-memory store: 6–12 GB
├─ Persistence: RDB (daily snapshot)
├─ Replication: Zone-redundant (2-node)
└─ Geo-replication: To Region 2, 3 (async)

Region 2 & 3 (Geo-replicas):
├─ Replicas: Read-only
├─ Replication lag: <1 second
├─ Failover: Automatic promotion (2 minutes)
└─ Use case: Read caching, DR

Failover Trigger:
├─ Master unavailable: 30s detection
├─ Promotion: Automatic to Region 2 replica
├─ DNS update: 60s propagation
└─ Application reconnect: <5 seconds
```

---

## Traffic Management

### Azure Front Door Routing

```
Client Requests:
└─ DNS query: contoso.azurefd.net
   └─ Front Door (global)
      └─ Geo-routing rules:
         ├─ US clients → East US 2 (lowest latency)
         ├─ US West → West US 2 (or East if unavailable)
         ├─ Europe → North Europe (GDPR)
         └─ Default → East US 2

Load Balancing Algorithm:
├─ Primary: Latency-based (lowest RTT wins)
├─ Secondary: Priority-based (failover order)
├─ Health check: Every 30 seconds
├─ Failover time: 60 seconds (DNS + client reconnect)
└─ Session affinity: Sticky session (cookie-based)

Cache Behavior:
├─ Static assets: 1-day TTL
├─ Dynamic content: No cache
├─ Query string: Include in cache key
└─ Request header: X-Azure-Ref (tracing)
```

### Application Gateway per Region

```
Listeners:
├─ HTTPS (443): Primary
├─ HTTP (80): Redirect to HTTPS
└─ Multi-site hosting: Multiple backend pools

Backend Pools:
├─ AKS service IPs (internal)
├─ Health probe: /health (HTTP 200)
├─ Healthy threshold: 2 checks
└─ Unhealthy threshold: 3 checks

Rules (Path-based routing):
├─ /api/v1/* → API backend pool
├─ /static/* → Static content (CDN-backed)
├─ /* → Web frontend pool
└─ /health → Health check endpoint

SSL/TLS:
├─ Protocols: TLS 1.2, 1.3
├─ Cipher suites: Modern (AES-GCM)
├─ Certificate: Azure-managed (auto-renewal)
└─ End-to-end encryption: AKS to App GW (TLS)
```

---

## Failover Automation

### Health Check Mechanisms

```
Azure Front Door Health Checks:
├─ Endpoint: /health (per backend)
├─ Protocol: HTTPS
├─ Interval: 30 seconds
├─ Timeout: 5 seconds
├─ Success threshold: 1 of 1
└─ Failure threshold: 3 consecutive failures
   (= 90 seconds to detect + 60s DNS = 150s RTO)

Application Insights Availability Tests:
├─ Synthetic transactions: Every 5 minutes
├─ Locations: 3+ regions
├─ Test: Multi-step web test (sign-in + transaction)
├─ Threshold: 80% pass rate
├─ Alert: <70% success → PagerDuty

Manual Failover Triggers (if auto unavailable):
├─ Operations team: Monitors dashboards
├─ On-call runbook: Initiate failover
├─ DNS propagation: 5–30 minutes
└─ Expected downtime: 30–60 minutes
```

### Failover Execution Plan

```
Step 1: Detection (0–150 seconds)
├─ Front Door detects unhealthy backend
├─ Marks Region 1 as DOWN
└─ Routes new traffic to Region 2

Step 2: Immediate Actions (150–300 seconds)
├─ Alert sent to on-call team
├─ Incident declared in PagerDuty
├─ Status page updated: Incident ongoing
└─ Communication: Teams notification

Step 3: Database Failover (if Region 1 completely down)
├─ PostgreSQL: Promote Region 2 read replica
│  ├─ Command: `pg_ctl promote`
│  ├─ Time: 60 seconds
│  └─ Verify: Test write operations
│
├─ Redis: Automatic promotion (2 minutes)
└─ Cosmos DB: Automatic (1-minute switch)

Step 4: Application Recovery (if restarting pods needed)
├─ Re-deploy from Helm charts
├─ Apply secrets from Azure Key Vault
├─ Initialize cache (warmup required)
└─ Run smoke tests

Step 5: Monitoring & Stabilization
├─ Monitor error rates (target: <0.1%)
├─ Check database replication lag
├─ Verify all pods healthy
└─ Hold for 30 minutes before declaring success

Step 6: Recovery & Rollback
├─ Investigate root cause
├─ Fix Region 1 (hardware/software/config)
├─ Re-enable replication (Region 1 → Region 2)
├─ Promote Region 1 back to primary (if desired)
└─ Post-incident review: Lessons learned
```

---

## Cost Analysis

### Monthly Cost Breakdown (All 3 Regions)

```
Compute:
├─ AKS per region (3 system + 6-12 app nodes):
│  ├─ East US 2 (D4s_v3): $3,500/month
│  ├─ West US 2 (D4s_v3): $3,815/month (+9%)
│  ├─ North Europe (D4s_v3): $4,200/month (+20%)
│  └─ Subtotal: $11,515/month (3 regions)
│
├─ Reserved Instances (3-year):
│  ├─ Discount: 35% savings plan
│  └─ New compute cost: $7,485/month
│
└─ Spot instances (for non-critical workloads):
   ├─ Discount: 70% (interruptible)
   └─ Estimated savings: $2,000/month

Storage:
├─ PostgreSQL (per region):
│  ├─ Flexible Server: $500/month (HA enabled)
│  ├─ 3 regions: $1,500/month
│  └─ Read replicas: Included in primary
│
├─ Cosmos DB (global):
│  ├─ Provisioned: 4K–100K RU/s
│  ├─ Average: 20K RU/s × $0.00013/RU = $2,600/month
│  └─ Multi-region write (optional): +$1,300/month
│
├─ Redis (per region):
│  ├─ Premium tier: $300/month (6GB)
│  ├─ 3 regions: $900/month
│  └─ Geo-replication: Included
│
└─ Blob Storage:
   ├─ GRS: $0.018/GB/month
   ├─ Estimated: 500 GB = $9/month
   └─ Lifecycle to Cool/Archive: Save 50%

Networking:
├─ Front Door:
│  ├─ Base: $32/month (all regions)
│  ├─ Rules: $0.50 each (10 rules = $5)
│  └─ Requests: $0.60 per million (varies by volume)
│
├─ Application Gateway (per region):
│  ├─ Small: $150/month
│  ├─ 3 regions: $450/month
│  └─ Data transfer: ~$200/month
│
├─ Data Transfer (inter-region):
│  ├─ Egress: $0.05/GB
│  ├─ Estimated: 10 TB/month = $500/month
│  └─ Internal (VNet peering): Free
│
└─ VNet & Private Endpoints:
   ├─ VNet: Free
   ├─ Private endpoints: $0.01/hour each (20 total)
   └─ Cost: $144/month

Monitoring & Logging:
├─ Application Insights:
│  ├─ Ingestion: $0.50/GB
│  ├─ Estimated: 100 GB/month = $50/month
│  └─ Retention: 90 days (included)
│
├─ Log Analytics:
│  ├─ Ingestion: $2.99/GB
│  ├─ Estimated: 50 GB/month = $150/month
│  └─ Retention: 30 days (configurable)
│
└─ Azure Monitor:
   ├─ Metrics queries: Free tier
   └─ Alerts: $0.10 per alert/month (50 alerts = $5)

Backup & Disaster Recovery:
├─ Recovery Services Vault:
│  ├─ Protected instances: $17/month per item
│  ├─ Estimated: 5 items = $85/month
│  └─ Backup storage: $0.05/GB (50 GB = $2.50)
│
└─ Site Recovery (if enabled):
   └─ ~$150/month (replicated VMs)

TOTAL MONTHLY COST:
├─ Compute: $7,485 (with savings plan)
├─ Storage: $4,500
├─ Networking: $1,100
├─ Monitoring: $205
├─ Backup: $240
└─ TOTAL: ~$13,530/month (~$162,360/year)

Cost Optimization Strategies:
├─ Use spot instances: Save $2,000/month
├─ Commit to 3-year RI: Save 35%
├─ Auto-scale during off-hours: Save 20%
├─ Lifecycle policies for storage: Save 50%
├─ Reserved capacity for databases: Save 30%
└─ TARGET: $8,500–10,000/month
```

---

## Operational Procedures

### Scaling Operations

```
Horizontal Pod Autoscaling (HPA):
├─ Metric: CPU utilization (70% target)
├─ Min replicas: 2 (always-on)
├─ Max replicas: 50 (per node pool)
├─ Scale-up: 30-second evaluation interval
├─ Scale-down: 300-second evaluation interval
└─ Cooldown: 5 minutes between scaling events

Node Pool Autoscaling:
├─ Min nodes: 3 (system pool), 2 (app pool)
├─ Max nodes: 12–20 (depends on node type)
├─ Trigger: Pod pending (no node capacity)
├─ Scale-up time: 2–5 minutes (VM provisioning)
└─ Scale-down time: 10 minutes (graceful drain)
```

### Upgrade & Patching

```
Kubernetes Version Upgrade (Quarterly):
├─ Window: Tuesday 2 AM UTC (off-peak)
├─ Control plane: First (1 hour downtime)
├─ Node pools: One pool at a time (rolling)
├─ Validation: Smoke tests after each pool
└─ Rollback: Available if issues detected

Security Patching (Monthly):
├─ OS patches: Automatic (unattended-upgrades)
├─ Container runtime: Patched weekly
├─ Dependencies: Updated via Dependabot
└─ Testing: Staging environment first
```

---

## Compliance & Regulatory

### Data Residency Requirements

```
GDPR (EU Data):
├─ Residence: North Europe (Amsterdam)
├─ Processing: Only EU region
├─ Transfers: Cross-border DPA required
└─ Tool: Azure Compliance Manager

Data Classification:
├─ Public: All regions (no restriction)
├─ Internal: All Azure regions
├─ Confidential: Encrypted at rest + in transit
├─ Restricted: Specific region (North Europe)
└─ PII: GDPR zone only (no replica to US)
```

---

## Monitoring Dashboard Template

Create custom dashboards in Azure Monitor:

```
1. Regional Health Dashboard:
   ├─ AKS cluster status (all regions)
   ├─ Database replication lag
   ├─ Cache hit/miss ratio
   └─ Network latency (inter-region)

2. Application Performance:
   ├─ Request rate (req/sec per region)
   ├─ Error rate (< 0.1% target)
   ├─ Latency P50/P95/P99
   └─ Dependency performance

3. Infrastructure Utilization:
   ├─ CPU/Memory (nodes & pods)
   ├─ Storage consumption
   ├─ Network throughput
   └─ Cost burn-down

4. Failover Status:
   ├─ Health check results
   ├─ Replica lag (PostgreSQL/Redis)
   ├─ Cosmos DB replication status
   └─ Front Door origin status
```

---

## Deployment Checklist

- [ ] All 3 regions provisioned
- [ ] Front Door configured (geo-routing enabled)
- [ ] AKS clusters deployed and linked
- [ ] PostgreSQL primary + standbys + read replicas
- [ ] Cosmos DB with multi-region writes (if needed)
- [ ] Redis caches with geo-replication
- [ ] Application Gateways per region
- [ ] Storage accounts with GRS
- [ ] Application Insights & Log Analytics
- [ ] Backup vault with cross-region restore
- [ ] Private endpoints configured
- [ ] Failover tests completed
- [ ] RTO/RPO documented & verified
- [ ] Cost analysis approved
- [ ] Runbook tested (manual failover)
- [ ] Team trained on procedures

---

**Classification**: Internal Use Only  
**Version**: 1.0  
**Created**: July 2026  
**Status**: Published
