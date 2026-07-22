# Volume 2: Migration Strategy
## Chapter 2: Phase-by-Phase Implementation Guide

---

## Migration Phases Overview

```mermaid
gantt
    title Azure to On-Premises Migration  -  26-Week Project Plan
    dateFormat  YYYY-MM-DD
    axisFormat  Week %W

    section Phase 1: Procurement & Planning
    Hardware Vendor Selection          :done,    p1a, 2024-01-01, 7d
    Hardware Procurement               :active,  p1b, 2024-01-08, 21d
    Software Licensing                 :         p1c, 2024-01-01, 14d
    Datacenter Site Assessment         :done,    p1d, 2024-01-01, 7d
    Network Design & Diagrams          :         p1e, 2024-01-08, 14d
    Kickoff Meeting                    :milestone, 2024-01-01, 0d

    section Phase 2: Infrastructure Setup
    Rack & Stack Hardware              :         p2a, 2024-01-29, 7d
    Power & Cooling Setup              :         p2b, 2024-01-29, 7d
    Network Switch Configuration       :         p2c, 2024-02-05, 7d
    Firewall Deployment                :         p2d, 2024-02-05, 7d
    VMware vSphere Install             :         p2e, 2024-02-12, 7d
    Storage (SAN/NAS) Setup            :         p2f, 2024-02-12, 7d
    Phase 2 Checkpoint                 :milestone, 2024-02-26, 0d

    section Phase 3: Middleware
    Load Balancer (F5) Config          :         p3a, 2024-02-26, 7d
    DNS & NTP Setup                    :         p3b, 2024-02-26, 7d
    HashiCorp Vault Deploy             :         p3c, 2024-03-04, 7d
    Harbor Registry Deploy             :         p3d, 2024-03-04, 7d
    MinIO Object Storage               :         p3e, 2024-03-11, 7d
    Redis Cluster Setup                :         p3f, 2024-03-11, 7d
    Phase 3 Checkpoint                 :milestone, 2024-03-25, 0d

    section Phase 4: Kubernetes
    K8s Control Plane Setup            :         p4a, 2024-03-25, 7d
    K8s Worker Nodes Join              :         p4b, 2024-04-01, 7d
    CNI (Calico) + MetalLB             :         p4c, 2024-04-01, 7d
    NGINX Ingress Controller           :         p4d, 2024-04-08, 7d
    ArgoCD + Monitoring Stack          :         p4e, 2024-04-08, 7d
    App Containerization               :         p4f, 2024-04-15, 7d
    Phase 4 Checkpoint                 :milestone, 2024-04-22, 0d

    section Phase 5: Testing & Validation
    Functional Testing                 :         p5a, 2024-04-22, 7d
    Performance / Load Testing         :         p5b, 2024-04-29, 7d
    Security / Pen Testing             :         p5c, 2024-05-06, 7d
    Disaster Recovery Drill            :         p5d, 2024-05-13, 7d
    UAT Sign-off                       :milestone, 2024-05-20, 0d

    section Phase 6: Go-Live
    Pre-cutover Freeze                 :crit,    p6a, 2024-05-20, 3d
    DNS Cutover                        :crit,    p6b, 2024-05-23, 1d
    Database Switch                    :crit,    p6c, 2024-05-23, 1d
    Azure Decommission Begin           :         p6d, 2024-05-27, 7d
    Go-Live                            :milestone, 2024-05-24, 0d

    section Phase 7: Stabilization
    24/7 Hypercare Support             :         p7a, 2024-05-27, 14d
    Performance Tuning                 :         p7b, 2024-06-10, 7d
    Documentation Finalization         :         p7c, 2024-06-10, 7d
    Project Closure                    :milestone, 2024-06-24, 0d
```

---

## Phase 1: Procurement & Planning (Weeks 1–4)

### Objectives
- Finalize hardware specifications and place orders
- Complete network and architecture design
- Prepare datacenter space

### Step-by-Step Actions

