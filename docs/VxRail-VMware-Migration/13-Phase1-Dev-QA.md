# Phase 1 Migration — Dev + QA Environments

> **Scope:** Migrate Dev and QA from Azure to VxRail on-prem  
> **Duration:** 8 weeks  
> **Risk Level:** Low — non-production environments  
> **Rollback:** Keep Azure Dev + QA running in parallel until Week 8 validation passes

---

## Phase 1 Timeline

```
Week 1  ─── Infrastructure Setup (VMs, K8s, networking)
Week 2  ─── Platform Services (Harbor, MinIO, ArgoCD, monitoring)
Week 3  ─── Dev Database Migration (PostgreSQL + MongoDB)
Week 4  ─── Dev Application Migration + Go-Live
Week 5  ─── QA Database Migration (PostgreSQL + MongoDB)
Week 6  ─── QA Application Migration + Go-Live
Week 7  ─── Parallel-run validation (both Azure and on-prem active)
Week 8  ─── Phase 1 sign-off → Azure Dev + QA decommission
```

---

## Go / No-Go Gates

### Gate 1 — After Week 2 (before Dev DB migration)

| Check | Pass Criteria |
|-------|--------------|
| All 12 Phase 1 VMs running | `govc vm.info '*'` shows all powered on |
| K8s cluster healthy | `kubectl get nodes` — all Ready |
| Harbor reachable | `curl https://harbor.internal.company.com/api/v2.0/health` returns 200 |
| MinIO reachable | `mc ls vxrail` lists buckets |
| Monitoring active | Prometheus scraping all nodes |
| DNS resolving | `nslookup db-dev-01.internal.company.com` resolves |

### Gate 2 — After Week 4 (before QA migration)

| Check | Pass Criteria |
|-------|--------------|
| Dev PostgreSQL connected | App can read/write to on-prem PG |
| Dev MongoDB connected | App can read/write to on-prem MongoDB |
| Dev app deployed | All dev pods Running, 0 CrashLoopBackOff |
| Dev smoke tests pass | Automated test suite: 100% pass |
| Dev performance baseline | P95 latency within 20% of Azure baseline |

### Gate 3 — End of Week 8 (Phase 1 complete)

| Check | Pass Criteria |
|-------|--------------|
| Dev running on-prem 2+ weeks | No P1 incidents in last 7 days |
| QA running on-prem 1+ week | No P1 incidents in last 5 days |
| All QA tests pass | CI/CD pipeline green on on-prem |
| Monitoring alerting | Alerts firing and routing correctly |
| Backup tested | Restore from backup verified for Dev DB |

---

## Week 1: Infrastructure Setup

### Step 1.1 — Create Phase 1 VMs

```bash
# From your jump host with govc configured
bash docs/VxRail-VMware-Migration/07-VM-Provisioning-vSphere.md/create-k8s-vms.sh
# (Create only masters + worker-1, worker-2 for Phase 1)

bash inject-and-boot-phase1.sh
# (See 07-VM-Provisioning-vSphere.md for full script)
```

### Step 1.2 — Configure DVS Port Groups

```bash
# Create port groups on VxRail DVS (one-time setup)
# See 08-Network-vSphere.md section 1.2

# Set Forged Transmits = Accept on PG-K8s-Nodes
govc dvs.portgroup.change -dc="Datacenter" \
  -dvs="VxRail-DVS" \
  PG-K8s-Nodes -mac-learning=true
```

### Step 1.3 — Install K8s Cluster

```bash
# On master-1, master-2, master-3 — install prerequisites
# (Full commands in 10-Kubernetes-vSphere.md)

# Summary:
# 1. Install containerd
# 2. Install kubeadm/kubectl/kubelet 1.29
# 3. kubeadm init on master-1 with VIP endpoint
# 4. Join master-2 and master-3
# 5. Join worker-1 and worker-2
# 6. Apply Calico CNI
# 7. Install MetalLB

# Verify
kubectl get nodes -o wide
# NAME           STATUS   ROLES           VERSION   INTERNAL-IP
# k8s-master-1   Ready    control-plane   v1.29.0   10.0.3.11
# k8s-master-2   Ready    control-plane   v1.29.0   10.0.3.12
# k8s-master-3   Ready    control-plane   v1.29.0   10.0.3.13
# k8s-worker-1   Ready    worker          v1.29.0   10.0.4.21
# k8s-worker-2   Ready    worker          v1.29.0   10.0.4.22
```

