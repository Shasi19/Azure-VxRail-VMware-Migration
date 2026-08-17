# QA Environment Migration Timeline
## 6 Weeks + 1 Week Buffer = 7 Weeks Total

> **Phase:** Phase 1 — Testing & Validation  
> **Timeline:** Weeks 1–7 (6 weeks of work, 1 week buffer)  
> **Objective:** Migrate and validate QA workloads on VxRail vSphere  
> **Success Criteria:** All QA applications running on-prem, performance validated, sign-off received

---

## 📅 Week-by-Week Breakdown

### **Week 1: Foundation & Discovery**
**Focus:** Establish shared infrastructure foundation

**Daily Tasks:**
- **Day 1:** Kickoff meeting, confirm team assignments
- **Day 2:** Access VxRail vCenter, vSAN status check
- **Day 3:** Verify network connectivity (on-prem ↔ Azure)
- **Day 4:** Review current QA infrastructure in Azure
- **Day 5:** Document baseline metrics (CPU, RAM, storage, I/O)

**Deliverables:**
- [ ] VxRail cluster status report
- [ ] QA workload inventory document
- [ ] Network diagram (Azure ↔ On-Prem)
- [ ] Team access credentials verified

**Success Metrics:**
- vCenter accessible and responsive
- All 6 nodes in cluster reporting healthy
- vSAN enabled and configured
- Network latency < 50ms to on-prem

**Rollback:** N/A (discovery phase)

---

### **Week 2: Infrastructure Preparation**
**Focus:** Build VMware foundation

**Daily Tasks:**
- **Day 1:** Create Oracle Linux 9 VM template
- **Day 2:** Configure network port groups (DVS)
- **Day 3:** Set up firewalld rules
- **Day 4:** Create storage classes in vSAN
- **Day 5:** Verify template with test VM

**Commands:**
```bash
# Connect to vCenter (via jump host)
export VCENTER="vcenter.onprem.local"
export VCENTER_USER="administrator@vsphere.local"
govc about -u $VCENTER_USER@$VCENTER

# Verify vSAN configuration
govc datastore.info -ds=vsan

# List port groups
govc dvs.portgroup.info
```

**Deliverables:**
- [ ] Oracle Linux 9 template created (VM ID: qa-ol9-template-v1)
- [ ] DVS port groups configured (qa-mgmt, qa-k8s, qa-data)
- [ ] Storage classes created (qa-fast, qa-standard)
- [ ] Network connectivity tested

**Success Metrics:**
- Template VM boots successfully
- Network connectivity within <5ms (same cluster)
- Storage I/O write speed > 100MB/s

**Rollback:** Delete template, revert DVS changes

---

### **Week 3: Kubernetes Cluster Deployment**
**Focus:** Build HA Kubernetes cluster on vSphere

**Daily Tasks:**
- **Day 1:** Clone 3 master node VMs from template
- **Day 2:** Clone worker node VMs (start with 3)
- **Day 3:** Configure hostnames, IPs, SSH keys
- **Day 4:** Install kubeadm, kubelet, kubectl on all nodes
- **Day 5:** Initialize Kubernetes cluster (kubeadm init)

**Commands:**
```bash
# On first master node
sudo kubeadm init \
  --control-plane-endpoint=qa-k8s-vip.onprem.local \
  --pod-network-cidr=10.244.0.0/16 \
  --service-cidr=10.96.0.0/12

# Join other master nodes
kubeadm join --control-plane

# Install CNI (Calico)
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.0/manifests/calico.yaml

# Install vSphere CCM
kubectl apply -f vsphere-cloud-controller-manager.yaml

# Verify cluster
kubectl get nodes
kubectl get pods --all-namespaces
```

**Deliverables:**
- [ ] 3 master nodes running (qa-master-1, qa-master-2, qa-master-3)
- [ ] 3 worker nodes running (qa-worker-1, qa-worker-2, qa-worker-3)
- [ ] Kubernetes cluster healthy (kubectl get nodes = Ready)
- [ ] Calico networking operational
- [ ] vSphere Cloud Controller Manager deployed

