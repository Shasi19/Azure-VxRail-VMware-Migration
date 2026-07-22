# Migration Execution — Step-by-Step with Commands

> **This is the master execution guide.** Follow in order. Do not skip steps. Each section has verification commands — do not proceed until verification passes.

---

## Pre-Execution Checklist

```bash
# Run this before EVERY migration session
bash docs/VxRail-VMware-Migration/04-Initial-Setup-Before-Migration.md  # Section 15 readiness script
# Must show: ✅ READY TO START MIGRATION
```

---

## PART A: Platform Build (Before Any Migration)

### A1. Build Kubernetes Cluster

#### A1.1 — Initialize Control Plane (master-1)

```bash
ssh oracle@10.0.3.11

# 1. Run node prep (swap off, modules, containerd, kubeadm)
# (see 10-Kubernetes-vSphere.md section 1 for full script)
sudo bash /usr/local/bin/k8s-node-prep.sh

# 2. Start keepalived + HAProxy
sudo systemctl start keepalived haproxy
ip addr show ens192 | grep "10.0.3.100"
# ✅ VIP must appear here before init

# 3. Create kubeadm config and init
cat > /tmp/kubeadm-init.yaml << 'EOF'
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: 10.0.3.11
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
  kubeletExtraArgs:
    cloud-provider: external
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.29.0
controlPlaneEndpoint: "10.0.3.100:6443"
networking:
  podSubnet: "192.168.0.0/16"
  serviceSubnet: "10.96.0.0/12"
apiServer:
  certSANs: ["10.0.3.100","10.0.3.11","10.0.3.12","10.0.3.13","k8s-api.internal.company.com"]
  extraArgs:
    cloud-provider: external
controllerManager:
  extraArgs:
    cloud-provider: external
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
EOF

sudo kubeadm init --config=/tmp/kubeadm-init.yaml --upload-certs 2>&1 | tee /tmp/kubeadm-init.log

# 4. Set up kubectl access
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# 5. SAVE the join commands from kubeadm output!
grep -A 3 "kubeadm join" /tmp/kubeadm-init.log
```

#### Verify master-1

```bash
kubectl get nodes   # master-1 should show NotReady (normal before CNI)
kubectl get pods -n kube-system   # all pods should be Running except coredns
```

#### A1.2 — Join master-2 and master-3

```bash
# Run on master-2 AND master-3 (separate SSH sessions)
# First run node prep:
sudo bash /usr/local/bin/k8s-node-prep.sh
sudo systemctl start keepalived haproxy

# Then join (use the control-plane join command from kubeadm init output)
sudo kubeadm join 10.0.3.100:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH> \
  --control-plane \
  --certificate-key <CERT_KEY> \
  --node-name k8s-master-2    # k8s-master-3 on the other
```

#### A1.3 — Install Calico CNI

```bash
# From jumphost or master-1
kubectl create -f \
  https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml

cat << 'EOF' | kubectl apply -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: 192.168.0.0/16
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
EOF

# Wait for all nodes to become Ready
kubectl wait --for=condition=Ready nodes --all --timeout=300s
kubectl get nodes   # All 3 masters: Ready
```

#### A1.4 — Join Phase 1 Workers (worker-1, worker-2)

```bash
# On worker-1 (10.0.4.21) and worker-2 (10.0.4.22)
sudo bash /usr/local/bin/k8s-node-prep.sh

sudo kubeadm join 10.0.3.100:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>

# Label workers
kubectl label node k8s-worker-1 workload-tier=dev-qa
kubectl label node k8s-worker-2 workload-tier=dev-qa
```

#### A1.5 — Install vSphere CSI Driver

```bash
# 1. Enable disk.EnableUUID (from jumphost)
bash enable-disk-uuid.sh

# 2. Create CSI config secret
kubectl create namespace vmware-system-csi

cat > /tmp/csi-vsphere.conf << EOF
[Global]
cluster-id = "vxrail-k8s-cluster"

[VirtualCenter "vcenter.internal.company.com"]
insecure-flag = "false"
user = "k8s-csi@vsphere.local"
password = "CSIuser2026!"
port = "443"
datacenters = "Datacenter"
EOF

kubectl create secret generic vsphere-config-secret \
  --from-file=csi-vsphere.conf=/tmp/csi-vsphere.conf \
  --namespace=vmware-system-csi

rm /tmp/csi-vsphere.conf

# 3. Deploy CSI
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/vsphere-csi-driver/v3.3.0/manifests/vanilla/deploy/vsphere-csi-driver.yaml

# 4. Verify
kubectl get pods -n vmware-system-csi
# All should be Running
```

#### A1.6 — Install MetalLB

