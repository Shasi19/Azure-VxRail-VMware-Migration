# Volume 4: Kubernetes Platform
## Chapter 2: Detailed Commands — Build, Operations & Troubleshooting

> **Audience**: Infrastructure engineers, DevOps engineers, application developers, operations team.

---

## 1. BUILD COMMANDS — Containers & Deployments

### Build and Push Docker Image

```bash
# ── Variables ─────────────────────────────────────────────────────────────
export HARBOR="harbor.internal.company.com"
export PROJECT="production"
export APP="webapp"
export TAG=$(git rev-parse --short HEAD)  # e.g., a3f1c9b

# ── Build (multi-stage, from project root) ────────────────────────────────
docker build \
  --target runtime \
  --build-arg BUILD_VERSION="${TAG}" \
  --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  -t ${HARBOR}/${PROJECT}/${APP}:${TAG} \
  -t ${HARBOR}/${PROJECT}/${APP}:latest \
  .

# ── Security scan before push (Trivy) ────────────────────────────────────
trivy image --exit-code 1 --severity CRITICAL \
  ${HARBOR}/${PROJECT}/${APP}:${TAG}

# ── Login to Harbor and push ─────────────────────────────────────────────
docker login ${HARBOR} -u ${HARBOR_USER} -p ${HARBOR_PASSWORD}
docker push ${HARBOR}/${PROJECT}/${APP}:${TAG}
docker push ${HARBOR}/${PROJECT}/${APP}:latest

echo "✅ Image pushed: ${HARBOR}/${PROJECT}/${APP}:${TAG}"
```

### Deploy via Helm

```bash
# ── Deploy to STAGING ─────────────────────────────────────────────────────
helm upgrade --install webapp-staging ./helm/webapp-chart \
  --namespace staging --create-namespace \
  --set image.tag=${TAG} \
  --values ./helm/values-staging.yaml \
  --wait --timeout 5m \
  --atomic          # Rollback automatically on failure

# ── Deploy to PRODUCTION ──────────────────────────────────────────────────
helm upgrade --install webapp-production ./helm/webapp-chart \
  --namespace production \
  --set image.tag=${TAG} \
  --values ./helm/values-production.yaml \
  --wait --timeout 10m \
  --atomic

# ── Rollback a failed release ─────────────────────────────────────────────
helm rollback webapp-production 0    # 0 = previous revision
helm history webapp-production       # Show all revisions

# ── Diff before deploy (Helm plugin) ─────────────────────────────────────
helm diff upgrade webapp-production ./helm/webapp-chart \
  --namespace production \
  --set image.tag=${TAG} \
  --values ./helm/values-production.yaml
```

---

## 2. KUBERNETES OPERATIONS — Daily Commands

### Pod & Deployment Management

```bash
# ── Check application health ──────────────────────────────────────────────
kubectl get pods -n production -o wide
kubectl get pods -n production -w              # Watch live
kubectl top pods -n production                 # CPU/Memory usage
kubectl top nodes                              # Node resource usage

# ── Describe a pod (debug events, resource limits) ────────────────────────
kubectl describe pod <pod-name> -n production

# ── Get logs ─────────────────────────────────────────────────────────────
kubectl logs <pod-name> -n production              # Current logs
kubectl logs <pod-name> -n production --previous   # Previous (crashed) container
kubectl logs <pod-name> -n production -f           # Follow live
kubectl logs -l app=webapp -n production --all-containers=true  # All webapp pods

# ── Execute into a running pod ───────────────────────────────────────────
kubectl exec -it <pod-name> -n production -- /bin/bash

# ── Scale deployment manually ─────────────────────────────────────────────
kubectl scale deployment webapp -n production --replicas=5
# (HPA will override this — for emergency use)

# ── Restart deployment (rolling) ─────────────────────────────────────────
kubectl rollout restart deployment/webapp -n production

# ── Check rollout status ──────────────────────────────────────────────────
kubectl rollout status deployment/webapp -n production

# ── Undo last rollout ─────────────────────────────────────────────────────
kubectl rollout undo deployment/webapp -n production
```

### HPA (Horizontal Pod Autoscaler) Management

