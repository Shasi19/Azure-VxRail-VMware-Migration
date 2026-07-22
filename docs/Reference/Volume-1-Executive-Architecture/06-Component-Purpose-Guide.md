# Volume 1: Executive & Solution Architecture
## Chapter 6: Component Purpose Guide — What Is Used For What

> **Purpose**: Plain-English explanation of every technology component, why it was chosen, what problem it solves, and how it maps to the Azure service it replaces.

---

## Quick Reference Map

| On-Premises Component | Replaces (Azure) | Purpose in One Line |
|-----------------------|-----------------|---------------------|
| Palo Alto PA-5250 NGFW | Azure Firewall + DDoS Protection | Inspect and control ALL network traffic entering the datacenter |
| F5 BIG-IP 5200 | Azure Application Gateway | Distribute incoming requests across application pods, terminate SSL |
| Cisco Nexus 9372PX | Azure Virtual Network + NSG | Physical network switching, VLAN isolation between tiers |
| Kubernetes (K8s) | Azure Kubernetes Service (AKS) | Run and manage containerised application pods at scale |
| Harbor Registry | Azure Container Registry (ACR) | Store and scan Docker images privately before deployment |
| ArgoCD | Azure DevOps / GitHub Actions CD | Auto-deploy applications from Git — no manual kubectl apply |
| GitLab CI | Azure DevOps Pipelines | Build, test, scan, and push Docker images automatically |
| PostgreSQL 15 + Patroni | Azure Database for PostgreSQL | Production relational database with automatic failover |
| HAProxy | Azure Load Balancer (DB tier) | Route DB connections: writes to primary, reads to replicas |
| PgBouncer | Built-in Azure PG connection pooling | Pool and reuse DB connections, prevent connection exhaustion |
| Redis Cluster | Azure Cache for Redis | Cache session data and hot query results to reduce DB load |
| MinIO | Azure Blob Storage | Store files, backups, exports — S3-compatible API |
| NetApp AFF A250 | Azure Files / Azure Disk | Fast shared NFS storage for persistent Kubernetes volumes |
| Prometheus | Azure Monitor (metrics) | Collect and store time-series metrics from every component |
| Grafana | Azure Monitor dashboards | Visualise metrics, build dashboards, send alerts |
| Alertmanager | Azure Monitor Alerts | Route alerts to PagerDuty, Slack, or email |
| ELK Stack | Azure Log Analytics | Centralise, search, and visualise logs from all systems |
| Jaeger | Azure Application Insights (traces) | Trace a single request through all microservices end-to-end |
| HashiCorp Vault | Azure Key Vault | Store secrets, rotate DB credentials, issue TLS certificates |
| Bacula | Azure Backup | Daily full backups of databases, files, and configurations |
| Velero | Azure Backup (K8s) | Snapshot and restore entire Kubernetes namespaces |
| Wazuh SIEM | Azure Sentinel | Detect threats, collect security events, trigger alerts |
| cert-manager | Azure-managed certificates | Auto-issue and renew TLS certificates inside Kubernetes |
| **MongoDB 7.0 ReplicaSet** | **Azure Cosmos DB** | **NoSQL document store — sessions, audit logs, notifications, app config** |

---

## Detailed Component Explanations

---

### 1. Palo Alto PA-5250 NGFW
**Category**: Security — Perimeter Firewall
**Replaces**: Azure Firewall + Azure DDoS Protection

**What it does:**
Every packet entering or leaving your datacenter passes through Palo Alto. It does far more than a simple firewall — it understands the application inside the packet (App-ID), the user who sent it (User-ID), and can decrypt + inspect SSL traffic to see if malware hides inside HTTPS.

**Why it was chosen:**
Azure Firewall only does basic L4 filtering. Palo Alto does L7 deep inspection, blocks zero-day threats in real time, integrates with threat intelligence feeds, and gives you 6 independent security zones (DMZ, K8s, Database, Storage, Management, Backup) so a breach in one zone cannot automatically reach another.

**Key features in use:**
- Active/Passive HA pair — if one dies, traffic switches in < 1 second
- SSL/TLS decryption — inspect encrypted traffic for malware
- IPS (Intrusion Prevention) — block known attack patterns
- App-ID — identify and block apps by name (e.g., block Tor, allow HTTPS-app only)
- Zone-based policy — DMZ can only talk to K8s on port 8080, nothing else

---

