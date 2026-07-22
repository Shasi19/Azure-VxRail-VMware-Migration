# 05 — Database Setup (Bare-Metal)

> **Goal**: Deploy PostgreSQL+Patroni HA (replaces Azure PostgreSQL) and MongoDB ReplicaSet (replaces Azure Cosmos DB) on the server-db-01/02/03 physical servers.  
> Steps are the same as KVM — the only difference is no VM disk management (raw disks used directly).

---

## Part A: PostgreSQL + Patroni (High Availability)

### A1. Prepare Data Partition

```bash
# On each server-db-0x — use a dedicated partition for PostgreSQL data
# Identify the data partition (assume /dev/nvme0n1p2 is not OS)
mkfs.xfs /dev/nvme0n1p2
mkdir -p /data/postgresql
echo "/dev/nvme0n1p2  /data/postgresql  xfs  defaults,noatime  0 0" >> /etc/fstab
mount -a

# Fix ownership (after PostgreSQL install)
# chown -R postgres:postgres /data/postgresql
```

### A2. Install PostgreSQL 15 + Patroni

```bash
# Add PostgreSQL repo
apt install -y postgresql-common
/usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y

apt install -y postgresql-15 postgresql-contrib-15

# Install Patroni
apt install -y python3-pip python3-dev libpq-dev
pip3 install patroni[etcd] psycopg2-binary

# Stop default PostgreSQL service
systemctl stop postgresql@15-main
systemctl disable postgresql@15-main
```

### A3. Install etcd for Patroni Consensus

```bash
# Install etcd on all 3 DB servers
apt install -y etcd-server etcd-client

# Configure etcd (change name and advertise IPs per server)
cat > /etc/default/etcd << 'EOF'
ETCD_NAME=server-db-01
ETCD_DATA_DIR=/var/lib/etcd
ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
ETCD_LISTEN_PEER_URLS=http://0.0.0.0:2380
ETCD_ADVERTISE_CLIENT_URLS=http://10.0.1.30:2379
ETCD_INITIAL_ADVERTISE_PEER_URLS=http://10.0.1.30:2380
ETCD_INITIAL_CLUSTER=server-db-01=http://10.0.1.30:2380,server-db-02=http://10.0.1.31:2380,server-db-03=http://10.0.1.32:2380
ETCD_INITIAL_CLUSTER_STATE=new
ETCD_INITIAL_CLUSTER_TOKEN=pg-etcd-baremetal
EOF

systemctl enable --now etcd

etcdctl --endpoints=http://10.0.1.30:2379,http://10.0.1.31:2379,http://10.0.1.32:2379 \
  endpoint health
```

### A4. Configure Patroni

```bash
mkdir -p /etc/patroni
chown postgres:postgres /etc/patroni

cat > /etc/patroni/patroni.yml << 'EOF'
scope: pg-cluster
name: server-db-01              # Change per node

restapi:
  listen: 0.0.0.0:8008
  connect_address: 10.0.1.30:8008   # Change IP per node

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
      parameters:
        max_connections: 300
        shared_buffers: 16GB         # ~25% of 64GB RAM on bare-metal
        effective_cache_size: 48GB
        wal_level: replica
        hot_standby: on
        max_wal_senders: 10
        max_replication_slots: 10
        checkpoint_completion_target: 0.9
        wal_buffers: 64MB
        default_statistics_target: 100
        random_page_cost: 1.1        # NVMe SSD (lower than spinning disk)
        effective_io_concurrency: 200

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
  data_dir: /data/postgresql/main
  bin_dir: /usr/lib/postgresql/15/bin
  pgpass: /tmp/pgpass

  authentication:
    replication:
      username: replicator
      password: Repl-OnPrem-2026!
    superuser:
      username: postgres
      password: PgSuper-OnPrem-2026!
EOF

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

chown -R postgres:postgres /etc/patroni
systemctl daemon-reload
systemctl enable --now patroni

patronictl -c /etc/patroni/patroni.yml list
```

### A5. HAProxy + PgBouncer

```bash
# HAProxy for read/write split
apt install -y haproxy pgbouncer

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
    default-server inter 3s fall 3 rise 2
    server db01 10.0.1.30:5432 check port 8008
    server db02 10.0.1.31:5432 check port 8008
    server db03 10.0.1.32:5432 check port 8008
EOF

systemctl enable --now haproxy

# PgBouncer connection pooling
cat > /etc/pgbouncer/pgbouncer.ini << 'EOF'
[databases]
devdb     = host=10.0.1.30 port=5000 dbname=devdb
qadb      = host=10.0.1.30 port=5000 dbname=qadb
preproddb = host=10.0.1.30 port=5000 dbname=preproddb
proddb    = host=10.0.1.30 port=5000 dbname=proddb
gitlabdb  = host=10.0.1.30 port=5000 dbname=gitlabdb

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = 6432
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
max_client_conn = 2000
default_pool_size = 50
min_pool_size = 5
EOF

echo '"postgres" "PgSuper-OnPrem-2026!"' > /etc/pgbouncer/userlist.txt
echo '"app_user" "AppUser-OnPrem-2026!"' >> /etc/pgbouncer/userlist.txt

systemctl enable --now pgbouncer
```