```
WEEK 1:
  ┌─ Day 1-2: Project Kickoff
  │   ├─ [ ] Assemble project team
  │   ├─ [ ] Confirm stakeholder roles
  │   ├─ [ ] Review architecture documents
  │   └─ [ ] Set up project tracking (Jira/Confluence)
  │
  ├─ Day 3-5: Site Assessment
  │   ├─ [ ] Survey data center space (rack units available)
  │   ├─ [ ] Confirm power capacity (40kW target)
  │   ├─ [ ] Confirm cooling capacity
  │   └─ [ ] Network patching plan

WEEK 2:
  ├─ Hardware Vendor RFP
  │   ├─ [ ] Issue RFPs to 3+ hardware vendors
  │   ├─ [ ] Evaluate VMware / Cisco / F5 / Palo Alto quotes
  │   ├─ [ ] Review lead times (4-8 weeks typical)
  │   └─ [ ] Select vendors and place orders

WEEK 3:
  ├─ Software Licensing
  │   ├─ [ ] VMware vSphere 8 Enterprise Plus licenses
  │   ├─ [ ] F5 BIG-IP LTM + ASM licenses
  │   ├─ [ ] Palo Alto Threat Prevention subscription
  │   ├─ [ ] RedHat or Ubuntu support subscriptions
  │   └─ [ ] HashiCorp Vault Enterprise (if needed)

WEEK 4:
  └─ Architecture Finalization
      ├─ [ ] IP addressing scheme approved
      ├─ [ ] VLAN design sign-off
      ├─ [ ] DNS naming convention established
      ├─ [ ] Security zones defined
      └─ [ ] Phase 2 runbook prepared
```

### Hardware Bill of Materials

```
┌──────────────────────────────────────────────────────────────────────┐
│                    HARDWARE PROCUREMENT LIST                          │
├──────────────────────┬──────────────┬─────────┬──────────────────────┤
│  Component           │  Model       │  Qty    │  Est. Cost           │
├──────────────────────┼──────────────┼─────────┼──────────────────────┤
│  Compute Servers     │  Dell R750   │  6      │  $300,000            │
│  (K8s Nodes)         │  2x Xeon     │         │                      │
│                      │  28-core     │         │                      │
│                      │  512GB RAM   │         │                      │
├──────────────────────┼──────────────┼─────────┼──────────────────────┤
│  Database Servers    │  Dell R750   │  2      │  $100,000            │
│                      │  2x Xeon     │         │                      │
│                      │  28-core     │         │                      │
│                      │  1TB RAM     │         │                      │
├──────────────────────┼──────────────┼─────────┼──────────────────────┤
│  Storage (NAS)       │  NetApp AFF  │  1      │  $150,000            │
│                      │  A250        │         │                      │
│                      │  10TB usable │         │                      │
├──────────────────────┼──────────────┼─────────┼──────────────────────┤
│  Load Balancer       │  F5 BIG-IP   │  2      │  $80,000             │
│                      │  5200        │  (HA)   │                      │
├──────────────────────┼──────────────┼─────────┼──────────────────────┤
│  Firewall            │  Palo Alto   │  2      │  $120,000            │
│                      │  PA-5250     │  (HA)   │                      │
├──────────────────────┼──────────────┼─────────┼──────────────────────┤
│  Core Switch         │  Cisco Nexus │  2      │  $80,000             │
│                      │  9372PX      │  (VPC)  │                      │
├──────────────────────┼──────────────┼─────────┼──────────────────────┤
│  Access Switches     │  Cisco Nexus │  4      │  $40,000             │
│                      │  9348GC-FXP  │         │                      │
├──────────────────────┼──────────────┼─────────┼──────────────────────┤
│  UPS Systems         │  APC Smart   │  2      │  $30,000             │
│                      │  UPS 20kVA   │         │                      │
├──────────────────────┼──────────────┼─────────┼──────────────────────┤
│  KVM / Crash Cart    │  Raritan     │  1      │  $5,000              │
├──────────────────────┼──────────────┼─────────┼──────────────────────┤
│  Cabling             │  Cat6A/Fiber │  Bulk   │  $15,000             │
├──────────────────────┼──────────────┼─────────┼──────────────────────┤
│                      │  TOTAL       │         │  ~$920,000           │
└──────────────────────┴──────────────┴─────────┴──────────────────────┘
```

---

## Phase 2: Infrastructure Setup (Weeks 5–8)

### Network Topology Setup

```mermaid
flowchart TD
    subgraph DC["Data Center Physical Setup"]
        ISP1[ISP Link 1\n1Gbps Primary] & ISP2[ISP Link 2\n1Gbps Backup]
        FW1[Palo Alto FW-1\nActive]
        FW2[Palo Alto FW-2\nPassive]
        CS1[Cisco Nexus Core-1\nVPC Primary]
        CS2[Cisco Nexus Core-2\nVPC Secondary]
        AS1[Access Switch 1] & AS2[Access Switch 2] & AS3[Access Switch 3]
        UPS1[UPS-1 20kVA] & UPS2[UPS-2 20kVA]
    end

    ISP1 & ISP2 --> FW1
    FW1 <-->|HA Sync| FW2
    FW1 & FW2 --> CS1 & CS2
    CS1 <-->|VPC Link| CS2
    CS1 & CS2 --> AS1 & AS2 & AS3

    style DC fill:#f0f8ff
```

