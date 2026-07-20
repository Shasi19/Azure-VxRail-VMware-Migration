# Volume 1: Executive & Solution Architecture
## Chapter 5: Target On-Premises Architecture — Visual Reference

> **Purpose**: Exact visual representation of the target on-premises deployment after migration.

---

## On-Premises Architecture — Full Stack Diagram

```mermaid
graph TB
    subgraph USERS["👥 End Users"]
        U1[🌍 Internet Users]
        U2[🏢 Corporate Users\nDirect LAN]
    end

    subgraph ISP_LAYER["🌐 Internet Connectivity"]
        ISP1[ISP Link 1\n1 Gbps Primary]
        ISP2[ISP Link 2\n1 Gbps Failover]
    end

    subgraph DMZ["🔒 Security Layer — DMZ (VLAN 20: 10.0.2.0/24)"]
        FW["🛡️ Palo Alto PA-5250 NGFW\n• Active/Passive HA Pair\n• 100 Gbps throughput\n• NGFW + IPS + AV + SSL Inspection\n• DPI | Web Filtering | App Control\n• Zone-based security policy\n• 6 security zones defined"]
        F5["⚖️ F5 BIG-IP 5200\n• Active/Passive HA (VRRP)\n• VIP: 10.0.2.10:443\n• SSL/TLS offloading\n• Least-connections LB\n• Health check: /health\n• Failover < 3 seconds"]
    end

    subgraph NETWORK["🔀 Network Core"]
        CS["🔀 Cisco Nexus 9372PX\n• VPC Pair (2 switches)\n• 14.4 Tbps throughput\n• L3 routing + OSPF\n• VLANs 10–90\n• < 1µs latency"]
        AS["📡 Cisco Nexus 9348\n• 4× Access Switches\n• 25.6 Tbps each\n• Trunk to core"]
    end

    subgraph K8S_CONTROL["☸️ Kubernetes Control Plane (VLAN 30: 10.0.3.0/24)"]
        CP1["🎛️ k8s-master-1\n10.0.3.11"]
        CP2["🎛️ k8s-master-2\n10.0.3.12"]
        CP3["🎛️ k8s-master-3\n10.0.3.13"]
        ETCD["📦 etcd Cluster\n3-node HA"]
        INGRESS["🚪 NGINX Ingress\n+ MetalLB\nVIP: 10.0.4.200"]
    end

    subgraph K8S_WORKERS["☸️ Kubernetes Workers (VLAN 40: 10.0.4.0/24)"]
        W1["💻 worker-1\n10.0.4.21\n56-core | 512GB"]
        W2["💻 worker-2\n10.0.4.22\n56-core | 512GB"]
        W3["💻 worker-3\n10.0.4.23\n56-core | 512GB"]
        W4["💻 worker-4\n10.0.4.24\n56-core | 512GB"]
        W5["💻 worker-5\n10.0.4.25\n56-core | 512GB"]
        W6["💻 worker-6\n10.0.4.26\n56-core | 512GB"]

        subgraph WORKLOADS["Application Workloads (Helm + ArgoCD)"]
            APP["📦 WebApp Pods\nReplicas: 3 → 5 (HPA)\n2 vCPU / 3Gi each"]
            JOBS["⚙️ K8s CronJobs\nBatch / ETL\n(replaces ACI)"]
        end
    end

    subgraph DATA["💾 Data Layer (VLAN 50: 10.0.5.0/24)"]
        PG1[("🗄️ PostgreSQL PRIMARY\nPatroni Leader\n10.0.5.1\nPG 15 | 56-core | 1TB RAM")]
        PG2[("🗄️ PostgreSQL STANDBY-1\nPatroni Follower\n10.0.5.2\nStreaming Replication")]
        PG3[("🗄️ PostgreSQL STANDBY-2\nPatroni Follower\n10.0.5.3\nRead Replica")]
        ETCD_DB["📦 etcd (Patroni DCS)\n3 nodes: 10.0.5.11-13"]
        HAP["⚖️ HAProxy\nVIP: 10.0.5.100\nPort 5432: Primary R/W\nPort 5433: Replicas R/O"]
        PGB["🔄 PgBouncer\nConnection Pool\n400 max connections\nTransaction mode"]
        REDIS["⚡ Redis Cluster\n3 masters + 3 replicas\n6 GB total\nAOF persistence + TLS"]
    end

    subgraph STORAGE["📁 Storage (VLAN 60: 10.0.6.0/24)"]
        NAS["🗂️ NetApp AFF A250\n• 10 TB usable NVMe\n• NFS + iSCSI\n• HA Pair\n• Daily snapshots 30-day"]
        MINIO["📦 MinIO Distributed\n• 4-node cluster\n• S3-compatible API\n• Replaces Azure Blob\n• Buckets: app-data, backup, logs"]
    end

    subgraph MONITORING["📊 Monitoring (VLAN 70: 10.0.7.0/24)"]
        PROM["📈 Prometheus\n• 30-day retention\n• 50 GB storage\n• 15-sec scrape\n• HA: 2 replicas"]
        GRAF["📊 Grafana\n• LDAP auth\n• 10+ dashboards\n• Infra, K8s, App, DB"]
        AM["🔔 Alertmanager\n• PagerDuty routing\n• Slack integration\n• Email alerts\n• 15+ alert rules"]
        ELK["📋 ELK Stack\n• Elasticsearch 3-node\n• Logstash pipelines\n• Kibana dashboards\n• Filebeat on all nodes"]
        JAEGER["🔍 Jaeger Tracing\n• Distributed traces\n• Replaces App Insights"]
    end

    subgraph MGMT["⚙️ Management (VLAN 80: 10.0.8.0/24)"]
        VAULT["🔑 HashiCorp Vault\n• 3-node HA cluster\n• K8s auth method\n• DB secret rotation\n• PKI engine (TLS certs)\n• Replaces Azure Key Vault"]
        ARGO["🔄 ArgoCD\n• GitOps continuous deploy\n• Sync from GitLab repo\n• Auto-heal + prune"]
        HARBOR["🐳 Harbor Registry\n• Private container registry\n• Trivy vuln scanning\n• LDAP auth\n• Replaces Azure ACR"]
        GITLAB["🦊 GitLab CI/CD\n• Build pipelines\n• Test automation\n• Image build + push"]
    end

    subgraph BACKUP["💿 Backup (VLAN 90: 10.0.9.0/24)"]
        BACULA["🔄 Bacula\n• Daily full backup 2 AM\n• 30-day retention\n• Geo-copy to remote site"]
        VELERO["☸️ Velero\n• K8s namespace backup\n• PV snapshot backup\n• Scheduled daily"]
    end

    U1 --> ISP1 & ISP2
    ISP1 & ISP2 --> FW
    FW --> F5
    F5 <-->|management| CS
    CS --> AS
    AS --> CP1 & CP2 & CP3
    AS --> W1 & W2 & W3 & W4 & W5 & W6
    F5 --> INGRESS
    INGRESS --> APP
    APP --> PGB --> HAP --> PG1
    PG1 -->|stream replication| PG2 & PG3
    ETCD_DB -.->|DCS| PG1 & PG2 & PG3
    APP --> REDIS
    APP --> MINIO
    NAS -->|NFS mounts| W1 & W2 & W3 & W4 & W5 & W6
    APP -->|metrics| PROM
    APP -->|logs| ELK
    APP -->|traces| JAEGER
    PROM --> GRAF & AM
    VAULT -->|inject secrets| APP
    ARGO -->|deploy| APP & JOBS
    HARBOR -->|images| APP
    GITLAB -->|push images| HARBOR
    BACULA -->|backup| PG1 & MINIO & NAS
    VELERO -->|backup| APP & JOBS

    style USERS fill:#e3f2fd,stroke:#1565c0
    style ISP_LAYER fill:#ede7f6,stroke:#4527a0
    style DMZ fill:#fce4ec,stroke:#880e4f
    style NETWORK fill:#e8eaf6,stroke:#283593
    style K8S_CONTROL fill:#e8f5e9,stroke:#1b5e20
    style K8S_WORKERS fill:#f1f8e9,stroke:#33691e
    style DATA fill:#fff3e0,stroke:#e65100
    style STORAGE fill:#fafafa,stroke:#424242
    style MONITORING fill:#f3e5f5,stroke:#4a148c
    style MGMT fill:#e0f7fa,stroke:#006064
    style BACKUP fill:#efebe9,stroke:#3e2723
```