```bash
# ── Check HPA status ─────────────────────────────────────────────────────
kubectl get hpa -n production
kubectl describe hpa webapp-hpa -n production

# ── Watch HPA in real time ────────────────────────────────────────────────
watch -n5 kubectl get hpa -n production

# ── Force scale event (for testing HPA) ──────────────────────────────────
kubectl run load-test --image=busybox --rm -it --restart=Never \
  -- sh -c "while true; do wget -q -O- http://webapp.production.svc.cluster.local/; done"
```

### Resource Quotas & Limits

```bash
# ── Check namespace resource usage ───────────────────────────────────────
kubectl describe resourcequota -n production
kubectl describe limitrange -n production

# ── Check node capacity ───────────────────────────────────────────────────
kubectl describe node worker-1.internal.company.com | grep -A10 "Allocated resources"

# ── Find resource-hungry pods ────────────────────────────────────────────
kubectl top pods -n production --sort-by=cpu
kubectl top pods -n production --sort-by=memory
```

---

## 3. DATABASE COMMANDS — PostgreSQL HA Operations

### Patroni Cluster Management

```bash
# ── Check cluster status ──────────────────────────────────────────────────
patronictl -c /etc/patroni/patroni.yml list

# Expected output:
# + Cluster: prod-postgres (7219825994932387437) +----+-----------+
# | Member    | Host        | Role    | State   | TL | Lag in MB |
# +-----------+-------------+---------+---------+----+-----------+
# | db-node-1 | 10.0.5.1:5432 | Leader | running |  1 |           |
# | db-node-2 | 10.0.5.2:5432 | Replica| running |  1 |         0 |
# | db-node-3 | 10.0.5.3:5432 | Replica| running |  1 |         0 |

# ── Manual failover ───────────────────────────────────────────────────────
patronictl -c /etc/patroni/patroni.yml failover prod-postgres \
  --master db-node-1 --candidate db-node-2 --force

# ── Switchover (planned, graceful) ───────────────────────────────────────
patronictl -c /etc/patroni/patroni.yml switchover prod-postgres \
  --master db-node-1 --candidate db-node-2

# ── Restart a Patroni member ──────────────────────────────────────────────
patronictl -c /etc/patroni/patroni.yml restart prod-postgres db-node-2

# ── Check replication lag ─────────────────────────────────────────────────
psql -h 10.0.5.1 -U postgres -c "
  SELECT application_name,
         state,
         pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes,
         replay_lag
  FROM pg_stat_replication;"
```

### PostgreSQL Operations

```bash
# ── Connect to database (via PgBouncer) ──────────────────────────────────
psql -h 10.0.5.200 -p 6432 -U appuser -d production_db

# ── Check active connections ──────────────────────────────────────────────
psql -h 10.0.5.1 -U postgres -c "
  SELECT count(*), state, wait_event_type, wait_event
  FROM pg_stat_activity
  GROUP BY state, wait_event_type, wait_event
  ORDER BY count DESC;"

# ── Find long-running queries ─────────────────────────────────────────────
psql -h 10.0.5.1 -U postgres -c "
  SELECT pid, now() - query_start AS duration, state, query
  FROM pg_stat_activity
  WHERE state != 'idle'
    AND query_start < now() - interval '30 seconds'
  ORDER BY duration DESC;"

# ── Kill a stuck query ────────────────────────────────────────────────────
psql -h 10.0.5.1 -U postgres -c "SELECT pg_terminate_backend(<pid>);"

# ── Check table bloat / vacuum status ────────────────────────────────────
psql -h 10.0.5.1 -U postgres -d production_db -c "
  SELECT schemaname, tablename,
         n_live_tup, n_dead_tup,
         ROUND(n_dead_tup::numeric/NULLIF(n_live_tup+n_dead_tup,0)*100,2) AS dead_pct,
         last_autovacuum, last_autoanalyze
  FROM pg_stat_user_tables
  ORDER BY n_dead_tup DESC LIMIT 20;"

# ── Manual VACUUM on a table ─────────────────────────────────────────────
psql -h 10.0.5.1 -U postgres -d production_db \
  -c "VACUUM ANALYZE public.orders;"

# ── Backup: pg_dump ───────────────────────────────────────────────────────
pg_dump -h 10.0.5.1 -U postgres -d production_db \
  --format=custom --compress=9 --no-owner \
  -f /mnt/backup/postgres/manual_$(date +%Y%m%d_%H%M%S).dump

# ── Restore from dump ─────────────────────────────────────────────────────
pg_restore -h 10.0.5.1 -U postgres -d production_db_restore \
  --jobs=8 --no-owner \
  /mnt/backup/postgres/manual_20240115_020000.dump

# ── PgBouncer stats ───────────────────────────────────────────────────────
psql -h 10.0.5.200 -p 6432 -U pgbouncer pgbouncer -c "SHOW POOLS;"
psql -h 10.0.5.200 -p 6432 -U pgbouncer pgbouncer -c "SHOW STATS;"
psql -h 10.0.5.200 -p 6432 -U pgbouncer pgbouncer -c "SHOW CLIENTS;"
```