### Step 1.4 — Install vSphere CSI Driver

```bash
# See 09-Storage-vSAN.md section 2
# 1. Enable disk.EnableUUID on all VMs via govc
# 2. Create vCenter CSI service account
# 3. Create vsphere-config-secret in K8s
# 4. Deploy CSI driver

kubectl get pods -n vmware-system-csi
```

### Step 1.5 — Create Namespaces

```bash
for NS in dev qa preprod prod monitoring logging; do
  kubectl create namespace $NS
  kubectl label namespace $NS environment=$NS
done

# Apply ResourceQuotas for Dev and QA (smaller allocations)
cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: dev-quota
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
  name: qa-quota
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

---

## Week 2: Platform Services

### Step 2.1 — Deploy Harbor (Replaces ACR)

```bash
# On harbor-01 VM (10.0.6.12)
ssh oracle@10.0.6.12

# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker ubuntu

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Add Harbor Helm chart
helm repo add harbor https://helm.goharbor.io
helm repo update

# Create Harbor values
cat > harbor-values.yaml << 'EOF'
expose:
  type: nodePort
  tls:
    enabled: true
    certSource: secret
    secret:
      secretName: harbor-tls
  nodePort:
    ports:
      http:
        nodePort: 30080
      https:
        nodePort: 30443
      notary:
        nodePort: 30444

externalURL: https://harbor.internal.company.com

persistence:
  enabled: true
  resourcePolicy: "keep"
  persistentVolumeClaim:
    registry:
      storageClass: "local-path"
      size: 200Gi
    chartmuseum:
      storageClass: "local-path"
      size: 20Gi
    database:
      storageClass: "local-path"
      size: 10Gi
    redis:
      storageClass: "local-path"
      size: 5Gi

harborAdminPassword: "Harbor@VxRail2026!"
EOF

helm install harbor harbor/harbor \
  --namespace harbor --create-namespace \
  --values harbor-values.yaml

# Verify
kubectl get pods -n harbor
```

### Step 2.2 — Deploy ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl patch svc argocd-server -n argocd \
  -p '{"spec": {"type": "LoadBalancer"}}'

# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

### Step 2.3 — Deploy Prometheus + Grafana

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.retention=30d \
  --set grafana.adminPassword=Grafana@VxRail2026! \
  --set grafana.service.type=LoadBalancer

# Verify
kubectl get svc -n monitoring | grep grafana
```

---

## Week 3: Dev Database Migration

### Step 3.1 — Set Up Dev PostgreSQL on db-dev-01

```bash
ssh oracle@10.0.5.11

# Install PostgreSQL 15
sudo dnf install -y postgresql15 postgresql15-server

# Configure pg_hba.conf to allow K8s worker IPs
sudo tee -a /etc/postgresql/15/main/pg_hba.conf << 'EOF'
host    dev_db    dev_user    10.0.4.0/24    scram-sha-256
host    dev_db    dev_user    10.0.3.0/24    scram-sha-256
EOF

# Set up database and user
sudo -u postgres psql << 'SQL'
CREATE DATABASE dev_db;
CREATE USER dev_user WITH ENCRYPTED PASSWORD 'DevPostgres2026!';
GRANT ALL PRIVILEGES ON DATABASE dev_db TO dev_user;
SQL

# Enable remote connections
sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" \
  /etc/postgresql/15/main/postgresql.conf

sudo systemctl restart postgresql
```

### Step 3.2 — Migrate Dev Data from Azure PostgreSQL