```bash
kubectl apply -f \
  https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml

kubectl wait --namespace metallb-system --for=condition=ready pod \
  --selector=app=metallb --timeout=120s

cat << 'EOF' | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: vxrail-pool
  namespace: metallb-system
spec:
  addresses:
    - 10.0.4.200-10.0.4.220
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: vxrail-l2
  namespace: metallb-system
spec:
  ipAddressPools: [vxrail-pool]
  interfaces: [ens192]
EOF
```

#### A1.7 — Create Namespaces and Resource Quotas

```bash
# Create all 4 app namespaces
for NS in dev qa preprod prod; do
  kubectl create namespace $NS 2>/dev/null || true
  kubectl label namespace $NS environment=$NS tier=application
done

# System namespaces
for NS in monitoring logging argocd harbor vault; do
  kubectl create namespace $NS 2>/dev/null || true
done

# Apply resource limits
cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: quota
  namespace: dev
spec:
  hard:
    requests.cpu: "8"
    requests.memory: 16Gi
    limits.cpu: "16"
    limits.memory: 32Gi
    persistentvolumeclaims: "20"
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: quota
  namespace: qa
spec:
  hard:
    requests.cpu: "8"
    requests.memory: 16Gi
    limits.cpu: "16"
    limits.memory: 32Gi
    persistentvolumeclaims: "20"
EOF
```

#### A1.8 — Verify Complete K8s Platform

```bash
echo "=== K8s Platform Health Check ==="
kubectl get nodes -o wide
kubectl get pods -A --field-selector=status.phase!=Running 2>/dev/null | head -20
kubectl get sc
kubectl get svc -n metallb-system

# Test a PVC
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-vsan-pvc
  namespace: default
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: vsan-dev-qa
  resources:
    requests:
      storage: 1Gi
EOF
sleep 20
kubectl get pvc test-vsan-pvc
kubectl delete pvc test-vsan-pvc
echo "=== Platform ready ==="
```

---

### A2. Install Platform Services

#### A2.1 — Harbor (Container Registry — replaces ACR)

```bash
helm repo add harbor https://helm.goharbor.io && helm repo update

helm install harbor harbor/harbor \
  --namespace harbor \
  --set expose.type=loadBalancer \
  --set expose.loadBalancer.IP=10.0.4.215 \
  --set expose.tls.enabled=true \
  --set expose.tls.certSource=secret \
  --set expose.tls.secret.secretName=wildcard-tls \
  --set externalURL=https://harbor.internal.company.com \
  --set harborAdminPassword=Harbor@VxRail2026! \
  --set persistence.enabled=true \
  --set persistence.persistentVolumeClaim.registry.storageClass=vsan-production \
  --set persistence.persistentVolumeClaim.registry.size=200Gi \
  --set persistence.persistentVolumeClaim.chartmuseum.storageClass=vsan-production \
  --set persistence.persistentVolumeClaim.chartmuseum.size=20Gi

# Wait for Harbor pods
kubectl get pods -n harbor --watch

# Test
curl -u "admin:Harbor@VxRail2026!" \
  https://harbor.internal.company.com/api/v2.0/health

# Create project for app images
curl -u "admin:Harbor@VxRail2026!" -X POST \
  https://harbor.internal.company.com/api/v2.0/projects \
  -H "Content-Type: application/json" \
  -d '{"project_name":"production","public":false}'
```

#### A2.2 — ArgoCD (GitOps)

```bash
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl patch svc argocd-server -n argocd \
  -p '{"spec":{"type":"LoadBalancer","loadBalancerIP":"10.0.4.216"}}'

# Get initial password
ARGOCD_PWD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
echo "ArgoCD password: $ARGOCD_PWD"

# Log in and change password
argocd login 10.0.4.216 --username admin --password "$ARGOCD_PWD" --insecure
argocd account update-password
```

#### A2.3 — Prometheus + Grafana (Monitoring)

```bash
helm install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.retention=90d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=vsan-production \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=100Gi \
  --set grafana.adminPassword=Grafana@VxRail2026! \
  --set grafana.service.type=LoadBalancer \
  --set grafana.service.loadBalancerIP=10.0.4.217

kubectl get svc -n monitoring | grep grafana
# Access: http://10.0.4.217   admin / Grafana@VxRail2026!
```

---

## PART B: Phase 1 — Dev Environment Migration

### B1. Set Up Dev PostgreSQL

