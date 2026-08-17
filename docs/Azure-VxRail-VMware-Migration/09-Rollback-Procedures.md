# Rollback Procedures

**Emergency Rollback & Recovery Procedures for All Phases**

---

## Rollback Decision Tree

```
◆ Critical data or service failure?
├── YES ──▶ Trigger rollback bridge
│          ├── DNS back to Azure
│          └── Re-enable Azure writes
└── NO ──▶ Continue remediation in place
```

---

## Flowchart 1 — Master Rollback Decision Tree

```
                        ⚠  INCIDENT DETECTED
                               │
               ┌───────────────┼───────────────┐
               ▼               ▼               ▼
        ◆ Severity?       ◆ Phase?        ◆ Data loss?
               │               │               │
   ┌───────────┼───────┐       │               ├── YES ──▶ CRITICAL
   │           │       │       │               └── NO  ──▶ assess below
 CRITICAL    HIGH    MEDIUM    │
   │           │       │       ├── QA       ──▶ Section 2
   │           │       │       ├── PREPROD  ──▶ Section 3
   ▼           ▼       ▼       └── PROD     ──▶ Section 4
  ┌──────────────────────────────────────────────────────────────┐
  │                    SEVERITY ASSESSMENT                       │
  ├──────────────────────────────────────────────────────────────┤
  │ CRITICAL (immediate rollback):                               │
  │  • Database corruption                                       │
  │  • Data loss confirmed                                       │
  │  • Complete infra failure                                    │
  │  • Security breach in migration path                         │
  │  • Network down > 5 min                                      │
  ├──────────────────────────────────────────────────────────────┤
  │ HIGH (rollback within 1 hour):                               │
  │  • Replication lag > 10 s sustained                          │
  │  • Error rate > 2% for > 10 min                              │
  │  • > 50% users impacted                                      │
  ├──────────────────────────────────────────────────────────────┤
  │ MEDIUM (assess & decide within 30 min):                      │
  │  • Performance > 20% degraded                                │
  │  • Intermittent connectivity                                 │
  │  • Isolated pod crashes                                      │
  ├──────────────────────────────────────────────────────────────┤
  │ LOW (monitor & proceed):                                     │
  │  • Single pod restart                                        │
  │  • Transient latency spike                                   │
  └──────────────────────────────────────────────────────────────┘
               │               │               │
   CRITICAL/HIGH             MEDIUM           LOW
               │               │               │
               ▼               ▼               ▼
        TRIGGER            Go/No-go        Continue +
        ROLLBACK           team vote       monitor
```

---

## Flowchart 2 — QA Rollback Flow

```
  ① Decision & Notification (0–5 min)
  ┌──────────────────────────────────────────────────────────┐
  │  Notify: QA Lead, Infra Lead, PM                         │
  │  Slack: #migration-qa-rollback                           │
  └────────────────────────┬─────────────────────────────────┘
                           │
  ② Pause QA tests
  ┌──────────────────────────────────────────────────────────┐
  │  Halt any running test suites                            │
  │  Document current failure state                          │
  └────────────────────────┬─────────────────────────────────┘
                           │
  ③ Re-point QA to Azure DNS
  ┌──────────────────────────────────────────────────────────┐
  │  az network dns record-set a update \                    │
  │    --resource-group rg-qa --zone-name qa.internal \      │
  │    --record-set-name api --ipv4-address <azure-qa-ip>    │
  └────────────────────────┬─────────────────────────────────┘
                           │
  ④ Verify Azure QA is responding
  ┌──────────────────────────────────────────────────────────┐
  │  curl -s https://qa-api.azure.internal/health → 200 OK   │
  └────────────────────────┬─────────────────────────────────┘
                           │
                  ◆ Azure QA healthy?
                  ├── NO ──▶ Escalate to Azure support
                  YES
                           │
  ⑤ Root cause investigation (parallel)
  ┌──────────────────────────────────────────────────────────┐
  │  Review pod logs, DB logs, network traces                │
  │  Fix issue in on-prem environment                        │
  │  Re-test before next migration attempt                   │
  └────────────────────────┬─────────────────────────────────┘
                           │
                           ▼
                  ✅ QA rollback complete (RTO target: 2 hrs)
```

