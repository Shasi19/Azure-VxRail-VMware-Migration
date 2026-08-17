# Production Cutover Runbook

**Minute-by-Minute Execution Guide: Friday 4 PM - Saturday 4 AM**

---

## Minute-by-Minute Cutover Flowchart

```
15:30 Prep ──▶ 16:00 Freeze ──▶ 16:30 Final Sync ──▶ 17:00 DNS Switch ──▶ Validate ──▶ Hypercare
```

---

## Flowchart 1 — Full Cutover Timeline (T+00:00 to T+12:00)

```
  T-00:30 (15:30)  FINAL PREPARATION
  ┌──────────────────────────────────────────────────────────────┐
  │  ① Notify all stakeholders (email + Slack #cutover-prod)    │
  │  ② Verify on-prem health: kubectl get nodes, patronictl list │
  │  ③ Document baseline: p95 latency, error rate, DB conns      │
  │  ④ Pre-stage DNS change commands (ready but NOT executed)    │
  │  ⑤ War room bridge open, all team members confirmed          │
  └────────────────────────┬─────────────────────────────────────┘
                           │
                  ◆ All pre-flight checks pass?
                  ├── NO ──▶ STOP — do not proceed — escalate
                  YES
                           ▼
  T+00:00 (16:00)  WRITE FREEZE
  ┌──────────────────────────────────────────────────────────────┐
  │  ⑥ Set Azure PROD DB to read-only:                          │
  │     ALTER DATABASE prod SET default_transaction_read_only    │
  │     = on;                                                    │
  │  ⑦ Confirm Azure app write traffic drops to 0               │
  └────────────────────────┬─────────────────────────────────────┘
                           │
  T+00:15 (16:15)  FINAL REPLICATION SYNC
  ┌──────────────────────────────────────────────────────────────┐
  │  ⑧ Monitor pglogical lag:                                   │
  │     SELECT now() - pg_last_xact_replay_timestamp() AS lag;  │
  │  ⑨ Wait for lag to reach 0 ms                               │
  └────────────────────────┬─────────────────────────────────────┘
                           │
                  ◆ Lag = 0 ms?
                  ├── NO (> 5 min wait) ──▶ Go/No-go decision
                  YES
                           ▼
  T+00:30 (16:30)  DROP SUBSCRIPTION — ON-PREM BECOMES PRIMARY
  ┌──────────────────────────────────────────────────────────────┐
  │  ⑩ Drop pglogical subscription:                             │
  │     SELECT pglogical.drop_subscription('onprem_sub');        │
  │  ⑪ On-prem DB promoted to read-write primary               │
  │  ⑫ Confirm: psql -c "SHOW transaction_read_only;" → "off"  │
  └────────────────────────┬─────────────────────────────────────┘
                           │
  T+00:45 (16:45)  DNS CUTOVER
  ┌──────────────────────────────────────────────────────────────┐
  │  ⑬ Flip external DNS:                                       │
  │     api.company.com → 10.52.100.10 (on-prem MetalLB VIP)   │
  │  ⑭ Flip internal DNS (Bind9 zone file update + rndc reload) │
  │  ⑮ Wait 60 s (TTL) then verify:                             │
  │     dig api.company.com +short → 10.52.100.10               │
  └────────────────────────┬─────────────────────────────────────┘
                           │
  T+01:00 (17:00)  RESTART APPLICATIONS TO PICK UP NEW DB
  ┌──────────────────────────────────────────────────────────────┐
  │  ⑯ kubectl rollout restart deployment/api-gateway -n prod   │
  │  ⑰ kubectl rollout restart deployment --all -n prod         │
  │  ⑱ Wait for all pods Running: kubectl get pods -n prod -w   │
  └────────────────────────┬─────────────────────────────────────┘
                           │
  T+01:30 (17:30)  POST-CUTOVER VALIDATION
  ┌──────────────────────────────────────────────────────────────┐
  │  ⑲ Health check: curl https://api.company.com/health        │
  │  ⑳ Smoke tests: run automated test suite                    │
  │  ㉑ Error rate < 0.1% in Grafana?                           │
  │  ㉒ p95 latency ≤ baseline in Prometheus?                   │
  └────────────────────────┬─────────────────────────────────────┘
                           │
                  ◆ All validation checks pass?
                  ├── NO ──▶ EMERGENCY ROLLBACK (see flowchart 4)
                  YES
                           ▼
  T+02:00 (18:00)  DECLARE CUTOVER SUCCESS
  ┌──────────────────────────────────────────────────────────────┐
  │  ㉓ Notify: "PROD cutover successful — on-prem is live"     │
  │  ㉔ Begin 24-hour hypercare monitoring window               │
  └────────────────────────┬─────────────────────────────────────┘
                           │
  T+12:00 (04:00 Sat)  HYPERCARE ENDS / AZURE DECOMMISSION BEGINS
  ┌──────────────────────────────────────────────────────────────┐
  │  ㉕ Confirm 12-hr metrics are nominal                       │
  │  ㉖ Schedule Azure resource cleanup (72-hr hold first)      │
  └──────────────────────────────────────────────────────────────┘
```

