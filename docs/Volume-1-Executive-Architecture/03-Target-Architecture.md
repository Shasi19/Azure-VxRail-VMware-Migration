# Volume 1: Executive & Solution Architecture
## Chapter 3: Target On-Premises Architecture

---

## Target Infrastructure Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                  ON-PREMISES INFRASTRUCTURE                      │
│                       (Target State)                             │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  TIER 1: NETWORK & SECURITY                              │  │
│  │  ├─ Firewall (Palo Alto Networks)                        │  │
│  │  ├─ Load Balancer (F5 BIG-IP) - HA Active/Passive       │  │
│  │  ├─ Virtual IP (VIP) 10.0.1.10                          │  │
│  │  ├─ Core Switch (Cisco Nexus)                           │  │
│  │  └─ Access Switches (x3)                                │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           │                                     │
│  ┌──────────────────────┬─▼─┬──────────────────────────────┐   │
│  │                      │   │                              │   │
│  ▼                      ▼   ▼                              ▼   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  TIER 2: VIRTUALIZATION                                 │  │
│  │  ├─ VMware vSphere ESXi Cluster (4 Nodes)              │  │
│  │  ├─ vCenter Server                                      │  │
│  │  ├─ HA/DRS Enabled                                      │  │
│  │  ├─ Shared Storage (SAN)                                │  │
│  │  └─ Backup Network (Isolated VLAN)                      │  │
│  └───────────────────────────────────────────────────────────┘  │
│         │            │            │            │                │
│         ▼            ▼            ▼            ▼                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  TIER 3: CONTAINER ORCHESTRATION                        │  │
│  │  ├─ Kubernetes Cluster (Multi-node)                     │  │
│  │  │  ├─ Control Plane (3 nodes)                          │  │
│  │  │  ├─ Worker Nodes (6 nodes)                           │  │
│  │  │  ├─ CNI: Calico                                      │  │
│  │  │  ├─ Load Balancer: MetalLB                           │  │
│  │  │  ├─ Ingress Controller: NGINX                        │  │
│  │  │  ├─ Storage: Persistent Volumes                      │  │
│  │  │  └─ Registry: Harbor (Private)                       │  │
│  │  ├─ Container Runtime: Docker/containerd                │  │
│  │  ├─ Orchestration: Kubernetes                           │  │
│  │  └─ Package Manager: Helm                               │  │
│  └──────────────────────────────────────────────────────────┘  │
│         │            │            │            │                │
│  ┌──────┴────────────┴────────────┴────────────┴──────────────┐ │
│  │  TIER 4: DATA LAYER                                      │ │
│  │  ├─ PostgreSQL Cluster (HA)                             │ │
│  │  │  ├─ Primary: 10.0.5.1                                │ │
│  │  │  ├─ Standby: 10.0.5.2                                │ │
│  │  │  ├─ Streaming Replication                            │ │
│  │  │  └─ Automated Failover (Patroni)                     │ │
│  │  ├─ Redis Cluster (Cache)                               │ │
│  │  ├─ Storage: NAS/SAN (10TB)                             │ │
│  │  └─ Backup Server (Bacula)                              │ │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  TIER 5: MONITORING & OBSERVABILITY                     │  │
│  │  ├─ Prometheus (Metrics)                                │  │
│  │  ├─ Grafana (Visualization)                             │  │
│  │  ├─ Elasticsearch (Logs)                                │  │
│  │  ├─ Logstash (Processing)                               │  │
│  │  ├─ Kibana (Analysis)                                   │  │
│  │  ├─ Alertmanager (Notifications)                        │  │
│  │  └─ Distributed Tracing: Jaeger                         │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  TIER 6: MANAGEMENT & SECURITY                          │  │
│  │  ├─ HashiCorp Vault (Secrets)                           │  │
│  │  ├─ LDAP/AD Integration                                 │  │
│  │  ├─ GitOps: ArgoCD                                      │  │
│  │  ├─ CI/CD: GitLab/Jenkins                               │  │
│  │  └─ Configuration Management: Ansible                   │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## Detailed Architecture Components

