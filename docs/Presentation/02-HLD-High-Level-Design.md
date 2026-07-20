# 🏗️ High Level Design (HLD)
## Azure to On-Premises Migration

---

## HLD Overview

```
┌───────────────────────────────────────────────────────────────────────────┐
│                    HIGH LEVEL DESIGN SUMMARY                              │
├──────────────────────┬────────────────────────────────────────────────────┤
│  Design Principle    │  Implementation                                    │
├──────────────────────┼────────────────────────────────────────────────────┤
│  High Availability   │  No single point of failure at any tier           │
│  Defense in Depth    │  6 security zones, NGFW + WAF + Vault + RBAC     │
│  GitOps              │  All deployments from Git via ArgoCD              │
│  Immutable Infra     │  Containers, Helm charts, Ansible — no manual     │
│  Observable          │  Prometheus, Grafana, ELK, Jaeger, Alertmanager   │
│  Scalable            │  Kubernetes HPA auto-scales 2→5 pods on demand    │
│  Recoverable         │  RTO < 5 min (DB), RPO < 1 min, daily backups    │
└──────────────────────┴────────────────────────────────────────────────────┘
```

---

## HLD Diagram 1: Current vs Target — Side by Side

```mermaid
graph TB
    subgraph CURRENT["☁️ CURRENT STATE — Azure"]
        direction TB
        C_EDGE["Azure Front Door + WAF\nGlobal CDN + DDoS"]
        C_LB["Application Gateway WAF_v2\nSSL + Path Routing"]
        C_APP["App Service 3× P1V2\n.NET | Windows | 2vCPU 3.5GB"]
        C_DB["PostgreSQL Managed PG11\n4vCore | 1TB | Zone HA"]
        C_CACHE["Redis Cache Premium\n6GB Cluster"]
        C_STORE["Azure Storage\n2.5TB RA-GRS"]
        C_MON["Azure Monitor\n+ Application Insights\n+ Log Analytics"]
        C_SEC["Key Vault + Security Center\n+ Azure Sentinel"]
        C_DR["Azure Backup\n+ Site Recovery"]

        C_EDGE --> C_LB --> C_APP
        C_APP --> C_DB & C_CACHE & C_STORE
        C_APP --> C_MON
        C_SEC -.->|secures| C_APP & C_DB
        C_DR -.->|protects| C_DB & C_STORE
    end

    subgraph TARGET["🏢 TARGET STATE — On-Premises"]
        direction TB
        T_FW["Palo Alto PA-5250\nNGFW HA | 6 Security Zones"]
        T_LB["F5 BIG-IP 5200\nActive/Passive | SSL Offload"]
        T_K8S["Kubernetes 9-node Cluster\n3 Masters + 6 Workers\nHPA | ArgoCD | MetalLB"]
        T_DB["PostgreSQL 15 HA\nPatroni 3-node | Streaming Replication\nHAProxy VIP + PgBouncer"]
        T_CACHE["Redis Cluster\n3+3 nodes | 6GB | TLS"]
        T_STORE["MinIO + NetApp NAS\n10TB NVMe | S3-compatible"]
        T_MON["Prometheus + Grafana\n+ ELK Stack + Jaeger\n30-day retention | 15+ alerts"]
        T_SEC["HashiCorp Vault HA\n+ Palo Alto IPS\n+ Wazuh SIEM"]
        T_DR["Bacula + Velero\nDaily + WAL Archive\nRTO < 5min | RPO < 1min"]

        T_FW --> T_LB --> T_K8S
        T_K8S --> T_DB & T_CACHE & T_STORE
        T_K8S --> T_MON
        T_SEC -.->|secures| T_K8S & T_DB
        T_DR -.->|protects| T_DB & T_STORE
    end

    CURRENT -->|"26-Week\nMigration"| TARGET

    style CURRENT fill:#fde8e8,stroke:#c62828
    style TARGET fill:#e8f5e9,stroke:#1b5e20
```

---

## HLD Diagram 2: Traffic Flow

