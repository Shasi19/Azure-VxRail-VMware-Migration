# QA Environment Migration Timeline
## 6 Weeks + 1 Week Buffer = 7 Weeks Total

> **Phase:** Phase 1 — Testing & Validation  
> **Timeline:** Weeks 1–7 (6 weeks of work, 1 week buffer)  
> **Target Stack:** Oracle Linux 9 + Kubernetes 1.34 on Dell VxRail vSphere  
> **Objective:** Migrate and validate QA workloads on VxRail vSphere  
> **Success Criteria:** All QA applications running on-prem, performance validated, sign-off received

---

## 📅 Week-by-Week Breakdown

### **Week 1: Infrastructure Assessment & Discovery**
**Focus:** Assess current QA infrastructure and plan migration

**Daily Tasks:**
- **Day 1:** Project kickoff meeting, confirm team assignments and escalation paths
- **Day 2:** Document current Azure QA environment (AKS cluster specs, database versions, storage size)
- **Day 3:** Audit VxRail physical cluster (verify 6 nodes healthy, CPU/RAM/storage available)
- **Day 4:** Test network connectivity between Azure and on-prem (verify < 50ms latency, bandwidth sufficient)
- **Day 5:** Create infrastructure inventory and document Oracle 9 / K8s 1.34 requirements

**Deliverables:**
- [ ] Current Azure QA infrastructure documented (K8s version, node counts, storage size)
- [ ] VxRail cluster health report (all 6 nodes, vSAN status)
- [ ] Network connectivity baseline (latency, throughput, VPN status)
- [ ] Team assignments with escalation paths
- [ ] Oracle 9 / K8s 1.34 compatibility requirements documented

**Success Metrics:**
- Network latency Azure ↔ On-Prem: < 50ms
- VxRail: All 6 nodes healthy, vSAN enabled
- Documentation complete and reviewed
- Team ready to begin Week 2

**Commands:**
```bash
# Verify vCenter accessibility
ping vcenter.onprem.local
curl -k https://vcenter.onprem.local/sdk

# Check vSAN status
govc about -u administrator@vsphere.local
govc datastore.info -ds=vsan

# Test network connectivity
ping -c 5 azure-app-gateway.eastus.cloudapp.azure.com
iperf3 -c azure-iperf-server -t 10  # Bandwidth test

# Check Azure AKS version
az aks show --resource-group <rg> --name <cluster> --query kubernetesVersion
```

**Rollback:** N/A (discovery phase only)

---

### **Week 2: Oracle 9 Template & Shared Infrastructure**
**Focus:** Create Oracle Linux 9 VM template and configure VMware vSphere foundation

**Daily Tasks:**
- **Day 1:** Download Oracle Linux 9 ISO and create VM template
- **Day 2:** Configure template with Kubernetes prerequisites (kubelet, kubeadm, kubectl)
- **Day 3:** Create Distributed Virtual Switch (DVS) with VLANs and firewall rules
- **Day 4:** Create vSAN storage classes and deploy vSphere Cloud Controller Manager
- **Day 5:** Test template VM boot and verify all prerequisites

**Oracle 9 Template Specifications:**
```
Template Name: ol9-k8s-v1.34-base
OS: Oracle Linux 9.4 (or latest)
Disk: 100GB (root /dev/sda1)
CPU: 4 cores (will resize per node type)
RAM: 8GB (will resize per node type)
Network: 1 NIC (DHCP initially, then static IP)

Installed Packages:
  - kubeadm 1.34.x
  - kubelet 1.34.x
  - kubectl 1.34.x
  - containerd (container runtime)
  - cri-tools
  - curl, wget, vim, git
  - chrony (NTP client)
  - firewalld
  - ca-certificates

Kernel modules enabled:
  - overlay (for containerd)
  - br_netfilter (for iptables/netfilter)
  
Sysctl parameters configured:
  - net.bridge.bridge-nf-call-iptables = 1
  - net.ipv4.ip_forward = 1
```

**Deliverables:**
- [ ] Oracle Linux 9 template created (ol9-k8s-v1.34-base)
- [ ] Kubernetes 1.34 packages installed and verified
- [ ] containerd configured and running
- [ ] DVS with 3 VLAN port groups: management (100), kubernetes (101), data (102)
- [ ] Firewall rules documented for all traffic types
- [ ] vSAN storage classes: fast (SSD), standard (HDD), archive
- [ ] vSphere Cloud Controller Manager deployed
- [ ] Template VM tested (boots in < 60s, network connectivity verified)

**Success Metrics:**
- `kubelet --version` returns v1.34.x
- `containerd --version` returns latest stable
- Template clones successfully
- Network connectivity < 5ms on same VLAN
- vSAN storage I/O write speed > 150MB/s
- CCM pod running: `kubectl get pods -n kube-system | grep vsphere-cloud-controller`

