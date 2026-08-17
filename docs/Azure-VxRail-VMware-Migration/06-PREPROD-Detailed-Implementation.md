# PREPROD Environment - Detailed Implementation Guide
**Phase 3 | Weeks 4-8 | PostgreSQL Patroni HA + Load Testing**

**Environment**: Kubernetes k8s-preprod, VLAN 110 (10.51.0.0/16), 75 GB storage quota, 1K-3K concurrent users

**Infrastructure Context** (from VxRail cluster):
- 6 VxRail hosts | 157 VMs currently running
- CPU: 149.84 GHz used / 871.58 GHz total / 721.75 GHz free (17.2% utilization — plenty of headroom)
- Memory: 3.11 TB used / 4.5 TB total / 1.38 TB free (69.1% — PREPROD gets 96 GB allocation)
- Storage: 156.8 TB used / 247.66 TB total / **90.86 TB free** (PREPROD gets 75 GB quota)
- 9 datastores configured | 113 networks available

---

## Overview & Phase Summary

| Phase | Duration | Nodes | Focus | Gate |
|-------|----------|-------|-------|------|
| PREPROD | 5 weeks work + 1 buffer | 3M + 9W | HA Database, pgBouncer & Load Testing | PREPROD Sign-Off |

---

## PREPROD Phase Flowchart

```
┌─────────────────────────────────────────────────────────────────────────┐
│              PREPROD PHASE FLOW (Weeks 4-8)                            │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │   ① QA Sign-Off Gate PASSED   │
              │   (Week 3 approval received)  │
              └───────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  WEEK 4: Infrastructure Scaling + Patroni HA Setup                     │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────────┐  │
│  │ Deploy 9     │───▶│ Install PG15 │───▶│ Configure Patroni + etcd │  │
│  │ Worker Nodes │    │ on 3 DB nodes│    │ + pgBouncer pooling      │  │
│  └──────────────┘    └──────────────┘    └──────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  WEEK 5: Application Deployment to PREPROD                             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────────┐  │
│  │ Harbor       │───▶│ ArgoCD       │───▶│ ConfigMaps + Secrets     │  │
│  │ Registry     │    │ Deployment   │    │ Migration                │  │
│  └──────────────┘    └──────────────┘    └──────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  WEEK 6: Load Testing (k6/Locust)                                      │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────────┐  │
│  │ 1K Users     │───▶│ 3K Users     │───▶│ DB Stress Test           │  │
│  │ Ramp Test    │    │ Sustained    │    │ + Performance Tuning     │  │
│  └──────────────┘    └──────────────┘    └──────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  WEEK 7: Failover & DR Testing                                         │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────────┐  │
│  │ Patroni      │───▶│ K8s Node     │───▶│ Storage Failure +        │  │
│  │ Failover     │    │ Failure      │    │ Network Partition Test   │  │
│  └──────────────┘    └──────────────┘    └──────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  WEEK 8: Sign-Off & PREPROD Completion                                 │
│                                                                        │
│        ◆ All load tests PASS? ───YES──▶ PREPROD SIGN-OFF              │
│                  │                      │                              │
│                 NO                      ▼                              │
│                  │             Proceed to PROD Phase                   │
│                  ▼                                                     │
│          Remediate + Retest                                            │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Week 4: Patroni HA Database Setup

### Why Patroni?

Patroni is the industry-standard High Availability solution for PostgreSQL. Unlike simple primary-replica setups, Patroni provides automatic failover, distributed consensus using etcd, replication management, REST health endpoints, and seamless pgBouncer integration.

### Step 1: Install PostgreSQL 15 on All DB Nodes

```bash
sudo dnf update -y
sudo dnf install -y epel-release wget curl vim net-tools bind-utils
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
sudo dnf -qy module disable postgresql
sudo dnf install -y postgresql15-server postgresql15-contrib postgresql15-pglogical
sudo mkdir -p /var/lib/pgsql/15/data
sudo chown -R postgres:postgres /var/lib/pgsql/15/
sudo chmod 700 /var/lib/pgsql/15/data
```

### Step 2: Install and Configure etcd Cluster

```bash
wget https://github.com/etcd-io/etcd/releases/download/v3.5.9/etcd-v3.5.9-linux-amd64.tar.gz
tar xzf etcd-v3.5.9-linux-amd64.tar.gz
sudo mv etcd-v3.5.9-linux-amd64/etcd /usr/local/bin/
sudo mv etcd-v3.5.9-linux-amd64/etcdctl /usr/local/bin/
sudo useradd --no-create-home --shell /bin/false etcd
sudo mkdir -p /var/lib/etcd /etc/etcd
sudo chown -R etcd:etcd /var/lib/etcd /etc/etcd
```

### Step 3: Configure Patroni

```yaml
scope: preprod-pg-cluster
namespace: /service/
name: pg-preprod-node1
restapi:
  listen: 10.30.0.110:8008
  connect_address: 10.30.0.110:8008
