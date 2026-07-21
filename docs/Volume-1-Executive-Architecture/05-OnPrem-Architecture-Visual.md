# Volume 1: Executive & Solution Architecture
## Chapter 5: Target On-Premises Architecture — Visual Reference

> **Purpose**: Exact visual representation of the target on-premises deployment after migration.

---

## On-Premises Architecture — Full Stack Diagram

```mermaid
graph TB
    INET[Internet Users] --> ISP1 & ISP2
    CORP[Corporate LAN Users] --> SW

    subgraph SECURITY["Security Layer  VLAN 20: 10.0.2.0/24"]
        ISP1[ISP Link 1 - 1Gbps Primary] --> FW
        ISP2[ISP Link 2 - 1Gbps Failover] --> FW
        FW[Palo Alto PA-5250 NGFW\nHA Active/Passive\n6 Security Zones]
        FW --> F5
        F5[F5 BIG-IP 5200\nVIP: 10.0.2.10\nSSL Offload / HA]
    end

    subgraph NETWORK["Network Core"]
        SW[Cisco Nexus 9372PX\nVPC Pair / VLANs 10-90]
    end

    subgraph K8S["Kubernetes Cluster  VLAN 30-40"]
        subgraph CP["Control Plane  10.0.3.x"]
            M1[master-1\n10.0.3.11]
            M2[master-2\n10.0.3.12]
            M3[master-3\n10.0.3.13]
        end
        INGR[NGINX Ingress\nMetalLB 10.0.4.200]
        subgraph PODS["Worker Nodes  10.0.4.x - 6 nodes"]
            APP[WebApp Pods\nHPA 2-5 replicas]
            JOBS[CronJobs\nBatch / ETL]
        end
    end

    subgraph DATA["Data Layer  VLAN 50: 10.0.5.0/24"]
        HAP[HAProxy VIP 10.0.5.100\nPort 5432 Primary / 5433 Replica]
        PGB[PgBouncer Pool\nPort 6432]
        PG1[(PostgreSQL Primary\nPatroni Leader 10.0.5.1)]
        PG2[(PostgreSQL Standby-1\n10.0.5.2)]
        PG3[(PostgreSQL Standby-2\n10.0.5.3)]
        MONGO[(MongoDB ReplicaSet\n3-node / 10.0.5.20-22\nReplaces Cosmos DB)]
        REDIS[Redis Cluster\n3+3 nodes / 6GB]
    end

    subgraph STORAGE["Storage  VLAN 60"]
        NAS[NetApp AFF A250\n10TB NVMe / HA Pair]
        MINIO[MinIO Distributed\n4-node / S3 API]
    end

    subgraph OBS["Observability  VLAN 70"]
        PROM[Prometheus\n30d retention]
        GRAF[Grafana\n10+ dashboards]
        ELK[ELK Stack\nElastic + Kibana]
    end

    subgraph MGMT["Management  VLAN 80"]
        VAULT[HashiCorp Vault\n3-node HA]
        ARGO[ArgoCD\nGitOps]
        HARBOR[Harbor Registry\nTrivy scanning]
    end

    F5 --> INGR --> APP
    SW --> M1 & M2 & M3
    SW --> PODS
    APP --> PGB --> HAP --> PG1
    PG1 -->|streaming replication| PG2 & PG3
    APP --> MONGO
    APP --> REDIS & MINIO
    NAS -.->|NFS| PODS
    APP --> PROM --> GRAF
    APP --> ELK
    VAULT -.->|inject secrets| APP
    ARGO -.->|deploy| APP & JOBS
    HARBOR -.->|images| APP

    style SECURITY fill:#fce4ec,stroke:#880e4f
    style NETWORK fill:#e8eaf6,stroke:#283593
    style K8S fill:#e8f5e9,stroke:#1b5e20
    style DATA fill:#fff3e0,stroke:#e65100
    style STORAGE fill:#f5f5f5,stroke:#616161
    style OBS fill:#f3e5f5,stroke:#6a1b9a
    style MGMT fill:#e0f7fa,stroke:#006064
```