### Step-by-Step Infrastructure Setup

```
WEEK 5: Physical Installation
  ├─ [ ] Rack and cable all servers
  ├─ [ ] Connect UPS systems
  ├─ [ ] Cable fiber/copper between switches
  ├─ [ ] Verify power distribution
  └─ [ ] Label all cables (both ends)

WEEK 6: Network Baseline
  ├─ Firewall (Palo Alto PA-5250)
  │   ├─ [ ] Initial bootstrap via console
  │   ├─ [ ] Upload license & update PAN-OS
  │   ├─ [ ] Configure HA (Active/Passive)
  │   ├─ [ ] Create security zones
  │   ├─ [ ] Configure NAT/PAT for internet
  │   └─ [ ] Enable Threat Prevention profiles
  │
  ├─ Core Switches (Cisco Nexus)
  │   ├─ [ ] NX-OS initial setup
  │   ├─ [ ] Configure VPC (Virtual Port Channel)
  │   ├─ [ ] Create VLANs 10-90
  │   ├─ [ ] Configure trunk ports to access switches
  │   └─ [ ] Enable OSPF for L3 routing
  │
  └─ Access Switches
      ├─ [ ] Configure uplinks to core (LACP)
      ├─ [ ] Assign VLANs per port group
      ├─ [ ] Configure STP (Rapid PVST+)
      └─ [ ] Verify connectivity

WEEK 7: VMware vSphere
  ├─ [ ] Install ESXi 8 on all 6 servers
  ├─ [ ] Deploy vCenter Server Appliance
  ├─ [ ] Create datacenter and cluster objects
  ├─ [ ] Configure shared storage (NFS/iSCSI)
  ├─ [ ] Enable HA + DRS on cluster
  ├─ [ ] Configure distributed virtual switch
  └─ [ ] Validate vMotion between hosts

WEEK 8: Storage & Baseline VMs
  ├─ NetApp NAS Setup
  │   ├─ [ ] Initialize ONTAP cluster
  │   ├─ [ ] Create SVMs for NFS and iSCSI
  │   ├─ [ ] Create volumes: k8s-pv, postgres, backup
  │   └─ [ ] Configure snapshots policy
  │
  └─ Baseline VMs
      ├─ [ ] Deploy jump server (bastion host)
      ├─ [ ] Deploy LDAP/AD server
      ├─ [ ] Deploy internal DNS (BIND9)
      ├─ [ ] Deploy NTP server
      └─ [ ] Validate all VMs accessible
```

---

## Phase 3: Middleware Deployment (Weeks 9–12)

```
WEEK 9: Load Balancer & Secrets
  ├─ F5 BIG-IP Setup
  │   ├─ [ ] Initial F5 bootstrap (management IP)
  │   ├─ [ ] Configure HA sync between F5-1 and F5-2
  │   ├─ [ ] Upload SSL certificates from Azure Key Vault
  │   ├─ [ ] Create Virtual Server VIP: 10.0.2.10:443
  │   ├─ [ ] Create backend pool (K8s ingress IPs)
  │   ├─ [ ] Configure health monitor (/health HTTP 200)
  │   ├─ [ ] Enable SSL offloading
  │   └─ [ ] Test failover between F5-1 and F5-2
  │
  └─ HashiCorp Vault
      ├─ [ ] Deploy Vault cluster (3 nodes for HA)
      ├─ [ ] Initialize and unseal Vault
      ├─ [ ] Configure LDAP authentication backend
      ├─ [ ] Create secret engines: kv, pki, database
      ├─ [ ] Migrate secrets from Azure Key Vault
      └─ [ ] Configure Vault Agent for K8s injection

WEEK 10: Container Registry & Object Storage
  ├─ Harbor Registry
  │   ├─ [ ] Deploy Harbor on VM or K8s
  │   ├─ [ ] Configure LDAP authentication
  │   ├─ [ ] Set up project: production, preprod
  │   ├─ [ ] Configure vulnerability scanning (Trivy)
  │   └─ [ ] Pull and push Azure images to Harbor
  │
  └─ MinIO Object Storage (Azure Blob replacement)
      ├─ [ ] Deploy MinIO distributed (4-node)
      ├─ [ ] Create buckets: app-data, backups, logs
      ├─ [ ] Configure access keys / service accounts
      ├─ [ ] Set lifecycle policies (30-day expiry for logs)
      └─ [ ] Begin data sync from Azure Storage

WEEK 11: Cache & Queue
  ├─ Redis Cluster
  │   ├─ [ ] Deploy 3 Redis master + 3 replica nodes
  │   ├─ [ ] Configure Redis Cluster mode
  │   ├─ [ ] Enable AOF persistence
  │   ├─ [ ] Configure TLS between nodes
  │   └─ [ ] Export and import Redis RDB from Azure
  │
  └─ Internal DNS
      ├─ [ ] Create DNS zones for on-prem domains
      ├─ [ ] Add A records for all services
      ├─ [ ] Configure split-horizon DNS
      └─ [ ] Test resolution from all VLANs

WEEK 12: Monitoring Foundation
  ├─ [ ] Deploy Prometheus server
  ├─ [ ] Deploy Grafana with LDAP auth
  ├─ [ ] Import dashboards for infrastructure
  ├─ [ ] Deploy Alertmanager with email/Slack routes
  ├─ [ ] Deploy Elasticsearch + Logstash + Kibana
  └─ [ ] Verify log ingestion from infrastructure
```