### TIER 1: Network & Security Layer

#### Firewall (Palo Alto Networks)

```
Configuration:
├─ Model: Palo Alto Networks PA-5250
├─ Throughput: 100 Gbps
├─ Concurrent Sessions: 1 Million
├─ Network Interfaces: 10 x 10GbE
├─ Redundancy: Active-Active (cluster)
├─ Failover: Stateful (<1 sec)
├─ Threat Prevention: Enabled
└─ DPI: Deep Packet Inspection

Security Features:
├─ Next-Generation Firewall (NGFW)
├─ Intrusion Prevention System (IPS)
├─ Anti-Virus & Anti-Malware
├─ Web Filtering
├─ Application Control
├─ SSL Inspection
└─ Advanced Threat Protection

SecurityZones:
├─ External (Internet)
├─ DMZ
├─ Internal
├─ Management
├─ Storage
└─ Database
```

#### Load Balancer (F5 BIG-IP)

```
Configuration:
├─ Model: F5 BIG-IP 5200 (2x for HA)
├─ Throughput: 1.6 Tbps
├─ Concurrent Connections: 100 Million
├─ Virtual IP (VIP): 10.0.1.10
├─ Active-Passive: With VRRP
├─ Failover Time: <3 seconds
├─ Health Check: Every 5 seconds
└─ Connection Persistence: 30 minutes

Load Balancing Methods:
├─ Round Robin
├─ Least Connections
├─ Weighted Round Robin
├─ Source IP Hash
└─ Least Response Time

Advanced Features:
├─ SSL/TLS Offloading
├─ Cookie Insertion
├─ URI Rewriting
├─ Request Rate Limiting
├─ Connection Rate Limiting
├─ iRules (Custom Logic)
└─ One Connect (Connection Reuse)

Backend Pool:
├─ K8s Ingress: 10.0.2.1:8080
├─ K8s Ingress: 10.0.2.2:8080
├─ K8s Ingress: 10.0.2.3:8080
└─ Health Check: /health (HTTP 200)
```

#### Network Switches

```
Core Switch (Cisco Nexus 9372PX):
├─ Ports: 72 x 100G Ethernet
├─ Throughput: 14.4 Tbps
├─ Latency: <1 microsecond
├─ VLAN Support: 4094
├─ Routing: L3 multicast, ECMP
├─ Redundancy: Dual supervisors
├─ Backup Power: Internal UPS
└─ Management: NX-OS CLI/Web UI

Access Switches (Cisco Nexus 9348 x 3):
├─ Ports: 48 x 100G + 8 x 400G
├─ Throughput: 25.6 Tbps
├─ PoE: 1,040W (optional)
├─ Stacking: Supported
├─ Management: In-band/Out-of-band
└─ Features: QoS, VLAN, Spanning Tree
```

### TIER 2: Virtualization Layer

#### VMware vSphere

```
Environment:
├─ vSphere Version: 8.0.x
├─ vCenter Server: 1 instance (HA)
├─ ESXi Hosts: 4 nodes (2-socket, 18-core)
├─ Cluster: prod-cluster (HA enabled)
├─ Resource Pool: Default + Custom
└─ vSAN: 4-node cluster, 2-node mirror

Key Features:
├─ High Availability (HA)
│  ├─ Restart Priority: High/Medium/Low
│  ├─ Host Isolation: PowerOff
│  ├─ Admission Control: Enabled
│  └─ Isolation Address: Default gateway
├─ Distributed Resource Scheduler (DRS)
│  ├─ Load Balancing: Aggressive
│  ├─ vMotion Automation: Enabled
│  ├─ Power Management: Disabled (always-on)
│  └─ VM/Host Affinity: Set per VM
├─ vMotion
│  ├─ Network: 10Gbps dedicated
│  ├─ Encryption: Enabled
│  └─ Multiple NICs: 2 (failover)
└─ Storage vMotion
   ├─ Datastore: Mirrored VMFS
   └─ Performance: Throttled to 100 MB/s

vCenter Configuration:
├─ Linked Mode: Not enabled
├─ PSC: Embedded
├─ Database: vCenter DB
├─ Backup: Weekly incremental
└─ Replication: None (single instance)

Datastore Configuration:
├─ Primary: VMFS 8.0 (SAN)
│  ├─ Capacity: 20 TB
│  ├─ RAID: RAID 10
│  ├─ Redundancy: Mirrored
│  └─ Latency: <10ms
├─ Secondary: vSAN (cluster)
│  ├─ Capacity: 10 TB
│  ├─ Reliability: RAID 1
│  └─ Tier 1: SSD (cache)
└─ Backup: Separate NAS
   ├─ Capacity: 10 TB
   └─ Retention: 30 days
```