### 2. F5 BIG-IP 5200
**Category**: Networking — Load Balancer / ADC
**Replaces**: Azure Application Gateway WAF_v2

**What it does:**
F5 is the single entry point for all user traffic after the firewall. It has a Virtual IP (VIP: 10.0.2.10) that your DNS points to. F5 terminates SSL (decrypts HTTPS), then passes plain HTTP to the NGINX Ingress inside Kubernetes. It health-checks all backend pods and stops sending traffic to any pod that is unhealthy.

**Why it was chosen:**
Azure App Gateway is a managed service — you can't customise how it handles traffic. F5 BIG-IP gives you iRules (custom traffic scripts), full SSL inspection, cookie-based session persistence, TCP connection optimisation, and Active/Passive HA that fails over in < 3 seconds with no traffic loss.

**Key features in use:**
- SSL offloading — decrypt once at F5, pods receive plain HTTP (saves CPU on pods)
- Least-connections algorithm — sends each new request to whichever pod is least busy
- Health monitor — polls `/health` every 5 seconds, auto-removes failed pods
- VRRP failover — Active F5 fails, Passive takes VIP in < 3 seconds
- iRules — custom routing logic (e.g., send `/api/*` to API pods, `/static/*` to storage)

---

### 3. Cisco Nexus 9372PX (Core Switch)
**Category**: Networking — Physical Switching
**Replaces**: Azure Virtual Network + Network Security Groups

**What it does:**
This is the physical spine of your network. Every server connects to a Cisco Nexus switch. It creates and enforces VLANs (Virtual LANs) — logical network segments that isolate traffic. Your database servers are on VLAN 50, Kubernetes workers on VLAN 40, management on VLAN 10, etc. Traffic between VLANs is only allowed if the firewall permits it.

**Why it is needed:**
In Azure, network isolation is software-defined. On-premises, you need physical switches. The Nexus 9372PX runs VPC (Virtual Port Channel) — two switches acting as one, so if a switch fails or a cable is pulled, network continues uninterrupted.

**VLANs configured:**
| VLAN | Name | Purpose |
|------|------|---------|
| 10 | Management | vCenter, IPMI, OOB access |
| 20 | DMZ | Firewall, F5 BIG-IP |
| 30 | K8s Control Plane | Masters, etcd |
| 40 | K8s Workers | App pods |
| 50 | Database | PostgreSQL, Redis, HAProxy |
| 60 | Storage | NetApp NAS, MinIO |
| 70 | Monitoring | Prometheus, Grafana, ELK |
| 80 | CI/CD + Mgmt | GitLab, ArgoCD, Harbor, Vault |
| 90 | Backup | Bacula, Velero |

---

### 4. Kubernetes (K8s) 1.28
**Category**: Compute — Container Orchestration
**Replaces**: Azure Kubernetes Service (AKS)

**What it does:**
Kubernetes is the "operating system for your applications". Instead of deploying apps directly on servers, you package apps into Docker containers and tell Kubernetes what to run, how many copies to run, and what resources each copy needs. Kubernetes automatically places containers on the right servers, restarts them if they crash, and scales them up/down based on load.

**Why it was chosen:**
AKS is Kubernetes as a managed service — but you pay Azure premium pricing and accept their limitations. Self-managed K8s on bare metal gives you full control: custom kernel parameters, dedicated hardware for latency-sensitive workloads, and no "noisy neighbour" problem from shared Azure VMs.

**Cluster layout:**
```
Control Plane (3 nodes — HA):
  k8s-master-1  10.0.3.11 — runs API server, scheduler, controller manager
  k8s-master-2  10.0.3.12 — etcd follower, standby control plane
  k8s-master-3  10.0.3.13 — etcd follower, standby control plane

Worker Nodes (6 nodes — run actual apps):
  worker-1 to worker-6  10.0.4.21-26
  56-core | 512 GB RAM each
  App pods, batch jobs, background workers all run here
```

**Key K8s features in use:**
- **HPA (Horizontal Pod Autoscaler)**: Automatically adds pods when CPU > 70%
- **MetalLB**: Gives F5 a real IP to send traffic to inside the cluster
- **NGINX Ingress**: Routes traffic to the right service by URL path or hostname
- **Namespaces**: Isolate dev, qa, preprod, prod within the same cluster
- **Resource Quotas**: Ensure dev can't accidentally use all production resources
- **Pod Disruption Budgets**: Ensure at least 2 pods always running during maintenance