```bash
# From a machine with Azure CLI and network access to Azure

# Step 1: Export from Azure PostgreSQL (Dev)
AZURE_PG_HOST="your-dev-pg.postgres.database.azure.com"
AZURE_PG_USER="pgadmin@your-dev-pg"
AZURE_PG_PASS="YourAzurePassword"

pg_dump \
  --host="${AZURE_PG_HOST}" \
  --port=5432 \
  --username="${AZURE_PG_USER}" \
  --dbname=dev_db \
  --format=custom \
  --verbose \
  --file=/tmp/dev_db_export_$(date +%Y%m%d).dump

# Step 2: Transfer to on-prem db-dev-01
scp /tmp/dev_db_export_*.dump ubuntu@10.0.5.11:/tmp/

# Step 3: Import to on-prem PostgreSQL 15
ssh oracle@10.0.5.11 "
  pg_restore \
    --host=localhost \
    --port=5432 \
    --username=dev_user \
    --dbname=dev_db \
    --format=custom \
    --no-owner \
    --verbose \
    /tmp/dev_db_export_*.dump
"

# Step 4: Verify row counts match
# Azure
psql "host=${AZURE_PG_HOST} user=${AZURE_PG_USER} password=${AZURE_PG_PASS} dbname=dev_db" \
  -c "SELECT schemaname, tablename, n_live_tup FROM pg_stat_user_tables ORDER BY n_live_tup DESC LIMIT 20;"

# On-prem
ssh oracle@10.0.5.11 \
  "psql -U dev_user -d dev_db -c \"SELECT schemaname, tablename, n_live_tup FROM pg_stat_user_tables ORDER BY n_live_tup DESC LIMIT 20;\""
```

### Step 3.3 — Set Up Dev MongoDB on mongo-dev-01

```bash
ssh oracle@10.0.5.21

# Install MongoDB 7.0
wget -qO - https://www.mongodb.org/static/pgp/server-7.0.asc | sudo apt-key add -
echo "deb [ arch=amd64 ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" \
  | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
sudo dnf install -y mongodb-org

# Configure MongoDB
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
EOF

sudo systemctl enable mongod && sudo systemctl start mongod

# Create dev database user
mongosh << 'JS'
use admin
db.createUser({
  user: "admin",
  pwd: "MongoAdmin2026!",
  roles: [{role: "root", db: "admin"}]
})
use dev-cosmos
db.createUser({
  user: "dev_user",
  pwd: "DevMongo2026!",
  roles: [{role: "readWrite", db: "dev-cosmos"}]
})
JS
```

### Step 3.4 — Migrate Dev MongoDB from Azure Cosmos DB

```bash
# Export from Azure Cosmos DB (MongoDB API)
COSMOS_ACCOUNT="your-cosmos-account"
COSMOS_KEY="your-cosmos-primary-key"
COSMOS_HOST="${COSMOS_ACCOUNT}.mongo.cosmos.azure.com"

mongodump \
  --uri="mongodb://${COSMOS_ACCOUNT}:${COSMOS_KEY}@${COSMOS_HOST}:10255/dev-cosmos?ssl=true&replicaSet=globaldb&retrywrites=false&maxIdleTimeMS=120000" \
  --out=/tmp/cosmos-dev-dump \
  --db=dev-cosmos

# Transfer to on-prem
scp -r /tmp/cosmos-dev-dump ubuntu@10.0.5.21:/tmp/

# Restore to on-prem MongoDB
ssh oracle@10.0.5.21 "
  mongorestore \
    --uri='mongodb://dev_user:DevMongo2026!@localhost:27017/dev-cosmos?authSource=dev-cosmos' \
    --drop \
    --dir=/tmp/cosmos-dev-dump/dev-cosmos
"

# Verify document count
ssh oracle@10.0.5.21 "mongosh --quiet --eval \"
  db.getSiblingDB('dev-cosmos').getCollectionNames().forEach(c => {
    print(c + ': ' + db.getSiblingDB('dev-cosmos').getCollection(c).countDocuments())
  })
\""
```

---

## Week 4: Dev Application Migration

### Step 4.1 — Push Images to Harbor

```bash
# Log in to Harbor from your CI/CD machine
docker login harbor.internal.company.com -u admin -p 'Harbor@VxRail2026!'

# Pull images from Azure ACR and re-push to Harbor
AZURE_ACR="your-acr.azurecr.io"
HARBOR="harbor.internal.company.com"

# Create project in Harbor first
curl -u "admin:Harbor@VxRail2026!" -X POST \
  "https://${HARBOR}/api/v2.0/projects" \
  -H "Content-Type: application/json" \
  -d '{"project_name": "production", "public": false}'

# Re-tag and push
az acr login --name "${AZURE_ACR%%.*}"
IMAGES=$(az acr repository list --name "${AZURE_ACR%%.*}" -o tsv)

for IMG in $IMAGES; do
  TAGS=$(az acr repository show-tags --name "${AZURE_ACR%%.*}" --repository "$IMG" -o tsv)
  for TAG in $TAGS; do
    docker pull "${AZURE_ACR}/${IMG}:${TAG}"
    docker tag "${AZURE_ACR}/${IMG}:${TAG}" "${HARBOR}/production/${IMG}:${TAG}"
    docker push "${HARBOR}/production/${IMG}:${TAG}"
  done
done
```

