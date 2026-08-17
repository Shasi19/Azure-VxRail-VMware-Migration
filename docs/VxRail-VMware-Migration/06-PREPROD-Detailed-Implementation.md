# PREPROD Phase - Detailed Implementation Guide

**Weeks 4-8: Infrastructure Scaling, HA Database & Load Testing**

---

## Overview

| Phase | Duration | Nodes | Focus | Gate |
|-------|----------|-------|-------|------|
| PREPROD | 5 weeks work + 1 buffer | 3M + 9W | HA Database & Load Testing | PREPROD Sign-Off |

**Environment**: Kubernetes k8s-preprod, VLAN 110 (10.51.0.0/16), 75 GB storage, 1K-3K concurrent users

---

## Week 4: Infrastructure Scaling

### Deploy 9 Worker Nodes

```bash
# Create 9 worker VMs (k8s-preprod-worker-01 to k8s-preprod-worker-09)
# VM Config: 8 vCPU, 32 GB RAM, 100 GB storage, VLAN 110

# Install Oracle Linux 9 & Kubernetes 1.34 (same as QA)
# Join all 9 workers to k8s-preprod cluster

kubectl get nodes  # Should show 3M + 9W = 12 total
kubectl create resourcequota preprod-compute --hard=requests.cpu=72,requests.memory=96Gi
```

### Deploy Patroni HA PostgreSQL Cluster

```bash
# Create 3 PostgreSQL VMs (VLAN 30: 10.30.0.110-112)
# Install PostgreSQL 14 + Patroni + etcd on each node

# Configure etcd cluster for Patroni distributed consensus
# Start etcd services: etcdctl member list && etcdctl endpoint health

# Create Patroni configuration (/etc/patroni/patroni.yml)
# Start Patroni: sudo systemctl start patroni && sudo systemctl enable patroni

# Restore database from QA/Azure
sudo su - postgres -c "gunzip < /backup/azure-pg-export.sql.gz | psql -d preprod_db"

# Verify Patroni cluster
patronictl -c /etc/patroni/patroni.yml list
```

---

## Week 5-6: Load Testing & Performance Tuning

### Deploy k6 Load Testing

```bash
# Create k6 load test job in Kubernetes
# Stages: Ramp 1K users → Hold 10 min → Ramp 2K → Hold 10 min → Ramp 3K → Hold 10 min

# Monitor metrics during test:
# - Response time p95 < 500ms
# - Error rate < 0.1%
# - Database replication lag < 100ms

kubectl logs -f job/k6-load-test -n preprod
```

### Database Performance Tuning

```bash
# Enable query logging: log_min_duration_statement = 100
# Create indexes: users(email), orders(user_id, created_at)
# Tune PostgreSQL parameters:
#   - max_connections = 400
#   - shared_buffers = 8GB
#   - effective_cache_size = 24GB
#   - maintenance_work_mem = 2GB

# Verify replication lag
psql -c 'SELECT now() - pg_last_wal_receive_time() as replication_lag;'
```

### Application Optimization

```bash
# Scale API deployments to 5 replicas
# Configure pod anti-affinity for distribution
# Set resource requests/limits: requests(500m/512Mi), limits(1000m/1Gi)
# Enable health checks (liveness, readiness)

kubectl apply -f deployment-tuned.yaml
kubectl rollout status deployment/api-gateway -n preprod
```

---

## Week 7-8: Validation & Sign-Off

### Load Test Results

| Metric | Target | Result | Status |
|--------|--------|--------|--------|
| Peak Users | 3,000 | 3,000 | ✓ |
| Response Time (p95) | < 500ms | _____ | ✓ |
| Error Rate | < 0.1% | _____ | ✓ |
| Replication Lag | < 100ms | _____ | ✓ |
| Auto-Scaling | Functional | Tested | ✓ |
| Memory Leaks | None | Verified | ✓ |

### PREPROD Sign-Off

```
Infrastructure: ✓ READY (12 nodes, 75 GB storage)
Database: ✓ READY (Patroni HA, replication stable)
Applications: ✓ READY (Auto-scaling verified)
Load Testing: ✓ PASSED (3K users sustained)
Performance: ✓ BASELINE SET

RECOMMENDATION: ✓ PROCEED TO PROD
```

---

**Reference**: [00-VxRail-Complete-Index.md](#), [07-PROD-Detailed-Implementation.md](#)

