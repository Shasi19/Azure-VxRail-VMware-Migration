# QA Phase - Detailed Implementation Guide

**Weeks 1-3: Testing & Validation on 3-Node Kubernetes Cluster**

---

## Overview

| Phase | Duration | Nodes | Focus | Go/No-Go Gate |
|-------|----------|-------|-------|---------------|
| QA | Weeks 1-3 (3 weeks work + 1 buffer) | 3M + 3W | Testing & Validation | QA Sign-Off |

**Environment Details**:
- Kubernetes Cluster: k8s-qa
- Total VMs: 6 (3 masters + 3 workers)
- Network VLAN: 100 (10.50.0.0/16)
- Storage Allocation: 50 GB (vSAN)
- Target Load: 200 concurrent users (test load, not production scale)

---

## Week 1: Infrastructure Setup

### Day 1-2: Kubernetes Cluster Initialization

#### Step 1: Deploy Master VMs

```bash
# On vCenter: Create 3 master VMs
# VM Configuration per master:
# - CPU: 8 vCPU
# - RAM: 32 GB
# - Storage: 100 GB
# - Network: VLAN 100 (10.50.0.0/16)
# - OS: Oracle Linux 9 (minimal image)

# Master IPs (static):
# k8s-qa-master-01: 10.50.0.100
# k8s-qa-master-02: 10.50.0.101
# k8s-qa-master-03: 10.50.0.102
```

#### Step 2: Oracle Linux 9 Configuration

```bash
# On each master and worker VM:

# Update system
sudo dnf update -y

# Install required packages
sudo dnf install -y \
  curl \
  wget \
  net-tools \
  iproute \
  vim \
  git \
  container-selinux \
  selinux-policy-base

# Load kernel modules for Kubernetes
sudo modprobe overlay
sudo modprobe br_netfilter

# Persist kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/kubernetes.conf
overlay
br_netfilter
EOF

# Set sysctl parameters
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
vm.overcommit_memory               = 1
kernel.panic                        = 10
kernel.panic_on_oops               = 1
net.ipv4.ip_unprivileged_port_start = 0
EOF

sudo sysctl --system
```

#### Step 3: Install containerd

```bash
# Add docker repository for containerd
sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo

# Install containerd
sudo dnf install -y containerd.io

# Create default config
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

# Update config for Kubernetes
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Start and enable containerd
sudo systemctl daemon-reload
sudo systemctl enable containerd
sudo systemctl start containerd

# Verify
sudo systemctl status containerd
containerd --version
```

#### Step 4: Install Kubernetes 1.34 Components

```bash
# Add Kubernetes repository
sudo dnf config-manager --add-repo https://pkgs.k8s.io/core:/stable:/v1.34/rpm/

# Install K8s binaries
sudo dnf install -y \
  kubeadm-1.34.* \
  kubelet-1.34.* \
  kubectl-1.34.*

# Enable and start kubelet
sudo systemctl daemon-reload
sudo systemctl enable kubelet
sudo systemctl start kubelet

# Verify installation
kubectl version --output=json || echo "kubectl not yet configured"
kubeadm version
kubelet --version
```

#### Step 5: Initialize Kubernetes Cluster (on first master)

```bash
# On k8s-qa-master-01:

kubeadm init \
  --kubernetes-version=v1.34.0 \
  --pod-network-cidr=10.200.0.0/16 \
  --service-cidr=10.96.0.0/12 \
  --cri-socket=unix:///run/containerd/containerd.sock \
  --upload-certs \
  --certificate-key=$(openssl rand -hex 32)

# Configure kubectl for current user
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Verify cluster
kubectl get nodes
kubectl get pods -n kube-system
```

#### Step 6: Join Masters to Cluster

```bash
# Save the join command from init output (includes --control-plane flag)
# On k8s-qa-master-02 and k8s-qa-master-03:

kubeadm join 10.50.0.100:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane \
  --certificate-key <certificate-key> \
  --cri-socket=unix:///run/containerd/containerd.sock

# Verify all masters joined
kubectl get nodes  # Should show all 3 masters
kubectl get pods -n kube-system
```

