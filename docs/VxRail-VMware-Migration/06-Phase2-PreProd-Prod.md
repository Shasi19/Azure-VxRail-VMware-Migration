# Phase 2 Migration — PreProd + Prod Environments

> **Scope:** Migrate PreProd and Production from Azure to VxRail on-prem  
> **Duration:** 10 weeks (Weeks 9–18)  
> **Risk Level:** High — production data and live traffic  
> **Prerequisite:** Phase 1 (Dev + QA) successfully completed and stable for 2+ weeks  
> **Strategy:** Live replication + scheduled maintenance window cutover for Prod

---

## Phase 2 Timeline

```
Week 9    ─── Provision Phase 2 VMs (PreProd workers, DB cluster VMs)
Week 10   ─── PreProd infrastructure setup + services
Week 11   ─── PreProd database migration + app deployment
Week 12   ─── PreProd 2-week validation (parallel run)
Week 13   ─── Prod infrastructure setup + workers
Week 14   ─── Prod database live replication start
Week 15   ─── Prod go-live window (2-hour maintenance weekend)
Week 16   ─── Prod post-go-live monitoring (1 week)
Week 17   ─── Prod stabilization + performance tuning
Week 18   ─── Azure PreProd + Prod decommission
```

---

## Go / No-Go Gates

### Gate P1 — Before PreProd Migration (end of Week 9)

| Check | Pass Criteria |
|-------|--------------|
| Phase 1 stable | No P1/P2 incidents in Dev or QA in last 7 days |
| Phase 2 VMs ready | All PreProd + Prod VMs created and reachable |
| Database HA tested | Patroni failover tested on dev DB (promoted replica, verified reconnect) |
| Storage capacity | vSAN has 12+ TB free usable capacity |
| Network | Routing from on-prem to Azure VPN/ExpressRoute working (for live replication) |

### Gate P2 — Before Prod Migration (end of Week 12)

| Check | Pass Criteria |
|-------|--------------|
| PreProd stable 2 weeks | No P1 incidents; P95 latency within 10% of Azure PreProd |
| All PreProd tests pass | UAT sign-off from QA team |
| Prod DB replication ready | `pglogical` replication lag < 1 second |
| Rollback tested | Full rollback to Azure PreProd tested in < 30 minutes |
| Monitoring alerting | All Prod SLA alerts configured and tested |
| Stakeholder sign-off | CTO / Product Owner approval in writing |

### Gate P3 — Prod Go-Live (Week 15 maintenance window)

| Check | Pass Criteria |
|-------|--------------|
| 0 active P1/P2 incidents | Incident tracker clear |
| DB replication lag | pglogical lag < 500ms; MongoDB oplog < 1 second |
| Load test passed | 150% normal traffic load tested on on-prem Prod |
| Rollback < 30 minutes | Rollback procedure rehearsed and timed |
| Team on call | DBA, K8s engineer, network engineer available for full window |
| Azure Prod still live | Do NOT delete Azure Prod until on-prem Prod stable for 1 week |

---

## Week 9: Provision Phase 2 VMs

### Step 9.1 — Create PreProd + Prod VMs