```bash
ssh oracle@10.0.5.11   # db-dev-01

# Install PostgreSQL 15 (Oracle Linux 9 — from PostgreSQL official RPM repo)
sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
sudo dnf -qy module disable postgresql
sudo dnf install -y postgresql15-server postgresql15 postgresql15-contrib

# Initialize database cluster
sudo /usr/pgsql-15/bin/postgresql-15-setup initdb

# Allow remote connections
sudo sed -i "s/#listen_addresses.*/listen_addresses = '*'/" \
  /var/lib/pgsql/15/data/postgresql.conf

# Set max connections and memory
sudo tee -a /var/lib/pgsql/15/data/postgresql.conf << 'EOF'
max_connections = 200
shared_buffers = 2GB
effective_cache_size = 6GB
work_mem = 16MB
maintenance_work_mem = 256MB
wal_level = replica
max_wal_senders = 10
EOF

# pg_hba.conf — allow K8s and masters
sudo tee -a /var/lib/pgsql/15/data/pg_hba.conf << 'EOF'
host    all    all    10.0.3.0/24    scram-sha-256
host    all    all    10.0.4.0/24    scram-sha-256
host    all    all    10.0.5.0/24    scram-sha-256
EOF

# Firewall (OL9 uses firewalld)
sudo firewall-cmd --permanent --add-service=postgresql && sudo firewall-cmd --reload

# Create database and user
sudo -u postgres /usr/pgsql-15/bin/psql << 'SQL'
CREATE DATABASE dev_db;
CREATE USER dev_user WITH ENCRYPTED PASSWORD 'DevPostgres2026!';
GRANT ALL PRIVILEGES ON DATABASE dev_db TO dev_user;
\c dev_db
GRANT ALL ON SCHEMA public TO dev_user;
SQL

sudo systemctl enable postgresql-15 && sudo systemctl start postgresql-15

# Verify
psql "host=10.0.5.11 user=dev_user password=DevPostgres2026! dbname=dev_db" \
  -c "SELECT version();"
```

### B2. Migrate Dev PostgreSQL Data from Azure

```bash
# Step 1: Export from Azure (run from jumphost with VPN access to Azure)
AZURE_DEV_PG="your-dev-pg.postgres.database.azure.com"
AZURE_USER="pgadmin@your-dev-pg"

echo "Starting pg_dump from Azure Dev PostgreSQL..."
pg_dump \
  --host="${AZURE_DEV_PG}" \
  --port=5432 \
  --username="${AZURE_USER}" \
  --dbname=dev_db \
  --format=custom \
  --compress=9 \
  --verbose \
  --file=/tmp/dev_db_$(date +%Y%m%d_%H%M).dump

# Step 2: Check dump size
ls -lh /tmp/dev_db_*.dump

# Step 3: Transfer to on-prem DB server
scp /tmp/dev_db_*.dump oracle@10.0.5.11:/tmp/

# Step 4: Restore on on-prem
ssh oracle@10.0.5.11 "
pg_restore \
  --host=localhost \
  --port=5432 \
  --username=dev_user \
  --dbname=dev_db \
  --format=custom \
  --no-owner \
  --role=dev_user \
  --verbose \
  /tmp/dev_db_*.dump 2>&1 | tee /tmp/pg_restore.log
echo 'Exit code: '\$?
"

# Step 5: Verify row counts match
echo "=== Azure Dev row counts ==="
psql "host=${AZURE_DEV_PG} user=${AZURE_USER} dbname=dev_db sslmode=require" \
  -c "SELECT schemaname, tablename, n_live_tup FROM pg_stat_user_tables WHERE n_live_tup > 0 ORDER BY n_live_tup DESC;"

echo "=== On-prem Dev row counts ==="
psql "host=10.0.5.11 user=dev_user password=DevPostgres2026! dbname=dev_db" \
  -c "SELECT schemaname, tablename, n_live_tup FROM pg_stat_user_tables WHERE n_live_tup > 0 ORDER BY n_live_tup DESC;"
```

### B3. Set Up Dev MongoDB

```bash
ssh oracle@10.0.5.21   # mongo-dev-01

# Install MongoDB 7.0 — Oracle Linux 9 (RHEL9-compatible RPM repo)
sudo tee /etc/yum.repos.d/mongodb-org-7.0.repo << 'EOF'
[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/9/mongodb-org/7.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-7.0.asc
EOF
sudo dnf install -y mongodb-org

# Firewall (OL9 uses firewalld)
sudo firewall-cmd --permanent --add-port=27017/tcp && sudo firewall-cmd --reload

# Configure
sudo tee /etc/mongod.conf << 'EOF'
storage:
  dbPath: /var/lib/mongodb
  wiredTiger:
    engineConfig:
      cacheSizeGB: 2
net:
  port: 27017
  bindIp: 0.0.0.0
security:
  authorization: enabled
operationProfiling:
  slowOpThresholdMs: 100
EOF

sudo systemctl enable mongod && sudo systemctl start mongod

# Create admin + app users
mongosh --quiet << 'JS'
use admin
db.createUser({user:"admin", pwd:"MongoAdmin2026!", roles:[{role:"root",db:"admin"}]})
use dev-cosmos
db.createUser({user:"dev_user", pwd:"DevMongo2026!", roles:[{role:"readWrite",db:"dev-cosmos"}]})
JS

# Verify
mongosh "mongodb://dev_user:DevMongo2026!@localhost:27017/dev-cosmos?authSource=dev-cosmos" \
  --eval "db.runCommand({ping:1})"
```