etcd:
  hosts: 10.30.0.110:2379,10.30.0.111:2379,10.30.0.112:2379
bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
postgresql:
  listen: 0.0.0.0:5432
  connect_address: 10.30.0.110:5432
  data_dir: /var/lib/pgsql/15/data
  bin_dir: /usr/pgsql-15/bin
```

### Step 4: Setup pgBouncer Connection Pooling

```bash
sudo dnf install -y pgbouncer
sudo systemctl enable --now pgbouncer
psql -h 127.0.0.1 -p 5432 -U pgbouncer_admin pgbouncer -c "SHOW POOLS;"
```

### Step 5: Validate Patroni HA Failover

```bash
patronictl -c /etc/patroni/patroni.yml list
psql -h 10.30.0.113 -p 5432 -U preprod_app preprod -c "SELECT pg_is_in_recovery();"
```

---

## Week 5: Application Deployment to PREPROD

### Harbor, ArgoCD, ConfigMaps, and Secrets

```bash
kubectl create namespace preprod
kubectl label namespace preprod environment=preprod tier=staging
argocd app sync preprod-apps --timeout 300
kubectl get pods -n preprod
```

---

## Week 6: Load Testing

### k6 and pgbench

```bash
kubectl create namespace k6-testing
helm repo add grafana https://grafana.github.io/helm-charts
helm install k6-operator grafana/k6-operator -n k6-testing
pgbench -h 10.30.0.113 -p 5432 -U preprod_app preprod -c 50 -j 4 -T 600 -P 10 --report-per-command
```

---

## Week 7: Failover & DR Testing

### Patroni, Kubernetes, Storage, and Network Tests

```bash
kubectl cordon k8s-preprod-worker-05
kubectl drain k8s-preprod-worker-05 --ignore-daemonsets --delete-emptydir-data --force
kubectl uncordon k8s-preprod-worker-05
```

---

## Week 8: Sign-Off & PREPROD Completion

### Success Criteria

| Category | Criterion | Target | Status |
|----------|-----------|--------|--------|
| Infrastructure | 12 nodes online (3M + 9W) | 12/12 | ☐ |
| Database HA | Patroni cluster 3-node | 3/3 running | ☐ |
| Load Testing | 3K users — error rate | < 0.1% | ☐ |
| Backup | Veeam backup of PREPROD VMs | Verified | ☐ |

### Sign-Off Checklist

- 12 Kubernetes nodes healthy
- vSAN storage datastores healthy (9 configured)
- 113 networks configured and accessible
- Failover test completed and verified

---

## Lessons Learned Documentation

- Patroni failover target: < 30 seconds
- pgBouncer helps avoid connection exhaustion
- k6 provides realistic load simulation

---

## Appendix A: Detailed Validation Worksheets

### Worksheet 001
- Objective: Capture PREPROD execution evidence item 1.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 002
- Objective: Capture PREPROD execution evidence item 2.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 003
- Objective: Capture PREPROD execution evidence item 3.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 004
- Objective: Capture PREPROD execution evidence item 4.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 005
- Objective: Capture PREPROD execution evidence item 5.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 006
- Objective: Capture PREPROD execution evidence item 6.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 007
- Objective: Capture PREPROD execution evidence item 7.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 008
- Objective: Capture PREPROD execution evidence item 8.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 009
- Objective: Capture PREPROD execution evidence item 9.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 010
- Objective: Capture PREPROD execution evidence item 10.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 011
- Objective: Capture PREPROD execution evidence item 11.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 012
- Objective: Capture PREPROD execution evidence item 12.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 013
- Objective: Capture PREPROD execution evidence item 13.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 014
- Objective: Capture PREPROD execution evidence item 14.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 015
- Objective: Capture PREPROD execution evidence item 15.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 016
- Objective: Capture PREPROD execution evidence item 16.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 017
- Objective: Capture PREPROD execution evidence item 17.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 018
- Objective: Capture PREPROD execution evidence item 18.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 019
- Objective: Capture PREPROD execution evidence item 19.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 020
- Objective: Capture PREPROD execution evidence item 20.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 021
- Objective: Capture PREPROD execution evidence item 21.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 022
- Objective: Capture PREPROD execution evidence item 22.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 023
- Objective: Capture PREPROD execution evidence item 23.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 024
- Objective: Capture PREPROD execution evidence item 24.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 025
- Objective: Capture PREPROD execution evidence item 25.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 026
- Objective: Capture PREPROD execution evidence item 26.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 027
- Objective: Capture PREPROD execution evidence item 27.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 028
- Objective: Capture PREPROD execution evidence item 28.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 029
- Objective: Capture PREPROD execution evidence item 29.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 030
- Objective: Capture PREPROD execution evidence item 30.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 031
- Objective: Capture PREPROD execution evidence item 31.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 032
- Objective: Capture PREPROD execution evidence item 32.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 033
- Objective: Capture PREPROD execution evidence item 33.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 034
- Objective: Capture PREPROD execution evidence item 34.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 035
- Objective: Capture PREPROD execution evidence item 35.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 036
- Objective: Capture PREPROD execution evidence item 36.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 037
- Objective: Capture PREPROD execution evidence item 37.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 038
- Objective: Capture PREPROD execution evidence item 38.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 039
- Objective: Capture PREPROD execution evidence item 39.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 040
- Objective: Capture PREPROD execution evidence item 40.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 041
- Objective: Capture PREPROD execution evidence item 41.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 042
- Objective: Capture PREPROD execution evidence item 42.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 043
- Objective: Capture PREPROD execution evidence item 43.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 044
- Objective: Capture PREPROD execution evidence item 44.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 045
- Objective: Capture PREPROD execution evidence item 45.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 046
- Objective: Capture PREPROD execution evidence item 46.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 047
- Objective: Capture PREPROD execution evidence item 47.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 048
- Objective: Capture PREPROD execution evidence item 48.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 049
- Objective: Capture PREPROD execution evidence item 49.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 050
- Objective: Capture PREPROD execution evidence item 50.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 051
- Objective: Capture PREPROD execution evidence item 51.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 052
- Objective: Capture PREPROD execution evidence item 52.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 053
- Objective: Capture PREPROD execution evidence item 53.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 054
- Objective: Capture PREPROD execution evidence item 54.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 055
- Objective: Capture PREPROD execution evidence item 55.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 056
- Objective: Capture PREPROD execution evidence item 56.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 057
- Objective: Capture PREPROD execution evidence item 57.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 058
- Objective: Capture PREPROD execution evidence item 58.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 059
- Objective: Capture PREPROD execution evidence item 59.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 060
- Objective: Capture PREPROD execution evidence item 60.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 061
- Objective: Capture PREPROD execution evidence item 61.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 062
- Objective: Capture PREPROD execution evidence item 62.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 063
- Objective: Capture PREPROD execution evidence item 63.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 064
- Objective: Capture PREPROD execution evidence item 64.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 065
- Objective: Capture PREPROD execution evidence item 65.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 066
- Objective: Capture PREPROD execution evidence item 66.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 067
- Objective: Capture PREPROD execution evidence item 67.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 068
- Objective: Capture PREPROD execution evidence item 68.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 069
- Objective: Capture PREPROD execution evidence item 69.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 070
- Objective: Capture PREPROD execution evidence item 70.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 071
- Objective: Capture PREPROD execution evidence item 71.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 072
- Objective: Capture PREPROD execution evidence item 72.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 073
- Objective: Capture PREPROD execution evidence item 73.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 074
- Objective: Capture PREPROD execution evidence item 74.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 075
- Objective: Capture PREPROD execution evidence item 75.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 076
- Objective: Capture PREPROD execution evidence item 76.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 077
- Objective: Capture PREPROD execution evidence item 77.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 078
- Objective: Capture PREPROD execution evidence item 78.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 079
- Objective: Capture PREPROD execution evidence item 79.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 080
- Objective: Capture PREPROD execution evidence item 80.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 081
- Objective: Capture PREPROD execution evidence item 81.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 082
- Objective: Capture PREPROD execution evidence item 82.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 083
- Objective: Capture PREPROD execution evidence item 83.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 084
- Objective: Capture PREPROD execution evidence item 84.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 085
- Objective: Capture PREPROD execution evidence item 85.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 086
- Objective: Capture PREPROD execution evidence item 86.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 087
- Objective: Capture PREPROD execution evidence item 87.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 088
- Objective: Capture PREPROD execution evidence item 88.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 089
- Objective: Capture PREPROD execution evidence item 89.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 090
- Objective: Capture PREPROD execution evidence item 90.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 091
- Objective: Capture PREPROD execution evidence item 91.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 092
- Objective: Capture PREPROD execution evidence item 92.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 093
- Objective: Capture PREPROD execution evidence item 93.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 094
- Objective: Capture PREPROD execution evidence item 94.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 095
- Objective: Capture PREPROD execution evidence item 95.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 096
- Objective: Capture PREPROD execution evidence item 96.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 097
- Objective: Capture PREPROD execution evidence item 97.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.

### Worksheet 098
- Objective: Capture PREPROD execution evidence item 98.
- Expected result: PASS with current VxRail capacity of 6 hosts, 157 VMs, 9 datastores, and 113 networks.
- Capacity note: CPU 871.58 GHz total / 149.84 GHz used / 721.75 GHz free; memory 4.5 TB total / 3.11 TB used / 1.38 TB free; storage 247.66 TB total / 156.8 TB used / 90.86 TB free.