---

## 4. REDIS OPERATIONS

```bash
# ── Connect to Redis cluster ──────────────────────────────────────────────
redis-cli -h 10.0.5.50 -p 6379 -a "${REDIS_PASSWORD}" --tls

# ── Check cluster status ──────────────────────────────────────────────────
redis-cli -h 10.0.5.50 -p 6379 -a "${REDIS_PASSWORD}" cluster info
redis-cli -h 10.0.5.50 -p 6379 -a "${REDIS_PASSWORD}" cluster nodes

# ── Monitor live commands ─────────────────────────────────────────────────
redis-cli -h 10.0.5.50 -p 6379 -a "${REDIS_PASSWORD}" monitor

# ── Check memory usage ────────────────────────────────────────────────────
redis-cli -h 10.0.5.50 -p 6379 -a "${REDIS_PASSWORD}" info memory

# ── Flush specific keys (pattern) ────────────────────────────────────────
redis-cli -h 10.0.5.50 -p 6379 -a "${REDIS_PASSWORD}" \
  --scan --pattern "session:*" | xargs redis-cli del

# ── Check hit/miss ratio ──────────────────────────────────────────────────
redis-cli -h 10.0.5.50 -p 6379 -a "${REDIS_PASSWORD}" info stats \
  | grep -E "keyspace_hits|keyspace_misses"
```

---

## 5. MONITORING COMMANDS — Prometheus & Grafana

```bash
# ── Port-forward Grafana to localhost (if no ingress) ─────────────────────
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring &
# Open: http://localhost:3000 (admin / <password>)

# ── Port-forward Prometheus ───────────────────────────────────────────────
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring &
# Open: http://localhost:9090

# ── Check Prometheus targets health ──────────────────────────────────────
curl -s http://localhost:9090/api/v1/targets \
  | python3 -m json.tool | grep -E '"health"|"job"'

# ── Query Prometheus (promQL) ─────────────────────────────────────────────
# Error rate last 5 minutes:
curl -s 'http://localhost:9090/api/v1/query?query=rate(http_requests_total{status=~"5.."}[5m])'

# P95 response time:
curl -s 'http://localhost:9090/api/v1/query?query=histogram_quantile(0.95,rate(http_request_duration_seconds_bucket[5m]))'

# ── Silence an alert in Alertmanager ─────────────────────────────────────
kubectl port-forward svc/monitoring-kube-prometheus-alertmanager 9093:9093 -n monitoring &
# Open: http://localhost:9093 → Silences → New Silence

# ── Test alert firing ────────────────────────────────────────────────────
kubectl run cpu-load --image=busybox --rm -it --restart=Never \
  -- sh -c "while true; do :; done"   # Will trigger CPU alert
```

---

## 6. VAULT COMMANDS — Secrets Management

