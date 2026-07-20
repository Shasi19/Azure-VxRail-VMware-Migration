# Volume 2: Migration Strategy
## Chapter 1: Migration Overview & Service Mapping

---

## Azure to On-Premises: Complete Service Mapping

```
┌───────────────────────────────────────────────────────────────────────────────────┐
│                     AZURE ──► ON-PREMISES SERVICE MAPPING                        │
├──────────────────────────┬──────────────────────────────┬────────────────────────┤
│  AZURE SERVICE           │  ON-PREMISES EQUIVALENT      │  MIGRATION TYPE        │
├──────────────────────────┼──────────────────────────────┼────────────────────────┤
│  Azure Front Door        │  F5 BIG-IP + NGINX Ingress   │  Lift & Replace        │
│  Application Gateway     │  F5 BIG-IP LTM               │  Lift & Replace        │
│  WAF                     │  Palo Alto NGFW + F5 ASM     │  Lift & Replace        │
│  App Service (3x P1V2)   │  Kubernetes Pods (6 workers) │  Replatform            │
│  Container Instances     │  K8s CronJobs + Jobs         │  Replatform            │
│  PostgreSQL Managed      │  PostgreSQL + Patroni HA     │  Lift & Shift (data)   │
│  Azure Storage Accounts  │  MinIO Object Storage / NAS  │  Lift & Shift (data)   │
│  Redis Cache             │  Redis Cluster (on-prem)     │  Lift & Shift          │
│  Azure Monitor           │  Prometheus + Alertmanager   │  Replace               │
│  Application Insights    │  Jaeger + Prometheus         │  Replace               │
│  Log Analytics           │  Elasticsearch + Kibana      │  Replace               │
│  Key Vault               │  HashiCorp Vault             │  Replace               │
│  Security Center         │  Wazuh SIEM                  │  Replace               │
│  Azure Sentinel          │  Wazuh + OSSEC               │  Replace               │
│  Azure Backup            │  Bacula + Velero             │  Replace               │
│  Site Recovery           │  Veeam / Zerto               │  Replace               │
│  Virtual Network         │  Cisco Nexus VLANs           │  Replace               │
│  Azure AD / Managed ID   │  LDAP / Active Directory     │  Integrate             │
│  Azure DNS               │  BIND9 / Infoblox DNS        │  Replace               │
│  Azure CDN               │  NGINX Caching / Varnish     │  Replace               │
└──────────────────────────┴──────────────────────────────┴────────────────────────┘
```

---

## High-Level Migration Architecture Flowchart

```mermaid
flowchart TD
    A([🌐 Start: Azure Cloud]) --> B{Migration\nReadiness\nAssessment}

    B -->|Not Ready| C[Gap Analysis &\nRemediation Plan]
    C --> B

    B -->|Ready| D[Phase 1: Procurement\n& Planning\nWeeks 1-4]

    D --> E[Phase 2: Infrastructure\nSetup\nWeeks 5-8]
    E --> F[Phase 3: Middleware\nDeployment\nWeeks 9-12]
    F --> G[Phase 4: Kubernetes\nPlatform Build\nWeeks 13-16]
    G --> H[Phase 5: Testing &\nValidation\nWeeks 17-20]
    H --> I{All Tests\nPassed?}

    I -->|No| J[Fix Issues &\nRe-test]
    J --> H

    I -->|Yes| K[Phase 6: Go-Live\n& Cutover\nWeeks 21-22]
    K --> L[Phase 7: Stabilization\nWeeks 23-26]
    L --> M([✅ Migration Complete])

    style A fill:#0078D4,color:#fff
    style M fill:#107C10,color:#fff
    style B fill:#FFB900,color:#000
    style I fill:#FFB900,color:#000
```

---

## Detailed Migration Decision Flowchart