---

## Flowchart 3 — PREPROD Rollback Flow

```
  ① Incident declared (0–5 min)
  ┌──────────────────────────────────────────────────────────┐
  │  Notify: Infra Lead, DB Admin, PM, Ops Lead              │
  │  Bridge: Start war room call                             │
  └────────────────────────┬─────────────────────────────────┘
                           │
  ② Stop application writes to on-prem
  ┌──────────────────────────────────────────────────────────┐
  │  kubectl scale deployment --all --replicas=0 -n preprod  │
  └────────────────────────┬─────────────────────────────────┘
                           │
  ③ Verify Azure PREPROD DB is at acceptable state
  ┌──────────────────────────────────────────────────────────┐
  │  psql -h <azure-preprod> -c "SELECT count(*) FROM <tbl>" │
  │  Compare with on-prem counts                             │
  └────────────────────────┬─────────────────────────────────┘
                           │
                  ◆ Data delta acceptable (< RPO 24hr)?
                  ├── NO ──▶ Evaluate data reconciliation
                  YES
                           │
  ④ Re-point PREPROD DNS to Azure
  ┌──────────────────────────────────────────────────────────┐
  │  Update DNS → Azure PREPROD LB IP                        │
  │  TTL flush on internal resolvers                         │
  └────────────────────────┬─────────────────────────────────┘
                           │
  ⑤ Scale Azure PREPROD apps back up
  ┌──────────────────────────────────────────────────────────┐
  │  kubectl scale deployment --all --replicas=2 -n preprod  │
  │  (pointing to Azure cluster)                             │
  └────────────────────────┬─────────────────────────────────┘
                           │
                           ▼
                  ✅ PREPROD rollback complete (RTO: 4 hrs)
```

---

## Flowchart 4 — PROD Rollback Flow (Minute-by-Minute)

```
  T+00:00  Incident declared
  ┌──────────────────────────────────────────────────────────┐
  │  On-call lead: "Initiating PROD rollback"                │
  │  Broadcast: Slack #prod-incident, PagerDuty              │
  └────────────────────────┬─────────────────────────────────┘

  T+02:00  Stop new writes to on-prem
  ┌──────────────────────────────────────────────────────────┐
  │  kubectl scale deployment/api-gateway --replicas=0 -n prod│
  │  All other write-path services scaled to 0               │
  └────────────────────────┬─────────────────────────────────┘

  T+05:00  Confirm Azure PROD DB is in a good state
  ┌──────────────────────────────────────────────────────────┐
  │  psql -h <azure-prod> -c "SELECT now(), count(*) ..."    │
  │  ◆ Azure DB healthy?                                     │
  │  ├── NO ──▶ CRITICAL ESCALATION: call Azure support NOW  │
  │  YES ──▶ continue                                        │
  └────────────────────────┬─────────────────────────────────┘

  T+08:00  Re-enable writes on Azure PROD
  ┌──────────────────────────────────────────────────────────┐
  │  ALTER DATABASE prod SET default_transaction_read_only   │
  │  = off;   (if it was set read-only during migration)     │
  └────────────────────────┬─────────────────────────────────┘

  T+10:00  Flip DNS back to Azure
  ┌──────────────────────────────────────────────────────────┐
  │  az network dns record-set a update \                    │
  │    --zone-name company.com \                             │
  │    --record-set-name api \                               │
  │    --ipv4-address <azure-prod-lb-ip>                     │
  │  TTL: 60 (already lowered before cutover)                │
  └────────────────────────┬─────────────────────────────────┘

  T+12:00  Verify DNS propagation
  ┌──────────────────────────────────────────────────────────┐
  │  dig api.company.com +short  → should show Azure IP      │
  │  curl -s https://api.company.com/health → 200 OK         │
  └────────────────────────┬─────────────────────────────────┘
                           │
                  ◆ Health check passes?
                  ├── NO ──▶ T+15 escalate, check Azure LB
                  YES
                           │
  T+15:00  Scale Azure PROD apps back up
  ┌──────────────────────────────────────────────────────────┐
  │  kubectl scale deployment --all --replicas=3 -n prod     │
  │  (Azure cluster)                                         │
  └────────────────────────┬─────────────────────────────────┘

  T+20:00  Validate application fully operational
  ┌──────────────────────────────────────────────────────────┐
  │  Run synthetic monitoring checks                         │
  │  Error rate < 0.1%?  p95 latency < baseline?            │
  └────────────────────────┬─────────────────────────────────┘
                           │
  T+30:00  Incident retrospective scheduled
  ┌──────────────────────────────────────────────────────────┐
  │  Document: timeline, root cause, fix required            │
  │  Schedule: retry migration attempt (after fix)           │
  └────────────────────────┬─────────────────────────────────┘
                           │
                           ▼
                  ✅ PROD rollback complete (RTO < 2 hrs)
```

