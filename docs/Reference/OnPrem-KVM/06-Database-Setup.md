# 06 — Database Setup (KVM)

> **Goal**: Deploy PostgreSQL+Patroni HA (replaces Azure PostgreSQL) and MongoDB ReplicaSet (replaces Azure Cosmos DB) on infra VMs.

---

## Part A: PostgreSQL + Patroni (High Availability)

### A1. Install PostgreSQL and Patroni on All 3 DB VMs

Run on infra-db-01, infra-db-02, infra-db-03:

```bash
# Install PostgreSQL 15
apt install -y postgresql-15 postgresql-contrib-15

# Install Patroni and dependencies
apt install -y python3-pip python3-dev libpq-dev

pip3 install patroni[etcd] psycopg2-binary

# Stop the default PostgreSQL service (Patroni manages it)
systemctl stop postgresql
systemctl disable postgresql
```

### A2. Install etcd (Patroni Distributed Consensus)

etcd stores cluster state so Patroni knows which node is primary.

```bash
# Install etcd on all 3 DB VMs
apt install -y etcd-server etcd-client

cat > /etc/default/etcd << 'EOF'
ETCD_NAME=infra-db-01              # Change per node: infra-db-01, 02, 03
ETCD_DATA_DIR=/var/lib/etcd
ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
ETCD_LISTEN_PEER_URLS=http://0.0.0.0:2380
ETCD_ADVERTISE_CLIENT_URLS=http://10.0.1.30:2379  # Change IP per node
ETCD_INITIAL_ADVERTISE_PEER_URLS=http://10.0.1.30:2380
ETCD_INITIAL_CLUSTER=infra-db-01=http://10.0.1.30:2380,infra-db-02=http://10.0.1.31:2380,infra-db-03=http://10.0.1.32:2380
ETCD_INITIAL_CLUSTER_STATE=new
ETCD_INITIAL_CLUSTER_TOKEN=pg-etcd-cluster
EOF

systemctl enable --now etcd

# Verify etcd cluster
etcdctl --endpoints=http://10.0.1.30:2379,http://10.0.1.31:2379,http://10.0.1.32:2379 \
  endpoint health
```

### A3. Configure Patroni

```bash
# Create Patroni config (on infra-db-01 — adjust name/connect_address per node)
mkdir -p /etc/patroni

cat > /etc/patroni/patroni.yml << 'EOF'
scope: pg-cluster
name: infra-db-01               # Change per node

restapi:
  listen: 0.0.0.0:8008
  connect_address: 10.0.1.30:8008  # Change IP per node

etcd:
  hosts: 10.0.1.30:2379,10.0.1.31:2379,10.0.1.32:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        max_connections: 200
        shared_buffers: 4GB
        effective_cache_size: 12GB
        wal_level: replica
        hot_standby: on
        max_wal_senders: 10
        max_replication_slots: 10

  initdb:
    - encoding: UTF8
    - data-checksums

  pg_hba:
    - host replication replicator 10.0.1.0/24 md5
    - host all all 10.0.1.0/24 md5
    - local all all trust

  users:
    admin:
      password: PgAdmin-OnPrem-2026!
      options: [createrole, createdb]

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 10.0.1.30:5432   # Change IP per node
  data_dir: /var/lib/postgresql/15/main
  bin_dir: /usr/lib/postgresql/15/bin
  pgpass: /tmp/pgpass

  authentication:
    replication:
      username: replicator
      password: Repl-OnPrem-2026!
    superuser:
      username: postgres
      password: PgSuper-OnPrem-2026!

tags:
  nofailover: false
  noloadbalance: false
  clonedfrom: false
  nosync: false
EOF

# Create systemd service for Patroni
cat > /etc/systemd/system/patroni.service << 'EOF'
[Unit]
Description=Patroni PostgreSQL HA
After=syslog.target network.target

[Service]
Type=simple
User=postgres
Group=postgres
ExecStart=/usr/local/bin/patroni /etc/patroni/patroni.yml
KillMode=process
TimeoutSec=30
Restart=no

[Install]
WantedBy=multi-user.target
EOF

# Fix permissions
chown -R postgres:postgres /etc/patroni
systemctl daemon-reload
systemctl enable --now patroni

# Check cluster status
patronictl -c /etc/patroni/patroni.yml list
```