---

## Flowchart 2 — Go / No-Go Decision Tree

```
  PRE-CUTOVER GO/NO-GO (T-00:30)
  ═══════════════════════════════

               ◆ Is pglogical lag < 50 ms (sustained 7 days)?
               ├── NO  ──▶  NO-GO: Fix replication first
               YES
               │
               ◆ Are all on-prem K8s nodes Ready?
               ├── NO  ──▶  NO-GO: Drain/fix affected nodes
               YES
               │
               ◆ Is Patroni cluster healthy (1 primary + 2 replicas)?
               ├── NO  ──▶  NO-GO: Resolve Patroni fencing issue
               YES
               │
               ◆ Have rollback procedures been tested this week?
               ├── NO  ──▶  NO-GO: Run rollback drill first
               YES
               │
               ◆ Are all team members confirmed on bridge?
               ├── NO  ──▶  DELAY: Wait for quorum (10 min max)
               YES
               │
               ◆ Is change window still within approved hours (16:00–20:00)?
               ├── NO  ──▶  NO-GO: Reschedule
               YES
               │
               ▼
         ✅ GO — Proceed with cutover
```

---

## Flowchart 3 — Post-Cutover Validation Flow

```
  T+01:30  BEGIN VALIDATION SUITE
                │
  ① Infrastructure layer
  ┌──────────────────────────────────────────────────────────┐
  │  kubectl get nodes       → all Ready                    │
  │  patronictl list         → 1 Leader, 2 Replica          │
  │  df -h /data             → > 20% free space             │
  └────────────────────────┬─────────────────────────────────┘
                           │
  ② Database layer
  ┌──────────────────────────────────────────────────────────┐
  │  SELECT count(*) FROM <critical_table>  (compare Azure) │
  │  SHOW transaction_read_only;  → "off"                   │
  │  Check pg_stat_replication for streaming replicas       │
  └────────────────────────┬─────────────────────────────────┘
                           │
  ③ Application layer
  ┌──────────────────────────────────────────────────────────┐
  │  curl https://api.company.com/health    → {"status":"ok"}│
  │  curl https://api.company.com/readiness → 200            │
  │  Check all 25 microservices Running in prod namespace    │
  └────────────────────────┬─────────────────────────────────┘
                           │
  ④ Observability layer
  ┌──────────────────────────────────────────────────────────┐
  │  Grafana: error rate < 0.1% (5-min window)              │
  │  Prometheus: p95 latency ≤ pre-cutover baseline + 10%   │
  │  Kibana: no ERROR logs from application pods             │
  └────────────────────────┬─────────────────────────────────┘
                           │
                  ◆ All 4 layers pass?
                  ├── ANY FAIL ──▶ Emergency rollback decision
                  ALL PASS
                           │
                           ▼
                  ✅ Post-cutover validation PASSED
```