```mermaid
flowchart LR
    subgraph AZURE["AZURE (Current State)"]
        A1[App Service\n3x P1V2]
        A2[PostgreSQL\nManaged]
        A3[Redis Cache]
        A4[Storage\nAccounts]
        A5[App Gateway\n+ WAF]
        A6[Azure Monitor\n+ App Insights]
        A7[Key Vault]
        A8[Azure Backup\n+ ASR]
    end

    subgraph MIGRATION["MIGRATION LAYER"]
        M1[Containerize Apps\nDocker Build]
        M2[pg_dump / pglogical\nLive Replication]
        M3[Redis DUMP/RESTORE\nRDB Snapshot]
        M4[rsync / rclone\nData Transfer]
        M5[Config Translation\nHelmCharts]
        M6[Agent Deployment\nPrometheus Exporters]
        M7[Secret Export\nVault Migration]
        M8[Backup Validation\nData Integrity]
    end

    subgraph ONPREM["ON-PREMISES (Target State)"]
        O1[Kubernetes\nPods + HPA]
        O2[PostgreSQL HA\nPatroni + etcd]
        O3[Redis Cluster\n3-node]
        O4[MinIO / NAS\nObject Storage]
        O5[F5 BIG-IP\n+ Palo Alto NGFW]
        O6[Prometheus +\nGrafana + ELK]
        O7[HashiCorp\nVault]
        O8[Bacula + Velero\nBackup System]
    end

    A1 --> M1 --> O1
    A2 --> M2 --> O2
    A3 --> M3 --> O3
    A4 --> M4 --> O4
    A5 --> M5 --> O5
    A6 --> M6 --> O6
    A7 --> M7 --> O7
    A8 --> M8 --> O8

    style AZURE fill:#0078D4,color:#fff
    style MIGRATION fill:#FFB900,color:#000
    style ONPREM fill:#107C10,color:#fff
```

---

## Migration Strategy: 3-Stage Approach

```mermaid
graph LR
    subgraph S1["Stage 1: Foundation (Weeks 1-8)"]
        T1A[Procurement\nand Planning] --> T1B[Hardware\nInstallation]
        T1B --> T1C[Network\nConfiguration]
        T1C --> T1D[Virtualization\nSetup]
    end
    subgraph S2["Stage 2: Platform (Weeks 9-16)"]
        T2A[Kubernetes\nCluster] --> T2B[PostgreSQL\nHA Setup]
        T2B --> T2C[Redis and\nMinIO]
        T2C --> T2D[Monitoring\nStack]
    end
    subgraph S3["Stage 3: Migration (Weeks 17-26)"]
        T3A[App\nContainerization] --> T3B[Data\nMigration]
        T3B --> T3C[Testing &\nValidation]
        T3C --> T3D[Go-Live\nCutover]
        T3D --> T3E[Stabilization]
    end

    S1 --> S2 --> S3

    style S1 fill:#e3f2fd,stroke:#1565c0
    style S2 fill:#e8f5e9,stroke:#2e7d32
    style S3 fill:#fff3e0,stroke:#e65100
```

---

## Infrastructure Architecture Overview

```mermaid
graph TB
    subgraph INTERNET["Internet"]
        USR[End Users]
        ISP[ISP / WAN Link\n1Gbps]
    end

    subgraph DMZ["DMZ Zone"]
        PA[Palo Alto NGFW\nHA Pair]
        F5[F5 BIG-IP\nActive/Passive]
    end

    subgraph K8S["Kubernetes Cluster"]
        subgraph CONTROL["Control Plane"]
            CP1[Master-1\n10.0.2.11]
            CP2[Master-2\n10.0.2.12]
            CP3[Master-3\n10.0.2.13]
        end
        subgraph WORKERS["Worker Nodes"]
            W1[Worker-1\n10.0.2.21]
            W2[Worker-2\n10.0.2.22]
            W3[Worker-3\n10.0.2.23]
            W4[Worker-4\n10.0.2.24]
            W5[Worker-5\n10.0.2.25]
            W6[Worker-6\n10.0.2.26]
        end
        ING[NGINX Ingress\nMetalLB VIP]
    end

    subgraph DATA["Data Layer"]
        PG1[(PostgreSQL\nPrimary\n10.0.5.1)]
        PG2[(PostgreSQL\nStandby\n10.0.5.2)]
        REDIS[Redis Cluster\n3-node]
        MINIO[MinIO\nObject Storage\n10TB]
    end

    subgraph MON["Monitoring"]
        PROM[Prometheus]
        GRAF[Grafana]
        ELK[ELK Stack]
    end

    subgraph MGMT["Management"]
        VAULT[HashiCorp Vault]
        ARGO[ArgoCD]
        HARBOR[Harbor Registry]
    end

    USR --> ISP --> PA --> F5 --> ING
    ING --> W1 & W2 & W3 & W4 & W5 & W6
    W1 & W2 & W3 --> PG1
    PG1 -->|Streaming Replication| PG2
    W1 & W2 & W3 --> REDIS
    W1 & W2 & W3 --> MINIO
    W1 & W2 & W3 -->|Metrics| PROM --> GRAF
    W1 & W2 & W3 -->|Logs| ELK

    style INTERNET fill:#e8f4fd
    style DMZ fill:#fde8e8
    style K8S fill:#e8fde8
    style DATA fill:#fdf8e8
    style MON fill:#f0e8fd
    style MGMT fill:#e8f0fd
```

