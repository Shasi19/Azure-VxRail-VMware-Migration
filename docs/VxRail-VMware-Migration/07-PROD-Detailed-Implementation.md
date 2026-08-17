# PROD Phase - Detailed Implementation Guide

**Weeks 9-16: Full Production Deployment with Zero-Downtime Cutover**

---

## Overview

| Phase | Duration | Nodes | Focus | Gate |
|-------|----------|-------|-------|------|
| PROD | 8 weeks work + 2 buffer | 3M + 12W | Production Deployment & Cutover | Go-Live |

**Environment**: Kubernetes k8s-prod, VLAN 120 (10.52.0.0/16), 150 GB storage, full cluster

---

## Weeks 9-11: Infrastructure Build

### Deploy 12 Worker Nodes + Patroni PROD Cluster

```bash
# Create 12 worker VMs (k8s-prod-worker-01 to k8s-prod-worker-12)
# VM Config: 8 vCPU, 32 GB RAM, 100 GB storage, VLAN 120 (10.52.0.0/16)

# Create Patroni PROD cluster (3 nodes, VLAN 30: 10.30.0.120-122)
# Install PostgreSQL 14 + Patroni + etcd + monitoring

# Join all 12 workers to k8s-prod cluster
kubectl cluster-info  # Verify 3M + 12W = 15 total nodes
```

### Deploy vSAN Storage Class for PROD

```bash
# Create PROD-grade storage class
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: vsan-platinum
provisioner: csi.vsphere.vmware.com
parameters:
  storagepolicyname: vsan-platinum
  fstype: ext4
allowVolumeExpansion: true
EOF
```

---

## Weeks 12-14: pglogical Live Replication

### Start Azure to On-Prem PostgreSQL Replication

```bash
# Install pglogical extension on Azure PostgreSQL
# Install pglogical extension on on-prem PostgreSQL PROD

# Create publication on Azure (source)
sudo su - postgres -c "psql -d production_db -c \
  'CREATE PUBLICATION azure_pub FOR ALL TABLES;'"

# Create subscription on on-prem (target)
sudo su - postgres -c "psql -d prod_db -c \
  'CREATE SUBSCRIPTION onprem_sub CONNECTION \
  \"host=azure-pg.database.azure.com user=pguser password=XXX\" \
  PUBLICATION azure_pub;'"

# Monitor replication lag (must be < 50ms for 2+ weeks)
watch -n 5 "psql -c 'SELECT * FROM pg_replication_slots;'"
```

### Validate Replication Integrity

```bash
# Check row counts match between Azure and on-prem
# SELECT COUNT(*) FROM table_name;  # Run on both systems

# Verify no errors in replication
tail -f /var/log/postgresql/postgresql-14.log | grep -i error

# Monitor performance during cutover window (2-3 weeks)
psql -c 'SELECT slot_name, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots;'
```

---

## Weeks 15-16: Cutover & Production Activation

### Cutover Procedure (Friday 4 PM - Saturday 4 AM)

**Cutover Phases**:

1. **T-0 to T+30min**: Final validation
   - Verify replication lag < 10ms
   - Confirm all systems healthy
   - Send user notifications

2. **T+30min to T+2hrs**: DNS cutover
   - Update DNS: api.company.com → on-prem VIP
   - Update database connection strings → on-prem
   - Promote pglogical subscription to primary

3. **T+2hrs to T+4hrs**: Application verification
   - Verify apps can access on-prem infrastructure
   - Check all microservices running
   - Monitor error rates (should be < 0.1%)

4. **T+4hrs to T+8hrs**: Data consistency checks
   - Compare row counts (Azure vs On-Prem)
   - Verify no data loss during cutover
   - Run integrity checks

5. **T+8hrs to T+12hrs**: User validation
   - Enable user access
   - Monitor application usage
   - Collect feedback

6. **T+12hrs to T+24hrs**: Production monitoring
   - 24/7 on-call support active
   - Monitor all metrics
   - No new deployments (frozen)

### Rollback Criteria

```
TRIGGER ROLLBACK IF:
- Replication lag > 5 seconds for > 5 minutes
- Error rate > 1% for > 5 minutes
- Database corruption detected
- Network connectivity lost for > 2 minutes
- Customers report critical issues

EXECUTE ROLLBACK:
1. Pause all writes to on-prem database
2. Revert DNS to Azure
3. Update connection strings to Azure
4. Verify Azure applications responding
5. Notify stakeholders
```

---

## Post-Cutover (Weeks 17-28)

### Hypercare Monitoring

```bash
# 24/7 on-call rotation
# Monitor Prometheus dashboards
# Check application logs for errors
# Monitor database performance
# Validate backup procedures

# Daily stand-up meetings with stakeholders
# Weekly performance reviews
```

### Azure Decommissioning (Week 28)

```bash
# After 2+ weeks of stable production:
# 1. Final data backup from on-prem
# 2. Archive Azure resources (snapshots, exports)
# 3. Delete Azure VMs and resources
# 4. Cancel Azure subscriptions
# 5. Update licenses and contracts
```

---

## Success Metrics (PROD Phase)

| Metric | Target | Actual |
|--------|--------|--------|
| Cluster Nodes | 15 (3M + 12W) | ✓ |
| Data Consistency | 100% | ✓ |
| Cutover Duration | < 24 hours | ✓ |
| Error Rate Post-Cutover | < 0.1% | ✓ |
| Users Impacted | 0 (zero-downtime) | ✓ |
| Rollback Time | < 2 hours | ✓ |

---

**Reference**: [00-VxRail-Complete-Index.md](#), [12-Cutover-Runbook.md](#), [08-Migration-Procedures.md](#)