**Commands:**
```bash
# Download Oracle Linux 9
wget https://yum.oracle.com/ISOS/OracleLinux-R9-U0-x86_64-dvd.iso

# Create template VM in vCenter
govc vm.create -ds=vsan \
  -m=8192 \
  -c=4 \
  -net=qa-management \
  -net.adapter=vmxnet3 \
  ol9-k8s-v1.34-base

# Install Kubernetes 1.34 packages
sudo dnf install -y kubeadm-1.34.* kubelet-1.34.* kubectl-1.34.*
sudo systemctl enable kubelet

# Install containerd
sudo dnf install -y containerd
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo systemctl enable containerd
sudo systemctl restart containerd

# Configure kernel modules for K8s
sudo modprobe overlay
sudo modprobe br_netfilter

cat << EOF | sudo tee /etc/modules-load.d/kubernetes.conf
overlay
br_netfilter
EOF

# Configure sysctl for K8s networking
cat << EOF | sudo tee /etc/sysctl.d/kubernetes.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

sudo sysctl --system

# Verify installation
kubeadm version -o short
kubelet --version
kubectl version --client --short
containerd --version

# Create DVS and port groups
govc dvs.create -dc <datacenter> qa-dvs
govc dvs.portgroup.create -dvs qa-dvs -vlan 100 qa-management
govc dvs.portgroup.create -dvs qa-dvs -vlan 101 qa-kubernetes
govc dvs.portgroup.create -dvs qa-dvs -vlan 102 qa-data

# Deploy vSphere CCM for K8s 1.34
wget https://raw.githubusercontent.com/kubernetes-sigs/cloud-provider-vsphere/master/manifests/controller-manager.yaml
# Edit with appropriate vCenter credentials
kubectl apply -f controller-manager.yaml
```

**Rollback:** Delete DVS, revert sysctl changes, delete storage classes

---

### **Week 3: Kubernetes 1.34 Cluster Deployment**
**Focus:** Build 3-master + 3-worker Kubernetes 1.34 cluster on vSphere

**Daily Tasks:**
- **Day 1:** Clone 3 master VMs from template (qa-master-1, qa-master-2, qa-master-3)
- **Day 2:** Clone 3 worker VMs (qa-worker-1, qa-worker-2, qa-worker-3)
- **Day 3:** Configure hostnames, static IPs, SSH keys, sudoers for all nodes
- **Day 4:** Pre-pull K8s 1.34 images, verify container runtime, configure kubelet
- **Day 5:** Bootstrap K8s 1.34 cluster with kubeadm init and join workers

**Node Sizing for QA:**
```
Master Nodes (qa-master-1/2/3):
  - CPU: 4 cores
  - RAM: 8GB
  - Disk: 100GB (/var/lib/kubelet grows with etcd database)
  - Network: qa-management, qa-kubernetes
  - OS: Oracle Linux 9 template
  
Worker Nodes (qa-worker-1/2/3):
  - CPU: 8 cores
  - RAM: 16GB
  - Disk: 200GB (/var/lib/docker for container images)
  - Network: qa-kubernetes, qa-data
  - OS: Oracle Linux 9 template
```

**Deliverables:**
- [ ] 3 master nodes running (qa-master-1, qa-master-2, qa-master-3) with Oracle 9
- [ ] 3 worker nodes running (qa-worker-1, qa-worker-2, qa-worker-3) with Oracle 9
- [ ] Kubernetes 1.34 cluster initialized and operational
- [ ] Calico CNI installed and pods networking
- [ ] MetalLB LoadBalancer controller running
- [ ] vSphere Cloud Controller Manager deployed
- [ ] vSAN CSI driver installed for persistent volumes
- [ ] DNS (CoreDNS) operational

**Success Metrics:**
- `kubectl get nodes` shows 6 nodes with status "Ready"
- `kubectl version --short` shows v1.34.x for both client/server
- All system pods running in kube-system namespace
- Pod-to-pod networking latency < 5ms
- PVC provisioning: Create PVC and verify vSAN volume appears in vCenter