---

## Flowchart 5 — DNS Rollback Sequence

```
  FORWARD (Cutover):  Azure IP ──▶ On-Prem IP
  ROLLBACK:           On-Prem IP ──▶ Azure IP

  ① Pre-requisite: TTL lowered to 60 sec before cutover window

  ② Rollback sequence:

  ┌─────────────────────────────────────────────────────────────────┐
  │  Record            │ Current (on-prem)     │ Rollback (Azure)   │
  ├─────────────────────────────────────────────────────────────────┤
  │  api.company.com   │ 10.52.100.10 (MetalLB)│ 40.x.x.x (Azure LB)│
  │  admin.company.com │ 10.52.100.11          │ 40.x.x.y           │
  │  *.internal        │ 10.52.100.x           │ 10.40.x.x (VNet)   │
  └─────────────────────────────────────────────────────────────────┘

  ③ Execute DNS change:
     External (Azure DNS zone):
     az network dns record-set a update \
       --zone-name company.com --record-set-name api \
       --ipv4-address <azure-ip>

     Internal (on-prem Bind9 → Azure Private DNS):
     rndc reload   # after updating zone file

  ④ Verify propagation globally:
     dig @8.8.8.8 api.company.com +short       → Azure IP
     dig @1.1.1.1 api.company.com +short       → Azure IP
     dig @<on-prem-dns> api.company.com +short → Azure IP

  ⑤ Wait TTL (60 s) + 30 s buffer, then re-confirm:
     curl -sk https://api.company.com/health | jq .status
     Expected: "ok"  |  Source header: "azure"

  ⑥ ◆ All resolvers returning Azure IP?
     ├── NO ──▶ Flush resolver cache:
     │          systemd-resolve --flush-caches
     │          kubectl rollout restart deployment/coredns -n kube-system
     YES ──▶ DNS rollback confirmed ✅
```