---

## On-Premises vs Azure: Component Comparison

```mermaid
graph LR
    subgraph AZURE_COL["☁️ Azure (Current)"]
        AZ1["Azure Front Door\n+ WAF"]
        AZ2["Application Gateway\nWAF_v2"]
        AZ3["App Service 3×P1V2\n.NET on Windows"]
        AZ4["PostgreSQL Managed\nPG 11 | Zone HA"]
        AZ5["Redis Cache Premium\n6 GB Cluster"]
        AZ6["Azure Blob Storage\n2.5 TB RA-GRS"]
        AZ7["Azure Monitor\n+ App Insights"]
        AZ8["Log Analytics\n30-day retention"]
        AZ9["Azure Key Vault\nPremium"]
        AZ10["Azure Backup\n+ Site Recovery"]
        AZ11["Azure DevOps\nCI/CD"]
    end

    subgraph ONPREM_COL["🏢 On-Premises (Target)"]
        OP1["Palo Alto PA-5250\nNGFW HA Pair"]
        OP2["F5 BIG-IP 5200\nActive/Passive HA"]
        OP3["K8s Pods\n.NET on Linux\nHPA 2–5 replicas"]
        OP4["PostgreSQL 15\nPatroni HA | 3-node"]
        OP5["Redis Cluster\n3+3 nodes | 6 GB"]
        OP6["MinIO Distributed\n10 TB NVMe NAS"]
        OP7["Prometheus\n+ Grafana + Jaeger"]
        OP8["ELK Stack\nUnlimited retention"]
        OP9["HashiCorp Vault\n3-node HA"]
        OP10["Bacula + Velero\nDaily + WAL archive"]
        OP11["GitLab CI\n+ ArgoCD GitOps"]
    end

    AZ1 -->|replaces| OP1
    AZ2 -->|replaces| OP2
    AZ3 -->|replaces| OP3
    AZ4 -->|replaces| OP4
    AZ5 -->|replaces| OP5
    AZ6 -->|replaces| OP6
    AZ7 -->|replaces| OP7
    AZ8 -->|replaces| OP8
    AZ9 -->|replaces| OP9
    AZ10 -->|replaces| OP10
    AZ11 -->|replaces| OP11

    style AZURE_COL fill:#e8f4fd,stroke:#0078D4
    style ONPREM_COL fill:#e8f5e9,stroke:#2e7d32
```