---

## Phase 4: Kubernetes Platform Build (Weeks 13–16)

```mermaid
flowchart TD
    K0([Start K8s Setup]) --> K1
    K1[Install kubeadm/kubelet/kubectl\non all 9 nodes] --> K2
    K2[Init control plane:\nkubeadm init --control-plane-endpoint\nweeks 13] --> K3
    K3[Join 2 additional masters\nfor HA control plane] --> K4
    K4[Install Calico CNI\nfor pod networking] --> K5
    K5[Join 6 worker nodes\nkubeadm join] --> K6
    K6[Deploy MetalLB\nfor LoadBalancer IPs] --> K7
    K7[Deploy NGINX\nIngress Controller] --> K8
    K8[Deploy cert-manager\nfor TLS certificates] --> K9
    K9[Deploy ArgoCD\nfor GitOps] --> K10
    K10[Deploy Prometheus\nstack on K8s] --> K11
    K11[Deploy Vault Agent\nInjector sidecar] --> K12
    K12[Deploy Harbor registry\nintegration] --> K13
    K13([K8s Platform Ready ✅])

    style K0 fill:#0078D4,color:#fff
    style K13 fill:#107C10,color:#fff
```

### Kubernetes Commands Reference

```bash
# ── STEP 1: Pre-flight on all nodes ──────────────────────────────────────
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
sudo modprobe overlay br_netfilter
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

# ── STEP 2: Install containerd ────────────────────────────────────────────
sudo apt install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd

# ── STEP 3: Install kubeadm, kubelet, kubectl ─────────────────────────────
sudo apt install -y apt-transport-https ca-certificates curl
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update && sudo apt install -y kubelet=1.29.0-1.1 kubeadm=1.29.0-1.1 kubectl=1.29.0-1.1
sudo apt-mark hold kubelet kubeadm kubectl

# ── STEP 4: Init control plane (on master-1) ─────────────────────────────
sudo kubeadm init \
  --control-plane-endpoint "k8s-api.internal:6443" \
  --pod-network-cidr "192.168.0.0/16" \
  --upload-certs \
  --kubernetes-version "v1.29.0"

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config

# ── STEP 5: Install Calico CNI ────────────────────────────────────────────
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.0/manifests/tigera-operator.yaml
kubectl apply -f - <<EOF
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: 192.168.0.0/16
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
EOF

# ── STEP 6: Install MetalLB ───────────────────────────────────────────────
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml
kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: onprem-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.0.2.200-10.0.2.220
EOF

# ── STEP 7: Install NGINX Ingress ─────────────────────────────────────────
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer

# ── STEP 8: Install cert-manager ─────────────────────────────────────────
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set installCRDs=true

# ── STEP 9: Install ArgoCD ────────────────────────────────────────────────
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

---

## Phase 5: Testing & Validation (Weeks 17–20)

```mermaid
flowchart LR
    subgraph FT["Functional Testing (Week 17)"]
        F1[App Smoke Tests] --> F2[API Endpoint Tests]
        F2 --> F3[DB CRUD Validation]
        F3 --> F4[Auth Flow Tests]
    end

    subgraph PT["Performance Testing (Week 18)"]
        P1[Baseline Load Test\n1000 users] --> P2[Peak Load Test\n10000 users]
        P2 --> P3[Stress Test\n150% capacity]
        P3 --> P4[Soak Test\n24 hours sustained]
    end

    subgraph ST["Security Testing (Week 19)"]
        S1[Vulnerability Scan\nNessus/OpenVAS] --> S2[Penetration Test]
        S2 --> S3[OWASP ZAP\nWeb App Scan]
        S3 --> S4[SSL/TLS Audit]
    end

    subgraph DR["DR Testing (Week 20)"]
        D1[Failover Test\nPostgreSQL Standby] --> D2[K8s Node Failure\nSimulation]
        D2 --> D3[Network Failover\nTest]
        D3 --> D4[Full DR Drill\nRTO/RPO Validation]
    end

    FT --> PT --> ST --> DR