### Day 3-4: Deploy Network & Storage

#### Step 7: Deploy Calico CNI

```bash
# Deploy Calico v3.27.0 (compatible with K8s 1.34)
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml

# Create Calico installation resource
cat <<EOF | kubectl apply -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - name: default
      cidr: 10.200.0.0/16
      encapsulation: VXLANCrossSubnet
  nodeMetricsPort: 9091
EOF

# Verify Calico deployment
kubectl wait --for=condition=Ready pod -l k8s-app=calico-node -n calico-system --timeout=300s
kubectl get pods -n calico-system
```

#### Step 8: Deploy vSphere CSI Driver (Storage)

```bash
# Download vSphere CSI driver manifests (v3.0.0+)
git clone https://github.com/kubernetes-sigs/vsphere-csi-driver.git
cd vsphere-csi-driver

# Create vSphere cloud credentials
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: vsphere-config-secret
  namespace: kube-system
stringData:
  csi-vsphere.conf: |
    [Global]
    cluster-id = "k8s-qa"
    insecure-flag = "true"
    
    [VirtualCenter "10.20.0.10"]
    user = "administrator@vsphere.local"
    password = "<password>"
    datacenters = "DC-OnPrem"
    port = "443"
    
    [Network]
    public-network = "VLAN 100"
EOF

# Deploy CSI driver
kubectl apply -f manifests/csi-driver-deployment.yaml

# Verify CSI driver
kubectl get pods -n kube-system | grep csi
kubectl get storageclass
```

### Day 5-7: Network & DNS Setup

#### Step 9: Configure MetalLB Load Balancer

```bash
# Install MetalLB v0.13.12 (compatible with K8s 1.34)
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml

# Create address pool for MetalLB
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: qa-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.50.100.0/24
  autoAssign: true
---
apiVersion: metallb.io/v1beta1
kind: BGPPeer
metadata:
  name: lab-peer
  namespace: metallb-system
spec:
  myASN: 65000
  peerASN: 65001
  peerAddress: 10.50.0.1
  sourceAddress: 10.50.0.100
EOF

# Verify MetalLB
kubectl get pods -n metallb-system
```

#### Step 10: Configure DNS

```bash
# Create CoreDNS configuration (already deployed)
kubectl get configmap coredns -n kube-system

# Add custom DNS entries if needed
kubectl edit configmap coredns -n kube-system

# Example entry:
# . {
#   hosts {
#     10.50.0.10  api.qa.internal
#     10.50.0.20  database.qa.internal
#   }
#   cache 30
#   loadbalance
# }
```

---

## Week 2: Application & Database Migration

### Day 8-9: PostgreSQL Single Instance Setup

#### Step 11: Deploy PostgreSQL VM

```bash
# Create PostgreSQL VM (can be on-prem VxRail or separate VM)
# VM Configuration:
# - CPU: 8 vCPU
# - RAM: 32 GB
# - Storage: 200 GB (for database)
# - Network: VLAN 30 (10.30.0.0/24)
# - IP: 10.30.0.100

# Install PostgreSQL on OL9
sudo dnf install -y postgresql14-server postgresql14-contrib

# Initialize database
sudo /usr/pgsql-14/bin/postgresql-14-setup initdb

# Configure for network access
sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /var/lib/pgsql/14/data/postgresql.conf

# Configure pg_hba.conf for network access
echo "host    all             all             10.50.0.0/16            md5" | sudo tee -a /var/lib/pgsql/14/data/pg_hba.conf

# Start PostgreSQL
sudo systemctl enable postgresql-14
sudo systemctl start postgresql-14

# Verify
sudo su - postgres -c "psql --version"
```

#### Step 12: Restore Database from Azure Backup

```bash
# Copy backup file from on-premises storage
sudo cp /backup/azure-pg-export.sql.gz /tmp/

# Restore database
sudo su - postgres -c "gunzip < /tmp/azure-pg-export.sql.gz | psql -U postgres -d production_db"

# Verify restoration
sudo su - postgres -c "psql -c 'SELECT datname FROM pg_database;'"

# Get statistics
sudo su - postgres -c "psql -d production_db -c 'SELECT COUNT(*) as total_tables FROM pg_tables WHERE schemaname != 'pg_catalog' AND schemaname != 'information_schema';'"
```