---

### 5. Harbor Registry
**Category**: DevOps — Container Image Registry
**Replaces**: Azure Container Registry (ACR)

**What it does:**
Harbor is a private Docker image registry. When your CI/CD pipeline builds a Docker image of your application, it pushes it to Harbor. When Kubernetes deploys your app, it pulls the image from Harbor. Harbor also runs automatic security scans (using Trivy) on every image to detect vulnerabilities before deployment.

**Why it was chosen over ACR:**
Harbor is open-source and runs in your own datacenter — your images never leave your network. ACR images are stored in Microsoft's cloud. Harbor provides project-level isolation (dev images cannot overwrite prod images), LDAP authentication, and vulnerability scanning all in one self-hosted solution.

**Key features:**
- Trivy security scanning — scans images for CVEs before allowing deployment
- Project isolation — separate projects for dev, qa, preprod, prod
- LDAP/AD integration — same login as your corporate directory
- Webhook notifications — ArgoCD gets notified when a new image is pushed

---

### 6. ArgoCD
**Category**: DevOps — GitOps Continuous Deployment
**Replaces**: Azure DevOps Pipelines (CD part)

**What it does:**
ArgoCD watches a Git repository. When the Git repo changes (e.g., a new Docker image tag or a Kubernetes config change), ArgoCD automatically applies those changes to Kubernetes. If someone manually modifies a Kubernetes resource (configuration drift), ArgoCD detects it and reverts it back to what Git says. **Git is always the single source of truth.**

**Why it matters:**
Without ArgoCD, someone has to manually run `kubectl apply` to deploy — which is error-prone and hard to audit. With ArgoCD, every deployment is a Git commit, giving you: full audit trail, easy rollback (just revert the commit), and automatic self-healing.

**Flow:**
```
Developer merges PR → GitLab CI builds + pushes image → 
Updates image tag in GitOps repo → ArgoCD detects change → 
ArgoCD applies to Kubernetes → App is updated (zero downtime rolling update)
```

---

### 7. GitLab CI
**Category**: DevOps — Continuous Integration
**Replaces**: Azure DevOps Pipelines (CI part)

**What it does:**
Every time a developer pushes code to GitLab, an automated pipeline runs. It:
1. Builds the .NET application
2. Runs unit tests and integration tests
3. Builds a Docker image
4. Scans the image for security vulnerabilities (Trivy)
5. Pushes the image to Harbor
6. Updates the image tag in the GitOps repository

This ensures no untested or unscanned code ever reaches production.

---

### 8. PostgreSQL 15 + Patroni
**Category**: Data — Relational Database with High Availability
**Replaces**: Azure Database for PostgreSQL (Managed)

**What it does:**
PostgreSQL is the relational database that stores all application data. **Patroni** is the HA (High Availability) layer on top of it — it monitors which PostgreSQL node is the leader, and if the leader fails, it automatically promotes a standby to leader within 30 seconds.

**Why it was chosen over managed Azure PostgreSQL:**
Azure PostgreSQL is managed but locked to PostgreSQL 11 and Microsoft's extension choices. On-premises PostgreSQL 15 gives you: newer features, custom extensions, fine-tuned memory/WAL settings, and full control over replication. Failover with Patroni is < 30 seconds vs. < 15 minutes on Azure managed.

**Architecture:**
```
PostgreSQL Primary (Leader)   ← all write queries go here
    │ streaming replication (synchronous copy)
    ▼
PostgreSQL Standby-1 (Sync)   ← zero data loss on failover
    │ streaming replication (asynchronous copy)
    ▼  
PostgreSQL Standby-2 (Async)  ← read-only query offloading

Patroni (on each node) watches etcd cluster for leadership
If Primary dies → Patroni promotes Standby-1 in < 30 seconds
HAProxy VIP (10.0.5.100) automatically points to new Primary
```

---

### 9. HAProxy
**Category**: Networking — Database Connection Routing
**Replaces**: Azure Load Balancer (database tier, built into managed PG)

**What it does:**
HAProxy runs in front of the PostgreSQL cluster. Applications connect to HAProxy's VIP (10.0.5.100) instead of connecting directly to a database server. HAProxy knows which PostgreSQL node is the current Primary and routes write connections there, and can route read-only queries to standby nodes. When Patroni promotes a new Primary, HAProxy automatically updates within seconds.