### Step 4.2 — Create K8s Secrets for Dev

```bash
# PostgreSQL connection
kubectl create secret generic db-credentials \
  --namespace=dev \
  --from-literal=DB_HOST=db-dev-01.internal.company.com \
  --from-literal=DB_PORT=5432 \
  --from-literal=DB_NAME=dev_db \
  --from-literal=DB_USER=dev_user \
  --from-literal=DB_PASSWORD=DevPostgres2026!

# MongoDB connection
kubectl create secret generic mongo-credentials \
  --namespace=dev \
  --from-literal=MONGO_URI="mongodb://dev_user:DevMongo2026!@10.0.5.21:27017/dev-cosmos?authSource=dev-cosmos"

# Harbor registry pull secret
kubectl create secret docker-registry harbor-pull \
  --namespace=dev \
  --docker-server=harbor.internal.company.com \
  --docker-username=admin \
  --docker-password=Harbor@VxRail2026!
```

### Step 4.3 — Deploy Dev Application via ArgoCD

```bash
# Create ArgoCD Application for Dev
cat << 'EOF' | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: webapp-dev
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://gitlab.internal.company.com/webapp/webapp.git
    targetRevision: HEAD
    path: helm/webapp-chart
    helm:
      valueFiles:
        - values-dev.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

# Monitor deployment
kubectl rollout status deployment/webapp -n dev --timeout=300s
kubectl get pods -n dev
```

### Step 4.4 — Dev Smoke Tests

```bash
# Get dev service URL
DEV_IP=$(kubectl get svc webapp-svc -n dev -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Basic health check
curl -f "http://${DEV_IP}/health" && echo "Health: PASS" || echo "Health: FAIL"

# API test
curl -f "http://${DEV_IP}/api/v1/status" | jq .

# Run automated test suite
kubectl run smoke-test \
  --image=postman/newman:latest \
  --namespace=dev \
  --restart=Never \
  --env="BASE_URL=http://${DEV_IP}" \
  -- run /tests/smoke-tests.json \
       --env-var "base_url=http://${DEV_IP}"

kubectl logs smoke-test -n dev --follow
```

---

## Week 5-6: QA Migration (Same Steps as Dev)

Repeat Weeks 3-4 for QA, using:
- `db-qa-01` (10.0.5.12) — PostgreSQL QA
- `mongo-qa-01` (10.0.5.22) — MongoDB QA
- Namespace: `qa`
- Credentials suffix: `qa` instead of `dev`
- Azure source: QA PostgreSQL and Cosmos DB

```bash
# QA-specific connection strings
kubectl create secret generic db-credentials \
  --namespace=qa \
  --from-literal=DB_HOST=db-qa-01.internal.company.com \
  --from-literal=DB_PORT=5432 \
  --from-literal=DB_NAME=qa_db \
  --from-literal=DB_USER=qa_user \
  --from-literal=DB_PASSWORD=QAPostgres2026!

kubectl create secret generic mongo-credentials \
  --namespace=qa \
  --from-literal=MONGO_URI="mongodb://qa_user:QAMongo2026!@10.0.5.22:27017/qa-cosmos?authSource=qa-cosmos"
```

---

## Week 7-8: Validation and Sign-Off

### Parallel Run Checklist