---

## On-Premises Network VLAN Map

```mermaid
graph TB
    subgraph VLANS["🔀 VLAN Segmentation"]
        V10["VLAN 10 — Management\n10.0.1.0/24\nvCenter | IPMI | OOB\nSwitches | Bastion"]
        V20["VLAN 20 — DMZ\n10.0.2.0/24\nPalo Alto NGFW\nF5 BIG-IP VIP: 10.0.2.10"]
        V30["VLAN 30 — K8s Control\n10.0.3.0/24\nMaster-1/2/3\netcd cluster"]
        V40["VLAN 40 — K8s Workers\n10.0.4.0/24\nWorker-1 to 6\nMetalLB: 10.0.4.200-220"]
        V50["VLAN 50 — Database\n10.0.5.0/24\nPostgreSQL Primary/Standby\nRedis Cluster\nHAProxy VIP: 10.0.5.100"]
        V60["VLAN 60 — Storage\n10.0.6.0/24\nNetApp NAS\nMinIO Cluster"]
        V70["VLAN 70 — Monitoring\n10.0.7.0/24\nPrometheus | Grafana\nELK | Jaeger"]
        V80["VLAN 80 — CI/CD & Mgmt\n10.0.8.0/24\nGitLab | ArgoCD\nHarbor Registry | Vault"]
        V90["VLAN 90 — Backup\n10.0.9.0/24\nBacula Server\nVelero"]
    end

    V10 -->|admin access| V20 & V30 & V40 & V50 & V60 & V70 & V80 & V90
    V20 -->|port 8080/8443| V40
    V40 -->|port 5432 pgsql| V50
    V40 -->|port 6379 redis| V50
    V40 -->|NFS 2049| V60
    V40 -->|metrics 9090| V70
    V40 -->|logs 5044| V70
    V80 -->|deploy| V40
    V90 -->|backup pull| V50 & V60

    style VLANS fill:#fafafa,stroke:#424242
    style V10 fill:#607d8b,color:#fff
    style V20 fill:#c62828,color:#fff
    style V30 fill:#1565c0,color:#fff
    style V40 fill:#2e7d32,color:#fff
    style V50 fill:#e65100,color:#fff
    style V60 fill:#4a148c,color:#fff
    style V70 fill:#006064,color:#fff
    style V80 fill:#f57f17,color:#fff
    style V90 fill:#3e2723,color:#fff
```

---

## On-Premises Hardware Summary

| Component | Model | Qty | Spec | Role |
|-----------|-------|-----|------|------|
| Firewall | Palo Alto PA-5250 | 2 (HA) | 100 Gbps | NGFW, IPS, SSL inspection |
| Load Balancer | F5 BIG-IP 5200 | 2 (HA) | 1.6 Tbps | SSL offload, VIP, health check |
| Core Switch | Cisco Nexus 9372PX | 2 (VPC) | 14.4 Tbps | L3 routing, VLAN trunk |
| Access Switch | Cisco Nexus 9348 | 4 | 25.6 Tbps | Server access ports |
| K8s Masters | Dell R750 | 3 | 2×28-core, 256GB RAM | Control plane + etcd |
| K8s Workers | Dell R750 | 6 | 2×28-core, 512GB RAM | App workloads |
| DB Servers | Dell R750 | 2 | 2×28-core, 1TB RAM | PostgreSQL HA |
| NAS Storage | NetApp AFF A250 | 2 (HA) | 10 TB NVMe | Persistent volumes, DB |
| UPS | APC Smart-UPS | 2 | 20 kVA each | Power protection |

---

## On-Premises Performance Targets

| Metric | Azure Current | On-Prem Target | Improvement |
|--------|--------------|----------------|-------------|
| Response Time P95 | 180 ms | < 150 ms | +17% faster |
| Response Time P99 | 500 ms | < 300 ms | +40% faster |
| Throughput | 5,000 req/s | 10,000 req/s | +100% |
| Concurrent Users | 5,000 | 10,000 | +100% |
| Availability | 99.95% | 99.99% | +4× fewer outages |
| DB Failover RTO | < 15 min | < 5 min | 3× faster |
| DB RPO | 15 min | < 1 min | 15× better |
| Monthly Cost | $46,000 | ~$15,000 (ops) | -67% |

---

**Document Version**: 2.0 | **Date**: July 2026 | **Classification**: Internal Use Only