**Two ports:**
- **Port 5432** → always routes to current Primary (read/write)
- **Port 5433** → routes to Standby replicas (read-only queries)

---

### 10. PgBouncer
**Category**: Data — Database Connection Pooler
**Replaces**: Built-in Azure PG connection management

**What it does:**
PostgreSQL has a hard limit on simultaneous connections (each connection uses ~10MB RAM). With 6 Kubernetes worker nodes each running 5 pods with 20 connections = 600 connections. PgBouncer sits between the application and PostgreSQL and reuses connections — 600 application connections become just 50 actual PostgreSQL connections, dramatically reducing memory pressure.

**Mode used:** Transaction pooling — a connection is borrowed from the pool for the duration of a single SQL transaction, then returned. Applications always think they have a dedicated connection.

---

### 11. Redis Cluster
**Category**: Data — In-Memory Cache
**Replaces**: Azure Cache for Redis (Premium)

**What it does:**
Redis stores frequently-accessed data in RAM for instant retrieval. Instead of hitting PostgreSQL every time a user's session data is needed (50ms query), the app checks Redis first (< 1ms). Redis is also used for distributed locking, rate limiting, and queuing background jobs.

**Architecture:**
```
3 Master nodes (each owns a shard of the data)
3 Replica nodes (one replica per master for HA)
If a master dies → its replica is promoted automatically
```

**What is cached:**
- User sessions (login tokens, preferences)
- Hot API responses (dashboard data, frequently read records)
- Distributed locks (prevent two pods processing the same job)
- Rate limit counters (prevent API abuse)

---

### 12. MongoDB 7.0 ReplicaSet
**Category**: Data — NoSQL Document Database
**Replaces**: Azure Cosmos DB

**What it does:**
MongoDB is a NoSQL document database that stores data as JSON-like documents (BSON). Instead of rows and columns like PostgreSQL, MongoDB stores flexible, schema-free documents — perfect for data that varies in shape (e.g., a notification document might have different fields per notification type). Applications connect to MongoDB for any non-relational data: user sessions, audit logs, application events, notifications, and dynamic configuration.

**Why it replaces Cosmos DB:**
Azure Cosmos DB is Microsoft's managed NoSQL service. Its most popular API is the MongoDB-compatible API — meaning most applications already use the MongoDB driver to talk to Cosmos DB. Migrating to self-hosted MongoDB Community Edition requires **only an endpoint URL change** in the application connection string. All queries, indexes, and aggregation pipelines work identically.

**Architecture per environment:**
```
Dev:      Standalone  (1 node — no HA, saves resources)
QA:       Standalone  (1 node — no HA, saves resources)
Pre-Prod: ReplicaSet  (1 Primary + 1 Secondary — HA for load testing)
Prod:     ReplicaSet  (1 Primary + 2 Secondaries — full HA, writeConcern: majority)
```

**What is stored in MongoDB (per environment):**
```
Collection: sessions
  → User login tokens, preferences (TTL: 24h auto-expire)
  → Was in Redis, but richer document structure needed

Collection: audit_logs
  → Who did what, when, from where (immutable, append-only)
  → Schema varies per action type — perfect for documents

Collection: notifications
  → Push notifications, email queue, in-app alerts
  → Rich nested structure (recipient, channels, template, payload)

Collection: config
  → Feature flags, environment-specific settings
  → Updated without redeployment

Collection: analytics
  → Pre-aggregated dashboard data (5-min snapshots)
  → Saves complex SQL queries at dashboard load time
```

**Key MongoDB features in use:**
- **ReplicaSet** — automatic failover, data redundancy, read from secondaries
- **Change Streams** — real-time event sourcing, used for live replication during migration
- **TTL indexes** — automatically expire session documents after 24 hours
- **Aggregation Pipeline** — analytics queries computed in the database, not the app
- **Atlas Migration Tool / mongodump** — official migration tool from Cosmos DB

