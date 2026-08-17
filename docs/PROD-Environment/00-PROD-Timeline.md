# PROD Environment Migration Timeline
## 10 Weeks + 2 Week Buffer = 12 Weeks Total

> **Phase:** Phase 3 — Production Migration & Go-Live  
> **Timeline:** Weeks 17–28 (10 weeks of work, 2 weeks buffer)  
> **Start Condition:** PREPROD approved and performance validated  
> **Objective:** Zero-downtime production migration to on-prem  
> **Success Criteria:** Production successfully running on-prem, Azure decommissioned

---

## 📅 Week-by-Week Breakdown

### **Week 17: PROD Infrastructure Build**
**Focus:** Build production-grade PROD cluster (largest environment)

**Scale:**
- 3 master nodes (HA control plane)
- 12 worker nodes (production workloads)
- 2TB storage (production data volumes)

**Tasks:**
- Provision prod-master-1/2/3 VMs
- Provision prod-worker-1 through prod-worker-12
- Configure prod VLANs with network redundancy
- Set up prod storage classes (fast/standard/archival)
- Configure DRS rules for pod affinity

**Success Criteria:**
- [ ] All 15 nodes healthy and Ready
- [ ] Storage properly tiered
- [ ] Network redundancy verified
- [ ] vCenter management responsive

---

### **Week 18: PostgreSQL HA Production Cluster**
**Focus:** 3-node HA PostgreSQL with Patroni, ready for live replication

**Critical Components:**
- 3-node Patroni cluster (prod-postgres-1/2/3)
- etcd for distributed consensus
- Point-in-time recovery (WAL archiving)
- Streaming replication to Azure (during dual-run)

**Deliverables:**
- [ ] Patroni cluster operational
- [ ] Automatic failover tested
- [ ] WAL archiving to backup storage
- [ ] Replication lag monitoring set up

---

### **Week 19: Start Live Replication (pglogical)**
**Focus:** BEGIN DUAL-RUN - both Azure and on-prem live simultaneously

**Key Milestone:** This is when we START the live clock

**Activities:**
- Install pglogical extension on both Azure and on-prem
- Set up logical replication subscriptions
- Start continuous data sync from Azure → on-prem
- Validate replication lag (target: < 1 second)
- Enable conflict resolution rules

**Implications:**
- Azure remains PRIMARY (all writes go here)
- On-prem is REPLICA (read-only)
- DUAL-RUN duration: 2-3 weeks
- Any Azure write automatically syncs to on-prem

**Deliverables:**
- [ ] pglogical replication active
- [ ] Lag monitoring shows < 1 second
- [ ] Conflict resolution tested
- [ ] Ops team trained on dual-run

---

### **Week 20: PROD Application Deployment**
**Focus:** Deploy all production applications to on-prem K8s

**Activities:**
- Push all PROD images to Harbor
- Deploy Helm charts to K8s (production configs)
- Verify database connections
- Configure production monitoring/alerting
- Set up log shipping (ELK)

**High Availability:**
- All deployments have 3+ replicas
- Pod Disruption Budgets configured
- Ingress/MetalLB for load balancing
- Service mesh (optional: Istio) for traffic control

**Deliverables:**
- [ ] All production apps deployed
- [ ] Health checks passing
- [ ] Database connections working
- [ ] Monitoring alerting active

---