### TIER 3: Kubernetes Cluster

#### Kubernetes Architecture

```
Cluster Overview:
├─ K8s Version: 1.29.x
├─ Deployment: Kubeadm (HA)
├─ Control Plane: 3 nodes (stacked etcd)
├─ Worker Nodes: 6 nodes
├─ Pod CIDR: 10.244.0.0/16
├─ Service CIDR: 10.96.0.0/12
└─ Total Nodes: 9 (3 control + 6 workers)

Control Plane (3 nodes, each):
├─ API Server
│  ├─ Bind Port: 6443
│  ├─ Audit Logging: Enabled
│  └─ Rate Limiting: 200 req/sec
├─ Etcd
│  ├─ Data Directory: /var/lib/etcd
│  ├─ Snapshots: Hourly
│  ├─ Defrag: Daily
│  └─ Backup: Offsite daily
├─ Scheduler
│  ├─ Pod Affinity: Enabled
│  ├─ Taints & Tolerations: Configured
│  └─ Preemption: Enabled
└─ Controller Manager
   ├─ Replicas: 3 (HA)
   └─ Sync Period: 30 seconds

Worker Nodes (6 nodes, each):
├─ kubelet
│  ├─ Max Pods: 110
│  ├─ Resource Reservation: Set
│  └─ Eviction Threshold: 5%
├─ kube-proxy
│  ├─ Mode: iptables
│  └─ Sync Period: 30 seconds
├─ Container Runtime: containerd
│  ├─ CRI Plugin: Enabled
│  └─ Storage Driver: snapshots
└─ cAdvisor
   ├─ Metrics Port: 10250
   └─ Monitoring: Enabled

Networking (CNI: Calico):
├─ Plugin: Calico v3.x
├─ Backend: Bird (BGP)
├─ IP-in-IP: Enabled
├─ Network Policies: Enforced
├─ Service Mesh: Istio (optional)
└─ MetalLB Load Balancer:
   ├─ Protocol: BGP
   ├─ Address Pool: 10.0.1.20-10.0.1.50
   └─ Announced: Via BGP

Ingress Controller (NGINX):
├─ Replicas: 3
├─ Service Type: LoadBalancer (MetalLB)
├─ SSL: Enabled (cert-manager)
├─ Rate Limiting: Per-IP
├─ WAF: ModSecurity (optional)
└─ Logging: Stdout + syslog

Storage:
├─ Persistent Volumes: NFS backend
├─ Dynamic Provisioning: StorageClass
├─ CSI Driver: NFS CSI
├─ Snapshots: Supported
└─ Backup: Velero integration

Namespaces (Logical Isolation):
├─ default
├─ kube-system
├─ kube-node-lease
├─ kube-public
├─ production
├─ preprod
├─ development
├─ monitoring
└─ ingress-nginx

Resource Quotas & Limits:
├─ Production Namespace:
│  ├─ CPU Limit: 40 cores
│  ├─ Memory Limit: 128 GB
│  ├─ Storage Limit: 500 GB
│  └─ Pod Count Limit: 200
├─ PreProd Namespace:
│  ├─ CPU Limit: 20 cores
│  ├─ Memory Limit: 64 GB
│  ├─ Storage Limit: 250 GB
│  └─ Pod Count Limit: 100
└─ Development Namespace:
   ├─ CPU Limit: 10 cores
   ├─ Memory Limit: 32 GB
   ├─ Storage Limit: 100 GB
   └─ Pod Count Limit: 50
```