```bash
# Additional K8s workers for PreProd and Prod
# (worker-3, worker-4 for PreProd; worker-5, worker-6 for Prod)
# Use the same create-k8s-vms.sh script from Phase 1 but for remaining VMs

# Additional workers
for VM_SPEC in \
  "k8s-worker-3|12|32768|150|vxrail-5.internal.company.com|PG-K8s-Nodes" \
  "k8s-worker-4|12|32768|150|vxrail-5.internal.company.com|PG-K8s-Nodes" \
  "k8s-worker-5|16|65536|200|vxrail-6.internal.company.com|PG-K8s-Nodes" \
  "k8s-worker-6|16|65536|200|vxrail-6.internal.company.com|PG-K8s-Nodes"; do
  IFS='|' read -r NAME CPUS MEM DISK HOST NETWORK <<< "$VM_SPEC"
  govc vm.clone --vm="ubuntu-22.04-template" --name="$NAME" \
    --host="$HOST" --datastore=vsanDatastore --on=false
  govc vm.change --vm="$NAME" --cpu="$CPUS" --memory="$MEM"
  govc vm.disk.change --vm="$NAME" --disk.label="Hard disk 1" --size="${DISK}GB"
done

# Database VMs for PreProd (2-node PostgreSQL)
for VM_SPEC in \
  "db-preprod-01|4|16384|500|vxrail-3.internal.company.com|PG-Databases" \
  "db-preprod-02|4|16384|500|vxrail-4.internal.company.com|PG-Databases" \
  "mongo-preprod-01|4|8192|300|vxrail-3.internal.company.com|PG-Databases" \
  "mongo-preprod-02|4|8192|300|vxrail-5.internal.company.com|PG-Databases"; do
  IFS='|' read -r NAME CPUS MEM DISK HOST NETWORK <<< "$VM_SPEC"
  govc vm.clone --vm="ubuntu-22.04-template" --name="$NAME" \
    --host="$HOST" --datastore=vsanDatastore --on=false
  govc vm.change --vm="$NAME" --cpu="$CPUS" --memory="$MEM"
  govc vm.disk.change --vm="$NAME" --disk.label="Hard disk 1" --size="${DISK}GB"
done

# Database VMs for Prod (3-node PostgreSQL + 3-node MongoDB)
for VM_SPEC in \
  "db-prod-01|8|32768|1024|vxrail-4.internal.company.com|PG-Databases" \
  "db-prod-02|8|32768|1024|vxrail-5.internal.company.com|PG-Databases" \
  "db-prod-03|8|32768|1024|vxrail-6.internal.company.com|PG-Databases" \
  "mongo-prod-01|4|16384|500|vxrail-4.internal.company.com|PG-Databases" \
  "mongo-prod-02|4|16384|500|vxrail-5.internal.company.com|PG-Databases" \
  "mongo-prod-03|4|16384|500|vxrail-6.internal.company.com|PG-Databases"; do
  IFS='|' read -r NAME CPUS MEM DISK HOST NETWORK <<< "$VM_SPEC"
  govc vm.clone --vm="ubuntu-22.04-template" --name="$NAME" \
    --host="$HOST" --datastore=vsanDatastore --on=false
  govc vm.change --vm="$NAME" --cpu="$CPUS" --memory="$MEM"
  govc vm.disk.change --vm="$NAME" --disk.label="Hard disk 1" --size="${DISK}GB"
done
```

### Step 9.2 — Join Phase 2 Workers to K8s Cluster

```bash
# Get join command (run on master-1)
JOIN_CMD=$(kubeadm token create --print-join-command)

# Join workers 3-6
for WORKER_IP in 10.0.4.23 10.0.4.24 10.0.4.25 10.0.4.26; do
  ssh ubuntu@"$WORKER_IP" "sudo ${JOIN_CMD}"
done

# Label workers for PreProd and Prod
kubectl label node k8s-worker-3 workload-tier=preprod
kubectl label node k8s-worker-4 workload-tier=preprod
kubectl label node k8s-worker-5 workload-tier=prod
kubectl label node k8s-worker-6 workload-tier=prod

# Taint Prod workers — only prod-labelled pods schedule here
kubectl taint node k8s-worker-5 env=prod:NoSchedule
kubectl taint node k8s-worker-6 env=prod:NoSchedule

# Verify
kubectl get nodes --show-labels | grep -E 'worker-[3-6]'
```

---

## Week 10-11: PreProd Migration

### Step 10.1 — PreProd PostgreSQL HA (2-node Patroni)

```bash
# On BOTH db-preprod-01 and db-preprod-02

# Install PostgreSQL 15, etcd, Patroni
sudo apt install -y postgresql-15 python3-pip python3-psycopg2
sudo pip3 install patroni[etcd] python-etcd

# Install etcd on monitoring-01 (or a dedicated etcd VM)
# For simplicity, use etcd on monitoring-01 as Patroni DCS

# Patroni config for db-preprod-01 (primary)
sudo tee /etc/patroni/patroni.yml << 'EOF'
scope: preprod-postgres
namespace: /patroni/
name: db-preprod-01

restapi:
  listen: 10.0.5.13:8008
  connect_address: 10.0.5.13:8008

etcd:
  hosts: 10.0.6.13:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      parameters:
        wal_level: replica
        max_wal_senders: 10
        max_replication_slots: 10

  initdb:
    - encoding: UTF8
    - data-checksums

  pg_hba:
    - host replication replicator 10.0.5.0/24 scram-sha-256
    - host all all 10.0.4.0/24 scram-sha-256
    - host all all 10.0.3.0/24 scram-sha-256

  users:
    admin:
      password: PreprodAdmin2026!
      options:
        - superuser
    replicator:
      password: Replicator2026!
      options:
        - replication

postgresql:
  listen: 10.0.5.13:5432
  connect_address: 10.0.5.13:5432
  data_dir: /var/lib/postgresql/15/main
  bin_dir: /usr/lib/postgresql/15/bin
  pgpass: /tmp/pgpass

  authentication:
    replication:
      username: replicator
      password: Replicator2026!
    superuser:
      username: postgres
      password: PreprodAdmin2026!

  parameters:
    shared_buffers: 4GB
    work_mem: 64MB
    maintenance_work_mem: 512MB
    max_connections: 200

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
EOF

sudo systemctl enable patroni
sudo systemctl start patroni

# Verify cluster status
patronictl -c /etc/patroni/patroni.yml list
```