### A4. Install HAProxy for PostgreSQL Load Balancing

```bash
# Install HAProxy on a separate VM or on the infra-db-01
apt install -y haproxy

cat >> /etc/haproxy/haproxy.cfg << 'EOF'
listen postgres-write
    bind *:5000
    mode tcp
    option tcp-check
    tcp-check expect string master
    default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions
    server db01 10.0.1.30:5432 check port 8008
    server db02 10.0.1.31:5432 check port 8008 backup
    server db03 10.0.1.32:5432 check port 8008 backup

listen postgres-read
    bind *:5001
    mode tcp
    balance roundrobin
    option tcp-check
    tcp-check expect string replica
    default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions
    server db01 10.0.1.30:5432 check port 8008
    server db02 10.0.1.31:5432 check port 8008
    server db03 10.0.1.32:5432 check port 8008
EOF

systemctl enable --now haproxy
```

### A5. Install PgBouncer (Connection Pooling)

```bash
apt install -y pgbouncer

cat > /etc/pgbouncer/pgbouncer.ini << 'EOF'
[databases]
devdb     = host=10.0.1.30 port=5000 dbname=devdb
qadb      = host=10.0.1.30 port=5000 dbname=qadb
preproddb = host=10.0.1.30 port=5000 dbname=preproddb
proddb    = host=10.0.1.30 port=5000 dbname=proddb

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = 6432
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 25
min_pool_size = 5
server_idle_timeout = 600
log_connections = 0
log_disconnections = 0
EOF

# Create user list
echo '"postgres" "PgSuper-OnPrem-2026!"' > /etc/pgbouncer/userlist.txt
echo '"app_user" "AppUser-OnPrem-2026!"' >> /etc/pgbouncer/userlist.txt

systemctl enable --now pgbouncer
```

### A6. Create Databases per Environment

```bash
# Connect to primary (via HAProxy write port)
psql -h 10.0.1.30 -p 5000 -U postgres << 'SQL'
CREATE DATABASE devdb;
CREATE DATABASE qadb;
CREATE DATABASE preproddb;
CREATE DATABASE proddb;

CREATE USER app_user WITH PASSWORD 'AppUser-OnPrem-2026!';
GRANT ALL PRIVILEGES ON DATABASE devdb TO app_user;
GRANT ALL PRIVILEGES ON DATABASE qadb TO app_user;
GRANT ALL PRIVILEGES ON DATABASE preproddb TO app_user;
GRANT ALL PRIVILEGES ON DATABASE proddb TO app_user;
SQL
```

---

## Part B: MongoDB ReplicaSet (Replaces Azure Cosmos DB)

### B1. Install MongoDB on All 3 DB VMs

```bash
# Add MongoDB 7.0 repo
wget -qO - https://www.mongodb.org/static/pgp/server-7.0.asc | apt-key add -
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" \
  > /etc/apt/sources.list.d/mongodb-org-7.0.list

apt update && apt install -y mongodb-org

# Create data directory
mkdir -p /data/mongodb
chown mongod:mongod /data/mongodb

# Configure MongoDB
cat > /etc/mongod.conf << 'EOF'
storage:
  dbPath: /data/mongodb
  journal:
    enabled: true
  engine: wiredTiger
  wiredTiger:
    engineConfig:
      cacheSizeGB: 8

systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log

net:
  port: 27017
  bindIp: 0.0.0.0

security:
  authorization: enabled
  keyFile: /etc/mongodb-keyfile

replication:
  replSetName: rs-prod        # rs-preprod for PreProd, standalone for dev/qa

processManagement:
  timeZoneInfo: /usr/share/zoneinfo
EOF
```