```bash
# ── Set Vault address ─────────────────────────────────────────────────────
export VAULT_ADDR="https://vault.company.com"
export VAULT_TOKEN="<root-or-admin-token>"

# ── Check Vault status ────────────────────────────────────────────────────
vault status

# ── Read a secret ─────────────────────────────────────────────────────────
vault kv get secret/webapp/db
vault kv get -field=DB_CONNECTION_STRING secret/webapp/db

# ── Write / update a secret ───────────────────────────────────────────────
vault kv put secret/webapp/db \
  DB_CONNECTION_STRING="Server=10.0.5.200;Database=production_db;Port=6432;..."

# ── List secrets ─────────────────────────────────────────────────────────
vault kv list secret/webapp/

# ── Generate dynamic DB credentials ──────────────────────────────────────
vault read database/creds/webapp-role
# Returns: username + password (rotated automatically)

# ── Rotate root DB credentials ────────────────────────────────────────────
vault write -force database/rotate-root/postgresql

# ── Unseal Vault (if restarted) ───────────────────────────────────────────
for pod in vault-0 vault-1 vault-2; do
  kubectl exec -n vault $pod -- vault operator unseal <UNSEAL_KEY_1>
  kubectl exec -n vault $pod -- vault operator unseal <UNSEAL_KEY_2>
  kubectl exec -n vault $pod -- vault operator unseal <UNSEAL_KEY_3>
done
```

---

## 7. ARGOCD COMMANDS — GitOps Operations

```bash
# ── Login to ArgoCD CLI ───────────────────────────────────────────────────
argocd login argocd.company.com \
  --username admin \
  --password $(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d)

# ── List applications ─────────────────────────────────────────────────────
argocd app list

# ── Sync an application ───────────────────────────────────────────────────
argocd app sync webapp-production --force

# ── Check sync status ─────────────────────────────────────────────────────
argocd app get webapp-production

# ── Rollback to previous version ─────────────────────────────────────────
argocd app rollback webapp-production

# ── Watch live sync ───────────────────────────────────────────────────────
argocd app wait webapp-production --health
```

---

## 8. TROUBLESHOOTING GUIDE

### App Not Starting — Debug Flow

```bash
# Step 1: Check pod events
kubectl describe pod <pod-name> -n production | tail -20

# Step 2: Check image pull
kubectl get events -n production --sort-by='.lastTimestamp' | grep -i "failed\|error\|back-off"

# Step 3: Check resource constraints
kubectl describe node $(kubectl get pod <pod-name> -n production -o jsonpath='{.spec.nodeName}') \
  | grep -A 5 "Allocated"

# Step 4: Check if readiness probe failing
kubectl logs <pod-name> -n production | grep -i "health\|ready\|error"

# Step 5: Check Vault secret injection
kubectl logs <pod-name> -n production -c vault-agent-init
kubectl exec -it <pod-name> -n production -- env | grep DB_

# Step 6: Check DNS resolution in pod
kubectl exec -it <pod-name> -n production -- nslookup kubernetes.default.svc.cluster.local
kubectl exec -it <pod-name> -n production -- nslookup db.production.svc.cluster.local
```

### Database Connection Issues

```bash
# Test from K8s pod to PostgreSQL
kubectl run db-test --image=postgres:15 --rm -it --restart=Never \
  -- psql -h 10.0.5.200 -p 6432 -U appuser -d production_db -c "SELECT 1;"

# Check HAProxy backend status
echo "show stat" | socat /var/run/haproxy/admin.sock stdio | cut -d',' -f1,2,18,19

# Check Patroni leader
curl -s http://10.0.5.1:8008/master    # Returns 200 if this node is leader
curl -s http://10.0.5.2:8008/replica   # Returns 200 if this node is replica

# Check replication lag > 0
psql -h 10.0.5.1 -U postgres \
  -c "SELECT client_addr, state, replay_lag FROM pg_stat_replication;"
```

### Network / Connectivity Issues

```bash
# Test from pod to external
kubectl exec -it <pod-name> -n production -- curl -v https://api.external.com

# Test node-to-node connectivity
ssh worker-1 ping -c 3 10.0.4.22    # Worker-1 to Worker-2

# Check Calico network policy
kubectl get networkpolicy -n production
calicoctl get globalnetworkpolicy

# Check MetalLB is responding on VIP
curl -v https://10.0.4.200/health    # NGINX Ingress VIP

# Check F5 pool member health (F5 CLI)
tmsh show ltm pool k8s-ingress-pool members

# Check Palo Alto routing
ssh admin@10.0.1.2 "show routing route type unicast"
```

### K8s Node Issues