### TIER 4: Data Layer

#### PostgreSQL HA Cluster

```
Configuration:
├─ PostgreSQL Version: 15.x
├─ High Availability: Patroni + etcd
├─ Replication: Streaming
├─ Failover: Automatic (<30 seconds)
├─ Primary: 10.0.5.1 (32-core, 128GB RAM)
├─ Standby: 10.0.5.2 (32-core, 128GB RAM)
└─ Backup: Separate machine

Database Specifications:
├─ Total Size: 2 TB
├─ Data Directory: /var/lib/postgresql
├─ WAL Archive: NFS mounted
├─ Backup Directory: /backup/postgres
├─ Transaction Log: 64 GB/day
└─ Max Connections: 1000

Performance Tuning:
├─ shared_buffers: 32 GB (25% RAM)
├─ effective_cache_size: 96 GB (75% RAM)
├─ work_mem: 100 MB (per sort operation)
├─ maintenance_work_mem: 4 GB
├─ random_page_cost: 1.1 (SSD)
├─ effective_io_concurrency: 200
├─ max_wal_size: 64 GB
└─ checkpoint_completion_target: 0.9

Security:
├─ SSL/TLS: Required
├─ Port: 5432
├─ Authentication: md5 + scram-sha-256
├─ Row Level Security: Enabled
├─ Audit Logging: Enabled
└─ Encrypted Replication: Yes

Backup:
├─ Full Backup: Weekly (Sunday 2 AM)
├─ Incremental: Daily (2 AM)
├─ Retention: 30 days
├─ Backup Type: pg_basebackup + WAL archive
├─ Backup Speed: 50 MB/sec (throttled)
└─ Restore Time: <15 minutes

Monitoring:
├─ Tool: Prometheus + Custom Exporter
├─ Metrics: 50+
├─ Alerts: 20+
├─ Dashboard: Grafana
└─ Slow Query Log: Enabled (>1000ms)
```

#### Redis Cache Cluster

```
Configuration:
├─ Redis Version: 7.x
├─ Deployment: Sentinel + Cluster
├─ Nodes: 6 (3 masters, 3 replicas)
├─ Mode: Cluster
├─ Replication: 1 (high reliability)
├─ Total Memory: 48 GB
└─ RDB + AOF: Both enabled

Memory Allocation:
├─ Session Storage: 10 GB
├─ Cache Layer: 20 GB
├─ Queue: 10 GB
├─ Temporary Data: 8 GB
└─ Reserve: Unused

Persistence:
├─ RDB:
│  ├─ Frequency: Every 60 seconds or 10000 changes
│  ├─ Compression: Enabled
│  └─ Snapshots: 7 retained
├─ AOF:
│  ├─ Rewrite: When 100% growth
│  ├─ Fsync: Every second
│  └─ Compression: Enabled
└─ Backup: Daily to NAS

Replication:
├─ Master-Replica: Asynchronous
├─ Replication Backlog: 1 MB
├─ Timeout: 60 seconds
└─ Retry: Automatic

Eviction Policy:
├─ Policy: allkeys-lru (Least Recently Used)
├─ Samples: 5 (approximate)
├─ Trigger: At 80% memory
└─ Max Memory: 48 GB
```

#### Storage Infrastructure