## Table of Contents
1. [Rollback Overview](#rollback-overview)
2. [QA Phase Rollback](#qa-phase-rollback)
3. [PREPROD Phase Rollback](#preprod-phase-rollback)
4. [PROD Phase Rollback](#prod-phase-rollback)
5. [Rollback Decision Tree](#rollback-decision-tree)
6. [Communication Protocol](#communication-protocol)

---

## Rollback Overview

### When to Trigger Rollback

```
CRITICAL ISSUES (Immediate Rollback):
- Database corruption detected
- Data loss or unrecoverable errors
- Complete infrastructure failure
- Security breach in migration path
- Network connectivity lost for > 5 minutes

HIGH SEVERITY (Rollback within 1 hour):
- Replication lag > 10 seconds (pglogical)
- Error rate > 2% sustained for > 10 minutes
- Application unavailable to > 50% users
- Database failover not working as expected
- Memory/CPU exhaustion causing OOM errors

MEDIUM SEVERITY (Assess & Decide):
- Performance degradation > 20%
- Intermittent connection issues
- Some API endpoints timing out
- Isolated pod crashes
- Non-critical service failures

LOW SEVERITY (Monitor & Proceed):
- Single pod restart
- Temporary network latency spike
- Minor performance fluctuation
- Expected maintenance activities
```

### Rollback RTO/RPO Targets

| Phase | RTO (Time to Recover) | RPO (Data Loss) | Complexity |
|-------|----------------------|-----------------|-----------|
| QA | 2 hours | 4 hours | Low |
| PREPROD | 4 hours | 24 hours | Medium |
| PROD | < 2 hours | < 1 hour | High |

---

## QA Phase Rollback

### Scenario: Database Restoration Corrupted

```bash
# Step 1: Decision & Communication (5 min)
- Notify: QA Lead, Infrastructure Lead, Project Manager
- Decision: Rollback to Azure QA environment
- Communication: Inform testing team, pause tests

# Step 2: Stop Kubernetes Workloads (5 min)
kubectl scale deployment/api-gateway --replicas=0 -n qa
kubectl scale deployment/authentication-service --replicas=0 -n qa

# Step 3: Update DNS Back to Azure (5 min)
# Update CoreDNS or upstream DNS to point to Azure QA cluster
# If using external DNS provider, update:
# api-qa.internal A 40.x.x.x (Azure Public IP)

# Step 4: Verify Azure QA is Operational (10 min)
# Connect to Azure AKS cluster
az account set --subscription <subscription-id>
az aks get-credentials --resource-group <rg> --name aks-qa-001

kubectl get nodes  # Should show 6 Azure nodes
kubectl get pods -n default  # Applications should be running

# Step 5: Application Reconnection (10 min)
# Update database connection strings back to Azure
# All applications automatically reconnect to Azure PostgreSQL

# Step 6: Validation (15 min)
- Run smoke tests from QA test suite
- Verify API endpoints responding
- Check database connectivity
- Monitor error logs for anomalies

# Step 7: Post-Rollback Analysis (24+ hours)
- Root cause analysis (what went wrong?)
- Update QA documentation
- Re-plan QA phase with corrective actions
- Prepare new implementation plan

# Total RTO: ~1 hour
# Data Loss: 0 (Azure backup was never modified)
```

---

## PREPROD Phase Rollback

### Scenario: Patroni Failover Not Working

```bash
# Step 1: Decision & Communication (5 min)
- Check: Is issue transient or permanent?
- Decision: Stop test operations, rollback to QA environment
- Notification: PREPROD team, skip load testing

# Step 2: Stop Load Testing (10 min)
kubectl delete job k6-load-test -n preprod

# Step 3: Pause PREPROD Operations (5 min)
kubectl scale deployment/api-gateway --replicas=0 -n preprod

# Step 4: Database Rollback Decision
if [ "Patroni_cluster_recoverable" = "true" ]; then
  # Option A: Recover Patroni on-prem
  # Check etcd cluster health
  etcdctl endpoint health
  
  # If etcd healthy, restart failed PostgreSQL node
  sudo systemctl restart postgresql-14
  patronictl -c /etc/patroni/patroni.yml list
  
  # If recovered, mark as "under observation" - DON'T re-start tests yet
  
else
  # Option B: Full rollback to Azure PREPROD
  # Restore from previous PREPROD database backup
  
  # Step 5: Restore from Azure PREPROD
  pg_restore -U postgres -d preprod_db \
    --verbose --clean /backup/azure-preprod.dump
  
  # Step 6: Update DNS & Connection Strings
  # API connections back to Azure PostgreSQL managed service
  
  # Step 7: Re-validate Kubernetes
  kubectl apply -f deployment-azure.yaml
fi

# Step 8: Validation (30 min)
- Verify Patroni cluster status
- Run database connectivity tests
- Confirm no replication lag
- Run application smoke tests

# Step 9: Decision Point
# If Patroni recovered: Resume PREPROD with enhanced monitoring
# If full rollback: Re-plan PREPROD phase with new approach

# Total RTO: 1-2 hours
# Data Loss: Up to 24 hours (last backup restore)
```

---

## PROD Phase Rollback

### **CRITICAL: Multi-Phase PROD Rollback Procedure**

#### Pre-Cutover Rollback (Weeks 9-15, pglogical replication stable)

```bash
# Simplest: Replication still active, Azure is still primary

# Step 1: Stop writes to on-prem (10 min)
sudo su - postgres -c "psql -d prod_db -c \
  'ALTER SYSTEM SET default_transaction_read_only = on;'
SELECT pg_reload_conf();"

# Step 2: Verify Azure is ahead (pglogical lag check)
# Get replication slot info
psql -U replication_user -h azure.host -d prod_db -c \
  "SELECT slot_name, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots;"

# Step 3: Stop on-prem subscription
sudo su - postgres -c "psql -d prod_db -c \
  'DROP SUBSCRIPTION onprem_subscription;'"

# Step 4: Update DNS to Azure
# api.company.com → Azure public IP (Azure Load Balancer)

# Step 5: Resume writes to Azure
# Application connection strings updated to Azure
# Applications automatically reconnect and resume operations

# Step 6: Kubernetes Applications
kubectl scale deployment/api-gateway --replicas=3 -n azure-prod

# Step 7: Validation (30 min)
# - Verify apps connected to Azure
# - Check error logs
# - Confirm no data loss (replication lag was < 50ms)

# Total RTO: 1 hour
# Data Loss: 0 (replication lag was < 50ms)
# User Impact: < 5 minutes (DNS propagation)
```

#### Post-Cutover Rollback (Weeks 15-28, cutover already executed)

**SCENARIO: Critical issue detected AFTER DNS cutover to on-prem**

```bash
# Step 1: Immediately Trigger Incident Response (1 min)
# - Page on-call engineer
# - Alert to infrastructure team
# - Notify leadership (executive sponsor)

# Step 2: Declare SEV-1 Incident (2 min)
# - Create incident ticket
# - Start status page (if public)
# - Begin incident bridge (Slack/conference call)

# Step 3: Quick Assessment (5 min)
# Is on-prem recoverable? OR must we roll back to Azure?

if [ "$OnPremRecoverable" = "YES" ]; then
  # Attempt to fix on-prem issue (parallel with rollback prep)
  # - Restart failed pod
  # - Increase resource limits
  # - Fix configuration
  # Max 15 minutes to attempt fix
fi

# Step 4: Prepare Rollback to Azure (5 min PARALLEL)
# On Azure side (run in background):
- Verify Azure infrastructure healthy
- Bring up standby Azure Kubernetes cluster
- Restore Azure PostgreSQL from backup (if needed)
- Prepare DNS change
- Prepare network routing change

# Step 5: Stop Writes to On-Prem (2 min)
# FREEZE all writes to on-prem database
sudo su - postgres -c "psql -d prod_db -c \
  'ALTER SYSTEM SET default_transaction_read_only = on;'
SELECT pg_reload_conf();"

# Step 6: Wait for Write Freeze (5 min)
# Let in-flight transactions complete
# Monitor for ongoing write attempts

# Step 7: Final Data Backup from On-Prem (10 min)
# If failure is data corruption:
pg_dump -U postgres -d prod_db --format=custom --compress=9 \
  --file=/backup/prod-emergency-backup.dump

# Step 8: Execute DNS Cutover to Azure (1 min)
# Change DNS: api.company.com → Azure public IP
# Update internal DNS: *.internal → Azure endpoints
# Update load balancer configurations

# Step 9: Azure Application Startup (5 min)
# On Azure (if not already running):
kubectl scale deployment/api-gateway --replicas=12 -n prod
kubectl scale deployment/authentication-service --replicas=6 -n prod
# ... scale other microservices

# Step 10: Verify Azure Cluster Health (10 min)
kubectl get nodes  # All nodes healthy?
kubectl get pods -n prod  # All pods running?
kubectl top nodes  # CPU/Memory OK?

# Step 11: Monitor Error Rates (15 min)
# Watch application metrics during Azure startup
# Expected: Brief spike (few minutes), then stabilization
# If errors not decreasing: escalate

# Step 12: End-to-End Smoke Tests (15 min)
- [ ] API login endpoint working
- [ ] Database queries responding
- [ ] File uploads succeeding
- [ ] Payments processing (in test mode)
- [ ] Notifications being sent

# Step 13: User Communication (2 min)
# Post to status page:
# "Brief service outage occurred. Investigating root cause.
#  Estimated recovery: 30 minutes. We apologize for the inconvenience."

# Step 14: Monitor for 1 Hour (60 min)
# Watch metrics for anomalies
# Be ready to rollback on-prem if needed

# Step 15: Post-Incident Review (24+ hours)
# - Root cause analysis (what caused the need to rollback?)
# - Impact assessment (how much data loss? user impacted?)
# - Action items (how to prevent future occurrences?)
# - Update runbooks and procedures

# Total RTO: 45 minutes - 1 hour
# Data Loss: Depends on issue, but potentially significant
# User Impact: Perceived outage, error messages during transition
# Cost: High (incident response, engineering time, potential data recovery)
```

---

## Rollback Decision Tree

```
INCIDENT DETECTED
    ↓
Is it HIGH SEVERITY? (error rate >2%, replication lag >10s)
    ↓ YES                                   ↓ NO
Can we FIX in < 15 min?                   Monitor & Log
    ↓ YES       ↓ NO
  Fix it      Initiate Rollback Planning
    ↓          ↓
              PROD Phase?
              ↓ YES              ↓ NO
         Before Cutover?    (QA/PREPROD)
         ↓ YES    ↓ NO      ↓
      Revert   Failback   Scale down
      pglogical to Azure   on-prem
         ↓         ↓         ↓
       NO-OP    MAJOR     Simple
              PROCEDURE   Restore
                ↓         ↓
             Post-incident Post-incident
             Review       Review
```

---

## Communication Protocol

### Incident Communication Template

```
INCIDENT #[number] - [Brief Description]

Severity: [CRITICAL / HIGH / MEDIUM]
Status: [INVESTIGATING / ROLLING BACK / MONITORING]
Impact: [Number] users unable to access [service]

Timeline:
- T+0 min: Issue detected
- T+5 min: Incident declared, team paged
- T+10 min: Root cause identified
- T+30 min: Rollback initiated
- T+60 min: Services restored
- T+90 min: Incident resolved

Next Update: [timestamp]

For questions: [incident bridge link]
```

### Status Page Updates

```
PRE-ROLLBACK (Transparent Communication):
"We are investigating elevated error rates in our production system.
We will provide updates every 15 minutes."

DURING ROLLBACK:
"Brief service interruption expected while we perform emergency
maintenance. Estimated duration: 30 minutes. We apologize for the
inconvenience."

POST-ROLLBACK:
"Services have been restored. We are monitoring closely for any
residual issues. Full incident post-mortem to follow within 24 hours."
```

---

## Prevention & Learning

### Post-Rollback Actions

1. **Root Cause Analysis** (within 24 hours)
   - What exactly failed?
   - Why didn't we catch it pre-cutover?
   - What signals were missed?

2. **Corrective Actions** (within 1 week)
   - Enhanced monitoring
   - Additional testing procedures
   - Process improvements

3. **Updated Runbooks** (within 1 week)
   - Document lessons learned
   - Update rollback procedures
   - Update troubleshooting guides

4. **Team Debrief** (within 2 days)
   - Review incident timeline
   - What went well
   - What could be better
   - Team morale & support

---

**Reference**: [00-VxRail-Complete-Index.md](./00-VxRail-Complete-Index.md), [12-Cutover-Runbook.md](./12-Cutover-Runbook.md), [09-Rollback-Procedures.md](./09-Rollback-Procedures.md)