---

## Flowchart 4 — Emergency Rollback Trigger

```
              ⚠  ANOMALY DETECTED POST-CUTOVER
                             │
  ◆ Within first 2 hours of cutover?
  │
  ├── YES ──▶ ◆ Severity?
  │            │
  │     CRITICAL / HIGH ──▶ IMMEDIATE ROLLBACK
  │            │            (see 09-Rollback-Procedures.md
  │            │             PROD Rollback Flow)
  │          MEDIUM ──▶ Team vote (5-min window)
  │            │        ├── ROLLBACK → execute
  │            │        └── CONTINUE → add monitoring
  │           LOW ──▶ Continue + document
  │
  └── NO (> 2 hrs) ──▶ ◆ Can fix forward?
                        ├── YES ──▶ Fix in place, document
                        └── NO  ──▶ Rollback decision:
                                    consult leadership

  ROLLBACK TRIGGERS (auto-escalate, no vote needed):
  ┌──────────────────────────────────────────────────────────┐
  │  • Database error rate > 5% for > 2 minutes              │
  │  • Data inconsistency detected                           │
  │  • > 50% of prod pods in CrashLoopBackOff               │
  │  • p99 latency > 3× baseline for > 5 minutes            │
  │  • pglogical subscriber showing row divergence           │
  └──────────────────────────────────────────────────────────┘
```


## Cutover Window: Friday 16:00 - Saturday 16:00 (24 hours)

### Pre-Cutover (T-1 week)

```
Monday: Final readiness review
- [ ] Replication lag stable (< 50ms for 7+ days)
- [ ] All systems performing normally
- [ ] Team trained and ready
- [ ] Communication plan finalized
- [ ] Rollback procedures tested

Wednesday: Final validation
- [ ] Database sizes match (Azure vs On-Prem)
- [ ] Row counts verified
- [ ] Application connectivity working both ways
- [ ] Network performance baseline established
- [ ] Monitoring alerts configured

Friday (Cutover Day): Final Pre-Flight
- [ ] Team assembled (5+ hours before cutover)
- [ ] War room established (conference bridge, Slack channel)
- [ ] Runbooks printed and ready
- [ ] Tools tested (psql, kubectl, DNS utilities)
- [ ] On-call rotation active
- [ ] External communication plan confirmed
```

---

## Cutover Execution Timeline

### T-30 Minutes (15:30)

```
PHASE: Final Preparation

[ ] Notify all stakeholders (email + Slack)
    Message: "Cutover window beginning in 30 minutes"

[ ] Verify current status
    kubectl get nodes -n prod  # All healthy?
    patronictl list             # Replication lag < 50ms?
    curl -s api.company.com     # Apps responding?

[ ] Document baseline metrics
    Response time (p95): _____ ms
    Error rate: _____ %
    Database connections: _____
    CPU utilization: _____ %

[ ] Prepare DNS change commands (ready to execute)
    OLD: api.company.com → 40.x.x.x (Azure)
    NEW: api.company.com → 10.52.100.x (On-Prem MetalLB)

[ ] Prepare database promotion command
    psql -d prod_db -c "SELECT pglogical.drop_subscription('onprem_subscription');"

[ ] Prepare application restart commands
    kubectl rollout restart deployment/api-gateway -n prod
```

### T-15 Minutes (15:45)

```
PHASE: Final Check-In

[ ] Roll call (all team members present)
    - Infrastructure Lead: _______
    - Database Administrator: _______
    - Network Engineer: _______
    - On-Call Manager: _______

[ ] Confirm communication channels
    - War room bridge: ACTIVE
    - Slack channel: ACTIVE
    - Status page: READY
    - Emergency contacts: LISTED

[ ] Perform final data sync
    Check replication lag:
    psql -c "SELECT pg_last_wal_receive_time();"
    Expected: lag < 10ms
```