```
NAS/SAN Configuration:
├─ Technology: NAS (Network Attached Storage)
├─ Capacity: 20 TB total
├─ RAID: RAID 10 (performance + redundancy)
├─ Controller: Redundant
├─ Network: 10GbE (dual)
├─ Protocol: NFS v4
├─ Performance: 10,000 IOPS
└─ RPO: <1 hour

Storage Breakdown:
├─ Kubernetes PV: 5 TB
├─ PostgreSQL Backups: 5 TB
├─ Application Data: 5 TB
├─ Logs: 2 TB
├─ Monitoring: 2 TB
└─ Reserve: 1 TB

Backup Storage:
├─ NAS Mount: /backup
├─ Capacity: 5 TB
├─ Redundancy: Full replication
├─ Retention: 30 days
├─ Protocol: NFS
└─ Encryption: At-rest (AES-256)

Exports:
├─ /k8s-pv (Kubernetes)
├─ /pg-backup (PostgreSQL)
├─ /app-data (Application)
├─ /logs (Centralized logs)
└─ /monitoring (Prometheus/Grafana)
```

### TIER 5: Monitoring & Observability

#### Prometheus Stack

```
Prometheus Configuration:
├─ Version: 2.x
├─ Scrape Interval: 15 seconds
├─ Evaluation Interval: 15 seconds
├─ Retention: 30 days
├─ Storage: 100 GB SSD
├─ Memory: 16 GB
└─ High Availability: 2 instances

Metrics Collection:
├─ Node Exporter: All hosts
├─ cAdvisor: All container hosts
├─ Kube-state-metrics: K8s clusters
├─ PostgreSQL Exporter: Databases
├─ Redis Exporter: Cache
├─ Custom Exporters: Application-specific
└─ Total Metrics: 1 million+

Alert Rules:
├─ Infrastructure Alerts: 30+
├─ Application Alerts: 20+
├─ Database Alerts: 15+
├─ Network Alerts: 10+
└─ Total Active Alerts: 75+
```

#### Grafana Dashboards

```
Dashboards:
├─ System Overview
│  ├─ CPU Usage
│  ├─ Memory Usage
│  ├─ Disk I/O
│  ├─ Network Traffic
│  └─ Temperature (if available)
├─ Kubernetes Cluster
│  ├─ Node Status
│  ├─ Pod Status
│  ├─ Resource Usage
│  ├─ Network Policies
│  └─ Persistent Volumes
├─ Application Performance
│  ├─ Request Rate
│  ├─ Response Time
│  ├─ Error Rate
│  ├─ Throughput
│  └─ Queue Depth
├─ Database Performance
│  ├─ Query Performance
│  ├─ Connection Count
│  ├─ Replication Lag
│  ├─ Backup Status
│  └─ Index Usage
└─ Business Metrics
   ├─ User Count
   ├─ Transaction Rate
   ├─ Revenue (if applicable)
   └─ SLA Compliance
```

#### ELK Stack

```
Elasticsearch:
├─ Version: 8.x
├─ Nodes: 3 (dedicated master, data, ingest)
├─ Storage: 2 TB
├─ Replication: 1
├─ Shards: 5 (index level)
└─ Retention: 30 days

Logstash:
├─ Instances: 2 (HA)
├─ Workers: 4 per instance
├─ Batch Size: 1000
├─ Inputs: Filebeat, syslog, API
├─ Filters: 50+ custom
└─ Outputs: Elasticsearch

Kibana:
├─ Instances: 1 (HA with load balancer)
├─ Visualization: 100+
├─ Alerting: Enabled
├─ Machine Learning: Basic
└─ Reporting: Daily, Weekly

Log Types Collected:
├─ Application Logs
├─ System Logs
├─ Network Logs
├─ Security Logs
├─ Audit Logs
├─ API Logs
├─ Database Logs
└─ Container Logs
```

### TIER 6: Management & Security

#### HashiCorp Vault

```
Configuration:
├─ Version: 1.x
├─ Deployment: HA (3 nodes)
├─ Storage: Raft (integrated)
├─ Seal: Auto-unseal via cloud KMS
├─ Audit Logging: Enabled
├─ TLS: Required
└─ High Availability: Yes

Secrets Stored:
├─ Database Credentials
├─ API Keys
├─ SSL/TLS Certificates
├─ SSH Keys
├─ Encryption Keys
├─ Service Credentials
└─ Third-party Tokens

Auth Methods:
├─ LDAP/AD
├─ Kubernetes
├─ JWT/OIDC
├─ TLS Certificate
└─ AppRole

Policies:
├─ Admin Policy
├─ DevOps Policy
├─ Application Policy
├─ Database Policy
└─ Audit Policy
```