```mermaid
sequenceDiagram
    actor User as 👤 End User
    participant DNS as 🌐 DNS
    participant F5 as ⚖️ F5 BIG-IP VIP
    participant PA as 🛡️ Palo Alto NGFW
    participant ING as 🚪 NGINX Ingress
    participant APP as 📦 App Pod (K8s)
    participant VAULT as 🔑 Vault
    participant DB as 🗄️ PostgreSQL
    participant REDIS as ⚡ Redis
    participant MINIO as 📁 MinIO

    User->>DNS: HTTPS GET app.company.com
    DNS-->>User: 10.0.2.10 (F5 VIP)
    User->>F5: TLS handshake + request
    Note over F5: SSL offload, health check
    F5->>PA: HTTP forwarded
    Note over PA: NGFW policy check\nZone: DMZ→K8s
    PA->>ING: Allowed: HTTP/8080
    ING->>APP: Route by host/path
    Note over APP: Pod receives request
    APP->>VAULT: Read DB credentials (cached 1h TTL)
    VAULT-->>APP: Dynamic credentials
    APP->>REDIS: Check session cache
    REDIS-->>APP: Cache hit (85% hit rate)
    APP->>DB: SQL query (via PgBouncer)
    DB-->>APP: Result set
    APP->>MINIO: Fetch file (if needed)
    MINIO-->>APP: Binary data
    APP-->>ING: HTTP 200 response
    ING-->>F5: Response
    F5-->>User: HTTPS response (< 150ms P95)
```

---

## HLD Diagram 3: Availability & HA Design

```mermaid
graph TB
    subgraph HA_DESIGN["🔄 High Availability Design — Every Tier"]
        subgraph TIER1["Tier 1: Network/Security — HA"]
            FW_A["Palo Alto FW-1\n🟢 Active"]
            FW_B["Palo Alto FW-2\n🔵 Passive"]
            FW_A <-->|"HA Sync\n< 1 sec failover"| FW_B

            LB_A["F5 BIG-IP LB-1\n🟢 Active"]
            LB_B["F5 BIG-IP LB-2\n🔵 Passive"]
            LB_A <-->|"VRRP\n< 3 sec failover"| LB_B

            SW_A["Cisco Core-SW-1\n🟢 VPC Primary"]
            SW_B["Cisco Core-SW-2\n🔵 VPC Secondary"]
            SW_A <-->|"vPC Peer Link\n< 1 sec failover"| SW_B
        end

        subgraph TIER2["Tier 2: Compute — K8s HA"]
            CP_A["K8s Master-1\n🟢 etcd Leader"]
            CP_B["K8s Master-2\n🔵 etcd Follower"]
            CP_C["K8s Master-3\n🔵 etcd Follower"]
            CP_A <-->|"Raft Consensus\nAuto-elect on failure"| CP_B & CP_C

            W_POOL["Worker Pool\n6 Nodes (W1–W6)\nPod anti-affinity\nspreads pods"]
        end

        subgraph TIER3["Tier 3: Database — Patroni HA"]
            DB_P["PostgreSQL Primary\n🟢 Leader"]
            DB_S1["PostgreSQL Standby-1\n🔵 Sync Replica"]
            DB_S2["PostgreSQL Standby-2\n🔵 Async Replica"]
            DB_P -->|"Streaming Replication\nLag < 100ms"| DB_S1 & DB_S2
            ETCD_C["etcd DCS\n3-node\nLeader election"]
            ETCD_C -.->|"Patroni failover\n< 30 seconds"| DB_P & DB_S1 & DB_S2
        end

        subgraph TIER4["Tier 4: Storage — HA"]
            NAS_A["NetApp NAS-1\n🟢 Active Controller"]
            NAS_B["NetApp NAS-2\n🔵 Passive Controller"]
            NAS_A <-->|"HA Pair Sync\nNDO (no disruption)"| NAS_B
        end
    end

    style HA_DESIGN fill:#f8f9fa
    style TIER1 fill:#fce4ec,stroke:#880e4f
    style TIER2 fill:#e3f2fd,stroke:#1565c0
    style TIER3 fill:#e8f5e9,stroke:#1b5e20
    style TIER4 fill:#fff3e0,stroke:#e65100
```

---

## HLD Diagram 4: CI/CD & GitOps Pipeline