```

### Performance Test Targets

```
Test Scenario               Tool          Pass Criteria
────────────────────────────────────────────────────────────
Response time P95           k6 / Gatling  < 200ms
Throughput sustained        k6            > 10,000 req/sec
Error rate under load       k6            < 0.1%
DB query time P95           pgBadger      < 100ms
Redis hit rate              redis-cli     > 85%
K8s pod restart count       kubectl       0 restarts
CPU usage at peak           Prometheus    < 80%
Memory usage at peak        Prometheus    < 85%
Disk I/O at peak            Prometheus    < 5,000 IOPS
Network throughput          iperf3        > 900 Mbps
```

---

## Phase 6: Go-Live & Cutover (Weeks 21–22)

### Cutover Sequence

```mermaid
sequenceDiagram
    actor Team as Migration Team
    participant AZ as Azure Platform
    participant DNS as DNS / Load Balancer
    participant ONPREM as On-Premises Platform
    participant MON as Monitoring

    Note over Team,MON: T-48h: Pre-Cutover Freeze
    Team->>AZ: Freeze application deployments
    Team->>ONPREM: Verify all systems healthy
    Team->>MON: Confirm alerts working

    Note over Team,MON: T-4h: Final Sync
    Team->>AZ: pg_dump final export
    AZ-->>ONPREM: pglogical final sync
    Team->>ONPREM: Validate data integrity (checksums)
    Team->>ONPREM: Run smoke tests

    Note over Team,MON: T=0: Cutover Window (2AM)
    Team->>AZ: Put Azure App Service in maintenance mode
    AZ-->>ONPREM: Final DB replication catch-up
    Team->>DNS: Update DNS TTL to 60s (done 24h prior)
    Team->>DNS: Point A records to F5 BIG-IP VIP
    Team->>ONPREM: Enable on-prem ingress traffic
    Team->>MON: Watch dashboards for errors

    Note over Team,MON: T+15min: Validation
    Team->>ONPREM: Run automated health checks
    ONPREM-->>Team: All checks PASS

    Note over Team,MON: T+1h: Decision Point
    alt All Systems Healthy
        Team->>AZ: Begin Azure cost reduction
        Team->>MON: Update runbooks
    else Issues Found
        Team->>DNS: Revert DNS to Azure
        Team->>AZ: Re-enable Azure App Service
        Team->>Team: Post-mortem & retry
    end
```

---

## Phase 7: Stabilization (Weeks 23–26)

```
Week 23-24: Hypercare (24/7 On-Call)
  ├─ [ ] Monitor all dashboards continuously
  ├─ [ ] Daily stand-up with on-call team (7am)
  ├─ [ ] P1 issues: Response < 15 minutes
  ├─ [ ] P2 issues: Response < 1 hour
  └─ [ ] Daily performance reports to stakeholders

Week 25: Optimization
  ├─ [ ] Tune Kubernetes resource limits based on usage
  ├─ [ ] Optimize PostgreSQL (autovacuum, connection pooling)
  ├─ [ ] Review and tighten firewall rules
  ├─ [ ] Adjust auto-scaling thresholds
  └─ [ ] Reduce Azure resource spend progressively

Week 26: Closure
  ├─ [ ] Complete all Azure decommissions
  ├─ [ ] Finalize operations runbooks
  ├─ [ ] Conduct knowledge transfer sessions
  ├─ [ ] Project retrospective meeting
  └─ [ ] Final project report to stakeholders
```

---

**Document Version**: 2.0
**Date**: July 2026
**Classification**: Internal Use Only