#### Identity & Access Management

```
LDAP/Active Directory Integration:
├─ Primary: On-premises AD
├─ Secondary: LDAP Server (backup)
├─ Sync: Real-time
├─ Groups: 50+
└─ Users: Managed centrally

Authentication:
├─ Multi-Factor Auth: TOTP + Push
├─ SSO: SAML 2.0
├─ Session Timeout: 8 hours
├─ Password Policy: Complex
└─ Account Lockout: After 5 failed attempts
```

---

## Network Architecture

### VLAN Structure

```
VLAN    Subnet              Purpose                      Hosts
────────────────────────────────────────────────────────────────
VLAN 10 10.0.10.0/24       Management                   50
VLAN 20 10.0.20.0/24       DMZ/Load Balancer            20
VLAN 30 10.0.30.0/24       Kubernetes/Containers       100
VLAN 40 10.0.40.0/24       Storage/NAS                  20
VLAN 50 10.0.50.0/24       Database                     20
VLAN 60 10.0.60.0/24       Monitoring                   30
VLAN 70 10.0.70.0/24       Backup/DR                    20
VLAN 80 10.0.80.0/24       Guest/IoT                    50
────────────────────────────────────────────────────────────────
Total Hosts: ~310
```

### IP Address Allocation

```
Network Summary:
├─ Core Network: 10.0.0.0/16
├─ Total Subnets: 8 (/24 each)
├─ Total Addresses: 2,048
├─ Usable Addresses: 1,520 (excluding network/broadcast)
├─ Currently Used: 310 (15% utilization)
└─ Growth Buffer: 75% remaining

DNS Configuration:
├─ Primary DNS: 10.0.10.1 (BIND9)
├─ Secondary DNS: 10.0.10.2 (BIND9 slave)
├─ External DNS: 8.8.8.8, 8.8.4.4
└─ Search Domain: company.internal

DHCP Configuration:
├─ DHCP Server: 10.0.10.3
├─ Pool: 10.0.30.100 - 10.0.30.200 (K8s only)
├─ Lease Time: 24 hours
└─ Reservation: All servers (static)
```

---

## Security Architecture

### Defense in Depth

```
Layer 1: Perimeter
├─ Firewall: Palo Alto
├─ DDoS Protection: ISP-level
├─ IDS/IPS: Enabled
└─ WAF: Yes

Layer 2: Network
├─ Network Segmentation: VLANs
├─ Access Lists: Per VLAN
├─ VPN: Site-to-site encrypted
└─ Encryption: IPsec

Layer 3: Host
├─ OS Hardening: CIS benchmarks
├─ Firewall: UFW/firewalld
├─ SELinux: Enforcing (production)
├─ Intrusion Detection: AIDE
└─ Log Aggregation: Syslog

Layer 4: Application
├─ Input Validation: Strict
├─ Output Encoding: UTF-8
├─ SQL Injection Prevention: Parameterized queries
├─ XSS Prevention: Content Security Policy
├─ CSRF Protection: Token-based
└─ Security Headers: Complete set

Layer 5: Data
├─ Encryption: AES-256 (at-rest)
├─ TLS 1.3: In-transit
├─ Key Management: Vault
├─ Access Control: RBAC
├─ Audit Logging: Immutable
└─ Data Classification: Implemented
```

---

## Conclusion

The target on-premises architecture provides a modern, scalable, highly available infrastructure that meets all current and projected business requirements. It offers superior operational control, cost efficiency, and flexibility compared to the current Azure deployment while maintaining or exceeding performance and availability standards.

The architecture is designed to support 10,000 concurrent users, process 10,000 requests per second, and maintain 99.99% availability through strategic use of redundancy, automation, and modern cloud-native technologies on premises.

---

**Document Version**: 1.0  
**Date**: January 2024  
**Classification**: Internal Use Only