### B4. Migrate Dev MongoDB from Azure Cosmos DB

```bash
# Export from Azure Cosmos DB (Mongo API) — run from jumphost
COSMOS_ACCOUNT="your-dev-cosmos-account"
COSMOS_KEY="your-cosmos-primary-key"
COSMOS_HOST="${COSMOS_ACCOUNT}.mongo.cosmos.azure.com"

echo "Exporting from Azure Cosmos DB..."
mongodump \
  --uri="mongodb://${COSMOS_ACCOUNT}:${COSMOS_KEY}@${COSMOS_HOST}:10255/dev-cosmos?ssl=true&replicaSet=globaldb&retrywrites=false&maxIdleTimeMS=120000" \
  --db=dev-cosmos \
  --out=/tmp/cosmos-dev-$(date +%Y%m%d)

# Transfer
scp -r /tmp/cosmos-dev-* oracle@10.0.5.21:/tmp/

# Restore
ssh oracle@10.0.5.21 "
mongorestore \
  --uri='mongodb://admin:MongoAdmin2026!@localhost:27017/?authSource=admin' \
  --nsFrom='dev-cosmos.*' \
  --nsTo='dev-cosmos.*' \
  --drop \
  --dir=/tmp/cosmos-dev-*/dev-cosmos
"

# Verify document counts
echo "=== Cosmos DB counts ==="
mongosh "mongodb://${COSMOS_ACCOUNT}:${COSMOS_KEY}@${COSMOS_HOST}:10255/dev-cosmos?ssl=true&replicaSet=globaldb&retrywrites=false" \
  --quiet --eval "db.getCollectionNames().forEach(c => print(c + ': ' + db[c].countDocuments()))"

echo "=== On-prem counts ==="
ssh oracle@10.0.5.21 "
  mongosh 'mongodb://dev_user:DevMongo2026!@localhost:27017/dev-cosmos?authSource=dev-cosmos' \
    --quiet --eval \"db.getCollectionNames().forEach(c => print(c + ': ' + db[c].countDocuments()))\"
"
```

### B5. Deploy Dev Application

```bash
# 1. Pull images from Azure ACR and push to Harbor
ACR_NAME="your-acr-name"
HARBOR="harbor.internal.company.com"

az acr login --name "${ACR_NAME}"
docker login "${HARBOR}" -u admin -p Harbor@VxRail2026!

# List all images in ACR and re-push to Harbor
az acr repository list --name "${ACR_NAME}" -o tsv | while read REPO; do
  az acr repository show-tags --name "${ACR_NAME}" --repository "${REPO}" -o tsv | while read TAG; do
    SRC="${ACR_NAME}.azurecr.io/${REPO}:${TAG}"
    DST="${HARBOR}/production/${REPO}:${TAG}"
    echo "Migrating: $SRC → $DST"
    docker pull "${SRC}"
    docker tag "${SRC}" "${DST}"
    docker push "${DST}"
  done
done

# 2. Create Kubernetes secrets for Dev
kubectl create secret generic db-credentials \
  --namespace=dev \
  --from-literal=DB_HOST=10.0.5.11 \
  --from-literal=DB_PORT=5432 \
  --from-literal=DB_NAME=dev_db \
  --from-literal=DB_USER=dev_user \
  --from-literal=DB_PASSWORD=DevPostgres2026!

kubectl create secret generic mongo-credentials \
  --namespace=dev \
  --from-literal=MONGO_URI="mongodb://dev_user:DevMongo2026!@10.0.5.21:27017/dev-cosmos?authSource=dev-cosmos"

kubectl create secret generic minio-credentials \
  --namespace=dev \
  --from-literal=MINIO_ENDPOINT=http://10.0.6.11:9000 \
  --from-literal=MINIO_ACCESS_KEY=minio-admin \
  --from-literal=MINIO_SECRET_KEY=MinIO@VxRail2026! \
  --from-literal=MINIO_BUCKET=dev-storage

kubectl create secret docker-registry harbor-pull \
  --namespace=dev \
  --docker-server=harbor.internal.company.com \
  --docker-username=admin \
  --docker-password=Harbor@VxRail2026!

# 3. Create ArgoCD Application for Dev
cat << 'EOF' | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: webapp-dev
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://gitlab.internal.company.com/webapp.git
    targetRevision: develop
    path: helm/webapp-chart
    helm:
      valueFiles: [values-dev.yaml]
  destination:
    server: https://kubernetes.default.svc
    namespace: dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

# 4. Monitor deployment
kubectl rollout status deployment/webapp -n dev --timeout=300s
kubectl get pods -n dev

# 5. Get Dev service IP and test
DEV_IP=$(kubectl get svc webapp-svc -n dev -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Dev app IP: ${DEV_IP}"

curl -f "http://${DEV_IP}/health"       && echo "Health: ✅ PASS" || echo "Health: ❌ FAIL"
curl -f "http://${DEV_IP}/api/v1/ping"  && echo "API: ✅ PASS"    || echo "API: ❌ FAIL"
```

