# PREPROD Environment Migration Timeline
## 8 Weeks + 1 Week Buffer = 9 Weeks Total

> **Phase:** Phase 2 — Load Testing & Production Staging  
> **Timeline:** Weeks 8–16 (8 weeks of work, 1 week buffer)  
> **Start Condition:** QA environment signed off and approved  
> **Objective:** Migrate PREPROD workloads, validate performance under realistic load  
> **Success Criteria:** PREPROD stable under load, performance meets production expectations

---

## 📅 Week-by-Week Breakdown

### **Week 8: Infrastructure Replication from QA**
**Focus:** Replicate QA infrastructure pattern to PREPROD scale

**Key Differences from QA:**
- PREPROD is 1.5x larger (9 workers instead of 3)
- Higher storage allocation (1TB instead of 500GB)
- Performance testing infrastructure

**Tasks:**
- Clone QA templates for PREPROD
- Create preprod-master-1/2/3 nodes
- Create preprod-worker-1 through preprod-worker-9
- Configure PREPROD-specific VLANs/firewall rules
- Replicate PostgreSQL cluster to PREPROD

**Success Criteria:**
- [ ] 3 masters + 9 workers deployed
- [ ] Kubernetes cluster healthy
- [ ] vSAN storage allocated (1TB)
- [ ] Network connectivity verified

---

### **Week 9: PostgreSQL HA & Patroni Setup**
**Focus:** High-availability PostgreSQL with automatic failover

**Key Components:**
- 3-node PostgreSQL cluster with Patroni
- etcd for cluster consensus
- Live replication from Azure (pglogical)
- Backup to Veeam daily

**Deliverables:**
- [ ] Patroni cluster operational
- [ ] Failover tested (kill primary, confirm secondary takes over)
- [ ] Replication lag < 1 second
- [ ] Backup jobs running

---

### **Week 10: Data Migration & Validation**
**Focus:** Migrate full PREPROD data sets, comprehensive validation

**Activities:**
- Dump all PREPROD databases from Azure
- Restore to on-prem PostgreSQL
- MongoDB data migration (if Cosmos DB)
- Data integrity validation (row counts, checksums)

**Expected Data Volumes:**
- PostgreSQL: 500GB - 1TB
- MongoDB: 200GB - 500GB
- File storage: 1-2TB

**Deliverables:**
- [ ] All databases restored
- [ ] Data integrity validated
- [ ] Replication to Azure confirmed

---

### **Week 11: Load Testing Infrastructure**
**Focus:** Set up tools to simulate production load

**Tools:**
- **Load Generator:** Apache JMeter / Locust
- **Monitoring:** Prometheus + Grafana
- **Logging:** ELK Stack with detailed metrics
- **APM:** Jaeger (distributed tracing)

**Baseline Tests:**
- 1,000 concurrent users
- 10,000 requests/second
- 24-hour sustained load
- Spike tests (5x normal load)

**Deliverables:**
- [ ] Load generators configured
- [ ] Monitoring dashboards created
- [ ] Baseline performance metrics recorded
- [ ] Alerting thresholds set

---

### **Week 12: Performance Testing Execution**
**Focus:** Run comprehensive load tests, identify bottlenecks

**Test Scenarios:**
1. **Normal Load:** 1,000 concurrent users (baseline)
2. **Peak Load:** 3,000 concurrent users (spike)
3. **Sustained Load:** 24-hour continuous run
4. **Failover Test:** Kill node mid-load, measure recovery

**Expected Results:**
- Response times: p95 < 1 second, p99 < 3 seconds
- Error rate: < 0.1%
- CPU utilization: 60-75% under peak load
- Memory usage: Stable, no memory leaks

**Deliverables:**
- [ ] Load test reports with detailed metrics
- [ ] Performance bottlenecks identified
- [ ] Optimization recommendations

---

### **Week 13: Optimization & Tuning**
**Focus:** Address performance issues, optimize configurations

**Areas to Tune:**
- **Kubernetes:** Pod resource limits, HPA configs
- **PostgreSQL:** Query optimization, indexing, connection pooling
- **Network:** MTU size, buffer sizes, QoS
- **Storage:** vSAN compression, deduplication settings
- **Application:** Caching, database connection pooling, async processing

**Deliverables:**
- [ ] Performance improvements documented
- [ ] Configuration changes tested
- [ ] Re-baseline performance metrics

---

### **Week 14: Pre-Production Validation**
**Focus:** Final validation before cutover preparation

**Activities:**
- Disaster recovery testing
- Backup/restore procedures
- Failover scenarios
- Cutover runbook dry-run
- Security scanning

**Deliverables:**
- [ ] DR test successful
- [ ] Cutover runbook validated
- [ ] Team trained on procedures

---

### **Week 15: Approval Gate & Documentation**
**Focus:** Obtain approval for PROD migration

**Activities:**
- Compile performance test results
- Create PREPROD sign-off document
- Stakeholder review meeting
- PROD migration planning meeting

**Deliverables:**
- [ ] PREPROD sign-off document (signed)
- [ ] PROD migration plan confirmed
- [ ] Resource allocation for PROD approved

---

### **Week 16: Buffer & Remediation**
**Focus:** Address remaining issues, prepare for PROD

**Activities:**
- Fix any issues from approval gate
- Update documentation
- Extend team training if needed
- Finalize PROD infrastructure specifications

**Deliverables:**
- [ ] All issues resolved
- [ ] PROD team ready to start
- [ ] Infrastructure specs finalized

---

## PREPROD Resource Allocation

### VxRail Cluster
- **Compute:** 12 vCPU + 48GB RAM (out of 96 total)
- **Storage:** 1TB (out of 3TB total)
- **Network:** preprod-mgmt, preprod-k8s, preprod-data VLANs

### Personnel
- **vSphere Admin:** 50% allocation
- **K8s Admin:** 60% allocation
- **Database Admin:** 40% allocation
- **Performance Engineer:** 80% allocation (Weeks 11-13)
- **QA Lead:** 30% allocation (Weeks 11-14)

---

## ⚠️ Key Success Factors

1. **Realistic Load Profile:**
   - Use actual PREPROD data volumes
   - Simulate real user behavior patterns
   - Include spike scenarios

2. **Comprehensive Monitoring:**
   - Baseline all metrics
   - Alert on deviations
   - Track trends across runs

3. **Failure Testing:**
   - Test failover scenarios early
   - Don't just test happy paths
   - Measure recovery time (RTO)

4. **Documentation:**
   - Record all configuration changes
   - Document why each change was made
   - Create playbooks for operations

---

## Next Steps

1. ✅ Confirm QA sign-off
2. ✅ Start PREPROD infrastructure build
3. ✅ Schedule load testing window (Week 11-12)
4. ✅ Reserve vendor resources if needed

**Next Document:** [PREPROD Architecture](01-PREPROD-Architecture.md)