### Step 10.2 — PreProd MongoDB ReplicaSet (2-node)

```bash
# On mongo-preprod-01 (10.0.5.23)
sudo tee /etc/mongod.conf << 'EOF'
storage:
  dbPath: /var/lib/mongodb
  wiredTiger:
    engineConfig:
      cacheSizeGB: 4
net:
  port: 27017
  bindIp: 0.0.0.0
security:
  authorization: enabled
  keyFile: /etc/mongodb-keyfile
replication:
  replSetName: rs-preprod
EOF

# Create keyfile (same on both nodes)
openssl rand -base64 756 | sudo tee /etc/mongodb-keyfile
sudo chmod 400 /etc/mongodb-keyfile
sudo chown mongodb:mongodb /etc/mongodb-keyfile

sudo systemctl restart mongod

# Initialize replica set (on node 1 only)
mongosh << 'JS'
rs.initiate({
  _id: "rs-preprod",
  members: [
    { _id: 0, host: "10.0.5.23:27017", priority: 2 },
    { _id: 1, host: "10.0.5.24:27017", priority: 1 }
  ]
})
JS
```

### Step 10.3 — Migrate PreProd Data

```bash
# PostgreSQL — same pg_dump/pg_restore process as Dev (Week 3)
# Source: Azure PreProd PostgreSQL
# Target: db-preprod-01 (Patroni will replicate to db-preprod-02)

AZURE_PREPROD_PG="your-preprod-pg.postgres.database.azure.com"

pg_dump \
  --host="${AZURE_PREPROD_PG}" \
  --username=pgadmin@your-preprod-pg \
  --dbname=preprod_db \
  --format=custom \
  --file=/tmp/preprod_db_$(date +%Y%m%d).dump

scp /tmp/preprod_db_*.dump ubuntu@10.0.5.13:/tmp/

ssh ubuntu@10.0.5.13 "
  pg_restore --host=localhost --username=postgres --dbname=preprod_db \
    --format=custom --no-owner /tmp/preprod_db_*.dump
"

# MongoDB — mongodump from Azure Cosmos DB (PreProd)
COSMOS_PREPROD="your-preprod-cosmos.mongo.cosmos.azure.com"
mongodump \
  --uri="mongodb://account:key@${COSMOS_PREPROD}:10255/preprod-cosmos?ssl=true&replicaSet=globaldb&retrywrites=false" \
  --out=/tmp/cosmos-preprod-dump

scp -r /tmp/cosmos-preprod-dump ubuntu@10.0.5.23:/tmp/

ssh ubuntu@10.0.5.23 "
  mongorestore \
    --uri='mongodb://admin:MongoAdmin2026!@localhost:27017/admin' \
    --drop --dir=/tmp/cosmos-preprod-dump
"
```

---

## Week 14: Production — Live Database Replication

> **Goal:** Replicate Production data from Azure to on-prem with near-zero lag before the cutover window. No data loss.

### Step 14.1 — Set Up Prod PostgreSQL (3-node Patroni HA)