**Success Metrics:**
- All nodes showing "Ready" status
- Cluster API latency < 100ms
- Pod networking functional
- Storage provisioning working

**Rollback:** Delete all K8s VMs, start over

---

### **Week 4: Database & Storage Migration**
**Focus:** Migrate PostgreSQL and prepare data storage

**Daily Tasks:**
- **Day 1:** Create PostgreSQL VM in vSphere
- **Day 2:** Set up PostgreSQL 14 with replication
- **Day 3:** Start pg_dump from Azure PostgreSQL
- **Day 4:** Restore dump to on-prem PostgreSQL
- **Day 5:** Validate data integrity, test connections

**Commands:**
```bash
# Dump from Azure (on jump host)
pg_dump -h <azure-pg>.postgres.database.azure.com \
  -U username@servername \
  -d qadb \
  --no-owner \
  -Fc > qadb-backup.dump

# Restore to on-prem
pg_restore -h qa-postgres.onprem.local \
  -U postgres \
  -d qadb \
  --clean \
  qadb-backup.dump

# Validate record count
psql -h qa-postgres.onprem.local -U postgres -d qadb -c "SELECT COUNT(*) FROM <table>;"
```

**For Cosmos DB → MongoDB Migration:**
```bash
# Export from Cosmos DB (export to JSON)
# Import to MongoDB on K8s
mongoimport --uri="mongodb://qa-mongo.onprem.local:27017/qadb" \
  --file=cosmos-export.json \
  --jsonArray
```

**Deliverables:**
- [ ] PostgreSQL database running on vSphere VM
- [ ] Data migrated from Azure
- [ ] Backup/restore validated
- [ ] MongoDB (if used) deployed to K8s and data migrated
- [ ] Storage classes provisioned and tested

**Success Metrics:**
- Database connectivity confirmed
- Record counts match Azure
- Query performance acceptable
- Replication lag < 1 second

**Rollback:** Keep Azure databases running in parallel

---

### **Week 5: Application Deployment & Integration**
**Focus:** Deploy QA applications to on-prem K8s

**Daily Tasks:**
- **Day 1:** Set up Harbor container registry (on K8s or VM)
- **Day 2:** Push QA app images to Harbor
- **Day 3:** Deploy Helm charts / manifests to K8s
- **Day 4:** Configure application secrets, ConfigMaps
- **Day 5:** Connect apps to on-prem databases

**Commands:**
```bash
# Deploy Harbor
helm repo add harbor https://goharbor.github.io/harbor
helm install harbor harbor/harbor -n harbor --create-namespace

# Push images to Harbor
docker tag myapp:latest harbor.onprem.local/qa/myapp:v1.0
docker push harbor.onprem.local/qa/myapp:v1.0

# Deploy app via Helm
helm install qa-app ./qa-app-chart \
  --namespace qa-apps \
  --values qa-values.yaml

# Verify deployment
kubectl get deployments -n qa-apps
kubectl get pods -n qa-apps
```

**Deliverables:**
- [ ] Harbor registry operational and accessible
- [ ] QA application images pushed to Harbor
- [ ] Applications deployed to K8s
- [ ] Database connections working
- [ ] Health checks passing

**Success Metrics:**
- All pods Running
- Application endpoints responding
- Database queries executing
- Logs showing normal operation

**Rollback:** Scale deployments to 0 replicas, revert to Azure

---

### **Week 6: Testing, Validation & Performance**
**Focus:** Comprehensive testing of migrated QA environment

**Daily Tasks:**
- **Day 1:** Functional testing — all features working?
- **Day 2:** Integration testing — services talking correctly?
- **Day 3:** Performance testing — baseline response times
- **Day 4:** Load testing — spike handling, stability
- **Day 5:** Document results, identify issues

