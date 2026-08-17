# PROD Environment Migration Timeline
## 10 Weeks + 2 Week Buffer = 12 Weeks Total

> **Phase:** Phase 3 — Production Migration & Go-Live  
> **Timeline:** Weeks 17–28 (10 weeks of work, 2 weeks buffer)  
> **Start Condition:** PREPROD approved and performance validated  
> **Target Stack:** Oracle Linux 9 + Kubernetes 1.34 on Dell VxRail vSphere  
> **Objective:** Zero-downtime production migration to on-prem  
> **Success Criteria:** Production successfully running on-prem, Azure decommissioned

---

## 📅 Week-by-Week Breakdown

### **Week 17: PROD Infrastructure Build**
**Focus:** Build production-grade cluster (full 6-node capacity, 12 workers on Oracle 9 + K8s 1.34)

**Scale:**
- 3 master nodes (HA control plane)
- 12 worker nodes (full production workloads)
- 2TB storage (production data volumes)

**Tasks:**
- Provision prod-master-1/2/3 VMs (Oracle 9)
- Provision prod-worker-1 through prod-worker-12 VMs (Oracle 9)
- Configure prod VLANs with network redundancy
- Set up production storage classes
- Configure DRS rules for pod affinity

**Deliverables:**
- [ ] All 15 nodes (3M + 12W) healthy and Ready
- [ ] Kubernetes 1.34 cluster operational
- [ ] Storage properly tiered (fast/standard/archive)
- [ ] Network redundancy verified

**Commands:**
```bash
# Clone 12 worker nodes for PROD
for i in {1..12}; do
  govc vm.clone -ds=vsan -m=16384 -c=8 \
    prod-worker-$i ol9-k8s-v1.34-base
done

# Initialize K8s 1.34 cluster on PROD
sudo kubeadm init \
  --kubernetes-version=v1.34.0 \
  --control-plane-endpoint=prod-k8s-vip.onprem.local:6443 \
  --pod-network-cidr=10.246.0.0/16 \
  --service-cidr=10.98.0.0/12

# Join all workers
# ... (repeat for all 12 worker nodes)

# Verify PROD cluster
kubectl get nodes -o wide
# Should show: 15 nodes (3M + 12W) Ready
```

---

### **Week 18: PostgreSQL HA Production Cluster**
**Focus:** 3-node HA PostgreSQL with Patroni, ready for live replication

**Deliverables:**
- [ ] Patroni cluster operational on Oracle 9 VMs
- [ ] Automatic failover tested
- [ ] WAL archiving configured
- [ ] Replication monitoring active

---

### **Week 19: Start Live Replication (pglogical)**
**Focus:** BEGIN DUAL-RUN mode

**Key Milestone:** Azure PRIMARY ↔ On-Prem REPLICA (synchronized)

**Deliverables:**
- [ ] pglogical replication active
- [ ] Replication lag < 1 second
- [ ] Conflict resolution tested
- [ ] Ops team trained

---

### **Week 20: PROD Application Deployment**
**Focus:** Deploy all production applications to on-prem K8s 1.34 cluster

**Deployments:**
- All PROD images pushed to Harbor
- Helm charts deployed with production config
- Database connections verified
- Monitoring/alerting active

**Deliverables:**
- [ ] All PROD apps deployed
- [ ] Health checks passing
- [ ] Database connectivity working
- [ ] Monitoring dashboards active

---

### **Week 21: Smoke Testing & Validation**
**Focus:** Light-touch validation (avoid stressing system during dual-run)

**Deliverables:**
- [ ] Smoke test report (all passed)
- [ ] Known issues documented
- [ ] Ops team sign-off

---

### **Week 22-25: Stabilization & Monitoring Window**
**Focus:** Run parallel for 2-3 weeks, watch for issues

**Daily Activities:**
- Monitor replication lag trend
- Check for error spikes
- Performance tuning adjustments
- Document any inconsistencies

**Gating Criteria for Cutover:**
- Replication lag consistently < 1 second
- No unresolved P1 issues
- Performance within 5% of Azure
- Team confident in cutover

**Deliverables:**
- [ ] 2+ weeks of clean metrics
- [ ] Cutover GO/NO-GO decision
- [ ] Cutover window finalized

---

### **Week 26: CUTOVER WINDOW (Maintenance)**
**Focus:** Switch production from Azure to on-prem

