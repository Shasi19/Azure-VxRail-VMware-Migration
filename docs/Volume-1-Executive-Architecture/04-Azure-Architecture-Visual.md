# Volume 1: Executive & Solution Architecture
## Chapter 4: Current Azure Architecture — Visual Reference

> **Purpose**: Exact visual representation of the existing Azure deployment before migration.

---

## Azure Architecture — Full Stack Diagram

```mermaid
graph TB
    U1[Global Users] --> AFD
    U2[Corporate Users / VPN] --> VPN_GW

    subgraph EDGE["Azure Edge Layer"]
        AFD[Azure Front Door\nGlobal CDN / WAF / DDoS\nSSL TLS 1.2+]
    end

    subgraph NETWORK["Azure Virtual Network  10.0.0.0/16"]
        APPGW[Application Gateway WAF_v2\nSSL Offload / Path Routing\nSubnet: 10.0.1.0/24]
        subgraph APP_TIER["App Tier  10.0.2.0/24"]
            AS1[App Service 1\nP1V2 / 2vCPU / 3.5GB]
            AS2[App Service 2\nP1V2 / 2vCPU / 3.5GB]
            AS3[App Service 3\nP1V2 / 2vCPU / 3.5GB]
            ACI[Container Instances\nBatch / ETL jobs]
        end
        subgraph DATA_TIER["Data Tier  10.0.3.0/24"]
            PG[(PostgreSQL Managed\nPG 11 / 4vCore / 1TB\n2 Read Replicas)]
            REDIS[Redis Cache Premium\n6 GB / Cluster / AOF]
            BLOB[Storage Accounts\n3.5 TB total / RA-GRS]
        end
        VPN_GW[VPN Gateway\nVpnGw1Az / 650 Mbps]
    end

    subgraph PLATFORM["Azure Platform Services"]
        MON[Azure Monitor\n+ App Insights\n+ Log Analytics]
        SEC[Key Vault / Security Center\n+ Azure Sentinel]
        DR[Azure Backup\n+ Site Recovery]
    end

    AFD --> APPGW
    APPGW --> AS1 & AS2 & AS3
    AS1 & AS2 & AS3 --> PG & REDIS & BLOB
    ACI --> PG
    AS1 & AS2 & AS3 --> MON
    SEC -.->|secures| AS1 & APPGW & PG
    DR -.->|backs up| PG & BLOB

    style EDGE fill:#e8eaf6,stroke:#3949ab
    style NETWORK fill:#e0f7fa,stroke:#00695c
    style APP_TIER fill:#e8f5e9,stroke:#2e7d32
    style DATA_TIER fill:#fff3e0,stroke:#e65100
    style PLATFORM fill:#fce4ec,stroke:#880e4f
```

---

## Azure Cost Breakdown (Current Monthly: ~$46,000)

| Category | Services | Monthly Cost | Share |
|----------|---------|-------------|-------|
| Compute | App Service 3x P1V2 + Container Instances | $17,000 | 37% |
| Data | PostgreSQL + Storage Accounts + Redis | $16,000 | 35% |
| Networking | VPN Gateway + Load Balancer | $3,000 | 7% |
| Monitoring | Azure Monitor + Log Analytics + App Insights | $4,500 | 10% |
| Security | Security Center + Key Vault | $1,500 | 3% |
| Backup and DR | Backup Vault + Site Recovery | $4,000 | 9% |
| **Total** | | **$46,000/mo** | **100%** |

```mermaid
pie title Azure Monthly Cost $46,000
    "Compute $17k" : 37
    "Data $16k" : 35
    "Monitoring $4.5k" : 10
    "Backup/DR $4k" : 9
    "Networking $3k" : 7
    "Security $1.5k" : 3
```

---

## Azure Network Topology

```mermaid
graph TB
    USERS[Global Users] --> AFD
    CORP[Corporate Users] -->|IPSec IKEv2| VPN_GW

    AFD[Azure Front Door\nGlobal Anycast IP] --> APPGW

    subgraph VNET["Virtual Network  10.0.0.0/16"]
        APPGW[Application Gateway\nWAF_v2 / 10.0.1.0/24]
        APP[App Service Plan\n3x P1V2 / 10.0.2.0/24]
        DB[(PostgreSQL\n10.0.3.10)]
        RD[Redis\n10.0.3.20]
        VPN_GW[VPN Gateway\n10.0.4.5]
    end

    subgraph SERVICES["Azure Platform Services"]
        KV[Key Vault]
        MON[Azure Monitor]
        BK[Azure Backup]
    end

    APPGW --> APP
    APP --> DB & RD
    APP --> MON & KV
    DB --> BK

    style VNET fill:#e8f4fd,stroke:#0078D4
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
graph LR
    PROB[Azure Limitations\nDriving Migration]

    PROB --> L1[Cost\n$552k/year\nGrowing 15% annually]
    PROB --> L2[Vendor Lock-in\nAzure-proprietary APIs\nLimited portability]
    PROB --> L3[Compliance\nData in Microsoft DCs\nShared security model]
    PROB --> L4[Customization\nNo kernel/OS tuning\nVersion lag - PG11 only]
    PROB --> L5[Performance\nNoisy neighbor effect\nLatency variability]

    style PROB fill:#c62828,color:#fff
    style L1 fill:#fde8e8
    style L2 fill:#fde8e8
    style L3 fill:#fde8e8
    style L4 fill:#fde8e8
    style L5 fill:#fde8e8
```

```

---

**Document Version**: 2.0 | **Date**: July 2026 | **Classification**: Internal Use Only