```bash
#!/bin/bash
# phase1-validation.sh — run this daily during weeks 7-8

echo "===== Phase 1 Validation $(date) ====="

echo -n "[Dev] PostgreSQL reachable: "
psql "host=10.0.5.11 user=dev_user password=DevPostgres2026! dbname=dev_db" \
  -c "SELECT version();" -t 2>/dev/null | grep -q PostgreSQL && echo "PASS" || echo "FAIL"

echo -n "[Dev] MongoDB reachable: "
mongosh "mongodb://dev_user:DevMongo2026!@10.0.5.21:27017/dev-cosmos?authSource=dev-cosmos" \
  --eval "db.runCommand({ping:1})" --quiet 2>/dev/null | grep -q '"ok": 1' && echo "PASS" || echo "FAIL"

echo -n "[Dev] App responding: "
curl -sf "http://$(kubectl get svc webapp-svc -n dev -o jsonpath='{.status.loadBalancer.ingress[0].ip}')/health" && echo "PASS" || echo "FAIL"

echo -n "[QA] PostgreSQL reachable: "
psql "host=10.0.5.12 user=qa_user password=QAPostgres2026! dbname=qa_db" \
  -c "SELECT version();" -t 2>/dev/null | grep -q PostgreSQL && echo "PASS" || echo "FAIL"

echo -n "[QA] App responding: "
curl -sf "http://$(kubectl get svc webapp-svc -n qa -o jsonpath='{.status.loadBalancer.ingress[0].ip}')/health" && echo "PASS" || echo "FAIL"

echo -n "[K8s] All nodes Ready: "
NOT_READY=$(kubectl get nodes --no-headers | grep -v Ready | wc -l)
[ "$NOT_READY" -eq 0 ] && echo "PASS" || echo "FAIL ($NOT_READY nodes not ready)"

echo -n "[Monitoring] Prometheus targets up: "
curl -sf "http://$(kubectl get svc -n monitoring kube-prometheus-stack-prometheus -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):9090/api/v1/targets" \
  | jq '.data.activeTargets | map(select(.health=="down")) | length' | grep -q "^0$" && echo "PASS" || echo "WARN — check Prometheus targets"

echo ""
echo "===== Validation complete ====="
```

### Azure Dev + QA Decommission (End of Week 8)

Only after all Gate 3 checks pass:

```bash
# 1. Update DNS to point to on-prem IPs
# dev.company.com → 10.0.4.200 (MetalLB IP for Dev)
# qa.company.com  → 10.0.4.201 (MetalLB IP for QA)

# 2. Delete Azure resources (Dev + QA only)
az aks delete --name aks-dev --resource-group rg-ae-prod-we-001 --yes
az aks delete --name aks-qa --resource-group rg-cv-preprod-we-001 --yes
az cosmosdb delete --name cosmos-dev --resource-group rg-ae-prod-we-001 --yes
az postgres server delete --name pg-dev --resource-group rg-ae-prod-we-001 --yes

# 3. Keep Azure PreProd and Prod running — Phase 2 handles those
echo "Phase 1 complete. PreProd and Prod still running on Azure."
```

---

## Phase 1 Gantt Chart (8 Weeks)

```mermaid
gantt
    title Phase 1 - Dev and QA Migration
    dateFormat  YYYY-MM-DD
    section Week 1-2 Prep
    Final infra validation          :a1, 2024-01-01, 5d
    Freeze Dev/QA Azure deployments :a2, after a1, 2d
    Announce maintenance window     :a3, after a1, 1d
    section Week 2-3 Images
    Pull all images from ACR        :b1, 2024-01-08, 2d
    Push images to Harbor           :b2, after b1, 1d
    Verify Harbor image pulls       :b3, after b2, 1d
    section Week 3-4 Databases
    pg_dump Dev DB from Azure       :c1, 2024-01-15, 1d
    Transfer and restore Dev PostgreSQL :c2, after c1, 1d
    mongodump Dev from Cosmos DB    :c3, after c1, 1d
    Restore Dev MongoDB             :c4, after c3, 1d
    Verify DB data integrity        :c5, after c2, 2d
    section Week 4-5 Dev Cutover
    Deploy Dev apps via ArgoCD      :d1, 2024-01-22, 2d
    Smoke test Dev environment      :d2, after d1, 2d
    Reduce Dev DNS TTL to 60s       :d3, after d2, 1d
    Dev DNS cutover                 :d4, after d3, 1d
    Post-cutover Dev validation     :d5, after d4, 2d
    section Week 5-6 QA
    pg_dump QA DB from Azure        :e1, 2024-01-29, 1d
    Transfer and restore QA DB      :e2, after e1, 1d
    Restore QA MongoDB              :e3, after e1, 1d
    Verify QA DB integrity          :e4, after e2, 2d
    section Week 6-7 QA Cutover
    Deploy QA apps via ArgoCD       :f1, 2024-02-05, 2d
    QA team regression testing      :f2, after f1, 3d
    QA DNS cutover                  :f3, after f2, 1d
    Post-cutover QA validation      :f4, after f3, 2d
    section Week 7-8 Cleanup
    Decommission Dev Azure resources :g1, 2024-02-12, 2d
    Decommission QA Azure resources  :g2, after g1, 2d
    Phase 1 retrospective           :g3, after g2, 1d
    Go/No-Go for Phase 2            :milestone, after g3, 0d
```