---

## Network VLAN Layout

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         NETWORK VLAN DESIGN                              │
├────────┬──────────────┬────────────────┬────────────────────────────────┤
│  VLAN  │  Name        │  Subnet        │  Purpose                       │
├────────┼──────────────┼────────────────┼────────────────────────────────┤
│   10   │  Management  │  10.0.1.0/24   │  OOB, IPMI, vCenter, Switches  │
│   20   │  DMZ         │  10.0.2.0/24   │  Firewall, Load Balancer       │
│   30   │  K8s Control │  10.0.3.0/24   │  Kubernetes Master Nodes       │
│   40   │  K8s Workers │  10.0.4.0/24   │  Kubernetes Worker Nodes       │
│   50   │  Database    │  10.0.5.0/24   │  PostgreSQL, Redis             │
│   60   │  Storage     │  10.0.6.0/24   │  NAS, SAN, MinIO              │
│   70   │  Monitoring  │  10.0.7.0/24   │  Prometheus, Grafana, ELK     │
│   80   │  CI/CD       │  10.0.8.0/24   │  GitLab, ArgoCD, Harbor       │
│   90   │  Backup      │  10.0.9.0/24   │  Bacula, Velero               │
├────────┼──────────────┼────────────────┼────────────────────────────────┤
│  KEY SECURITY RULES:                                                     │
│  • Internet → DMZ: Port 443, 80 only                                    │
│  • DMZ → K8s Workers: Port 8080, 8443 only                              │
│  • K8s → Database: Port 5432, 6379 only                                 │
│  • Management → All: SSH (22), HTTPS (443)                               │
│  • Database → Storage: Port 2049 (NFS), 3260 (iSCSI)                   │
│  • Backup → All: Pull-based backup on port 9102                         │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Risk Register

```mermaid
graph TD
    subgraph CRITICAL["CRITICAL  -  Mitigate Immediately"]
        R1["Hardware Delivery Delays\nProb: High | Impact: High\nMitigation: Order 8 weeks early"]
        R2["Data Loss During Migration\nProb: Medium | Impact: Critical\nMitigation: pglogical live replication + rollback"]
    end
    subgraph HIGH["HIGH  -  Active Monitoring"]
        R3["Performance Degradation\nProb: Medium | Impact: High\nMitigation: Load test pre-cutover"]
        R4["DB Replication Lag\nProb: High | Impact: Medium\nMitigation: Monitor lag < 100ms"]
        R5["Team Skill Gaps\nProb: High | Impact: Medium\nMitigation: K8s + Patroni training"]
    end
    subgraph MEDIUM["MEDIUM  -  Contingency Plan"]
        R6["Network Connectivity\nProb: Medium | Impact: Medium\nMitigation: Dual ISP links"]
        R7["License Compliance\nProb: Low | Impact: Medium\nMitigation: License audit upfront"]
        R8["Rollback Complexity\nProb: Low | Impact: High\nMitigation: Tested rollback runbook"]
        R9["Compliance Drift\nProb: Low | Impact: High\nMitigation: Compliance gate per phase"]
    end
    subgraph LOW["LOW  -  Accept / Monitor"]
        R10["Vendor Support Gaps\nProb: Low | Impact: Medium\nMitigation: Support contracts pre-go-live"]
    end

    style CRITICAL fill:#fde8e8,stroke:#c62828
    style HIGH fill:#fff3e0,stroke:#e65100
    style MEDIUM fill:#fffde7,stroke:#f9a825
    style LOW fill:#e8f5e9,stroke:#2e7d32
```

