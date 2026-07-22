# 06 — Platform Services (Bare-Metal)

> **Goal**: Deploy Harbor (replaces ACR), ArgoCD (GitOps), GitLab CI (pipelines), Vault (secrets), and Redis.

---

## 1. Harbor — Container Registry (Replaces Azure Container Registry)

### 1a. Install Harbor with Helm

```bash
helm repo add harbor https://helm.goharbor.io
helm repo update

# Create Harbor namespace
kubectl create namespace harbor

# Create MinIO secret for Harbor storage backend
kubectl create secret generic harbor-minio \
  --namespace harbor \
  --from-literal=accesskey=minioadmin \
  --from-literal=secretkey='MinIO-OnPrem-2026!'

cat > /tmp/harbor-values.yaml << 'EOF'
expose:
  type: loadBalancer
  loadBalancer:
    IP: 10.0.2.10
  tls:
    enabled: true
    certSource: secret
    secret:
      secretName: harbor-tls

externalURL: https://harbor.internal

persistence:
  enabled: true
  resourcePolicy: keep
  persistentVolumeClaim:
    registry:
      storageClass: netapp-nfs
      size: 500Gi
    chartmuseum:
      storageClass: netapp-nfs
      size: 10Gi
    jobservice:
      storageClass: netapp-nfs
      size: 10Gi
    database:
      storageClass: netapp-nfs
      size: 20Gi
    redis:
      storageClass: netapp-nfs
      size: 5Gi
    trivy:
      storageClass: netapp-nfs
      size: 10Gi

harborAdminPassword: HarborAdmin-2026!

database:
  type: internal

registry:
  replicas: 2

portal:
  replicas: 2
EOF

helm install harbor harbor/harbor \
  --namespace harbor \
  --values /tmp/harbor-values.yaml \
  --version 1.14.0

# Wait for Harbor to start (~3 min)
kubectl get pods -n harbor -w

# Check access
curl -k https://harbor.internal/api/v2.0/health
```

### 1b. Create Projects per Environment

```bash
# Log in with admin
docker login harbor.internal -u admin -p 'HarborAdmin-2026!'

# Create projects via Harbor API
for ENV in dev qa preprod prod; do
  curl -sk -u admin:HarborAdmin-2026! \
    -X POST https://harbor.internal/api/v2.0/projects \
    -H 'Content-Type: application/json' \
    -d "{\"project_name\": \"${ENV}\", \"public\": false, \"metadata\": {\"public\": \"false\"}}"
done
```

### 1c. Configure K8s to Pull from Harbor

```bash
# Create imagePullSecret in each namespace
for NS in dev qa preprod prod; do
  kubectl create secret docker-registry harbor-credentials \
    --namespace=$NS \
    --docker-server=harbor.internal \
    --docker-username=admin \
    --docker-password='HarborAdmin-2026!'
done

# Patch default service account to use the secret
for NS in dev qa preprod prod; do
  kubectl patch serviceaccount default \
    -n $NS \
    -p '{"imagePullSecrets": [{"name": "harbor-credentials"}]}'
done
```

---

## 2. ArgoCD — GitOps Deployment (Replaces AKS Deployment Pipelines)

### 2a. Install ArgoCD

```bash
kubectl create namespace argocd

kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.10.0/manifests/install.yaml

# Expose ArgoCD via LoadBalancer
kubectl patch svc argocd-server -n argocd \
  -p '{"spec": {"type": "LoadBalancer", "loadBalancerIP": "10.0.2.11"}}'

# Wait for pods
kubectl get pods -n argocd -w

# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Login via CLI
argocd login 10.0.2.11 --username admin --password <initial-password> --insecure
# Change admin password
argocd account update-password
```

### 2b. Register Cluster and Git Repo

```bash
# Register Git repo (GitLab)
argocd repo add https://gitlab.internal/platform/k8s-manifests \
  --username argocd-user \
  --password 'GitLab-Token-Here'

# Create ArgoCD Application per environment
cat > /tmp/argocd-dev-app.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: dev-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://gitlab.internal/platform/k8s-manifests
    targetRevision: main
    path: environments/dev
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

kubectl apply -f /tmp/argocd-dev-app.yaml

# Check sync status
argocd app list
argocd app sync dev-app
```

---

## 3. GitLab CI — Build Pipelines (Replaces Azure DevOps)

### 3a. Install GitLab via Helm

```bash
helm repo add gitlab https://charts.gitlab.io
helm repo update

kubectl create namespace gitlab

cat > /tmp/gitlab-values.yaml << 'EOF'
global:
  hosts:
    domain: internal
    https: true
  ingress:
    enabled: false
  edition: ce

gitlab:
  gitaly:
    persistence:
      storageClass: netapp-nfs
      size: 100Gi

postgresql:
  install: false
  host: 10.0.1.30
  port: 6432
  database: gitlabdb
  username: gitlab_user
  password: GitLab-PG-2026!

redis:
  install: true

nginx-ingress:
  enabled: false

service:
  type: LoadBalancer
  loadBalancerIP: 10.0.2.12
EOF

# Create GitLab DB first
psql -h 10.0.1.30 -p 5000 -U postgres -c "CREATE DATABASE gitlabdb; CREATE USER gitlab_user WITH PASSWORD 'GitLab-PG-2026!'; GRANT ALL ON DATABASE gitlabdb TO gitlab_user;"

helm install gitlab gitlab/gitlab \
  --namespace gitlab \
  --values /tmp/gitlab-values.yaml \
  --timeout 600s

# Get root password
kubectl get secret gitlab-gitlab-initial-root-password \
  -n gitlab -o jsonpath='{.data.password}' | base64 -d && echo
```