### T-0 (16:00 - CUTOVER BEGINS)

```
PHASE 1: FINAL VALIDATION (T+0 to T+30min)

T+0 (16:00):
[ ] Post to status page: "Scheduled maintenance begins"
[ ] Announce cutover start in war room
[ ] Begin screen recording (for audit/post-mortem)

T+5 (16:05):
[ ] Final replication lag check
    psql -c "SELECT slot_name, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots;"
    Expected: All replication slots healthy, lag < 10ms
    
    If lag > 100ms: ABORT CUTOVER (wait 24 hours)
    If slots unhealthy: ABORT CUTOVER

[ ] Monitor Azure PostgreSQL
    - All queries completing
    - No connection errors
    - Replication slot functioning

T+15 (16:15):
[ ] Final application status check
    kubectl get pods -n prod  # All pods healthy?
    Expected: All pods in Running state
    
    If any pod crashing: Troubleshoot & fix
    If cannot fix: ABORT CUTOVER

T+25 (16:25):
[ ] Announce: "Team ready, proceeding with cutover"
[ ] Take screenshot of current metrics (pre-cutover baseline)
[ ] All team members confirm readiness

T+30 (16:30):
[ ] Post to status page: "Cutover in progress"
```

### T+30 to T+2H (16:30 - 18:30) PHASE 2: DNS & DATABASE CUTOVER

```
T+30 (16:30):
STEP 1: STOP NEW WRITES TO ON-PREM (Precautionary)
[ ] Pause application deployments on on-prem
    kubectl patch deployment api-gateway -n prod -p \
      '{"spec":{"replicas":0}}'  # Scale down briefly

[ ] Set on-prem database to read-only
    psql -d prod_db -c "ALTER SYSTEM SET default_transaction_read_only = on;"
    psql -d prod_db -c "SELECT pg_reload_conf();"

[ ] Log the moment of truth
    echo "Cutover initiated at $(date)" >> /var/log/cutover.log

T+35 (16:35):
STEP 2: WAIT FOR IN-FLIGHT TRANSACTIONS
[ ] Monitor Azure for completing transactions
    psql -h azure.host -d prod_db -c "SELECT COUNT(*) FROM pg_stat_activity WHERE state != 'idle';"
    
[ ] Wait for active transaction count to reach 0
    Expected: Takes 5-10 minutes
    
    If stuck: Investigate query, check for locks
    If critical: Kill long-running queries (carefully!)

T+45 (16:45):
STEP 3: PROMOTE ON-PREM DATABASE (pglogical → Primary)
[ ] Drop the subscription (stops replication)
    psql -d prod_db -c "DROP SUBSCRIPTION onprem_subscription;"
    
    Expected output: "DROP SUBSCRIPTION"

[ ] Verify subscription removed
    psql -d prod_db -c "SELECT * FROM pg_subscription;"
    Expected: No rows (empty result)

[ ] Remove read-only flag (enable writes)
    psql -d prod_db -c "ALTER SYSTEM SET default_transaction_read_only = off;"
    psql -d prod_db -c "SELECT pg_reload_conf();"

T+50 (16:50):
STEP 4: VERIFY ON-PREM DATABASE WRITABLE
[ ] Test write transaction
    psql -d prod_db -c "BEGIN; INSERT INTO test_table VALUES (1); COMMIT;"
    Expected: INSERT 0 1 (successful write)

[ ] Verify data persisted
    psql -d prod_db -c "SELECT * FROM test_table;"
    Expected: Row with value 1 present

T+55 (16:55):
STEP 5: DNS CUTOVER (CRITICAL STEP - POINT OF NO RETURN)
[ ] Execute DNS change
    # Via provider console or API:
    api.company.com A 10.52.100.x  # On-Prem MetalLB VIP
    # OR update internal DNS/CoreDNS
    
[ ] Wait for DNS propagation
    Expected: 2-5 minutes for client caches to expire
    
[ ] Verify DNS resolution
    nslookup api.company.com
    Expected: Resolves to 10.52.100.x (on-prem)

T+70 (17:10):
STEP 6: UPDATE APPLICATION CONNECTION STRINGS
[ ] Scale applications back up to production level
    kubectl scale deployment/api-gateway --replicas=12 -n prod
    kubectl scale deployment/auth-service --replicas=6 -n prod
    # ... scale other services

[ ] Monitor pod startup logs
    kubectl logs -f deployment/api-gateway -n prod --tail=50
    Expected: Pods connecting to on-prem PostgreSQL (10.30.0.10:5432)
```