---

## Migration Risk Register Detail

| Risk | Probability | Impact | Score | Mitigation |
|------|-------------|--------|-------|------------|
| Hardware delivery delays | High (65%) | High | 🔴 Critical | Order 8 weeks early, identify backup vendors |
| Data loss during migration | Medium (35%) | Critical | 🔴 Critical | pglogical live replication, rollback plan |
| Performance degradation | Medium (55%) | High | 🟠 High | Load testing pre-cutover, auto-scaling |
| Database replication lag | High (60%) | Medium | 🟠 High | Monitor lag <100ms before cutover |
| Team skill gaps | High (70%) | Medium | 🟠 High | K8s + Patroni training 4 weeks prior |
| Network connectivity issues | Medium (40%) | Medium | 🟡 Medium | Dual ISP links, tested failover |
| License compliance issues | Low (45%) | Medium | 🟡 Medium | License audit before procurement |
| Rollback complexity | Low (30%) | High | 🟡 Medium | Documented rollback runbook |
| Vendor support gaps | Low (35%) | Medium | 🟢 Low | Support contracts before go-live |
| Compliance drift | Low (25%) | High | 🟡 Medium | Compliance validation gate per phase |

---

## Migration Team Structure

```mermaid
graph TD
    PM[Project Manager] --> TL[Technical Lead / Architect]
    TL --> NET[Network Engineer x2]
    TL --> INFRA[Infrastructure Engineer x2]
    TL --> DBA[Database Administrator x1]
    TL --> K8S[Kubernetes Engineer x2]
    TL --> SEC[Security Engineer x1]
    TL --> DEV[Application Developer x2]
    TL --> OPS[Operations Engineer x1]
    PM --> QA[QA Lead x1]
    QA --> TESTER[Test Engineers x2]

    style PM fill:#0078D4,color:#fff
    style TL fill:#107C10,color:#fff
```

---

## Document Navigation

| Volume | Document | Status |
|--------|----------|--------|
| Vol 1 Ch 1 | [Executive Summary](../Volume-1-Executive-Architecture/01-Executive-Summary.md) | ✅ Complete |
| Vol 1 Ch 2 | [Existing Azure Architecture](../Volume-1-Executive-Architecture/02-Existing-Azure-Architecture.md) | ✅ Complete |
| Vol 1 Ch 3 | [Target Architecture](../Volume-1-Executive-Architecture/03-Target-Architecture.md) | ✅ Complete |
| Vol 2 Ch 1 | Migration Overview & Service Mapping *(this document)* | ✅ Complete |
| Vol 2 Ch 2 | [Phase Implementation Guide](./02-Phase-Implementation-Guide.md) | ✅ Complete |
| Vol 2 Ch 3 | [Timeline & Milestones](./03-Timeline-And-Milestones.md) | ✅ Complete |
| Vol 3 | [Infrastructure Setup](../Volume-3-Infrastructure-Setup/) | ✅ Complete |
| Vol 4 | [Kubernetes Platform](../Volume-4-Kubernetes-Platform/01-Kubernetes-Setup-Guide.md) | ✅ Complete |
| Vol 5 | [Database Migration](../Volume-5-Database-Migration/) | ✅ Complete |
| Vol 6 | [Application Migration](../Volume-6-Application-Migration/) | ✅ Complete |
| Vol 7 | [Monitoring & Security](../Volume-7-Monitoring-Security/) | ✅ Complete |
| Vol 8 | [Go-Live & Operations](../Volume-8-GoLive-Operations/) | ✅ Complete |

---

**Document Version**: 2.0
**Date**: July 2026
**Classification**: Internal Use Only