**Pre-Cutover (Friday 2:00 PM):**
- [ ] All replication lag < 500ms
- [ ] Backups current on both sides
- [ ] On-call team assembled
- [ ] Rollback criteria documented

**Cutover Steps (Friday 4:00 PM - Saturday 4:00 AM):**

**Phase 1: Prepare (2 hours)**
- Enable Azure maintenance mode (read-only)
- Wait for replication to catch up
- Verify final lag < 100ms

**Phase 2: Promote On-Prem (1 hour)**
- Disable pglogical subscriptions
- Promote on-prem PostgreSQL to primary
- Point apps to on-prem database

**Phase 3: DNS Cutover (30 minutes)**
- Update DNS to on-prem ingress IPs
- Flush all DNS caches
- Validate new resolution

**Phase 4: Validation (2 hours)**
- Test all critical flows
- Verify database writes
- Check backup execution
- Monitor for errors

**Phase 5: Monitoring (8 hours overnight)**
- 24/7 on-call team standing by
- Watch for anomalies
- Document issues

**Rollback (if needed, before Monday AM):**
- Reverse DNS changes
- Re-subscribe to replica
- Switch traffic back to Azure

**Deliverables:**
- [ ] Production successfully running on-prem
- [ ] No P1 errors in first 2 hours
- [ ] Cutover log documented

---

### **Week 27: Hypercare & Stabilization**
**Focus:** 24/7 monitoring, immediate issue response

**Deliverables:**
- [ ] 7 days clean production run on-prem
- [ ] Hypercare sign-off
- [ ] Incident log reviewed

---

### **Week 28: Azure Decommissioning & Buffer**
**Focus:** Safely shut down Azure resources

**Activities:**
- Final backup of Azure databases
- Document Azure configurations
- Archive remaining data
- Delete resources per retention policy
- Keep Azure as warm standby (1-2 weeks)

**Deliverables:**
- [ ] Azure resources deleted (per policy)
- [ ] Cost savings confirmed
- [ ] Project closure documentation

---

## 📊 Resource Allocation (PROD)

### VxRail Cluster (Full Capacity)
- **Compute:** 48 vCPU + 96GB RAM (using full cluster)
- **Storage:** 2TB vSAN
- **Network:** prod-mgmt, prod-k8s, prod-data, prod-backup VLANs

### Personnel
| Role | Allocation |
|------|-----------|
| vSphere Admin | 100% |
| K8s Admin (Oracle 9/1.34 expert) | 100% |
| Database Admin | 100% |
| Application PM | 50% |
| Network Engineer | 50% |
| Backup Admin | 50% |
| DBA (Cutover) | 100% (Week 26) |

---

## 🔴 Critical Success Factors

### Before Cutover
1. Replication lag: Consistently < 1 second
2. Data integrity: All row counts match Azure
3. Performance: On-prem within 5% of Azure
4. Team readiness: All trained and prepared
5. Documentation: All runbooks complete

### During Cutover (Friday 4 PM - Saturday 4 AM)
1. Maintenance window: Announced to users
2. Communication: Status updates every 30 min
3. Rollback plan: Tested and ready
4. On-call team: All present
5. Escalation: Clear and documented

### After Cutover (Hypercare)
1. Monitoring: 24/7 on standby
2. Issue response: < 30 min for P1
3. Backup verification: Test restore Day 1
4. Performance validation: Compare to Azure baseline
5. Team debriefing: Lessons learned session

---

## ⚠️ Rollback Decision Criteria

**ROLLBACK IMMEDIATELY if:**
- Critical application down (all users impacted)
- Database corruption detected
- Data loss suspected
- Network connectivity loss

**ROLLBACK WITHIN 1 HOUR if:**
- > 5% transaction failure rate
- Database replication inconsistency
- Security breach

**CONTINUE if:**
- < 1% transaction failure rate
- Non-critical services degraded
- Performance within 10% of Azure

---

## Next Steps

1. ✅ Confirm PREPROD sign-off
2. ✅ Finalize PROD infrastructure specs
3. ✅ Book maintenance window (Week 26)
4. ✅ Notify stakeholders
5. ✅ Start pglogical setup (Week 19)

**→ Next Document:** [PROD Architecture](01-PROD-Architecture.md)