### Day 10-11: Deploy Applications to QA Kubernetes

#### Step 13: Configure Namespace & RBAC

```bash
# Create QA namespace
kubectl create namespace qa

# Create ServiceAccount for applications
kubectl create serviceaccount qa-app -n qa

# Create RBAC role for pods
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: qa
  name: qa-app-role
rules:
- apiGroups: [""]
  resources: ["pods", "services"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: qa
  name: qa-app-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: qa-app-role
subjects:
- kind: ServiceAccount
  name: qa-app
  namespace: qa
EOF
```

#### Step 14: Deploy Container Images

```bash
# Create image pull secret for Harbor
kubectl create secret docker-registry harbor-cred \
  --docker-server=harbor.internal \
  --docker-username=<username> \
  --docker-password=<password> \
  -n qa

# Deploy sample application
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway
  namespace: qa
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api-gateway
  template:
    metadata:
      labels:
        app: api-gateway
    spec:
      serviceAccountName: qa-app
      imagePullSecrets:
      - name: harbor-cred
      containers:
      - name: api-gateway
        image: harbor.internal/qa/api-gateway:1.0.0
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: 250m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
        env:
        - name: DATABASE_URL
          value: "postgresql://qa:password@10.30.0.100:5432/production_db"
---
apiVersion: v1
kind: Service
metadata:
  name: api-gateway-service
  namespace: qa
spec:
  type: LoadBalancer
  ports:
  - port: 443
    targetPort: 8080
  selector:
    app: api-gateway
EOF

# Verify deployment
kubectl get pods -n qa
kubectl get svc -n qa
```

### Day 12-14: Data Validation & Testing

#### Step 15: Validate Data Integrity

```bash
# Connect to PostgreSQL and verify
sudo su - postgres -c "psql -d production_db"

# SQL Commands:
-- List all tables
SELECT tablename FROM pg_tables WHERE schemaname = 'public';

-- Get row counts
SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) 
FROM pg_tables WHERE schemaname = 'public' ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Check for NULL values unexpectedly
SELECT COUNT(*) FROM users WHERE user_id IS NULL;

-- Verify foreign key constraints
SELECT * FROM pg_constraint WHERE contype = 'f';

-- Get summary statistics
ANALYZE;
```

#### Step 16: Run Smoke Tests

```bash
# Test API endpoint from K8s pod
kubectl run -i -t --rm debug --image=curlimages/curl --restart=Never -n qa -- \
  curl -v http://api-gateway-service:443/health

# Expected: HTTP 200 OK

# Test database connectivity from pod
kubectl run -i -t --rm debug --image=postgres:14 --restart=Never -n qa -- \
  psql -h 10.30.0.100 -U qa -d production_db -c "SELECT 1;"

# Expected: Output "1"
```

---

## Week 3: Testing & Sign-Off

### Day 15-16: Functional Testing

#### Step 17: Execute Test Cases

```bash
# Create test suite
cat <<EOF > /tmp/qa-test-suite.sh
#!/bin/bash

echo "=== QA Test Suite ==="

# Test 1: API Gateway connectivity
echo "Test 1: API Gateway..."
curl -I https://api-gateway-service/health -n qa

# Test 2: Database connectivity
echo "Test 2: Database..."
kubectl run -n qa --rm -it test-db --image=postgres:14 -- \
  psql -h 10.30.0.100 -U qa -c "SELECT 1;"

# Test 3: Container image pull
echo "Test 3: Container Image Pull..."
kubectl run -n qa --rm -it test-image \
  --image=harbor.internal/qa/api-gateway:1.0.0 -- \
  echo "Image pull successful"

echo "=== Test Suite Complete ==="
EOF

chmod +x /tmp/qa-test-suite.sh
bash /tmp/qa-test-suite.sh
```