**Connection string change (all that's needed for most apps):**
```
# Before (Azure Cosmos DB)
mongodb://<account>:<key>@<account>.mongo.cosmos.azure.com:10255/prod-cosmos?ssl=true

# After (on-prem MongoDB — same driver, same queries)
mongodb://prod_user:<vault-secret>@10.0.5.25:27017,10.0.5.26:27017,10.0.5.27:27017/prod-cosmos?replicaSet=rs-prod&tls=true
```

---

### 13. MinIO
**Category**: Storage — Object Storage
**Replaces**: Azure Blob Storage

**What it does:**
MinIO provides an S3-compatible API for storing files, documents, images, exports, and backups. Applications use the exact same S3 API calls they would use for Azure Blob — only the endpoint URL changes. A 4-node MinIO cluster stores data across all nodes with erasure coding, so even if 2 nodes fail, data is still accessible.

**Use cases:**
- Application file uploads (user documents, images)
- Report exports (CSV, PDF)
- Database backup storage (Bacula archives)
- Log archives

---

### 14. NetApp AFF A250
**Category**: Storage — Shared NFS Storage
**Replaces**: Azure Disk (Persistent Volumes) + Azure Files

**What it does:**
NetApp provides fast NFS (Network File System) storage that all Kubernetes worker nodes can mount simultaneously. When a Kubernetes pod needs persistent storage (e.g., a database data directory, a Prometheus TSDB), it gets a volume from NetApp via NFS. If a pod moves to a different node, the volume moves with it.

**Why fast storage matters:**
NetApp AFF (All-Flash FAS) uses NVMe SSDs — 300,000+ IOPS with sub-millisecond latency. This is critical for PostgreSQL WAL writes and Prometheus time-series data.

---

### 15. Prometheus
**Category**: Observability — Metrics Collection
**Replaces**: Azure Monitor (metrics)

**What it does:**
Prometheus scrapes (collects) numeric metrics from every component every 15 seconds. It stores metrics as time-series data (e.g., "CPU usage of worker-3 at 14:23:15 was 67%"). Every K8s pod, node, PostgreSQL instance, Redis node, and network device exposes a `/metrics` endpoint that Prometheus reads.

**What it monitors:**
- Kubernetes pod CPU, memory, restarts
- PostgreSQL query rate, connection count, replication lag
- Redis hit rate, memory usage, evictions
- Application request rate, error rate, response time (P50/P95/P99)
- Node disk I/O, network throughput, filesystem usage
- Palo Alto throughput, session counts

---

### 16. Grafana
**Category**: Observability — Dashboards and Alerting UI
**Replaces**: Azure Monitor Dashboards

**What it does:**
Grafana is the visual layer on top of Prometheus. It reads Prometheus data and draws graphs, charts, and tables. Operations teams use Grafana dashboards to see the current health of every system at a glance. Grafana also shows alerts — when Prometheus detects a problem, Grafana displays it prominently.

**Dashboards configured:**
- Infrastructure Overview (all nodes CPU/memory/disk)
- Kubernetes Cluster (pod counts, restarts, resource requests)
- Application Performance (request rate, error rate, latency percentiles)
- PostgreSQL HA (replication lag, connection pool, query time)
- Redis (hit rate, memory, evictions)
- Migration Progress (side-by-side Azure vs on-prem metrics)

---

### 17. Alertmanager
**Category**: Observability — Alert Routing
**Replaces**: Azure Monitor Alerts + Action Groups

**What it does:**
Alertmanager receives alerts from Prometheus and routes them to the right people via the right channel. A database failure alert goes to the DBA on-call via PagerDuty at 3am. A minor disk-space warning sends a Slack message during business hours. It deduplicates alerts (if 10 pods are down, you get 1 alert, not 10) and groups related alerts together.

---

### 18. ELK Stack (Elasticsearch + Logstash + Kibana)
**Category**: Observability — Log Management
**Replaces**: Azure Log Analytics + Azure Monitor Logs

**What it does:**
Every component (app pods, PostgreSQL, Palo Alto, F5, K8s nodes) generates log lines. ELK collects all logs centrally:
- **Filebeat** runs on every server/pod — it reads log files and ships them
- **Logstash** parses and enriches log data (e.g., extracts HTTP status codes)
- **Elasticsearch** stores and indexes logs — you can search billions of logs in milliseconds
- **Kibana** provides a web UI to search, filter, and visualise logs

**Why it beats Azure Log Analytics:**
Azure Log Analytics charges per GB ingested ($2.76/GB). ELK runs on your hardware — unlimited log retention, unlimited query volume, zero per-GB cost.

---

### 19. Jaeger
**Category**: Observability — Distributed Tracing
**Replaces**: Azure Application Insights (distributed tracing)

**What it does:**
When a user request comes in, it may touch 5-10 different services (Ingress → App Pod → Redis → PgBouncer → PostgreSQL → MinIO). Jaeger assigns a unique trace ID to the request and records exactly how long each step took. If a request is slow, Jaeger shows you exactly which service is the bottleneck.

---

### 20. HashiCorp Vault
**Category**: Security — Secrets Management
**Replaces**: Azure Key Vault

**What it does:**
Vault stores and manages secrets (passwords, API keys, certificates, encryption keys). Instead of hardcoding database passwords in application config files, pods ask Vault for a database credential at startup. Vault generates a unique, temporary credential just for that pod — it expires after 1 hour and is automatically rotated.

**Key features in use:**
- **K8s Auth**: Pods authenticate using their K8s service account — no static passwords
- **Dynamic DB credentials**: Each pod gets a unique DB username/password that expires
- **PKI Engine**: Vault issues TLS certificates for internal service-to-service encryption
- **Encryption as a Service**: Vault can encrypt/decrypt data on behalf of apps (Transit engine)

---

### 21. Bacula
**Category**: Data Protection — Traditional Backup
**Replaces**: Azure Backup

**What it does:**
Bacula runs scheduled backup jobs every night at 2 AM. It backs up PostgreSQL data directories, MinIO buckets, application configuration files, and OS-level data to the backup storage (VLAN 90). Backups are retained for 30 days, with weekly backups retained for 3 months.

**Backup schedule:**
- Full backup: Every Sunday 2 AM
- Incremental backup: Mon–Sat 2 AM
- PostgreSQL WAL archiving: Continuous (every 5 minutes — for point-in-time recovery)

---

### 22. Velero
**Category**: Data Protection — Kubernetes Backup
**Replaces**: Azure Backup for AKS

**What it does:**
While Bacula backs up raw files, Velero specifically understands Kubernetes. It backs up entire K8s namespaces — all Deployments, Services, ConfigMaps, Secrets, and PersistentVolumes in one snapshot. If a namespace is accidentally deleted or corrupted, Velero can restore it completely in minutes, including all application config and data.

---

### 23. cert-manager
**Category**: Security — TLS Certificate Automation
**Replaces**: Azure-managed certificates

**What it does:**
Every service inside Kubernetes that communicates over the network needs a TLS certificate. cert-manager automatically requests, issues, and renews these certificates. It integrates with HashiCorp Vault's PKI engine — when a new pod starts, cert-manager requests a certificate from Vault, and the pod's connections are encrypted immediately.

---

## Technology Decision Summary

```
NETWORK & SECURITY LAYER
├── Palo Alto PA-5250  → "The gate": inspect and control everything entering/leaving
├── F5 BIG-IP          → "The doorman": receive user traffic, balance to app pods
├── Cisco Nexus        → "The roads": physical network connecting all servers
└── HashiCorp Vault    → "The safe": store all secrets, rotate credentials automatically

COMPUTE LAYER
├── Kubernetes         → "The conductor": decide where apps run, heal failures, scale
├── Harbor             → "The image store": keep Docker images secure and scanned
├── ArgoCD             → "The auto-deployer": apply Git changes to K8s automatically
└── GitLab CI          → "The builder": compile, test, scan, and package code

DATA LAYER
├── PostgreSQL+Patroni → "The relational database": store and retrieve structured app data, auto-failover
├── MongoDB ReplicaSet → "The document store": store flexible NoSQL data (replaces Cosmos DB)
├── HAProxy            → "The DB traffic cop": send writes to PG primary, reads to replicas
├── PgBouncer          → "The connection recycler": prevent DB connection exhaustion
├── Redis              → "The fast memory": cache hot data so DB is not hit every time
├── MinIO              → "The file store": store uploaded files, exports, backups (S3 API)
└── NetApp AFF A250    → "The fast disk": NVMe shared storage for K8s persistent volumes

OBSERVABILITY LAYER
├── Prometheus         → "The data collector": gather numeric metrics every 15 seconds
├── Grafana            → "The dashboard": visualise metrics, show alerts
├── Alertmanager       → "The pager": route alerts to right person via right channel
├── ELK Stack          → "The log search engine": centralise and search all log data
└── Jaeger             → "The tracer": track a request across all microservices

BACKUP & RECOVERY
├── Bacula             → "The nightly backup": traditional file-level backup with retention
└── Velero             → "The K8s snapshot": backup and restore entire K8s namespaces
```

---

**Document Version**: 1.0 | **Date**: July 2026 | **Classification**: Internal Use Only