### B6. Dev DNS Cutover

```bash
# 1. Verify on-prem Dev is healthy for 3+ days
# 2. Lower DNS TTL: dev.company.com TTL → 60 seconds (do 24h before cutover)
# 3. At cutover time, update DNS:
#    dev.company.com  A → 10.0.4.200  (or $DEV_IP if MetalLB assigned different IP)

# 4. Monitor for 1 hour
watch -n 30 "curl -s -o /dev/null -w 'HTTP %{http_code} latency:%{time_total}s' http://dev.company.com/health"
```

---

## PART C: Phase 1 — QA Environment Migration

Repeat PART B for QA (identical steps, different IPs and credentials):

| Resource | Dev | QA |
|----------|-----|-----|
| PostgreSQL VM | `db-dev-01` (10.0.5.11) | `db-qa-01` (10.0.5.12) |
| MongoDB VM | `mongo-dev-01` (10.0.5.21) | `mongo-qa-01` (10.0.5.22) |
| DB name | `dev_db` | `qa_db` |
| Mongo DB | `dev-cosmos` | `qa-cosmos` |
| K8s namespace | `dev` | `qa` |
| App MetalLB IP | 10.0.4.200 | 10.0.4.201 |
| DB user password | `DevPostgres2026!` | `QAPostgres2026!` |
| Mongo user password | `DevMongo2026!` | `QAMongo2026!` |
| DNS cutover | `dev.company.com` | `qa.company.com` |

```bash
# QA-specific command — create secrets
kubectl create secret generic db-credentials --namespace=qa \
  --from-literal=DB_HOST=10.0.5.12 \
  --from-literal=DB_USER=qa_user \
  --from-literal=DB_PASSWORD=QAPostgres2026! \
  --from-literal=DB_NAME=qa_db

kubectl create secret generic mongo-credentials --namespace=qa \
  --from-literal=MONGO_URI="mongodb://qa_user:QAMongo2026!@10.0.5.22:27017/qa-cosmos?authSource=qa-cosmos"
```

---

## PART D: Phase 2 — PreProd + Prod Migration

> **Only start after Phase 1 Gate 3 passes (Dev+QA stable for 2+ weeks)**

### D1. Add Phase 2 Workers to K8s

```bash
# For each worker 3-6 (10.0.4.23 through 10.0.4.26):
for WORKER_IP in 10.0.4.23 10.0.4.24 10.0.4.25 10.0.4.26; do
  echo "Joining worker $WORKER_IP..."
  ssh oracle@"${WORKER_IP}" "
    sudo bash /usr/local/bin/k8s-node-prep.sh
    sudo kubeadm join 10.0.3.100:6443 \
      --token <TOKEN> \
      --discovery-token-ca-cert-hash sha256:<HASH>
  "
done

# Label nodes
kubectl label node k8s-worker-3 workload-tier=preprod
kubectl label node k8s-worker-4 workload-tier=preprod
kubectl label node k8s-worker-5 workload-tier=prod
kubectl label node k8s-worker-6 workload-tier=prod

# Taint prod workers
kubectl taint node k8s-worker-5 env=prod:NoSchedule
kubectl taint node k8s-worker-6 env=prod:NoSchedule
```

### D2. PreProd Migration (Weeks 10-12)

Follow same steps as Dev+QA but use PreProd VMs:
- `db-preprod-01` (10.0.5.13) + `db-preprod-02` (10.0.5.14) in Patroni HA
- `mongo-preprod-01` (10.0.5.23) + `mongo-preprod-02` (10.0.5.24) in ReplicaSet
- Namespace: `preprod`
- App MetalLB IP: 10.0.4.202
- DNS: `preprod.company.com`

Full detail in `14-Phase2-PreProd-Prod.md` sections 10-12.

### D3. Production Migration (Weeks 14-15)

#### D3.1 Start pglogical Live Replication (Week 14 — do NOT wait for maintenance window)

```bash
# On Azure Prod PostgreSQL
psql "host=your-prod-pg.postgres.database.azure.com user=pgadmin dbname=prod_db sslmode=require" << 'SQL'
CREATE EXTENSION IF NOT EXISTS pglogical;
SELECT pglogical.create_node(
  node_name := 'azure-prod',
  dsn := 'host=your-prod-pg.postgres.database.azure.com port=5432 dbname=prod_db user=pglogical_user password=PglogicalPass2026! sslmode=require'
);
SELECT pglogical.replication_set_add_all_tables('default', ARRAY['public']);
SQL

# On on-prem db-prod-01 (must have wal_level=logical in postgresql.conf)
psql -h 10.0.5.15 -U postgres << 'SQL'
CREATE EXTENSION IF NOT EXISTS pglogical;
SELECT pglogical.create_node(
  node_name := 'onprem-prod',
  dsn := 'host=10.0.5.15 port=5432 dbname=prod_db user=postgres password=ProdAdmin2026!'
);
SELECT pglogical.create_subscription(
  subscription_name := 'prod-live-sync',
  provider_dsn := 'host=your-prod-pg.postgres.database.azure.com port=5432 dbname=prod_db user=pglogical_user password=PglogicalPass2026! sslmode=require',
  replication_sets := ARRAY['default'],
  synchronize_data := true
);
SQL

# Monitor lag every 5 minutes
watch -n 300 "psql -h 10.0.5.15 -U postgres -c \
  \"SELECT subscription_name, status,
    extract(epoch from (now() - last_apply_time)) AS lag_seconds
    FROM pglogical.show_subscription_status();\""
```

