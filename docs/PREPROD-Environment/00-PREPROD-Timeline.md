# PREPROD Environment Migration Timeline
## 8 Weeks + 1 Week Buffer = 9 Weeks Total

> **Phase:** Phase 2 — Load Testing & Production Staging  
> **Timeline:** Weeks 8–16 (8 weeks of work, 1 week buffer)  
> **Start Condition:** QA environment signed off  
> **Target Stack:** Oracle Linux 9 + Kubernetes 1.34 on Dell VxRail vSphere  
> **Objective:** Migrate PREPROD workloads, validate performance under realistic load  
> **Success Criteria:** PREPROD stable under load, performance meets production expectations

---

## 📅 Week-by-Week Breakdown

### **Week 8: Infrastructure Build (Oracle 9 + K8s 1.34)**
**Focus:** Scale up from QA to PREPROD (9 worker nodes)

**Key Differences from QA:**
- PREPROD: 3 masters + 9 workers (vs QA: 3 masters + 3 workers)
- Storage: 1TB (vs QA: 500GB)
- Compute: 24 vCPU + 48GB RAM

**Tasks:**
- Clone 3 master VMs from existing Oracle 9 template
- Clone 9 worker VMs from existing Oracle 9 template
- Configure PREPROD-specific VLANs and firewall rules
- Setup vSAN storage for PREPROD
- Deploy Kubernetes 1.34 cluster on PREPROD nodes

**Deliverables:**
- [ ] 3 masters + 9 workers deployed and healthy
- [ ] K8s 1.34 cluster passing all health checks
- [ ] All nodes showing "Ready" status
- [ ] vSAN storage allocated (1TB)
- [ ] Network connectivity verified

**Commands:**
```bash
# Clone worker nodes from template
for i in {1..9}; do
  govc vm.clone -ds=vsan -m=16384 -c=8 \
    preprod-worker-$i ol9-k8s-v1.34-base
done

# Initialize K8s 1.34 cluster (same process as QA)
sudo kubeadm init \
  --kubernetes-version=v1.34.0 \
  --control-plane-endpoint=preprod-k8s-vip.onprem.local:6443 \
  --pod-network-cidr=10.245.0.0/16 \
  --service-cidr=10.97.0.0/12

# Join all 9 worker nodes
kubeadm join preprod-k8s-vip.onprem.local:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>

# Verify cluster
kubectl get nodes -o wide
# Should show: 3 masters + 9 workers = 12 nodes Ready
```

**Success Criteria:**
- [ ] 12 nodes (3M + 9W) all Ready
- [ ] Kubernetes 1.34 fully operational
- [ ] Storage allocation: 1TB vSAN available
- [ ] Network: All VLANs operational

---

### **Week 9: PostgreSQL HA (Patroni) with Replication**
**Focus:** High-availability database setup for PREPROD

**Components:**
- 3-node PostgreSQL 14 cluster with Patroni
- Streaming replication from Azure (pglogical)
- Daily backup to Veeam

**Deliverables:**
- [ ] 3-node Patroni cluster on Oracle 9 VMs
- [ ] Automatic failover tested
- [ ] Replication lag < 1 second
- [ ] Backup jobs running

**Commands:**
```bash
# Deploy Patroni on Oracle 9
sudo dnf install -y patroni patroni-postgresql postgresql14-server

# Configure Patroni for K8s 1.34 awareness
# Set up 3-node cluster: preprod-postgres-1/2/3

# Verify failover
# Kill primary, verify secondary takes over within 30 seconds
```

---

### **Week 10-11: Data Migration & Validation**
**Focus:** Migrate full PREPROD datasets

**Deliverables:**
- [ ] All PREPROD PostgreSQL data restored
- [ ] MongoDB data migrated (if applicable)
- [ ] Data integrity validated
- [ ] Replication to Azure confirmed

---

### **Week 12: Load Testing Infrastructure Setup**
**Focus:** Prepare tools for comprehensive load testing

**Tools:**
- Apache JMeter or Locust
- Prometheus + Grafana monitoring
- ELK Stack for logging
- Jaeger for distributed tracing

**Deliverables:**
- [ ] Load generators configured
- [ ] Monitoring dashboards created
- [ ] Baseline metrics recorded
- [ ] Alerting configured

---

### **Week 13: Performance Testing Execution**
**Focus:** Run load tests with realistic workload profiles

**Test Scenarios:**
1. **Normal Load:** 1,000 concurrent users
2. **Peak Load:** 3,000 concurrent users
3. **Sustained:** 24-hour continuous run
4. **Failover:** Node failure mid-test

**Deliverables:**
- [ ] Load test reports with metrics
- [ ] Bottlenecks identified
- [ ] Performance vs Azure baseline documented

---

### **Week 14: Optimization & Tuning**
**Focus:** Optimize based on load test results

**Areas to Tune:**
- Kubernetes resource limits and HPA
- PostgreSQL query optimization
- Network MTU, buffer sizes
- vSAN compression/deduplication

**Deliverables:**
- [ ] Configuration tuning applied
- [ ] Re-baseline performance metrics
- [ ] Improvements documented

---

### **Week 15: Pre-Production Validation**
**Focus:** Final validation before PROD approval

**Activities:**
- DR testing and validation
- Backup/restore procedures verified
- Cutover runbook dry-run
- Security scanning

**Deliverables:**
- [ ] DR test successful
- [ ] Cutover runbook validated
- [ ] Team trained

---

### **Week 16: Approval Gate & Buffer**
**Focus:** Obtain approval for PROD migration

**Deliverables:**
- [ ] PREPROD sign-off document (signed)
- [ ] PROD team ready to start
- [ ] Resource allocation approved

---

## 📊 Resource Allocation (PREPROD)

### VxRail Cluster
- **Compute:** 24 vCPU + 48GB RAM
- **Storage:** 1TB vSAN
- **Network:** preprod-mgmt, preprod-k8s, preprod-data VLANs

### Personnel
- **vSphere Admin:** 50% allocation
- **K8s Admin (Oracle 9/1.34):** 60% allocation
- **Database Admin:** 40% allocation
- **Performance Engineer:** 80% allocation (Weeks 12-14)

---

## Next Steps

1. ✅ Confirm QA sign-off
2. ✅ Start PREPROD infrastructure
3. ✅ Schedule load testing window
4. ✅ Book vendor resources if needed

**→ Next Document:** [PREPROD Architecture](01-PREPROD-Architecture.md)