### T+2H to T+4H (18:30 - 20:30) PHASE 3: VERIFICATION

```
T+120 (18:30):
STEP 7: APPLICATION CONNECTIVITY CHECK
[ ] Verify all pods running
    kubectl get pods -n prod
    Expected: All pods in Running state (no CrashLoopBackOff)

[ ] Check application logs for errors
    kubectl logs -l app=api-gateway -n prod --tail=100 | grep -i error
    Expected: No connection errors to database

[ ] Test API endpoints
    curl -I https://api.company.com/health
    Expected: HTTP 200 OK
    
    curl -I https://api.company.com/api/users
    Expected: HTTP 200 OK

T+140 (18:50):
STEP 8: DATABASE CONSISTENCY CHECK
[ ] Verify row counts (sample tables)
    psql -d prod_db -c "SELECT COUNT(*) FROM users;"  # On-prem
    psql -h azure.host -d prod_db -c "SELECT COUNT(*) FROM users;"  # Azure
    
    Expected: Counts match (last count from before cutover)

[ ] Check for replication errors (if any pglogical residue)
    psql -d prod_db -c "SELECT * FROM pg_replication_slots;"
    Expected: Empty (no slots remaining)

T+160 (19:10):
STEP 9: MONITOR ERROR RATES
[ ] Check Prometheus dashboard
    http://prometheus:9090/graph
    Query: rate(http_requests_total{status=~"5.."}[5m])
    
    Expected: Error rate < 0.5% (brief spike OK, should decline)

[ ] Check application logs
    kubectl logs -f pod/api-gateway-xyz -n prod --tail=20
    Expected: Normal operation, some DB queries showing

T+180 (19:30):
STEP 10: PERFORMANCE CHECK
[ ] Query response time
    SELECT version();  # Should be < 50ms
    
[ ] API response time
    curl -w "Response time: %{time_total}s\n" api.company.com/api/users
    Expected: < 500ms response time

T+200 (19:50):
STEP 11: USER-FACING VALIDATION
[ ] Open browser, login as test user
    - Username: test@company.com
    - Password: test123
    Expected: Can login successfully
    
[ ] Perform basic user actions
    - [ ] View dashboard
    - [ ] Create order (if e-commerce)
    - [ ] Upload file
    - [ ] Send message
    Expected: All actions succeed

T+240 (20:30):
STEP 12: POST-CUTOVER STATUS
[ ] Declare cutover SUCCESSFUL (if all checks passed)
    Post to status page: "Cutover successful. Service restored to on-premises infrastructure."
    
[ ] Post to war room: "✓ All validations passed. On-prem systems healthy."
```

### T+4H to T+12H (20:30 - 04:30) PHASE 4: EXTENDED MONITORING

```
T+240 to T+720 (20:30 - 04:30):
HYPERCARE MONITORING (Continuous, 8 hours)

[ ] Hourly status checks
    Every hour, on the hour:
    - kubectl get pods -n prod  # Any pod issues?
    - SELECT COUNT(*) FROM users;  # Row counts stable?
    - Prometheus dashboard  # Error rate OK?
    - Application logs  # Errors?

[ ] On-call rotation active
    - Keep incident bridge open
    - Slack channel monitored 24/7
    - Response time: < 5 minutes for any alerts

[ ] Proactive monitoring
    - Watch for memory leaks (kubectl top nodes)
    - Watch for storage filling up
    - Watch for connection pool exhaustion
    - Watch for replication issues (if any)

[ ] Database backup verification
    - Confirm hourly backups running successfully
    - Verify backup completion logs
    - Test point-in-time recovery (optional, might wait until T+24H)
```