#### D3.2 Maintenance Window Cutover (Week 15, Saturday 22:00)

```bash
# Full script in 15-Cutover-Runbook.md — Part 3
bash prod-maintenance-cutover.sh 2>&1 | tee /var/log/prod-cutover-$(date +%Y%m%d).log

# After cutover, update DNS:
# prod.company.com A → 10.0.4.210  (MetalLB Prod IP)
```

---

## PART E: Azure Decommission

Only after Prod is stable on-prem for 7+ days with no P1/P2 incidents:

```bash
#!/bin/bash
# azure-decommission.sh

echo "=== AZURE DECOMMISSION CHECKLIST ==="
echo "Confirm all environments are stable on-prem before running:"
read -p "Type YES to proceed: " CONFIRM
[ "$CONFIRM" = "YES" ] || { echo "Aborted"; exit 1; }

# 1. Delete AKS clusters
echo "Deleting Azure AKS clusters..."
az aks delete --name aks-dev    --resource-group rg-ae-prod-we-001    --yes --no-wait
az aks delete --name aks-qa     --resource-group rg-cv-preprod-we-001 --yes --no-wait
az aks delete --name aks-preprod --resource-group rg-as-las-we-001    --yes --no-wait
az aks delete --name aks-prod   --resource-group rg-dls-coe-we-001    --yes --no-wait

# 2. Delete Cosmos DB accounts
echo "Deleting Azure Cosmos DB..."
az cosmosdb delete --name cosmos-dev     --resource-group rg-ae-prod-we-001    --yes
az cosmosdb delete --name cosmos-qa      --resource-group rg-cv-preprod-we-001 --yes
az cosmosdb delete --name cosmos-preprod --resource-group rg-as-las-we-001     --yes
az cosmosdb delete --name cosmos-prod    --resource-group rg-dls-coe-we-001    --yes

# 3. Delete PostgreSQL servers
echo "Deleting Azure PostgreSQL..."
az postgres server delete --name pg-dev     --resource-group rg-ae-prod-we-001    --yes
az postgres server delete --name pg-qa      --resource-group rg-cv-preprod-we-001 --yes
az postgres server delete --name pg-preprod --resource-group rg-as-las-we-001     --yes
az postgres server delete --name pg-prod    --resource-group rg-dls-coe-we-001    --yes

# 4. Delete ACR (confirm all images are in Harbor first)
echo "Deleting Azure Container Registry..."
az acr delete --name "${ACR_NAME}" --resource-group rg-dls-coe-we-001 --yes

# 5. Delete VPN Gateway (migration complete, no longer needed)
az network vnet-gateway delete --name vpn-gateway-hub --resource-group rg-hub-we-001

echo "=== Azure decommission complete ==="
echo "Final: Cancel Azure subscription if no other services remain"
```

---

## Troubleshooting Quick Reference

| Problem | Where to Look | Fix |
|---------|--------------|-----|
| Pod stuck Pending | `kubectl describe pod <name> -n <ns>` | Check node affinity, PVC status, resource quota |
| PVC not binding | `kubectl describe pvc <name>` + CSI controller logs | Check disk.EnableUUID; check vSphere CSI pods |
| DB connection refused | `telnet <db-ip> 5432` from worker | Check pg_hba.conf; check firewalld on DB VM: firewall-cmd --list-ports |
| MongoDB auth failure | `mongosh --eval "db.runCommand({ping:1})"` | Check authSource in URI; check user created in correct db |
| pglogical lag increasing | Check Azure network, VPN bandwidth | Increase VPN SKU or use ExpressRoute; check DML rate |
| K8s node NotReady | `kubectl describe node` | Check kubelet logs; check containerd; check cloud-provider setting |
| MetalLB VIP not responding | `arping -I ens192 <vip>` from node | Check Forged Transmits on DVS port group |
| Harbor push rejected | `docker login harbor.internal.company.com` | Check TLS cert trusted; check project exists |
| ArgoCD sync failed | ArgoCD UI > App > Sync Status | Check Git credentials; check Helm values; check namespace |
| vSAN space full | vCenter > vSAN > Capacity | Delete old snapshots; increase vSAN policy to RAID-5; add disks |