```bash
# Node NotReady — investigate
kubectl describe node <node-name> | grep -A10 "Conditions:"
kubectl get events --field-selector involvedObject.name=<node-name>

# Drain a node for maintenance
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Uncordon after maintenance
kubectl uncordon <node-name>

# Check kubelet status on node
ssh <node-name> systemctl status kubelet
ssh <node-name> journalctl -u kubelet -n 50 --no-pager

# Check disk pressure
ssh <node-name> df -h
ssh <node-name> du -sh /var/lib/containerd   # Container storage usage
```

### Performance Issues

```bash
# Find slowest endpoints (Prometheus query)
# Via: http://prometheus:9090/graph
# Query: topk(10, histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])))

# Check DB slow queries (pgBadger)
pgbadger /var/log/postgresql/postgresql-*.log -o /tmp/report.html
# Open report.html for top slow queries

# K8s pod resource usage history
kubectl top pods -n production --sort-by=cpu
kubectl top pods -n production --sort-by=memory

# Check GC pressure in JVM apps (if applicable)
kubectl exec -it <pod-name> -n production -- jcmd 1 GC.heap_info

# Network throughput test between nodes
kubectl run iperf-server --image=networkstatic/iperf3 --port=5201 -- iperf3 -s
kubectl run iperf-client --image=networkstatic/iperf3 --rm -it --restart=Never \
  -- iperf3 -c iperf-server.default.svc.cluster.local -t 30
```

---

## 9. END-USER OPERATIONS — For App Team

```bash
# ── Check your app version running ───────────────────────────────────────
kubectl get deployment webapp -n production \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# ── Trigger a new deployment ─────────────────────────────────────────────
# 1. Commit and push your code to GitLab main branch
# 2. GitLab CI builds image, pushes to Harbor
# 3. Update image tag in GitOps repo
# 4. ArgoCD picks up change and deploys automatically

# ── Deploy a hotfix manually ─────────────────────────────────────────────
argocd app sync webapp-production --force --prune
# OR via Helm:
helm upgrade webapp-production ./helm/webapp-chart \
  --namespace production \
  --set image.tag=hotfix-abc123 \
  --reuse-values --wait

# ── Check if your changes are live ───────────────────────────────────────
curl -s https://app.company.com/api/version
curl -s https://app.company.com/health

# ── View your app logs ────────────────────────────────────────────────────
# Option 1: Kibana → http://kibana.company.com (filter: kubernetes.namespace: production)
# Option 2: kubectl
kubectl logs -l app=webapp -n production --tail=100 -f

# ── Open a debug shell in a running pod ──────────────────────────────────
kubectl exec -it $(kubectl get pod -n production -l app=webapp -o name | head -1) \
  -n production -- /bin/bash

# ── Copy a file from pod ─────────────────────────────────────────────────
kubectl cp production/<pod-name>:/app/logs/app.log ./app.log
```

---

## 10. BACKUP & RESTORE COMMANDS

```bash
# ── Velero: K8s namespace backup ─────────────────────────────────────────
velero backup create production-backup-$(date +%Y%m%d) \
  --include-namespaces production \
  --wait

# ── Velero: List backups ──────────────────────────────────────────────────
velero backup get

# ── Velero: Restore a namespace ──────────────────────────────────────────
velero restore create --from-backup production-backup-20240115 \
  --include-namespaces production \
  --namespace-mappings production:production-restored

# ── PostgreSQL: Point-in-time restore ────────────────────────────────────
# 1. Stop patroni on all nodes
systemctl stop patroni

# 2. Restore base backup
pg_restore -h localhost -U postgres -d production_db_pitr \
  --jobs=8 \
  /mnt/backup/postgres/base_20240115_020000/

# 3. Set recovery target in postgresql.conf
echo "recovery_target_time = '2024-01-15 14:30:00'" >> \
  /var/lib/postgresql/15/data/postgresql.conf

# 4. Create recovery signal
touch /var/lib/postgresql/15/data/recovery.signal

# 5. Start PostgreSQL and verify
systemctl start postgresql
psql -c "SELECT pg_is_in_recovery();"   # Should be true during recovery
```

---

**Document Version**: 2.0 | **Date**: July 2026 | **Classification**: Internal Use Only