### A6. Create Databases

```bash
psql -h 10.0.1.30 -p 5000 -U postgres << 'SQL'
CREATE DATABASE devdb;
CREATE DATABASE qadb;
CREATE DATABASE preproddb;
CREATE DATABASE proddb;
CREATE DATABASE gitlabdb;

CREATE USER app_user WITH PASSWORD 'AppUser-OnPrem-2026!';
CREATE USER gitlab_user WITH PASSWORD 'GitLab-PG-2026!';

GRANT ALL PRIVILEGES ON DATABASE devdb TO app_user;
GRANT ALL PRIVILEGES ON DATABASE qadb TO app_user;
GRANT ALL PRIVILEGES ON DATABASE preproddb TO app_user;
GRANT ALL PRIVILEGES ON DATABASE proddb TO app_user;
GRANT ALL PRIVILEGES ON DATABASE gitlabdb TO gitlab_user;
SQL
```

---

## Part B: MongoDB ReplicaSet (Replaces Azure Cosmos DB)

### B1. Install MongoDB 7.0

```bash
# On all 3 DB servers
wget -qO - https://www.mongodb.org/static/pgp/server-7.0.asc | apt-key add -
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" \
  > /etc/apt/sources.list.d/mongodb-org-7.0.list

apt update && apt install -y mongodb-org

# Prepare data directory on NVMe
mkdir -p /data/mongodb
chown mongod:mongod /data/mongodb

cat > /etc/mongod.conf << 'EOF'
storage:
  dbPath: /data/mongodb
  journal:
    enabled: true
  engine: wiredTiger
  wiredTiger:
    engineConfig:
      cacheSizeGB: 16            # ~25% of 64GB RAM

systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log

net:
  port: 27017
  bindIp: 0.0.0.0
  maxIncomingConnections: 1000

security:
  authorization: enabled
  keyFile: /etc/mongodb-keyfile

replication:
  replSetName: rs-prod
  oplogSizeMB: 10240

operationProfiling:
  slowOpThresholdMs: 100
EOF
```

### B2. Create ReplicaSet Keyfile

```bash
# Generate on server-db-01, copy to others
openssl rand -base64 756 > /etc/mongodb-keyfile
chmod 400 /etc/mongodb-keyfile
chown mongod:mongod /etc/mongodb-keyfile

# Copy to db-02 and db-03
scp /etc/mongodb-keyfile admin@10.0.1.31:/tmp/
scp /etc/mongodb-keyfile admin@10.0.1.32:/tmp/
# On each:
# mv /tmp/mongodb-keyfile /etc/mongodb-keyfile
# chmod 400 /etc/mongodb-keyfile
# chown mongod:mongod /etc/mongodb-keyfile

systemctl enable --now mongod
```

### B3. Initialise ReplicaSet

```bash
# On server-db-01 ONLY (before auth is enabled)
mongosh --host 10.0.1.30 << 'EOF'
use admin
db.createUser({
  user: "admin",
  pwd: "MongoAdmin-OnPrem-2026!",
  roles: [{ role: "root", db: "admin" }]
})

rs.initiate({
  _id: "rs-prod",
  members: [
    { _id: 0, host: "10.0.1.30:27017", priority: 2 },
    { _id: 1, host: "10.0.1.31:27017", priority: 1 },
    { _id: 2, host: "10.0.1.32:27017", priority: 1 }
  ]
})
EOF

# Wait ~10 seconds then verify
mongosh --host 10.0.1.30 -u admin -p 'MongoAdmin-OnPrem-2026!' --authenticationDatabase admin \
  --eval "rs.status().members.forEach(m => print(m.name, m.stateStr))"
```

### B4. Create App Users and K8s Secrets

```bash
# Create per-env users
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

# Create K8s secrets
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
echo "=== PostgreSQL Cluster ==="
patronictl -c /etc/patroni/patroni.yml list

echo "=== MongoDB ReplicaSet ==="
mongosh --host 10.0.1.30,10.0.1.31,10.0.1.32 \
  --replicaSet rs-prod \
  -u admin -p 'MongoAdmin-OnPrem-2026!' \
  --authenticationDatabase admin \
  --eval "rs.status().members.map(m => m.name + ' ' + m.stateStr)"

echo "=== PgBouncer Pool ==="
psql -h 10.0.1.30 -p 6432 -U postgres pgbouncer -c 'SHOW POOLS;'
```

---

*Next: [06-Platform-Services.md](06-Platform-Services.md)*