---

## Migration Sequence Diagram

```mermaid
sequenceDiagram
    participant AZ as Azure
    participant VPN as VPN Tunnel
    participant JH as Jump Host
    participant DB as On-Prem DB VMs
    participant K8S as On-Prem K8s
    participant DNS as Internal DNS

    Note over AZ,DNS: Phase 1 - Dev + QA Migration

    AZ->>JH: Step 1 - Pull container images from ACR
    JH->>K8S: Step 2 - Push images to Harbor registry

    AZ->>VPN: Step 3 - pg_dump from Azure PostgreSQL
    VPN->>JH: Stream dump file
    JH->>DB: Step 4 - pg_restore to on-prem PostgreSQL

    AZ->>VPN: Step 5 - mongodump from Azure Cosmos DB
    VPN->>JH: Stream dump archive
    JH->>DB: Step 6 - mongorestore to on-prem MongoDB

    JH->>K8S: Step 7 - Apply K8s manifests via ArgoCD
    K8S->>DB: Step 8 - Apps connect to on-prem DBs

    JH->>DNS: Step 9 - Reduce DNS TTL to 60 seconds

    Note over K8S,DNS: Validation period - 30 minutes

    JH->>DNS: Step 10 - Update DNS to on-prem IP
    Note over AZ,DNS: Traffic now flows to on-prem
    AZ->>AZ: Step 11 - Decommission Dev/QA Azure resources
```

---

## PostgreSQL Migration — Complete Commands

### Check Azure PostgreSQL Version

```bash
# From jump host — connect to Azure PostgreSQL
psql -h <azure-pg-host>.postgres.database.azure.com \
     -U adminuser@<server-name> \
     -d postgres \
     -c "SELECT version();"
# Note the version — must match or be older than on-prem PostgreSQL 15
```

### Full Database Dump from Azure

```bash
# Set Azure credentials (one-time)
export PGHOST=<your-server>.postgres.database.azure.com
export PGUSER=adminuser@<your-server>
export PGPASSWORD='AzureDBPassword'
export PGDATABASE=appdb

# List all databases to migrate
psql -l

# Dump ALL databases (parallel, compressed)
DUMP_DIR=/data/pg-dumps/$(date +%Y%m%d)
mkdir -p $DUMP_DIR

for DB in appdb_dev appdb_qa; do
  echo "Dumping $DB..."
  pg_dump \
    -h $PGHOST \
    -U $PGUSER \
    -d $DB \
    -F directory \          # directory format (allows parallel restore)
    -j 4 \                  # 4 parallel dump workers
    --compress=9 \          # maximum compression
    --no-owner \            # don't dump owner (will set on restore)
    --no-privileges \       # don't dump GRANT/REVOKE
    -v \                    # verbose
    -f $DUMP_DIR/${DB}.dump
  echo "Done: $DB → $DUMP_DIR/${DB}.dump"
done

# Verify dump is not empty
du -sh $DUMP_DIR/
ls -la $DUMP_DIR/
```

### Transfer Dump to On-Prem

```bash
# Transfer via VPN (from jump host to on-prem DB server)
# Option A: rsync (shows progress, resumes if interrupted)
rsync -avz --progress \
  $DUMP_DIR/ \
  oracle@10.0.5.11:/data/pg-restore/

# Option B: scp
scp -r $DUMP_DIR oracle@10.0.5.11:/data/pg-restore/

# Verify transfer (compare checksums)
local_md5=$(find $DUMP_DIR -type f | sort | xargs md5sum | md5sum)
remote_md5=$(ssh oracle@10.0.5.11 "find /data/pg-restore -type f | sort | xargs md5sum | md5sum")
echo "Local:  $local_md5"
echo "Remote: $remote_md5"
# Must match!
```

### Restore to On-Prem PostgreSQL

```bash
# On the on-prem DB VM (e.g., db-dev-01 at 10.0.5.11)
ssh oracle@10.0.5.11

# Create database
sudo -u postgres psql -c "CREATE DATABASE appdb_dev ENCODING 'UTF8';"

# Restore
sudo -u postgres pg_restore \
  -h localhost \
  -U postgres \
  -d appdb_dev \
  -F directory \
  -j 4 \           # parallel restore workers
  --no-owner \
  --no-privileges \
  -v \
  /data/pg-restore/appdb_dev.dump \
  2>&1 | tee /tmp/pg-restore.log

# Verify row counts match Azure
sudo -u postgres psql -d appdb_dev << 'SQL'
SELECT schemaname, tablename, n_live_tup
FROM pg_stat_user_tables
ORDER BY n_live_tup DESC
LIMIT 20;
SQL

# Compare with Azure counts (run same query on Azure before dump)
```

---

## MongoDB Migration — Complete Commands

### Dump from Azure Cosmos DB (MongoDB API)