**Test Cases:**
```
1. Application Login
   - User authentication works
   - Sessions created correctly
   - Expected result: Login succeeds in <2 seconds

2. Database Operations
   - CRUD operations functional
   - Data consistency verified
   - Expected result: All queries < 500ms

3. API Endpoints
   - All endpoints reachable
   - Response times < 1 second
   - Error handling working
   - Expected result: HTTP 200/201 for valid requests

4. Load Testing
   - 100 concurrent users → measure CPU/memory
   - 500 concurrent users → measure stability
   - Expected result: <5% error rate, graceful degradation

5. Backup/Restore
   - Veeam backup job executes
   - Restore test successful
   - Expected result: RTO < 1 hour, RPO < 15 min
```

**Deliverables:**
- [ ] Test report with pass/fail results
- [ ] Performance baseline documentation
- [ ] Issue log with severity/priority
- [ ] Sign-off from QA team

**Success Metrics:**
- > 95% functional tests passing
- Response times within SLA
- Load testing passed with <5% errors
- Backup/restore working

**Rollback:** If major issues: Keep Azure as primary, on-prem as staging

---

### **Week 7: Buffer & Approvals**
**Focus:** Address issues, obtain sign-off, prepare for PREPROD

**Daily Tasks:**
- **Day 1-2:** Fix critical issues from testing
- **Day 3:** Re-test critical paths
- **Day 4:** Prepare QA sign-off documentation
- **Day 5:** QA team sign-off meeting, lessons learned

**Deliverables:**
- [ ] All P1 issues resolved
- [ ] Test report updated
- [ ] QA environment sign-off document signed
- [ ] PREPROD team briefing completed
- [ ] Lessons learned documented

**Success Metrics:**
- QA team confirms readiness for PREPROD
- All blocking issues resolved
- Knowledge transfer completed

**Rollback:** If QA not ready: Extend buffer or return to previous week

---