```bash
# Install Patroni on db-prod-01 (10.0.5.15), db-prod-02 (.16), db-prod-03 (.17)
# Same setup as PreProd but with 3 nodes

# Patroni config for db-prod-01 (adjust IPs for -02 and -03)
sudo tee /etc/patroni/patroni.yml << 'EOF'
scope: prod-postgres
name: db-prod-01

restapi:
  listen: 10.0.5.15:8008
  connect_address: 10.0.5.15:8008

etcd:
  hosts: 10.0.6.13:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      parameters:
        wal_level: logical        # logical for pglogical live migration
        max_wal_senders: 20
        max_replication_slots: 20

  users:
    admin:
      password: ProdAdmin2026!
      options: [superuser]
    replicator:
      password: ProdReplicator2026!
      options: [replication]

postgresql:
  listen: 10.0.5.15:5432
  connect_address: 10.0.5.15:5432
  data_dir: /var/lib/postgresql/15/main
  parameters:
    shared_buffers: 8GB
    work_mem: 128MB
    max_connections: 400
    wal_level: logical
EOF
```

### Step 14.2 — Start pglogical Live Replication from Azure

```bash
# Install pglogical on BOTH Azure Prod PostgreSQL and on-prem db-prod-01
# On Azure Prod (using psql):
psql -h your-prod-pg.postgres.database.azure.com -U pgadmin -d prod_db << 'SQL'
CREATE EXTENSION pglogical;
SELECT pglogical.create_node(
  node_name := 'azure-prod-publisher',
  dsn := 'host=your-prod-pg.postgres.database.azure.com port=5432 dbname=prod_db user=pgadmin password=ProdAzure2026!'
);
-- Add all tables to replication set
SELECT pglogical.replication_set_add_all_tables('default', ARRAY['public']);
SQL

# On on-prem db-prod-01:
psql -h localhost -U postgres -d prod_db << 'SQL'
CREATE EXTENSION pglogical;
SELECT pglogical.create_node(
  node_name := 'onprem-prod-subscriber',
  dsn := 'host=10.0.5.15 port=5432 dbname=prod_db user=postgres password=ProdAdmin2026!'
);
SELECT pglogical.create_subscription(
  subscription_name := 'azure-to-onprem-prod',
  provider_dsn := 'host=your-prod-pg.postgres.database.azure.com port=5432 dbname=prod_db user=pgadmin password=ProdAzure2026! sslmode=require',
  replication_sets := ARRAY['default'],
  synchronize_data := true,    -- initial bulk copy
  forward_origins := ARRAY['all']
);
SQL

# Monitor replication lag
psql -h localhost -U postgres -c "
  SELECT subscription_name, status,
         pg_size_pretty(received_lsn - last_applied_lsn) AS lag
  FROM pglogical.show_subscription_status();
"
```

### Step 14.3 — MongoDB Prod ReplicaSet + Live Sync

```bash
# Set up 3-node MongoDB ReplicaSet (mongo-prod-01/02/03)
# Initialize on mongo-prod-01
mongosh << 'JS'
rs.initiate({
  _id: "rs-prod",
  members: [
    { _id: 0, host: "10.0.5.25:27017", priority: 3 },
    { _id: 1, host: "10.0.5.26:27017", priority: 2 },
    { _id: 2, host: "10.0.5.27:27017", priority: 1 }
  ]
})
JS

# Initial data load from Azure Cosmos DB (Prod)
COSMOS_PROD="your-prod-cosmos.mongo.cosmos.azure.com"
mongodump \
  --uri="mongodb://account:key@${COSMOS_PROD}:10255/prod-cosmos?ssl=true&replicaSet=globaldb&retrywrites=false" \
  --out=/tmp/cosmos-prod-dump

scp -r /tmp/cosmos-prod-dump ubuntu@10.0.5.25:/tmp/

ssh ubuntu@10.0.5.25 "
  mongorestore \
    --uri='mongodb://admin:MongoAdmin2026!@localhost:27017/admin' \
    --drop --dir=/tmp/cosmos-prod-dump
"

# Monitor for oplog lag — should be < 1 second before cutover
ssh ubuntu@10.0.5.25 "
  mongosh --eval \"
    var lag = rs.printSecondaryReplicationInfo()
    printjson(lag)
  \"
"
```

---

## Week 15: Production Go-Live

### Maintenance Window Plan

```
Saturday 22:00 — Maintenance window starts (6-hour window)
22:00 - Stop writes to Azure Prod application
22:05 - Wait for pglogical lag = 0 and MongoDB oplog lag = 0
22:15 - Final pg_dump + mongodump from Azure (point-in-time backup)
22:30 - Deploy Prod app pods to on-prem K8s
22:45 - Update Kubernetes secrets to point to on-prem databases
23:00 - Run smoke tests on on-prem Prod
23:30 - Update DNS: prod.company.com → 10.0.4.210 (on-prem MetalLB IP)
23:45 - Monitor on-prem Prod (watch Grafana, log errors)
00:00 - If healthy: maintenance window SUCCESS
       If issues:   trigger rollback procedure
02:00 - Rollback deadline: must decide by 02:00 or risk data divergence
04:00 - Maintenance window closes
```