### T+12H to T+24H (04:30 - 16:30 next day) PHASE 5: STABILITY & PRODUCTION

```
T+720 to T+1440 (04:30 - 16:30):
FULL PRODUCTION MONITORING

[ ] Morning shift handoff (08:00)
    - Review night-time metrics and logs
    - Check for any alerts or issues
    - Confirm all systems stable

[ ] Declare cutover FULLY SUCCESSFUL (T+24H)
    Post to status page: "Cutover complete. Services fully stable on new infrastructure."
    Send thank-you message to team

[ ] Schedule post-incident review (within 48 hours)
    - What went well?
    - What could be better?
    - Lessons learned for next time

[ ] Cancel Azure infrastructure (Week 28)
    - Keep as backup for 2 more weeks (if decision made to stay on-prem)
    - Archive important data
    - Decommission VMs
```

---

## Rollback Decision Tree (IF NEEDED)

```
Issue detected during cutover?
    ↓
Is it CRITICAL? (error rate >5%, complete outage)
    ├─ YES: Execute IMMEDIATE ROLLBACK
    │   ↓
    │   1. Stop on-prem applications (kubectl scale --replicas=0)
    │   2. Update DNS back to Azure
    │   3. Restore pglogical subscription (if possible)
    │   4. Resume Azure applications
    │   5. Notify stakeholders
    │   6. Post-incident review
    │
    └─ NO: Investigate & Continue Monitoring
        ↓
        Can we FIX in < 1 hour?
        ├─ YES: Fix issue, continue cutover
        └─ NO: EXECUTE ROLLBACK (same steps as above)
```

---

## Success Criteria

```
CUTOVER SUCCESSFUL IF:
✓ All pods running on-prem Kubernetes
✓ Applications responding to requests
✓ Error rate < 0.1% (within 30 min of cutover)
✓ Database accessible, read & write working
✓ No data loss (row counts match)
✓ Performance baseline met (p95 < 500ms)
✓ Users able to login and use applications
✓ All backups completing successfully
✓ No critical alerts (only informational logging)

CUTOVER FAILED IF:
✗ Multiple pods not coming up
✗ API endpoints returning errors
✗ Database connectivity failing
✗ Error rate > 2% sustained for > 15 minutes
✗ Application logs showing data corruption
✗ Performance degraded > 50% from baseline
✗ User reports widespread outages
→ TRIGGER ROLLBACK
```

---

## Post-Cutover Tasks (Week 17+)

```
Day 1-7 (Hypercare):
- [ ] 24/7 on-call coverage
- [ ] Monitor all metrics
- [ ] No new deployments (frozen)
- [ ] Incident response team on standby

Day 8-14 (Stabilization):
- [ ] Reduce on-call to business hours
- [ ] Resume normal deployments (with extra caution)
- [ ] Monitor for memory leaks / performance issues

Day 15-28 (Production):
- [ ] Full operations normal
- [ ] Resume full deployment schedule
- [ ] Azure decommissioning (if decision made)
- [ ] Final lessons-learned review

Day 29+ (Optimization):
- [ ] Performance tuning based on real usage
- [ ] Cost optimization
- [ ] Capacity planning for future growth
```

---

**Reference**: [00-VxRail-Complete-Index.md](./00-VxRail-Complete-Index.md), [09-Rollback-Procedures.md](./09-Rollback-Procedures.md), [07-PROD-Detailed-Implementation.md](./07-PROD-Detailed-Implementation.md)