---

## Week-by-Week Task Breakdown

### Week 1: Preparation

| Day | Task | Owner | Duration | Verification |
|-----|------|-------|----------|-------------|
| Mon | Final infrastructure validation — all VMs running, K8s healthy | Infra team | 4h | kubectl get nodes shows all Ready |
| Mon | Backup confirmation — Veeam jobs ran successfully last night | Backup admin | 1h | Veeam console — all jobs green |
| Tue | Announce: Dev/QA change freeze (no new Azure deployments) | Project manager | 30min | Email to Dev/QA teams |
| Tue | Document current Azure resource inventory (VMs, IPs, configs) | Infra team | 4h | Spreadsheet completed |
| Wed | Set up monitoring alerts for migration period | DevOps | 2h | Test alert fires correctly |
| Wed | Prepare migration scripts — dry run in test | Infra team | 4h | Scripts run without errors on test data |
| Thu | Team walkthrough of migration steps | All | 2h | All team members understand their tasks |
| Fri | Confirm go/no-go with stakeholders | PM | 1h | Written approval from Dev/QA leads |

### Week 2-3: Image Migration

```bash
# Day 1: Inventory all ACR images
az acr repository list --name <your-acr> -o table
az acr repository show-tags --name <your-acr> --repository <image> -o table

# Day 2-3: Migrate images
# (run migration script from migration execution guide)

# Verify in Harbor:
# Login to https://harbor.internal.company.com
# Check: Projects → migration → repositories
# Confirm all images are present with correct tags

# Test pull from K8s cluster:
kubectl run test-pull \
  --image=harbor.internal.company.com/migration/<your-image>:latest \
  --restart=Never \
  -n dev
kubectl describe pod test-pull -n dev
# Should show: Successfully pulled image
kubectl delete pod test-pull -n dev
```

---

## Dev Environment Cutover Checklist

Complete every item before executing DNS cutover:

```
PRE-CUTOVER (Day before cutover window):
  [ ] DB dump completed and verified (row counts match)
  [ ] Images available in Harbor (test docker pull from K8s)
  [ ] App pods running and healthy: kubectl get pods -n dev
  [ ] App health check endpoint responding: curl http://<MetalLB-IP>/health
  [ ] DB connections working: app logs show no DB connection errors
  [ ] Veeam backup of on-prem Dev VMs completed
  [ ] Rollback tested: can revert DNS in < 5 minutes
  [ ] Stakeholders notified of cutover time
  [ ] On-call team confirmed available during cutover window

CUTOVER EXECUTION (Maintenance window: e.g., Saturday 02:00-04:00):
  [ ] 02:00 - Stop all write operations on Azure Dev app
  [ ] 02:05 - Final pg_dump delta (any changes since initial dump)
  [ ] 02:10 - Apply delta to on-prem PostgreSQL
  [ ] 02:15 - Reduce Azure DNS TTL: set to 60 seconds
  [ ] 02:20 - Verify all traffic still hitting Azure
  [ ] 02:30 - Update DNS to point to on-prem MetalLB IP
  [ ] 02:35 - Monitor traffic: should shift to on-prem within 1 min
  [ ] 02:40 - Run smoke tests against on-prem Dev app
  [ ] 03:00 - Confirm with Dev team: app working
  [ ] 03:30 - Azure Dev resources kept running (standby for 1 week)

POST-CUTOVER (1 week after):
  [ ] No rollback triggered
  [ ] Performance metrics stable (compare to Azure baseline)
  [ ] All automated tests passing
  [ ] Decommission Azure Dev: stop VMs → delete resources
```

---

## Go/No-Go Criteria Before Phase 2

All of these must be YES before starting PreProd/Prod migration:

| Criteria | Target | Actual | Pass/Fail |
|----------|--------|--------|-----------|
| Dev uptime (1 week post-cutover) | > 99.5% | | |
| QA uptime (1 week post-cutover) | > 99.5% | | |
| No P1/P2 incidents in on-prem Dev or QA | 0 incidents | | |
| Veeam backups running daily | 14/14 jobs succeeded | | |
| K8s cluster health | 0 node failures | | |
| DB replication/performance | < 10ms query time for common queries | | |
| Team confidence level | Team votes Go | | |
| Budget approved for Phase 2 | Finance approved | | |