## 🎯 QA Environment Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    ON-PREMISES VXRAIL CLUSTER                   │
│                       (6-Node Dell HCI)                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │           VMWARE VSPHERE & VSAN (Shared)                 │  │
│  │  - vCenter: vcenter.onprem.local                         │  │
│  │  - Cluster: qa-cluster-1                                 │  │
│  │  - vSAN: Enabled, Deduplication ON                       │  │
│  └──────────────────────────────────────────────────────────┘  │
│           │                      │                      │       │
│           ▼                      ▼                      ▼       │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────┐  │
│  │  Kubernetes      │  │  PostgreSQL      │  │  Harbor      │  │
│  │  (3M + 3W nodes) │  │  (on vSphere VM) │  │  Registry    │  │
│  │                  │  │                  │  │  (on K8s)    │  │
│  │ - Calico CNI     │  │ - Patroni HA     │  │              │  │
│  │ - MetalLB        │  │ - Replication    │  │ - Pull/Push  │  │
│  │ - vSphere CCM    │  │ - pg_repack      │  │ - Auth       │  │
│  │ - StorageClass   │  │                  │  │              │  │
│  │   (vSAN CSI)     │  │ Storage: 100GB   │  │ Storage: 50GB│  │
│  │                  │  │ CPU: 4 cores     │  │ CPU: 2 cores │  │
│  │ Storage: 500GB   │  │ RAM: 8GB         │  │ RAM: 4GB     │  │
│  │ CPU: 16 cores    │  │                  │  │              │  │
│  │ RAM: 64GB        │  │                  │  │              │  │
│  └──────────────────┘  └──────────────────┘  └──────────────┘  │
│           │                      │                      │       │
│           └──────────┬───────────┴────────────┬─────────┘       │
│                      │                        │                 │
│                      ▼                        ▼                 │
│            ┌────────────────────┐   ┌─────────────────────┐    │
│            │   QA Applications  │   │  Monitoring Stack   │    │
│            │                    │   │                     │    │
│            │ - Microservices    │   │ - Prometheus        │    │
│            │ - APIs             │   │ - Grafana           │    │
│            │ - Workers          │   │ - ELK Stack         │    │
│            │                    │   │ - Alerting          │    │
│            └────────────────────┘   └─────────────────────┘    │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│  Storage: vSAN (3 TB total, FTT=1)                              │
│  Network: DVS, VLANs (qa-mgmt, qa-k8s, qa-data)                 │
│  Backup: Veeam B&R (daily incremental, weekly full)             │
└─────────────────────────────────────────────────────────────────┘
```

---

## ✅ QA Sign-Off Checklist

Before moving to PREPROD, confirm:

- [ ] **Infrastructure**
  - [ ] All 6 VxRail nodes healthy
  - [ ] vSphere cluster operational
  - [ ] vSAN storage with 3TB available
  - [ ] Network connectivity verified

- [ ] **Kubernetes**
  - [ ] 3 masters + 3 workers healthy
  - [ ] Calico CNI functional
  - [ ] Storage provisioning works
  - [ ] Ingress controller (MetalLB) working

- [ ] **Applications**
  - [ ] All QA apps deployed and Running
  - [ ] Application health checks passing
  - [ ] Database connections established
  - [ ] APIs responding to requests

- [ ] **Testing**
  - [ ] Functional tests: >95% pass
  - [ ] Performance tests: Within SLA
  - [ ] Load tests: Handled spike gracefully
  - [ ] Backup/restore: Validated

- [ ] **Operations**
  - [ ] Monitoring dashboard active
  - [ ] Alerts configured and tested
  - [ ] Logging functional (ELK)
  - [ ] On-call runbook prepared

- [ ] **Approval**
  - [ ] QA team lead: Sign-off
  - [ ] Infrastructure team lead: Approval
  - [ ] Change control board: Notified

---

## 📊 Resource Requirements

### VxRail Cluster Allocation (QA)
- **Compute:** 8 vCPU + 24GB RAM (out of 96 total available)
- **Storage:** 500GB (out of 3TB total available)
- **Network:** qa-mgmt, qa-k8s, qa-data VLANs

### Personnel
- **vSphere Admin:** 40% allocation (Weeks 1-7)
- **K8s Admin:** 50% allocation (Weeks 1-7)
- **Database Admin:** 30% allocation (Weeks 1-7)
- **QA Lead:** 20% allocation (Weeks 1-7)

### External Connections
- **Azure Connectivity:** VPN tunnel (existing Veeam connection)
- **Network Bandwidth:** 100Mbps minimum
- **Management Access:** Jump host SSH access

---

## 🚨 Critical Risks

| Risk | Impact | Mitigation |
|------|--------|-----------|
| **vSAN Capacity** | Storage exhaustion | Monitor disk usage daily, resize if >80% |
| **Network Latency** | Slow database queries | Test Azure→OnPrem connectivity, optimize |
| **Database Corruption** | Data loss | Validate dumps before restore, test recovery |
| **K8s Node Failure** | Pod eviction, service interruption | Ensure 3 workers minimum, DRS anti-affinity rules |
| **Application Compatibility** | Apps won't start on OL9 | Test thoroughly in Week 5, address issues early |

---

## 📞 Escalation Points

- **Infrastructure Issue:** Escalate to VxRail TAC (Dell)
- **vSphere Issue:** Escalate to VMware support
- **Kubernetes Issue:** Escalate to Kubernetes community / expert
- **Database Issue:** Escalate to PostgreSQL community / DBA expert
- **Timeline Slip:** Escalate to Project Manager → Steering Committee

---

## Next Steps

1. ✅ Complete Week 1 discovery
2. ✅ Confirm team assignments
3. ✅ Schedule weekly status meetings
4. ✅ Prepare for Week 2 infrastructure work

**Next Document:** [QA Architecture](01-QA-Architecture.md)
