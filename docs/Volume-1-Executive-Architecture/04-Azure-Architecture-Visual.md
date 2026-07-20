# Volume 1: Executive & Solution Architecture
## Chapter 4: Current Azure Architecture — Visual Reference

> **Purpose**: Exact visual representation of the existing Azure deployment before migration.

---

## Azure Architecture — Full Stack Diagram

```mermaid
graph TB
    subgraph USERS["👥 End Users / Internet"]
        U1[🌍 Global Users]
        U2[🏢 Corporate Users\nVPN]
    end

    subgraph AZURE_EDGE["☁️ Azure Edge — Global Layer"]
        AFD["🌐 Azure Front Door\n• Global CDN\n• WAF OWASP 3.0\n• DDoS Protection Standard\n• SSL Termination TLS 1.2+\n• Geo-routing & Caching"]
    end

    subgraph AZURE_NETWORK["🔒 Azure Virtual Network (prod-vnet 10.0.0.0/16)"]
        subgraph SUBNET_FRONT["Subnet: Front-end 10.0.1.0/24"]
            APPGW["⚖️ Azure Application Gateway WAF_v2\n• SKU: WAF_v2 | Instances: 2–10 (autoscale)\n• SSL offloading | Path-based routing\n• Host-based routing | Cookie affinity\n• Backend: 3 × App Service"]
        end

        subgraph SUBNET_APP["Subnet: App 10.0.2.0/24"]
            AS1["📦 App Service Instance 1\nP1V2 | 2 vCPU | 3.5GB RAM\nWindows Server 2019 | .NET 4.8"]
            AS2["📦 App Service Instance 2\nP1V2 | 2 vCPU | 3.5GB RAM\nWindows Server 2019 | .NET 4.8"]
            AS3["📦 App Service Instance 3\nP1V2 | 2 vCPU | 3.5GB RAM\nWindows Server 2019 | .NET 4.8"]
            ACI["📋 Azure Container Instances\n• Batch jobs (daily)\n• ETL processes (nightly)\n• Report generation\n• Data exports (hourly)"]
            AUTOSCALE["⚡ Autoscale Rules\nMin: 2 | Max: 5\nScale-out: CPU > 70%\nScale-in: CPU < 30%\nCooldown: 5 min"]
        end

        subgraph SUBNET_DATA["Subnet: Data 10.0.3.0/24"]
            PG["🗄️ Azure Database for PostgreSQL\n• Version: PostgreSQL 11\n• 4 vCore Memory-Optimized\n• Storage: 1 TB | DB size: 500 GB\n• 400 max connections\n• 2 Read Replicas\n• Zone Redundant HA\n• Geo-redundant backup (7 days)\n• SSL required | AES-256 at rest"]
            REDIS["⚡ Azure Cache for Redis\n• SKU: Premium | 6 GB\n• Cluster mode enabled\n• AOF persistence\n• TLS enabled\n• VNet integrated\n• Hit rate: 85–90%"]
            ST1["📁 Storage Account 1\n• App Data (Hot, RA-GRS)\n• 1 TB | 5,000+ blobs\n• AES-256 encrypted"]
            ST2["📁 Storage Account 2\n• Backup Storage (Cool, RA-GRS)\n• 2 TB | 100+ archives"]
            ST3["📁 Storage Account 3\n• Logs (Hot, GRS)\n• 500 GB diagnostics"]
        end

        subgraph SUBNET_MGMT["Subnet: Management 10.0.4.0/24"]
            VPN["🔗 VPN Gateway\n• SKU: VpnGw1Az\n• Route-based | 650 Mbps\n• 2 connections (redundant)\n• IKEv2 enabled"]
        end
    end

    subgraph AZURE_MONITOR["📊 Monitoring & Observability"]
        AM["📈 Azure Monitor\n• Metrics: every 1 min\n• Logs: 30-day retention\n• 15+ alert rules\n• 3 action groups"]
        AI["🔍 Application Insights\n• SDK instrumented\n• 100% sampling rate\n• 90-day retention\n• 50+ custom events\n• 100+ custom metrics"]
        LA["📋 Log Analytics\n• 50 GB/day ingestion\n• 20+ saved queries\n• 5+ custom workbooks"]
    end

    subgraph AZURE_SECURITY["🔐 Security & Compliance"]
        KV["🔑 Azure Key Vault\n• SKU: Premium\n• 5 SSL certificates\n• DB credentials, API keys\n• RBAC-based access\n• Soft-delete: 90 days"]
        ASC["🛡️ Azure Security Center\n• Tier: Standard\n• Score: 78/100\n• 5 compliance frameworks\n• PCI DSS, ISO 27001\n• HIPAA, SOC 2, GDPR"]
        SENT["🚨 Azure Sentinel\n• 10+ data connectors\n• 20+ analytics rules\n• 5 automated playbooks\n• SOAR automation"]
    end

    subgraph AZURE_DR["💾 Backup & Disaster Recovery"]
        BKP["🔄 Azure Backup\n• Geo-redundant vault\n• Daily at 2 AM UTC\n• 30-day retention\n• 1.5 TB backup size\n• Customer-managed keys"]
        ASR["♻️ Azure Site Recovery\n• Primary: US East\n• Secondary: US West 2\n• RTO: < 1 hour\n• RPO: 15 minutes\n• Failover test: Monthly"]
    end

    U1 & U2 --> AFD
    AFD --> APPGW
    APPGW --> AS1 & AS2 & AS3
    AUTOSCALE -.->|controls| AS1 & AS2 & AS3
    AS1 & AS2 & AS3 --> PG & REDIS & ST1
    AS1 & AS2 & AS3 -->|read from| ST2 & ST3
    ACI --> PG & ST1
    AS1 & AS2 & AS3 -->|telemetry| AI --> AM & LA
    KV -->|secrets| AS1 & AS2 & AS3
    SENT --> AM
    BKP -->|backs up| PG & ST1 & ST2
    ASR -->|replicates| PG

    style USERS fill:#e3f2fd,stroke:#1565c0
    style AZURE_EDGE fill:#e8eaf6,stroke:#3949ab
    style AZURE_NETWORK fill:#e0f2f1,stroke:#00695c
    style AZURE_MONITOR fill:#f3e5f5,stroke:#6a1b9a
    style AZURE_SECURITY fill:#fce4ec,stroke:#880e4f
    style AZURE_DR fill:#fff3e0,stroke:#e65100
```