**Commands:**
```bash
# On first master node (qa-master-1)
# Initialize K8s 1.34 cluster
sudo kubeadm init \
  --kubernetes-version=v1.34.0 \
  --apiserver-advertise-address=10.10.100.10 \
  --control-plane-endpoint=qa-k8s-vip.onprem.local:6443 \
  --pod-network-cidr=10.244.0.0/16 \
  --service-cidr=10.96.0.0/12 \
  --cri-socket unix:///run/containerd/containerd.sock

# Setup kubeconfig
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Verify cluster initialized
kubectl cluster-info
kubectl get pods -A

# Join second and third master nodes
# Get join command from first master
kubeadm token create --print-join-command

# On qa-master-2 and qa-master-3, run:
sudo kubeadm join qa-k8s-vip.onprem.local:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane

# Verify all masters are ready
kubectl get nodes -l node-role.kubernetes.io/control-plane

# Install Calico CNI (compatible with K8s 1.34)
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/custom-resources.yaml

# Install MetalLB for LoadBalancer services
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/manifests/namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/manifests/metallb.yaml

# Install vSAN CSI Driver for K8s 1.34
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/vsphere-csi-driver/master/manifests/vanilla/vsphere-csi-controller-deployment.yaml

# Join worker nodes
# On qa-worker-1/2/3, run:
sudo kubeadm join qa-k8s-vip.onprem.local:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>

# Verify full cluster
kubectl get nodes -o wide
kubectl get pods -A
kubectl top nodes  # Verify metrics collection

# Verify K8s version across cluster
kubectl get nodes -o wide | grep -i version
```

**Rollback:** `kubeadm reset -f` on all nodes, delete all VMs

---

### **Week 4: Database Migration (PostgreSQL & Cosmos DB)**
**Focus:** Migrate data from Azure to on-prem

**Daily Tasks:**
- **Day 1-2:** Deploy PostgreSQL 14 VM (qa-postgres-primary), configure replication
- **Day 3:** Start pg_dump from Azure and restore to on-prem
- **Day 4:** Deploy MongoDB (if using Cosmos DB) to K8s and migrate data
- **Day 5:** Validate data integrity, backup/restore tested

**Deliverables:**
- [ ] PostgreSQL 14 running on Oracle 9 VM on vSphere
- [ ] All Azure PostgreSQL databases dumped and restored
- [ ] Row counts validated (match Azure within 0.1%)
- [ ] Backup/restore tested and verified
- [ ] MongoDB deployed to K8s (if needed)
- [ ] Cosmos DB collections imported to MongoDB
- [ ] Connection strings updated in ConfigMaps

**Success Metrics:**
- PostgreSQL connection latency < 100ms
- Query response time < 500ms
- Replication lag (if setup) < 1 second
- Backup restore completes in < 1 hour
- Document counts match Cosmos DB

**Commands:**
```bash
# Deploy PostgreSQL VM with Oracle 9
govc vm.create -ds=vsan -m=8192 -c=4 \
  -net=qa-data qa-postgres-primary

# On qa-postgres-primary, install PostgreSQL 14
sudo dnf install -y postgresql14-server postgresql14-contrib

# Dump from Azure PostgreSQL
pg_dumpall -h qadb.postgres.database.azure.com \
  -U postgres@qadb \
  --password \
  --format=plain > /tmp/azure-full-backup.sql

# Restore to on-prem
psql -h qa-postgres.onprem.local -U postgres < /tmp/azure-full-backup.sql

# Validate data
psql -h qa-postgres.onprem.local -U postgres \
  -c "SELECT datname, count(*) FROM pg_tables GROUP BY datname;"

# Deploy MongoDB to K8s (if using Cosmos DB)
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install qa-mongo bitnami/mongodb \
  -n qa-data --create-namespace \
  --set auth.enabled=true \
  --set auth.rootPassword=<password>

# Import Cosmos DB data
mongoimport --uri="mongodb://root:password@qa-mongo.qa-data.svc.cluster.local/qadb" \
  --file=cosmos-export.json \
  --jsonArray
```

**Rollback:** Keep Azure databases running, on-prem as replica

---

### **Week 5: Application Migration & Deployment**
**Focus:** Deploy QA applications to on-prem Kubernetes 1.34 cluster

**Daily Tasks:**
- **Day 1:** Set up Harbor container registry on K8s or VM
- **Day 2:** Build and push all QA application images to Harbor
- **Day 3:** Prepare Helm charts with on-prem configuration
- **Day 4:** Deploy applications to qa-apps namespace
- **Day 5:** Verify health, connectivity, performance

**Deliverables:**
- [ ] Harbor registry deployed and accessible
- [ ] All QA app images pushed to Harbor (compatible with K8s 1.34)
- [ ] Helm charts updated with on-prem hosts/IPs
- [ ] All applications deployed with 3+ replicas
- [ ] Health checks passing for all services
- [ ] ConfigMaps/Secrets created for credentials