```bash
# Azure Cosmos DB MongoDB API connection string
COSMOS_CONN="mongodb://<account>:<key>@<account>.mongo.cosmos.azure.com:10255/?ssl=true&replicaSet=globaldb"

DUMP_DIR=/data/mongo-dumps/$(date +%Y%m%d)
mkdir -p $DUMP_DIR

# Dump with oplog for point-in-time consistency
mongodump \
  --uri "$COSMOS_CONN" \
  --db appdb_dev \
  --out $DUMP_DIR \
  --oplog \
  --gzip \
  --numParallelCollections 4 \
  --verbose

# List what was dumped
ls -la $DUMP_DIR/appdb_dev/
# Shows: collection1.bson.gz, collection1.metadata.json.gz, etc.
```

### Restore to On-Prem MongoDB

```bash
# Transfer to on-prem MongoDB VM
rsync -avz $DUMP_DIR/ oracle@10.0.5.21:/data/mongo-restore/

# On mongo-dev-01 (10.0.5.21)
ssh oracle@10.0.5.21

mongorestore \
  --host localhost:27017 \
  --db appdb_dev \
  --dir /data/mongo-restore/appdb_dev \
  --oplogReplay \
  --gzip \
  --numParallelCollections 4 \
  --verbose

# Verify document counts
mongosh --eval "
  db = db.getSiblingDB('appdb_dev');
  db.getCollectionNames().forEach(function(name) {
    print(name + ': ' + db[name].countDocuments());
  });
"
```

---

## Container Image Migration (ACR → Harbor)

```bash
# List all images in Azure ACR
az acr repository list --name <your-acr-name> --output table

# For each image, pull from ACR and push to Harbor
ACR_NAME="<your-acr-name>"
HARBOR_HOST="harbor.internal.company.com"
HARBOR_PROJECT="migration"

# Login to ACR
az acr login --name $ACR_NAME

# Login to Harbor
docker login $HARBOR_HOST -u admin -p HarborAdmin2026!

# Pull, retag, push
IMAGES=$(az acr repository list --name $ACR_NAME -o tsv)
for IMAGE in $IMAGES; do
  TAGS=$(az acr repository show-tags --name $ACR_NAME --repository $IMAGE -o tsv)
  for TAG in $TAGS; do
    FULL_IMAGE="${ACR_NAME}.azurecr.io/${IMAGE}:${TAG}"
    TARGET="${HARBOR_HOST}/${HARBOR_PROJECT}/${IMAGE}:${TAG}"
    
    echo "Migrating: $FULL_IMAGE → $TARGET"
    docker pull $FULL_IMAGE
    docker tag $FULL_IMAGE $TARGET
    docker push $TARGET
    docker rmi $FULL_IMAGE $TARGET  # clean up local disk
  done
done

echo "All images migrated to Harbor"
```

---

## Application Deployment via ArgoCD

```yaml
# Create ArgoCD Application manifests for each environment
# argocd-app-dev.yaml

apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-dev
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<your-org>/<your-repo>.git
    targetRevision: dev
    path: k8s/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

```bash
# Apply all ArgoCD applications
kubectl apply -f argocd-app-dev.yaml
kubectl apply -f argocd-app-qa.yaml

# Monitor sync status
argocd app list
argocd app sync app-dev
argocd app wait app-dev --health

# Verify pods are running
kubectl get pods -n dev
kubectl get pods -n qa
```

---

## Rollback Procedure at Each Stage

```mermaid
flowchart TD
    A([Migration Step Fails]) --> B{Which step\nfailed?}
    B -->|Image push to Harbor| C[Keep using ACR\nUpdate imagePullSecret in K8s]
    B -->|DB restore failed| D[Drop on-prem DB\nFix restore, retry]
    B -->|App pods failing| E[kubectl rollout undo\nor ArgoCD rollback]
    B -->|DNS cutover done| F[Revert DNS TTL\nPoint DNS back to Azure IP\nTest Azure app]
    C --> G{Resolved?}
    D --> G
    E --> G
    F --> G
    G -->|Yes| H[Resume migration\nfrom failed step]
    G -->|No| I[Escalate to team\nlog incident]
```

```bash
# DNS rollback (fastest — < 5 minutes)
# Repoint DNS back to Azure:
nsupdate << 'EOF'
server 10.0.1.5
zone internal.company.com
update delete app-dev A
update add app-dev 60 A <AZURE_APP_DEV_IP>
send
EOF

# Verify
nslookup app-dev.internal.company.com 10.0.1.5

# App rollback via ArgoCD
argocd app rollback app-dev
argocd app wait app-dev --health

# Database rollback: Azure DB is still running (not deleted yet)
# Just update app config to point back to Azure connection string
kubectl set env deployment/app-api \
  -n dev \
  DATABASE_URL=postgresql://user:pass@<azure-host>:5432/appdb_dev
```