### **Week 21: Smoke Testing & Validation**
**Focus:** Light-touch validation (don't stress system during dual-run)

**Tests:**
- All application APIs responding
- Database queries returning correct data
- File uploads/downloads working
- Background jobs executing
- Monitoring dashboards updating

**Note:** Skip heavy load testing (still running in Azure)

**Deliverables:**
- [ ] Smoke test report (all passed)
- [ ] Known issues documented
- [ ] Ops team sign-off

---

### **Week 22-25: Stabilization & Monitoring Window**
**Focus:** Run parallel for 2-3 weeks, watch for issues

**Daily Activities:**
- Monitor replication lag trend
- Check for error spikes in on-prem
- Compare metrics between Azure and on-prem
- Document any inconsistencies
- Make performance tuning adjustments

**Gating Criteria for Cutover:**
- Replication lag consistently < 1 second
- No unresolved P1 issues on on-prem
- Performance within 5% of Azure
- Team confident in cutover procedures

**Contingency:** If issues arise, extend this window

**Deliverables:**
- [ ] 2+ weeks of clean metrics
- [ ] Cutover decision: GO or NO-GO
- [ ] Cutover window finalized (usually Friday PM - Sunday)

---

### **Week 26: CUTOVER WINDOW (Maintenance)**
**Focus:** Switch production from Azure to on-prem

**Pre-Cutover Checklist (Friday 2:00 PM):**
- [ ] All replication lag < 500ms
- [ ] Backups current on both sides
- [ ] On-call team assembled
- [ ] Rollback decision criteria documented

**Cutover Steps (Friday 4:00 PM - Saturday 4:00 AM):**

**Phase 1: Prepare (2 hours)**
- Enable maintenance mode on Azure (read-only)
- Wait for replication to catch up (target: 5 minutes)
- Verify final replication lag (must be < 100ms)

**Phase 2: Promote On-Prem (1 hour)**
- pglogical: Disable subscriptions (stop replica)
- Promote on-prem PostgreSQL from replica → primary
- Point applications to on-prem database

**Phase 3: DNS Cutover (30 minutes)**
- Update DNS records to point to on-prem ingress IPs
- Flush all DNS caches
- Validate new DNS resolution

**Phase 4: Validation (2 hours)**
- Test all critical application flows
- Verify database writes working
- Check backup job execution
- Monitor for errors in logs

**Phase 5: Monitoring (8 hours overnight)**
- Round-the-clock monitoring
- On-call team standing by
- Watch for any anomalies
- Document any issues

**Rollback (if needed, execute before Monday AM):**
- Reverse DNS changes (back to Azure)
- pglogical: Re-subscribe to replica
- Pause on-prem applications
- Switch application traffic back to Azure

**Success Criteria:**
- All critical transactions processing
- No P1 errors in first 2 hours
- Database replication lag N/A (on-prem is now primary)

---

### **Week 27: Hypercare & Stabilization**
**Focus:** 24/7 monitoring, immediate issue response

**Activities:**
- Senior engineers on standby
- Monitor all metrics closely
- Watch for late-appearing issues (async processes)
- Performance tuning if needed
- Run backups to verify recovery procedures

**Deliverables:**
- [ ] 7 days clean production run on-prem
- [ ] Hypercare sign-off document
- [ ] Incident log reviewed

---

### **Week 28: Azure Decommissioning & Buffer**
**Focus:** Safely shut down Azure resources

**Tasks:**
- Final backup of Azure databases
- Document Azure-specific configurations
- Archive any remaining data
- Delete test/dev Azure resources first
- Schedule production resource deletion (staggered)
- Keep Azure as warm standby for 1-2 weeks

**Deliverables:**
- [ ] Azure resources deleted (per retention policy)
- [ ] Cost savings confirmed
- [ ] Project closure documentation

---

## PROD Resource Allocation

### VxRail Cluster (Full Capacity)
- **Compute:** 48 vCPU + 96GB RAM (using full cluster)
- **Storage:** 2TB (using most of 3TB)
- **Network:** prod-mgmt, prod-k8s, prod-data, prod-backup VLANs
- **Backup:** 1TB reserved for Veeam

### Personnel
- **vSphere Admin:** 100% allocation (Weeks 17-28)
- **K8s Admin:** 100% allocation (Weeks 17-28)
- **Database Admin:** 100% allocation (Weeks 17-28)
- **Application PM:** 50% allocation (Weeks 17-28)
- **Network Engineer:** 50% allocation (Weeks 17-28)
- **Veeam/Backup Admin:** 50% allocation (Weeks 17-28)
- **DBA (Weekend Cutover):** 100% allocation (Week 26)

### Outsourced Resources (Optional)
- **VMware TAC:** On-call support
- **Dell VxRail TAC:** Hardware support
- **Database Consultant:** Cutover support
- **Network Consultant:** DNS/routing support

---

## 🔴 Critical Success Factors

### Before Cutover
1. **Replication Lag:** Consistently < 1 second
2. **Data Integrity:** All row counts match Azure
3. **Performance:** On-prem within 5% of Azure
4. **Team Readiness:** All team members trained
5. **Documentation:** Runbooks complete and tested

### During Cutover (Friday 4 PM - Saturday 4 AM)
1. **Maintenance Window:** Announced to users
2. **Communication:** Status updates every 30 min
3. **Rollback Plan:** Tested and ready
4. **On-Call Team:** All members present
5. **Escalation Path:** Clear and documented

### After Cutover (Hypercare)
1. **Monitoring:** 24/7 on standby
2. **Issue Response:** < 30 min for P1 issues
3. **Backup Verification:** Test restore on Day 1
4. **Performance Validation:** Compare to Azure baseline
5. **Team Debriefing:** Lessons learned session

---

## ⚠️ Rollback Decision Criteria

**ROLLBACK IMMEDIATELY if:**
- Critical application down (all users impacted)
- Database corruption detected
- Data loss suspected
- Unrecoverable network connectivity loss

**ROLLBACK WITHIN 1 HOUR if:**
- > 5% transaction failure rate
- Database replication inconsistency
- Security breach detected

**CONTINUE if:**
- < 1% transaction failure rate
- Non-critical services degraded
- Performance within 10% of Azure

---

## Next Steps

1. ✅ Confirm PREPROD sign-off
2. ✅ Finalize PROD infrastructure specs
3. ✅ Book maintenance window (Week 26)
4. ✅ Notify stakeholders of timeline
5. ✅ Start pglogical setup in Week 19

**Next Document:** [PROD Architecture](01-PROD-Architecture.md)