---

## On-Premises vs Azure: Component Comparison

| Azure Service | On-Premises Replacement | Migration Tool |
|---|---|---|
| Azure Kubernetes Service (AKS) | Self-managed K8s 1.29 (bare metal) | kubeadm, Helm, ArgoCD |
| Azure Storage Account | MinIO Distributed (S3-compatible) | rclone sync |
| **Azure Cosmos DB** | **MongoDB Community 7.0 ReplicaSet** | **mongodump / mongorestore + Change Streams** |
| Azure Container Registry (ACR) | Harbor (private, Trivy scan) | docker push to Harbor |
| Azure Database for PostgreSQL | PostgreSQL 15 + Patroni HA | pglogical live replication |
| Azure Monitor | Prometheus + Grafana + Alertmanager | Helm chart deploy |
| Application Insights | Jaeger (tracing) + ELK (logs) | SDK endpoint change |
| Azure Key Vault | HashiCorp Vault 3-node HA | vault kv migrate |
| Azure Backup | Bacula + Velero | Scheduled jobs |
| Azure DevOps / ACR CI/CD | GitLab CI + ArgoCD | Pipeline migration |

```mermaid
graph LR
    subgraph AZURE_COL["Azure Current - Per Environment"]
        AZ1["AKS\nKubernetes Service"]
        AZ2["Storage Account\nBlob/File/Queue"]
        AZ3["Azure Cosmos DB\nNoSQL Documents"]
        AZ4["ACR\nContainer Registry"]
        AZ5["PostgreSQL\nManaged PG11"]
    end

    subgraph ONPREM_COL["On-Premises Target - Per Environment"]
        OP1["Kubernetes\nnamespace per env"]
        OP2["MinIO\nS3-compatible"]
        OP3["MongoDB 7.0\n3-node ReplicaSet"]
        OP4["Harbor\nTrivy scan"]
        OP5["PostgreSQL 15\nPatroni HA"]
    end

    AZ1 -->|replaces| OP1
    AZ2 -->|replaces| OP2
    AZ3 -->|replaces| OP3
    AZ4 -->|replaces| OP4
    AZ5 -->|replaces| OP5

    style AZURE_COL fill:#e8f4fd,stroke:#0078D4
    style ONPREM_COL fill:#e8f5e9,stroke:#2e7d32
```

---

## On-Premises Network VLAN Map

```mermaid
graph LR
    V10[VLAN 10 Management\n10.0.1.0/24\nvCenter / IPMI / Bastion]
    V20[VLAN 20 DMZ\n10.0.2.0/24\nNGFW / F5 VIP 10.0.2.10]
    V30[VLAN 30 K8s Control\n10.0.3.0/24\nMasters 1-3 / etcd]
    V40[VLAN 40 K8s Workers\n10.0.4.0/24\nWorkers 1-6\nMetalLB 10.0.4.200]
    V50[VLAN 50 Database\n10.0.5.0/24\nPostgreSQL / Redis\nHAProxy 10.0.5.100]
    V60[VLAN 60 Storage\n10.0.6.0/24\nNetApp NAS / MinIO]
    V70[VLAN 70 Monitoring\n10.0.7.0/24\nPrometheus / Grafana\nELK / Jaeger]
    V80[VLAN 80 CI/CD\n10.0.8.0/24\nGitLab / ArgoCD\nHarbor / Vault]
    V90[VLAN 90 Backup\n10.0.9.0/24\nBacula / Velero]

    V10 -->|admin SSH/HTTPS| V20
    V10 -->|admin SSH/HTTPS| V30
    V10 -->|admin SSH/HTTPS| V40
    V10 -->|admin SSH/HTTPS| V50
    V20 -->|port 8080| V40
    V40 -->|port 5432| V50
    V40 -->|port 6379| V50
    V40 -->|NFS 2049| V60
    V40 -->|metrics 9090| V70
    V40 -->|logs 5044| V70
    V80 -->|deploy| V40
    V90 -->|backup pull| V50
    V90 -->|backup pull| V60

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