---

## Azure Cost Breakdown (Current Monthly: ~$46,000)

```mermaid
graph LR
    subgraph COSTS["💰 Monthly Cost Distribution ($46,000)"]
        C1["🖥️ Compute\n$17,000/mo (37%)\n• App Service 3×P1V2: $15k\n• Container Instances: $2k"]
        C2["💾 Data\n$16,000/mo (35%)\n• PostgreSQL: $8k\n• Storage Accts: $5k\n• Redis Cache: $3k"]
        C3["🌐 Networking\n$3,000/mo (7%)\n• VPN Gateway: $2k\n• Load Balancer: $1k"]
        C4["📊 Monitoring\n$4,500/mo (10%)\n• Azure Monitor: $2k\n• Log Analytics: $1.5k\n• App Insights: $1k"]
        C5["🔐 Security\n$1,500/mo (3%)\n• Security Center: $1k\n• Key Vault: $0.5k"]
        C6["💿 Backup & DR\n$4,000/mo (9%)\n• Backup Vault: $1.5k\n• Site Recovery: $2.5k"]
    end

    style COSTS fill:#fff8e1,stroke:#f9a825
    style C1 fill:#e3f2fd,stroke:#1565c0
    style C2 fill:#e8f5e9,stroke:#2e7d32
    style C3 fill:#f3e5f5,stroke:#6a1b9a
    style C4 fill:#e0f2f1,stroke:#00695c
    style C5 fill:#fce4ec,stroke:#880e4f
    style C6 fill:#fff3e0,stroke:#e65100
```