**Commands:**
```bash
# Deploy Harbor to K8s
helm repo add harbor https://goharbor.github.io/harbor
helm install harbor harbor/harbor \
  -n harbor-system --create-namespace

# Login to Harbor
docker login harbor.onprem.local -u admin -p <password>

# Build and push app images
docker build -t harbor.onprem.local/qa/app1:v1.0 -f Dockerfile.app1 .
docker push harbor.onprem.local/qa/app1:v1.0

# Create namespace and pull secrets
kubectl create namespace qa-apps
kubectl create secret docker-registry harbor-creds \
  --docker-server=harbor.onprem.local \
  --docker-username=admin \
  --docker-password=<password> \
  -n qa-apps

# Create ConfigMaps for database hosts
kubectl create configmap qa-config \
  --from-literal=DB_HOST=qa-postgres.onprem.local \
  --from-literal=MONGO_HOST=qa-mongo.qa-data.svc.cluster.local \
  -n qa-apps

# Deploy applications via Helm
helm install qa-app1 ./charts/app1 \
  -n qa-apps \
  --values values-qa.yaml

# Verify deployments
kubectl get deployments -n qa-apps
kubectl get pods -n qa-apps -w
```

**Success Metrics:**
- All pods Running (0 restarts)
- Application endpoints responding
- Database queries executing
- Logs clean (no ERROR messages)

**Rollback:** `helm uninstall qa-app*` in qa-apps namespace

---

### **Week 6: Testing, Validation & Performance**
**Focus:** Comprehensive testing for QA environment

**Daily Tasks:**
- **Day 1:** Functional testing (all features work end-to-end)
- **Day 2:** Integration testing (microservices communication)
- **Day 3:** Performance baseline (measure response times)
- **Day 4:** Load testing (100-500 concurrent users)
- **Day 5:** Backup/restore validation, security scanning

**Test Acceptance Criteria:**

| Test | Threshold |
|------|-----------|
| Functional tests pass rate | > 95% |
| API response time (p95) | < 1 second |
| Database query time (p95) | < 500ms |
| Load test error rate (500 VU) | < 5% |
| CPU usage under peak load | < 75% |
| Memory usage (stable, no leaks) | < 80% |
| Backup restore time | < 1 hour |
| Security vulnerabilities (critical) | 0 |

**Deliverables:**
- [ ] Functional test report (pass/fail per feature)
- [ ] Performance baseline document
- [ ] Load test report with metrics
- [ ] Issue log with severity
- [ ] Security scan results
- [ ] Sign-off from QA lead

**Commands:**
```bash
# Performance testing with Apache Bench
ab -n 1000 -c 50 https://app.onprem.local/

# Load testing with JMeter
jmeter -n -t testplan.jmx -l results.jtl

# Security scanning with Trivy
trivy image harbor.onprem.local/qa/app1:v1.0

# Backup and restore test
kubectl exec -it <backup-pod> -- backup-now
# Verify restore from backup

# Container image compliance
kubectl run -it --rm debug --image=harbor.onprem.local/qa/app1:v1.0 -- bash
```

**Success Metrics:**
- Tests > 95% pass
- Response times within SLA
- Load test < 5% errors
- Backup restore works
- No critical vulnerabilities

**Rollback:** Keep Azure as primary, on-prem as staging

---

### **Week 7: Buffer, Remediation & Sign-Off**
**Focus:** Resolve issues and obtain approval

**Daily Tasks:**
- **Day 1-2:** Fix all P1 issues from testing
- **Day 3:** Re-test critical paths after fixes
- **Day 4:** Prepare QA sign-off document
- **Day 5:** Sign-off meeting and lessons learned

**Deliverables:**
- [ ] All P1 issues resolved
- [ ] Test report final
- [ ] QA environment sign-off document signed
- [ ] Lessons learned documented
- [ ] PREPROD team briefing completed

**Success Criteria:**
- QA environment approved and stable
- No blocking issues for PREPROD
- Team confident and trained
- Documentation complete

---

## 📊 Resource Requirements (QA Phase)

### VxRail Cluster Allocation
- **CPU:** 16 vCPU (out of 96 total)
- **RAM:** 64 GB (out of 96 total)
- **Storage:** 500 GB vSAN
- **Network:** qa-management, qa-kubernetes, qa-data VLANs

### Team
| Role | Allocation |
|------|-----------|
| vSphere Admin | 40% |
| K8s Admin (Oracle/1.34 experienced) | 50% |
| Database Admin | 30% |
| QA Lead | 20% |

---

## ✅ QA Sign-Off Checklist

- [ ] All 6 VxRail nodes healthy
- [ ] vSphere cluster operational
- [ ] Oracle 9 template created and tested
- [ ] Kubernetes 1.34 cluster healthy (6 nodes Ready)
- [ ] All applications deployed
- [ ] Tests > 95% pass
- [ ] Performance baseline established
- [ ] P1 issues resolved
- [ ] QA team signed off
- [ ] PREPROD ready to start

---

## Next Steps

1. ✅ Confirm team availability
2. ✅ Schedule Week 1 kickoff
3. ✅ Prepare Azure documentation
4. ✅ Allocate vCenter resources

**→ Next Document:** [QA Architecture](01-QA-Architecture.md)