```mermaid
flowchart LR
    DEV["👨‍💻 Developer\npushes code"] --> GL

    subgraph GITLAB_CI["🦊 GitLab CI Pipeline"]
        GL["GitLab\nRepository"] --> BUILD["Build Stage\ndotnet build\ndocker build"]
        BUILD --> TEST["Test Stage\nunit tests\nintegration tests"]
        TEST --> SCAN["Security Stage\nTrivy image scan\nSAST scan"]
        SCAN --> PUSH["Push Stage\ndocker push\nHarbor Registry"]
        PUSH --> UPDATE["Update Stage\ngit commit image tag\nto GitOps repo"]
    end

    subgraph GITOPS["🔄 ArgoCD GitOps"]
        UPDATE --> GITOPS_REPO["GitOps Repository\nHelm values\nK8s manifests"]
        GITOPS_REPO --> ARGO["ArgoCD\nDetects change\nAutomatically syncs"]
    end

    subgraph K8S_DEPLOY["☸️ Kubernetes Deployment"]
        ARGO --> STAGING["Deploy to\nStaging namespace"]
        STAGING --> SMOKE["Automated\nSmoke Tests"]
        SMOKE -->|"✅ Pass"| PROD["Deploy to\nProduction namespace\nRolling update"]
        SMOKE -->|"❌ Fail"| ROLLBACK["Auto Rollback\nto previous version"]
    end

    PROD --> MON["📊 Prometheus\nMonitor new version"]
    MON -->|"Alert on errors"| ROLLBACK

    style GITLAB_CI fill:#fc6d26,color:#fff
    style GITOPS fill:#e3f2fd,stroke:#1565c0
    style K8S_DEPLOY fill:#e8f5e9,stroke:#1b5e20
```

---

## HLD Diagram 5: Security Architecture

```mermaid
graph TB
    subgraph EXTERNAL["🌐 External (Untrusted)"]
        INT[Internet Traffic]
    end

    subgraph SEC_LAYERS["🛡️ Security Layers — Defense in Depth"]
        L1["Layer 1: DDoS\nISP-level filtering\n+ Palo Alto inline"]
        L2["Layer 2: NGFW\nPalo Alto PA-5250\nApp-ID | User-ID | IPS\nSSL Inspection | AV"]
        L3["Layer 3: WAF\nF5 ASM / NGINX ModSecurity\nOWASP Top 10 protection"]
        L4["Layer 4: Network Segmentation\n9 VLANs | Zero-trust between segments\nFirewall rules per flow"]
        L5["Layer 5: K8s Security\nNetwork Policies (Calico)\nPod Security Standards\nService Account + RBAC\nread-only root filesystem"]
        L6["Layer 6: App Security\nHashiCorp Vault (secrets)\nDynamic DB credentials\nTLS everywhere (cert-manager)\nmTLS between services"]
        L7["Layer 7: Audit & SIEM\nWazuh SIEM\nImmutable audit logs\nAnomalous behavior detection\nPagerDuty alerting"]
    end

    INT --> L1 --> L2 --> L3 --> L4 --> L5 --> L6
    L6 --> L7

    style EXTERNAL fill:#fde8e8,stroke:#c62828
    style SEC_LAYERS fill:#fff3e0,stroke:#e65100
    style L1 fill:#ef9a9a
    style L2 fill:#ef9a9a
    style L3 fill:#ffcc02,color:#000
    style L4 fill:#ffe082,color:#000
    style L5 fill:#a5d6a7
    style L6 fill:#81c784
    style L7 fill:#66bb6a
```

---

## HLD Design Decisions

| Decision | Options Considered | Choice | Rationale |
|----------|-------------------|--------|-----------|
| Container orchestration | Kubernetes, Docker Swarm, Nomad | **Kubernetes 1.28** | Industry standard, rich ecosystem, HPA, GitOps |
| DB HA solution | Patroni, Citus, Pgpool-II, Crunchy | **Patroni + etcd** | Battle-tested, automatic failover, K8s-native |
| Load balancer | F5, HAProxy, NGINX, Keepalived | **F5 BIG-IP** | Enterprise HA, SSL offload, iRules, support |
| Firewall | Palo Alto, Fortinet, Cisco ASA | **Palo Alto PA-5250** | NGFW + App-ID + SSL inspection, best threat intel |
| Secrets management | Vault, CyberArk, Sealed Secrets | **HashiCorp Vault** | K8s native inject, dynamic creds, PKI engine |
| GitOps engine | ArgoCD, Flux, Jenkins | **ArgoCD** | UI + drift detection + self-healing + rollback |
| Container registry | Harbor, JFrog, GitLab | **Harbor** | Free, Trivy scanning, LDAP, project isolation |
| Monitoring | Prometheus+Grafana, Datadog, Zabbix | **Prometheus + Grafana** | Open-source, K8s native, vast dashboard library |
| Log management | ELK, Loki+Grafana, Splunk | **ELK Stack** | Full-text search, Kibana SIEM, mature ecosystem |
| Object storage | MinIO, Ceph, GlusterFS | **MinIO** | S3-compatible API (drop-in Azure Blob replace) |

---

**Document Version**: 2.0 | **Date**: July 2026 | **Audience**: Architects, Tech Leads