---

## Azure Network Topology

```mermaid
graph TB
    subgraph INTERNET["🌐 Internet"]
        USR[👥 Global Users]
    end

    subgraph AZURE["☁️ Azure Cloud — US East Region"]
        AFD[Azure Front Door\nGlobal Anycast IP]

        subgraph VNET["Virtual Network 10.0.0.0/16"]
            subgraph NSG1["NSG: allow-inbound-https"]
                APPGW[Application Gateway\nWAF_v2\n10.0.1.0/24]
            end
            subgraph NSG2["NSG: allow-app-tier"]
                APP[App Service Plan\n3× P1V2\n10.0.2.0/24]
            end
            subgraph NSG3["NSG: allow-data-tier"]
                DB[(PostgreSQL\n10.0.3.10)]
                RD[Redis\n10.0.3.20]
            end
            subgraph NSG4["NSG: allow-mgmt"]
                MGMT[Management\n10.0.4.0/24]
                VPN_GW[VPN Gateway\n10.0.4.5]
            end
        end

        subgraph SERVICES["Azure Platform Services"]
            KV2[Key Vault]
            MON[Monitor]
            BK[Backup]
        end
    end

    subgraph ONSITE["🏢 Corporate On-Site"]
        CORP[Corporate Users\nSite-to-Site VPN]
    end

    USR --> AFD --> APPGW --> APP
    APP --> DB & RD
    APP --> KV2 & MON
    DB --> BK
    CORP -->|IPSec IKEv2| VPN_GW --> MGMT

    style AZURE fill:#e8f4fd,stroke:#0078D4
    style VNET fill:#d0ebff,stroke:#0078D4
    style SERVICES fill:#cce5ff,stroke:#0078D4
```

---

## Azure Performance Baseline

| Metric | Current Value | SLA Target |
|--------|--------------|------------|
| Response Time P50 | 120 ms | < 100 ms |
| Response Time P95 | 180 ms | < 200 ms |
| Response Time P99 | 500 ms | < 1000 ms |
| Error Rate | 0.1% | < 0.5% |
| Availability | 99.95% | 99.9%+ |
| Throughput | 5,000 req/s | 5,000 req/s |
| Concurrent Users | 3,000 avg | 10,000 peak |
| Page Load Time | 2.5 sec | < 3 sec |
| DB Connections (avg) | 200 | < 400 |
| Redis Hit Rate | 87% | > 85% |
| Storage Used | 2.5 TB | — |
| Database Size | 500 GB | — |
| Monthly Cost | $46,000 | — |

---

## Azure Services Limitations (Why We Migrate)

```mermaid
graph TD
    PROB["❌ Azure Limitations Driving Migration"]

    PROB --> L1["💸 Cost\n$552,000/year cloud spend\nGrowing 15% annually\nUnpredictable scaling costs"]
    PROB --> L2["🔒 Vendor Lock-in\nAzure-proprietary APIs\nLimited portability\nMigration complexity"]
    PROB --> L3["📜 Compliance\nData in Microsoft datacenters\nLimited audit capability\nShared security model\nData residency issues"]
    PROB --> L4["⚙️ Customization\nLimited kernel/OS tuning\nService throttling\nNo direct hardware access\nVersion lag (PG 11 only)"]
    PROB --> L5["📶 Performance\nNoisy neighbor effect\nLatency variability\nNo QoS guarantees\nCDN cache miss latency"]

    style PROB fill:#c62828,color:#fff
    style L1 fill:#fde8e8
    style L2 fill:#fde8e8
    style L3 fill:#fde8e8
    style L4 fill:#fde8e8
    style L5 fill:#fde8e8
```

---

**Document Version**: 2.0 | **Date**: July 2026 | **Classification**: Internal Use Only