### Cutover Script

```bash
#!/bin/bash
# prod-cutover.sh — run during maintenance window

set -e
echo "===== PROD CUTOVER $(date) ====="

# 1. Verify replication lag is zero
echo "[1] Checking pglogical lag..."
LAG=$(psql -h localhost -U postgres -t -c "
  SELECT received_lsn - last_applied_lsn FROM pglogical.show_subscription_status()
  LIMIT 1;" 2>/dev/null || echo "999")
echo "    pglogical lag: ${LAG} bytes"
[ "${LAG}" -le 1000 ] || { echo "ABORT: pglogical lag too high"; exit 1; }

echo "[2] Checking MongoDB oplog lag..."
ssh ubuntu@10.0.5.25 "
  mongosh --quiet --eval \"
    var status = rs.status()
    status.members.filter(m => m.stateStr == 'SECONDARY').forEach(m => {
      var lag = (new Date() - m.optimeDate) / 1000
      print('Member ' + m.name + ' lag: ' + lag + 's')
    })
  \"
"

# 2. Scale down Azure app (stop writes)
echo "[3] Scaling down Azure AKS deployments..."
az aks get-credentials --resource-group rg-dls-coe-we-001 --name aks-prod
kubectl config use-context aks-prod
kubectl scale deployment --all --replicas=0 -n production

# 3. Wait for final replication flush
echo "[4] Waiting 5 minutes for final replication flush..."
sleep 300

# 4. Verify zero lag
echo "[5] Final lag check..."
psql -h localhost -U postgres -c \
  "SELECT * FROM pglogical.show_subscription_status();"

# 5. Remove pglogical subscription (read-only from now on)
psql -h localhost -U postgres -c \
  "SELECT pglogical.drop_subscription('azure-to-onprem-prod');"

# 6. Scale up on-prem Prod
echo "[6] Starting on-prem Prod application..."
kubectl config use-context vxrail-k8s
kubectl scale deployment webapp --replicas=3 -n prod

# 7. Smoke tests
echo "[7] Running smoke tests..."
kubectl wait --for=condition=available deployment/webapp -n prod --timeout=120s
PROD_IP=$(kubectl get svc webapp-svc -n prod -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -f "http://${PROD_IP}/health" && echo "    Health check: PASS" || { echo "ABORT: health check failed"; exit 1; }

echo ""
echo "===== CUTOVER COMPLETE. Update DNS now. ====="
echo "Update: prod.company.com → ${PROD_IP}"
```

### DNS Cutover

```bash
# Update DNS record (replace with your DNS provider API or manual update)
# prod.company.com A record: change from Azure IP to 10.0.4.210
# TTL: lower to 60 seconds BEFORE the maintenance window (during Week 14 preparation)
# Verify propagation
nslookup prod.company.com 8.8.8.8
```

---

## Week 18: Azure Decommission

Only after on-prem Prod has been stable for **7+ days** with no P1/P2 incidents:

```bash
# Delete Azure Prod AKS
az aks delete --name aks-prod --resource-group rg-dls-coe-we-001 --yes --no-wait

# Delete Azure PreProd AKS
az aks delete --name aks-preprod --resource-group rg-as-las-we-001 --yes --no-wait

# Delete Cosmos DB (Prod + PreProd)
az cosmosdb delete --name cosmos-prod --resource-group rg-dls-coe-we-001 --yes
az cosmosdb delete --name cosmos-preprod --resource-group rg-as-las-we-001 --yes

# Delete PostgreSQL (Prod + PreProd)
az postgres server delete --name pg-prod --resource-group rg-dls-coe-we-001 --yes
az postgres server delete --name pg-preprod --resource-group rg-as-las-we-001 --yes

# Delete ACR (only after confirming all images are in Harbor)
az acr delete --name your-acr --resource-group rg-dls-coe-we-001 --yes

# Final: export Azure cost report for ROI comparison
az consumption usage list --start-date "2026-01-01" --end-date "$(date +%Y-%m-%d)" \
  --output table > azure-final-costs.txt
echo "Azure decommission complete. Migration to VxRail finished."
```