### 3b. Sample .gitlab-ci.yml Pipeline

```yaml
# .gitlab-ci.yml — place in each application repo
stages:
  - build
  - scan
  - push
  - deploy

variables:
  HARBOR_URL: harbor.internal
  IMAGE_NAME: $HARBOR_URL/$CI_ENVIRONMENT_SLUG/$CI_PROJECT_NAME

build:
  stage: build
  image: docker:24
  services: [docker:24-dind]
  script:
    - docker build -t $IMAGE_NAME:$CI_COMMIT_SHA .
    - docker build -t $IMAGE_NAME:latest .

scan:
  stage: scan
  image: aquasec/trivy:latest
  script:
    - trivy image --exit-code 1 --severity HIGH,CRITICAL $IMAGE_NAME:$CI_COMMIT_SHA

push:
  stage: push
  image: docker:24
  services: [docker:24-dind]
  script:
    - docker login $HARBOR_URL -u $HARBOR_USER -p $HARBOR_PASSWORD
    - docker push $IMAGE_NAME:$CI_COMMIT_SHA
    - docker push $IMAGE_NAME:latest

deploy:
  stage: deploy
  image: bitnami/kubectl:latest
  script:
    - argocd app sync $CI_ENVIRONMENT_SLUG-app --auth-token $ARGOCD_TOKEN
  environment:
    name: $CI_ENVIRONMENT_SLUG
```

---

## 4. HashiCorp Vault — Secrets Management

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

kubectl create namespace vault

helm install vault hashicorp/vault \
  --namespace vault \
  --set server.ha.enabled=true \
  --set server.ha.replicas=3 \
  --set server.ha.raft.enabled=true \
  --set ui.enabled=true \
  --set ui.serviceType=LoadBalancer \
  --set ui.loadBalancerIP=10.0.2.15

# Initialise Vault (first time only)
kubectl exec -n vault vault-0 -- vault operator init \
  -key-shares=5 \
  -key-threshold=3 \
  -format=json > /secure/vault-init.json

# Unseal Vault with 3 of the 5 keys
cat /secure/vault-init.json | jq -r '.unseal_keys_b64[0]' | xargs kubectl exec -n vault vault-0 -- vault operator unseal
cat /secure/vault-init.json | jq -r '.unseal_keys_b64[1]' | xargs kubectl exec -n vault vault-0 -- vault operator unseal
cat /secure/vault-init.json | jq -r '.unseal_keys_b64[2]' | xargs kubectl exec -n vault vault-0 -- vault operator unseal

# Enable Kubernetes auth
ROOT_TOKEN=$(cat /secure/vault-init.json | jq -r '.root_token')
kubectl exec -n vault vault-0 -- vault login $ROOT_TOKEN
kubectl exec -n vault vault-0 -- vault auth enable kubernetes

# Create secret paths per environment
kubectl exec -n vault vault-0 -- vault secrets enable -path=secret kv-v2
kubectl exec -n vault vault-0 -- vault kv put secret/dev/mongodb password='DevMongo-2026!'
kubectl exec -n vault vault-0 -- vault kv put secret/dev/postgres password='AppUser-OnPrem-2026!'
kubectl exec -n vault vault-0 -- vault kv put secret/prod/mongodb password='ProdMongo-2026!'
```

---

## 5. Redis — Caching Layer

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Deploy Redis per environment (or shared with namespace isolation)
for NS in dev qa preprod prod; do
  helm install redis bitnami/redis \
    --namespace $NS \
    --set architecture=replication \
    --set auth.password="Redis-${NS}-2026!" \
    --set master.persistence.storageClass=netapp-nfs \
    --set replica.replicaCount=2 \
    --set replica.persistence.storageClass=netapp-nfs
done

# Verify
kubectl get pods -n prod | grep redis
```

---

## Verify All Platform Services

```bash
echo "=== Harbor ==="
curl -sk https://harbor.internal/api/v2.0/health | jq '.status'

echo "=== ArgoCD ==="
argocd app list

echo "=== GitLab ==="
curl -sk https://gitlab.internal/api/v4/version

echo "=== Vault ==="
kubectl exec -n vault vault-0 -- vault status

echo "=== Redis ==="
for NS in dev qa preprod prod; do
  kubectl exec -n $NS deploy/redis-master -- redis-cli ping
done
```

---

*Next: [07-Observability-Security.md](07-Observability-Security.md)*