#### Step 18: Performance Baseline

```bash
# Establish performance baselines with Apache Bench
kubectl run -i -t --rm debug --image=httpd:2-alpine --restart=Never -n qa -- \
  ab -n 1000 -c 50 http://api-gateway-service/api/users

# Record results:
# - Requests/sec: ________
# - Response time (mean): ________ ms
# - Response time (p95): ________ ms
# - Failures: ________
```

### Day 17-21: Validation & Sign-Off

#### Step 19: Quality Assurance Checklist

```bash
# QA Checklist:
- [ ] All pods running (kubectl get pods -n qa)
- [ ] All services have endpoints (kubectl get svc -n qa)
- [ ] Database reachable from pods
- [ ] Application logs clean (kubectl logs -n qa)
- [ ] No unschedulable pods (kubectl describe nodes)
- [ ] Storage provisioned correctly (kubectl get pvc -n qa)
- [ ] Network policies enforced (kubectl get networkpolicies -n qa)
- [ ] Backup/restore tested
- [ ] Performance within acceptable range
- [ ] Security scan passed (container images)
```

#### Step 20: Go/No-Go Assessment

```bash
# Sign-Off Template:

QA ENVIRONMENT SIGN-OFF:

Infrastructure Status: ✓ READY
- Kubernetes Cluster: Healthy (6 nodes running)
- Storage: Operational (50 GB allocated)
- Network: Functional (all VLANs reachable)
- Database: Restored and verified

Application Status: ✓ READY
- Containers deployed: 14/14 running
- Services operational: All tests passing
- Performance: Baseline established (______ req/sec)

Database Status: ✓ READY
- Data restored: 1,247 tables, _______ GB
- Integrity verified: No corruption detected
- Connectivity: All pods can connect

Testing Status: ✓ COMPLETE
- Smoke tests: PASSED
- Functional tests: PASSED
- Performance tests: BASELINE SET
- Security scan: PASSED

RECOMMENDATION: ✓ PROCEED TO PREPROD

Signed:
- QA Lead: _________________________ (Date: _______)
- Infrastructure Lead: ______________ (Date: _______)
- Database Administrator: __________ (Date: _______)
- Project Manager: _________________ (Date: _______)
```

---

## Success Metrics (QA Phase)

| Metric | Target | Actual |
|--------|--------|--------|
| Kubernetes Cluster Health | 100% nodes ready | ✓ |
| Pod Success Rate | > 99.5% | ✓ |
| Database Connectivity | 100% | ✓ |
| Data Integrity | 100% match (pre/post) | ✓ |
| API Response Time (p95) | < 500ms | ✓ |
| Error Rate | < 0.1% | ✓ |
| Storage Provisioning | < 30 seconds | ✓ |
| Backup Restore Time | < 1 hour | ✓ |

---

## Troubleshooting (QA Phase)

### Common Issues & Resolution

1. **Pods not scheduling**
   - Check: `kubectl describe nodes` (out of resources?)
   - Check: `kubectl describe pod <pod-name>` (affinity issues?)
   - Resolution: Increase resource requests or add more worker nodes

2. **Database connection refused**
   - Check: `telnet 10.30.0.100 5432` (port accessible?)
   - Check: `sudo systemctl status postgresql-14` (service running?)
   - Resolution: Verify firewall rules and database service status

3. **Image pull errors**
   - Check: `kubectl get events -n qa` (registry reachable?)
   - Check: Image credentials in imagePullSecret
   - Resolution: Verify Harbor credentials and network connectivity

4. **Storage mount failures**
   - Check: `kubectl get pv` and `kubectl get pvc -n qa`
   - Check: vSAN datastore health (vCenter)
   - Resolution: Create missing PVC or fix storage policy

---

**End of QA Detailed Implementation**

Reference: [00-VxRail-Complete-Index.md](./00-VxRail-Complete-Index.md), [06-PREPROD-Detailed-Implementation.md](./06-PREPROD-Detailed-Implementation.md), [04-Pre-Migration-Checklist.md](./04-Pre-Migration-Checklist.md)