### B2. Create MongoDB Keyfile (for ReplicaSet Auth)

```bash
# Generate keyfile on infra-db-01 and copy to all nodes
openssl rand -base64 756 > /etc/mongodb-keyfile
chmod 400 /etc/mongodb-keyfile
chown mongod:mongod /etc/mongodb-keyfile

# Copy to other nodes
scp /etc/mongodb-keyfile admin@10.0.1.31:/tmp/
scp /etc/mongodb-keyfile admin@10.0.1.32:/tmp/

# On infra-db-02 and infra-db-03:
mv /tmp/mongodb-keyfile /etc/mongodb-keyfile
chmod 400 /etc/mongodb-keyfile
chown mongod:mongod /etc/mongodb-keyfile

# Start MongoDB on all nodes
systemctl enable --now mongod
```

### B3. Initialise the ReplicaSet (run on infra-db-01)

```bash
mongosh --host 10.0.1.30 << 'EOF'
// First, create admin user BEFORE enabling auth
use admin
db.createUser({
  user: "admin",
  pwd: "MongoAdmin-OnPrem-2026!",
  roles: [{ role: "root", db: "admin" }]
})

// Initiate the replica set
rs.initiate({
  _id: "rs-prod",
  members: [
    { _id: 0, host: "10.0.1.30:27017", priority: 2 },
    { _id: 1, host: "10.0.1.31:27017", priority: 1 },
    { _id: 2, host: "10.0.1.32:27017", priority: 1, hidden: false }
  ]
})

// Wait for primary election (takes ~10s)
rs.status()
EOF
```

### B4. Create Application Users

```bash
mongosh --host 10.0.1.30 -u admin -p 'MongoAdmin-OnPrem-2026!' --authenticationDatabase admin << 'EOF'
use dev-cosmos
db.createUser({ user: "dev_user", pwd: "DevMongo-2026!", roles: [{ role: "readWrite", db: "dev-cosmos" }] })

use qa-cosmos
db.createUser({ user: "qa_user", pwd: "QaMongo-2026!", roles: [{ role: "readWrite", db: "qa-cosmos" }] })

use preprod-cosmos
db.createUser({ user: "preprod_user", pwd: "PreProdMongo-2026!", roles: [{ role: "readWrite", db: "preprod-cosmos" }] })

use prod-cosmos
db.createUser({ user: "prod_user", pwd: "ProdMongo-2026!", roles: [{ role: "readWrite", db: "prod-cosmos" }] })
EOF
```

### B5. Create Kubernetes Secrets for DB Connections

```bash
# PostgreSQL connection strings
for NS in dev qa preprod prod; do
  kubectl create secret generic db-credentials \
    --namespace=$NS \
    --from-literal=pg-host=10.0.1.30 \
    --from-literal=pg-port=6432 \
    --from-literal=pg-database=${NS}db \
    --from-literal=pg-user=app_user \
    --from-literal=pg-password='AppUser-OnPrem-2026!' \
    --from-literal=mongo-uri="mongodb://${NS}_user:${NS}Mongo-2026!@10.0.1.30:27017,10.0.1.31:27017,10.0.1.32:27017/${NS}-cosmos?authSource=${NS}-cosmos&replicaSet=rs-prod"
done
```

---

## Verify All Databases

```bash
# PostgreSQL cluster
patronictl -c /etc/patroni/patroni.yml list
# Should show 1 Leader + 2 Replicas

psql -h 10.0.1.30 -p 6432 -U postgres -c '\l'
# Should show devdb, qadb, preproddb, proddb

# MongoDB replicaset
mongosh --host 10.0.1.30,10.0.1.31,10.0.1.32 \
  --replicaSet rs-prod \
  -u admin -p 'MongoAdmin-OnPrem-2026!' \
  --authenticationDatabase admin \
  --eval "rs.status().members.map(m => m.name + ' ' + m.stateStr)"
# Expected: each member shows PRIMARY or SECONDARY
```

---

*Next: [07-Platform-Services.md](07-Platform-Services.md)*
