# PREPROD Environment — Detailed Implementation Guide

**Phase 3 | Weeks 4–8 | Kubernetes Cluster + Patroni HA + Load Testing**

> **Prerequisite:** QA sign-off complete (Gate 1 passed)  
> **Environment:** k8s-preprod | VLAN 110 (10.51.0.0/16) | DB VLAN 30 (10.30.0.0/24)  
> **Total VMs:** 3 Masters + 9 Workers + 3 DB nodes = 15 VMs  

---

## Phase Flowchart

```
PREPROD PHASE — COMPLETE FLOW (Weeks 4–8)
══════════════════════════════════════════════════════════════════════════

  [GATE: QA SIGN-OFF ✅]
          │
          ▼
  ┌────────────────────────────────────────────────────────────────────┐
  │  WEEK 4 — INFRASTRUCTURE BUILD (run in parallel, Day 1)           │
  │                                                                    │
  │  ① Masters (VLAN 110)        ② Workers (VLAN 110)    ③ DB (VLAN 30)│
  │  ┌─────────────────┐        ┌─────────────────┐    ┌────────────┐ │
  │  │ Create 3 master │        │ Create 9 worker │    │ Create 3   │ │
  │  │  VMs via govc   │        │  VMs via govc   │    │  DB VMs    │ │
  │  │ 8vCPU/32GB/150G │        │ 16vCPU/64GB/250G│    │ 16vCPU/    │ │
  │  │ Configure OL9   │        │ Configure OL9   │    │ 64GB/700GB │ │
  │  │ Install K8s 1.34│        │ Install K8s 1.34│    │ Install    │ │
  │  │ kubeadm init    │        │ kubeadm join    │    │ PG15+Patroni│ │
  │  │ Join masters 2,3│        │ (after Calico)  │    │ etcd cluster│ │
  │  └────────┬────────┘        └────────┬────────┘    └─────┬──────┘ │
  │           │                          │                   │        │
  │           └──────── Deploy Calico ───┘                   │        │
  │                     Deploy CSI                            │        │
  │                     Deploy MetalLB ◄──────────────────────┘        │
  │  Verify: 12 nodes Ready | Patroni: 1 Leader + 2 Replicas           │
  └────────────────────────────────────────────────────────────────────┘
          │
          ▼
  ┌────────────────────────────────────────────────────────────────────┐
  │  WEEK 5 — APPLICATION DEPLOYMENT                                   │
  │  ① Restore DB from QA / Azure export                               │
  │  ② Create preprod namespace, RBAC, Secrets                         │
  │  ③ Deploy apps via ArgoCD (preprod branch)                         │
  │  ④ Smoke tests — all endpoints returning 200                       │
  └────────────────────────────────────────────────────────────────────┘
          │
          ▼
  ┌────────────────────────────────────────────────────────────────────┐
  │  WEEK 6 — LOAD TEST PHASE 1 (up to 1 000 users)                   │
  │  ① Deploy k6 load testing framework                                │
  │  ② Run: 100 → 500 → 1 000 user ramp                               │
  │  ③ Tune PostgreSQL, connection pools, pod resources                │
  │  ④ Validate: p95 < 500 ms, error rate < 0.1%                      │
  └────────────────────────────────────────────────────────────────────┘
          │
          ▼
  ┌────────────────────────────────────────────────────────────────────┐
  │  WEEK 7 — LOAD TEST PHASE 2 (3 000 users) + FAILOVER DRILLS       │
  │  ① Run: 1 K → 2 K → 3 K users                                     │
  │  ② Patroni failover drill (kill primary → auto-elect replica)      │
  │  ③ K8s node drain test (simulate host failure)                     │
  │  ④ Verify: failover < 30 s, zero data loss                         │
  └────────────────────────────────────────────────────────────────────┘
          │
          ▼
  ┌────────────────────────────────────────────────────────────────────┐
  │  WEEK 8 — VALIDATION & SIGN-OFF                                    │
  │  ① Full regression suite                                           │
  │  ② Security scan (Trivy, RBAC audit)                               │
  │  ③ Backup & restore test (Veeam)                                   │
  │  ④ PREPROD sign-off form — all stakeholders                        │
  └────────────────────────────────────────────────────────────────────┘
          │
      ◆ ALL GATES PASS?
     /         \
   YES           NO
    │             │
  [PROD       [Fix + Retest
  Week 9]      Week 8]
```

---

## VM Inventory — Complete Reference

```
┌─────────────────────────────────────────────────────────────────────────────┐
│              PREPROD VM INVENTORY (all 15 VMs)                              │
├───────────────────────┬────────────────┬──────────────┬─────────────────────┤
│ VM Name               │ IP Address     │ Specs        │ Role                │
├───────────────────────┼────────────────┼──────────────┼─────────────────────┤
│ k8s-preprod-master-01 │ 10.51.0.10     │ 8vCPU/32G/150G│ K8s control-plane  │
│ k8s-preprod-master-02 │ 10.51.0.11     │ 8vCPU/32G/150G│ K8s control-plane  │
│ k8s-preprod-master-03 │ 10.51.0.12     │ 8vCPU/32G/150G│ K8s control-plane  │
│ API VIP (HAProxy)     │ 10.51.0.100    │ —            │ K8s API endpoint    │
├───────────────────────┼────────────────┼──────────────┼─────────────────────┤
│ k8s-preprod-worker-01 │ 10.51.1.101    │ 16vCPU/64G/250G│ K8s workloads     │
│ k8s-preprod-worker-02 │ 10.51.1.102    │ 16vCPU/64G/250G│ K8s workloads     │
│ k8s-preprod-worker-03 │ 10.51.1.103    │ 16vCPU/64G/250G│ K8s workloads     │
│ k8s-preprod-worker-04 │ 10.51.1.104    │ 16vCPU/64G/250G│ K8s workloads     │
│ k8s-preprod-worker-05 │ 10.51.1.105    │ 16vCPU/64G/250G│ K8s workloads     │
│ k8s-preprod-worker-06 │ 10.51.1.106    │ 16vCPU/64G/250G│ K8s workloads     │
│ k8s-preprod-worker-07 │ 10.51.1.107    │ 16vCPU/64G/250G│ K8s workloads     │
│ k8s-preprod-worker-08 │ 10.51.1.108    │ 16vCPU/64G/250G│ K8s workloads     │
│ k8s-preprod-worker-09 │ 10.51.1.109    │ 16vCPU/64G/250G│ K8s workloads     │
├───────────────────────┼────────────────┼──────────────┼─────────────────────┤
│ pg-preprod-01         │ 10.30.0.110    │ 16vCPU/64G/700G│ Patroni Leader    │
│ pg-preprod-02         │ 10.30.0.111    │ 16vCPU/64G/700G│ Patroni Replica   │
│ pg-preprod-03         │ 10.30.0.112    │ 16vCPU/64G/700G│ Patroni Replica   │
│ pgBouncer VIP         │ 10.30.0.100    │ —            │ DB connection pool  │
└───────────────────────┴────────────────┴──────────────┴─────────────────────┘

Sizing rationale:
  Masters  8vCPU/32GB/150GB — etcd + API server + controller-manager
  Workers 16vCPU/64GB/250GB — 64 GB handles 3K-user peak (~54 GB active pods)
  DB nodes 16vCPU/64GB/700GB — 64 GB RAM: shared_buffers=16GB, heavy caching
                                 700 GB: 500GB data + 150GB WAL + 50GB logs
```

---

## Week 4, Step 1: Provision Master VMs

### Create 3 Master VMs in vSphere

```bash
# On vCenter jump host
# WHY: Masters run etcd (cluster state), API server, scheduler, controller-manager
# 3 masters = quorum — cluster survives 1 master failure

for i in 01 02 03; do
  govc vm.clone \
    -vm    "/Datacenter/vm/Templates/ol9-k8s-template" \
    -ds    "vsanDatastore" \
    -pool  "/Datacenter/host/VxRail-Cluster/Resources/PREPROD-Masters" \
    -net   "VLAN-110-PREPROD" \
    -name  "k8s-preprod-master-${i}" \
    -m     32768 \   # 32 GB RAM — etcd ~3 GB, API server ~4 GB, leaves 25 GB buffer
    -c     8 \       # 8 vCPUs — control-plane is multi-threaded
    -disk  "150GB"   # OS 50 GB + etcd data 50 GB + logs/audit 50 GB
  echo "✅ Created k8s-preprod-master-${i}"
done

# Spread masters across different physical VxRail hosts (anti-affinity)
govc cluster.rule.create \
  -name "preprod-master-anti-affinity" -enable -affinity=false \
  "k8s-preprod-master-01" "k8s-preprod-master-02" "k8s-preprod-master-03"

for i in 01 02 03; do govc vm.power -on "k8s-preprod-master-${i}"; done
sleep 60
echo "✅ Masters powered on"
```

### Configure OS on Each Master (run on master-01, 02, 03)

```bash
# ── Change these per node ──
NODE_NUM="01"           # 01 / 02 / 03
NODE_IP="10.51.0.10"   # .10 / .11 / .12
GATEWAY="10.51.0.1"
DNS="10.20.0.53"

# 1. Hostname
hostnamectl set-hostname "k8s-preprod-master-${NODE_NUM}"

# 2. Static IP
cat > /etc/NetworkManager/system-connections/eth0.nmconnection << EOF
[connection]
id=eth0
type=ethernet
interface-name=eth0
autoconnect=yes
[ipv4]
method=manual
addresses=${NODE_IP}/16
gateway=${GATEWAY}
dns=${DNS};8.8.8.8
EOF
chmod 600 /etc/NetworkManager/system-connections/eth0.nmconnection
nmcli connection reload && nmcli connection up eth0

# 3. /etc/hosts (all cluster nodes)
cat >> /etc/hosts << EOF
# PREPROD K8s Cluster
10.51.0.10  k8s-preprod-master-01
10.51.0.11  k8s-preprod-master-02
10.51.0.12  k8s-preprod-master-03
10.51.0.100 k8s-preprod-api
10.51.1.101 k8s-preprod-worker-01
10.51.1.102 k8s-preprod-worker-02
10.51.1.103 k8s-preprod-worker-03
10.51.1.104 k8s-preprod-worker-04
10.51.1.105 k8s-preprod-worker-05
10.51.1.106 k8s-preprod-worker-06
10.51.1.107 k8s-preprod-worker-07
10.51.1.108 k8s-preprod-worker-08
10.51.1.109 k8s-preprod-worker-09
EOF

# 4. Disable swap (K8s requirement)
swapoff -a && sed -i '/swap/d' /etc/fstab

# 5. Kernel modules for K8s networking
cat > /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
EOF
modprobe overlay && modprobe br_netfilter

# 6. sysctl — enable bridge netfilter and IP forwarding
cat > /etc/sysctl.d/99-k8s.conf << EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
vm.overcommit_memory                = 1
kernel.panic                        = 10
kernel.panic_on_oops                = 1
fs.inotify.max_user_instances       = 8192
fs.inotify.max_user_watches         = 524288
EOF
sysctl --system

# 7. containerd
dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
dnf install -y containerd.io
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
# Enable systemd cgroup driver — required for OL9
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable containerd --now

# 8. Kubernetes 1.34
cat > /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.34/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.34/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl
EOF
dnf install -y --disableexcludes=kubernetes \
  kubelet-1.34.0 kubeadm-1.34.0 kubectl-1.34.0
systemctl enable kubelet

echo "✅ Master k8s-preprod-master-${NODE_NUM} OS ready"
```

### Initialise the Kubernetes Cluster (master-01 only)

```bash
# On k8s-preprod-master-01 ONLY
# WHY --control-plane-endpoint: Points to the HAProxy VIP (10.51.0.100)
# so kubectl and worker joins always go to a healthy master, not a fixed IP

kubeadm init \
  --control-plane-endpoint "10.51.0.100:6443" \
  --upload-certs \
  --pod-network-cidr "10.210.0.0/16" \
  --service-cidr "10.211.0.0/16" \
  --kubernetes-version "v1.34.0" \
  --cri-socket unix:///run/containerd/containerd.sock

# Configure kubectl for the root user
mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# SAVE the two join commands from the output — you need them for:
#   --control-plane flag  → masters 02 and 03
#   (without flag)        → all 9 workers

echo "✅ Cluster initialised on master-01"
```

### Join Masters 02 and 03

```bash
# On k8s-preprod-master-02 AND k8s-preprod-master-03
# Use the --control-plane join command from kubeadm init output

kubeadm join 10.51.0.100:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane \
  --certificate-key <cert-key> \
  --cri-socket unix:///run/containerd/containerd.sock

# Copy kubeconfig on each new master too
mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# Verify on master-01
kubectl get nodes
# NAME                     STATUS     ROLES           AGE
# k8s-preprod-master-01   NotReady   control-plane   5m   ← NotReady until Calico
# k8s-preprod-master-02   NotReady   control-plane   2m
# k8s-preprod-master-03   NotReady   control-plane   1m
```

---

## Week 4, Step 2: Provision Worker VMs

### Create 9 Worker VMs in vSphere

```bash
# On vCenter jump host — 9 workers, 16vCPU / 64 GB / 250 GB each
# WHY 64 GB: 3 000 concurrent users → ~45 active pods × 1.2 GB avg = ~54 GB peak
# 250 GB disk: container images ~100 GB + PersistentVolumes ~100 GB + logs 50 GB

for i in $(seq -f "%02g" 1 9); do
  govc vm.clone \
    -vm    "/Datacenter/vm/Templates/ol9-k8s-template" \
    -ds    "vsanDatastore" \
    -pool  "/Datacenter/host/VxRail-Cluster/Resources/PREPROD-Workers" \
    -net   "VLAN-110-PREPROD" \
    -name  "k8s-preprod-worker-${i}" \
    -m     65536 \
    -c     16 \
    -disk  "250GB"
  echo "✅ Created k8s-preprod-worker-${i}"
done

# Anti-affinity — workers spread across VxRail hosts
govc cluster.rule.create \
  -name "preprod-worker-anti-affinity" -enable -affinity=false \
  $(for i in $(seq -f "k8s-preprod-worker-%02g" 1 9); do echo -n "$i "; done)

for i in $(seq -f "%02g" 1 9); do govc vm.power -on "k8s-preprod-worker-${i}"; done
sleep 90 && echo "✅ All 9 workers powered on"
```

### Configure OS on Each Worker (run on worker-01 through 09)

```bash
# IP map: worker-01=10.51.1.101  worker-02=10.51.1.102  worker-03=10.51.1.103
#         worker-04=10.51.1.104  worker-05=10.51.1.105  worker-06=10.51.1.106
#         worker-07=10.51.1.107  worker-08=10.51.1.108  worker-09=10.51.1.109

NODE_NUM="01"           # Change per node
NODE_IP="10.51.1.101"  # Change per node
GATEWAY="10.51.0.1"
DNS="10.20.0.53"

# 1. Hostname
hostnamectl set-hostname "k8s-preprod-worker-${NODE_NUM}"

# 2. Static IP
cat > /etc/NetworkManager/system-connections/eth0.nmconnection << EOF
[connection]
id=eth0
type=ethernet
interface-name=eth0
autoconnect=yes
[ipv4]
method=manual
addresses=${NODE_IP}/16
gateway=${GATEWAY}
dns=${DNS};8.8.8.8
EOF
chmod 600 /etc/NetworkManager/system-connections/eth0.nmconnection
nmcli connection reload && nmcli connection up eth0

# 3. /etc/hosts
cat >> /etc/hosts << EOF
10.51.0.10  k8s-preprod-master-01
10.51.0.11  k8s-preprod-master-02
10.51.0.12  k8s-preprod-master-03
10.51.0.100 k8s-preprod-api
10.51.1.101 k8s-preprod-worker-01
10.51.1.102 k8s-preprod-worker-02
10.51.1.103 k8s-preprod-worker-03
10.51.1.104 k8s-preprod-worker-04
10.51.1.105 k8s-preprod-worker-05
10.51.1.106 k8s-preprod-worker-06
10.51.1.107 k8s-preprod-worker-07
10.51.1.108 k8s-preprod-worker-08
10.51.1.109 k8s-preprod-worker-09
EOF

# 4–8. Swap, kernel modules, sysctl, containerd, K8s (identical to masters above)
swapoff -a && sed -i '/swap/d' /etc/fstab

cat > /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
EOF
modprobe overlay && modprobe br_netfilter

cat > /etc/sysctl.d/99-k8s.conf << EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
vm.overcommit_memory                = 1
kernel.panic                        = 10
kernel.panic_on_oops                = 1
net.core.somaxconn                  = 32768
fs.inotify.max_user_instances       = 8192
fs.inotify.max_user_watches         = 524288
EOF
sysctl --system

dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
dnf install -y containerd.io
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable containerd --now

cat > /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.34/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.34/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl
EOF
dnf install -y --disableexcludes=kubernetes \
  kubelet-1.34.0 kubeadm-1.34.0 kubectl-1.34.0
systemctl enable kubelet

echo "✅ Worker k8s-preprod-worker-${NODE_NUM} ready for join"
```

### Deploy Calico CNI, then Join Workers

```bash
# On master-01 — deploy Calico FIRST (workers need CNI to become Ready)
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml

cat <<EOF | kubectl apply -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - name: default
      cidr: 10.210.0.0/16
      encapsulation: VXLANCrossSubnet
EOF

# Wait for Calico to be ready
kubectl wait --for=condition=Ready pod -l k8s-app=calico-node \
  -n calico-system --timeout=300s
echo "✅ Calico CNI ready"

# Generate worker join command
JOIN_CMD=$(kubeadm token create --print-join-command)
echo "Worker join command: ${JOIN_CMD}"

# On EACH worker (01-09) — run the join command
${JOIN_CMD} \
  --cri-socket unix:///run/containerd/containerd.sock \
  --node-name $(hostname)

# On master-01 — verify all 12 nodes
kubectl get nodes -o wide
# Expected: 3 masters + 9 workers all Ready

# Label and taint
for i in $(seq -f "%02g" 1 9); do
  kubectl label node "k8s-preprod-worker-${i}" \
    node-role.kubernetes.io/worker="" environment=preprod
done
for m in 01 02 03; do
  kubectl taint nodes "k8s-preprod-master-${m}" \
    node-role.kubernetes.io/control-plane:NoSchedule --overwrite
done
echo "✅ PREPROD K8s cluster: 3 masters + 9 workers = 12 nodes Ready"
```

### Deploy vSphere CSI and MetalLB

```bash
# vSphere CSI driver — allows pods to use vSAN-backed PersistentVolumes
kubectl create secret generic vsphere-config-secret -n kube-system \
  --from-literal=csi-vsphere.conf='
[Global]
cluster-id = "k8s-preprod"
insecure-flag = "true"
[VirtualCenter "10.20.0.10"]
user = "administrator@vsphere.local"
password = "<vcenter-password>"
datacenters = "DC-OnPrem"
port = "443"
[Network]
public-network = "VLAN-110-PREPROD"'

kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/vsphere-csi-driver/master/manifests/vanilla/deploy/vsphere-csi-controller-deployment.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/vsphere-csi-driver/master/manifests/vanilla/deploy/vsphere-csi-node-ds.yaml

# StorageClass for PREPROD (vSAN backed)
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: vsan-preprod
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: csi.vsphere.volume
parameters:
  storagePolicyName: "PREPROD-vSAN-Policy"
reclaimPolicy: Delete
allowVolumeExpansion: true
EOF

# MetalLB LoadBalancer — gives services real IPs on the network
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml
sleep 30

cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: preprod-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.51.200.0/24   # Range reserved for PREPROD LoadBalancer IPs
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: preprod-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - preprod-pool
EOF

echo "✅ CSI driver and MetalLB deployed"
```

---

## Week 4, Step 3: Provision & Configure Database VMs (Patroni HA)

### Why Patroni HA Instead of a Single PostgreSQL?

```
PATRONI HA — WHY IT MATTERS
════════════════════════════════════════════════════════════════════

  WITHOUT Patroni (single node):
  ┌──────────────────────────────────────────────────────────────┐
  │  App ──▶ PostgreSQL (10.30.0.110)                            │
  │                    │                                         │
  │              Node fails ──▶ OUTAGE                           │
  │              Manual recovery: 30–120 minutes                 │
  └──────────────────────────────────────────────────────────────┘

  WITH Patroni HA (3 nodes):
  ┌──────────────────────────────────────────────────────────────┐
  │  App ──▶ pgBouncer VIP (10.30.0.100)                         │
  │                    │                                         │
  │          ┌─────────▼──────────┐                             │
  │          │  etcd (consensus)  │  ← elects one leader        │
  │          └─────────┬──────────┘                             │
  │         ┌──────────┼───────────┐                            │
  │         ▼          ▼           ▼                            │
  │  pg-preprod-01  pg-preprod-02  pg-preprod-03                 │
  │  (Leader)       (Replica)      (Replica)                     │
  │  10.30.0.110    10.30.0.111    10.30.0.112                   │
  │                                                              │
  │  Node fails ──▶ etcd detects ──▶ replica promoted           │
  │  Automatic failover: < 30 seconds                            │
  │  pgBouncer VIP auto-routes to new primary                    │
  └──────────────────────────────────────────────────────────────┘
```

### Create 3 Database VMs

```bash
for i in 01 02 03; do
  govc vm.clone \
    -vm    "/Datacenter/vm/Templates/ol9-base-template" \
    -ds    "vsanDatastore" \
    -pool  "/Datacenter/host/VxRail-Cluster/Resources/PREPROD-DB" \
    -net   "VLAN-30-DATABASE" \
    -name  "pg-preprod-${i}" \
    -m     65536 \    # 64 GB RAM — shared_buffers=16GB, hot data in memory
    -c     16 \       # 16 vCPUs — parallel queries, vacuums, pg_dump
    -disk  "700GB"    # 500GB data + 150GB WAL archives + 50GB OS/logs
  echo "✅ Created pg-preprod-${i}"
done

for i in 01 02 03; do govc vm.power -on "pg-preprod-${i}"; done
sleep 60
```

### Configure OS on Each DB Node (run on pg-preprod-01, 02, 03)

```bash
# IP map: pg-preprod-01=10.30.0.110  02=10.30.0.111  03=10.30.0.112
NODE_NUM="01"
NODE_IP="10.30.0.110"
GATEWAY="10.30.0.1"
DNS="10.20.0.53"

hostnamectl set-hostname "pg-preprod-${NODE_NUM}"

cat > /etc/NetworkManager/system-connections/eth0.nmconnection << EOF
[connection]
id=eth0
type=ethernet
interface-name=eth0
autoconnect=yes
[ipv4]
method=manual
addresses=${NODE_IP}/24
gateway=${GATEWAY}
dns=${DNS};8.8.8.8
EOF
chmod 600 /etc/NetworkManager/system-connections/eth0.nmconnection
nmcli connection reload && nmcli connection up eth0

cat >> /etc/hosts << EOF
10.30.0.110 pg-preprod-01
10.30.0.111 pg-preprod-02
10.30.0.112 pg-preprod-03
EOF

# Tune OS for PostgreSQL
cat >> /etc/sysctl.d/99-postgresql.conf << EOF
vm.swappiness         = 1        # Avoid swap — hurts PostgreSQL performance
vm.dirty_ratio        = 15       # Flush dirty pages when 15% of RAM is dirty
vm.dirty_background_ratio = 5
kernel.shmmax         = 68719476736   # 64 GB shared memory segment max
kernel.shmall         = 16777216
EOF
sysctl --system

# Data disk (separate vSAN disk for PostgreSQL data)
# Format and mount /data for PostgreSQL
mkfs.xfs /dev/sdb
mkdir -p /data/patroni
echo "/dev/sdb /data xfs defaults,noatime 0 0" >> /etc/fstab
mount -a
chown -R postgres:postgres /data

echo "✅ DB node pg-preprod-${NODE_NUM} OS configured"
```

### Install PostgreSQL 15 + etcd + Patroni

```bash
# Run on ALL THREE DB nodes

# PostgreSQL 15
dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
dnf -qy module disable postgresql
dnf install -y postgresql15-server postgresql15-contrib postgresql15-pglogical

# etcd (distributed consensus store for Patroni)
ETCD_VER="v3.5.9"
wget -q https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz
tar xzf etcd-${ETCD_VER}-linux-amd64.tar.gz
mv etcd-${ETCD_VER}-linux-amd64/etcd /usr/local/bin/
mv etcd-${ETCD_VER}-linux-amd64/etcdctl /usr/local/bin/
useradd --no-create-home --shell /bin/false etcd
mkdir -p /var/lib/etcd /etc/etcd
chown -R etcd:etcd /var/lib/etcd /etc/etcd

# Patroni
pip3 install patroni[etcd] psycopg2-binary

echo "✅ PG15 + etcd + Patroni installed"
```

### Configure etcd Cluster (run on each DB node — change IPs per node)

```bash
# On pg-preprod-01 (10.30.0.110):
cat > /etc/etcd/etcd.conf << EOF
ETCD_NAME="pg-preprod-01"
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_LISTEN_PEER_URLS="http://10.30.0.110:2380"
ETCD_LISTEN_CLIENT_URLS="http://10.30.0.110:2379,http://127.0.0.1:2379"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://10.30.0.110:2380"
ETCD_ADVERTISE_CLIENT_URLS="http://10.30.0.110:2379"
ETCD_INITIAL_CLUSTER_TOKEN="preprod-etcd"
ETCD_INITIAL_CLUSTER="pg-preprod-01=http://10.30.0.110:2380,pg-preprod-02=http://10.30.0.111:2380,pg-preprod-03=http://10.30.0.112:2380"
ETCD_INITIAL_CLUSTER_STATE="new"
EOF
# On 02: change ETCD_NAME="pg-preprod-02" and all 10.30.0.110 → 10.30.0.111
# On 03: change ETCD_NAME="pg-preprod-03" and all 10.30.0.110 → 10.30.0.112

# Start etcd on all 3 nodes (within 60 s of each other)
systemctl enable etcd --now

# Verify (from any node)
etcdctl --endpoints=http://10.30.0.110:2379,http://10.30.0.111:2379,http://10.30.0.112:2379 \
  endpoint health
# Expected: all 3 → "is healthy"
```

### Configure Patroni (run on each DB node — change name/IP per node)

```bash
# On pg-preprod-01 (change name + listen IPs for 02 and 03)
cat > /etc/patroni/patroni.yml << 'EOF'
scope: preprod-postgres
namespace: /service/
name: pg-preprod-01          # ← change to pg-preprod-02 / pg-preprod-03

dcs:
  etcd3:
    hosts:
      - 10.30.0.110:2379
      - 10.30.0.111:2379
      - 10.30.0.112:2379

restapi:
  listen: 10.30.0.110:8008   # ← change per node
  connect_address: 10.30.0.110:8008

postgresql:
  listen: 10.30.0.110:5432   # ← change per node
  connect_address: 10.30.0.110:5432
  data_dir: /data/patroni
  pgpass: /tmp/.pgpass

  authentication:
    replication:
      username: replicator
      password: "ReplPass_Preprod_2026!"
    superuser:
      username: postgres
      password: "AdminPass_Preprod_2026!"

  parameters:
    # Tuned for 64 GB RAM
    shared_buffers: 16GB            # 25 % of RAM — PostgreSQL working set cache
    effective_cache_size: 48GB      # OS + PG cache estimate for query planner
    work_mem: 64MB                  # Per sort / hash operation
    maintenance_work_mem: 2GB       # VACUUM, CREATE INDEX
    max_connections: 400            # pgBouncer handles app connections; PG can be lower
    max_wal_size: 4GB
    wal_level: replica              # Required for streaming replication
    max_wal_senders: 10
    wal_keep_size: 1GB
    synchronous_commit: on
    synchronous_standby_names: 'ANY 1 (pg-preprod-02,pg-preprod-03)'
    hot_standby: on
    hot_standby_feedback: on
    log_min_duration_statement: 100
    log_checkpoints: on
    log_connections: on
    log_lock_waits: on
    shared_preload_libraries: 'pg_stat_statements,pglogical'

  pg_hba:
    - host replication replicator 10.30.0.0/24 scram-sha-256
    - host all postgres           10.30.0.0/24 scram-sha-256
    - host all all                10.51.0.0/16 scram-sha-256  # PREPROD K8s
    - host all all                127.0.0.1/32 trust

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576   # Don't promote if > 1 MB behind
    postgresql:
      use_pg_rewind: true
      use_slots: true
  post_bootstrap: |
    psql -c "CREATE ROLE replicator REPLICATION LOGIN ENCRYPTED PASSWORD 'ReplPass_Preprod_2026!'"
    psql -c "CREATE DATABASE preprod_db OWNER postgres"
    psql -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements"
    psql -c "CREATE EXTENSION IF NOT EXISTS pglogical"

tags:
  nofailover: false
  noloadbalance: false
EOF

# Create systemd service
cat > /etc/systemd/system/patroni.service << EOF
[Unit]
Description=Patroni PostgreSQL HA
After=network.target etcd.service
[Service]
Type=simple
User=postgres
ExecStart=/usr/local/bin/patroni /etc/patroni/patroni.yml
KillMode=process
TimeoutSec=30
Restart=no
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload

# Start on pg-preprod-01 FIRST (becomes initial Leader)
systemctl enable patroni --now
sleep 15

# Then start on pg-preprod-02 and pg-preprod-03 (become Replicas)
# (run on each): systemctl enable patroni --now
```

### Verify Patroni Cluster

```bash
patronictl -c /etc/patroni/patroni.yml list
# Expected:
# + Cluster: preprod-postgres +---------+----+-----------+
# | Member        | Role    | State   | TL | Lag in MB |
# | pg-preprod-01 | Leader  | running |  1 |           |
# | pg-preprod-02 | Replica | running |  1 |         0 |
# | pg-preprod-03 | Replica | running |  1 |         0 |

# Check replication lag
psql -h 10.30.0.110 -U postgres -c \
  "SELECT client_addr, state, pg_wal_lsn_diff(sent_lsn,replay_lsn) lag_bytes
   FROM pg_stat_replication;"
```

### Configure pgBouncer Connection Pooler

```bash
# Why pgBouncer: K8s apps open many short connections.
# Without pooling: 3K users → 3K PG connections → OOM on DB server
# With pgBouncer: 3K app connections pool into max 200 PG connections

dnf install -y pgbouncer

cat > /etc/pgbouncer/pgbouncer.ini << 'EOF'
[databases]
preprod_db = host=10.30.0.110 port=5432 dbname=preprod_db

[pgbouncer]
listen_addr    = 0.0.0.0
listen_port    = 6432
auth_type      = scram-sha-256
auth_file      = /etc/pgbouncer/userlist.txt
pool_mode      = transaction   # Best for OLTP workloads
default_pool_size = 50
max_client_conn   = 2000
reserve_pool_size = 10
log_connections   = 1
log_disconnections = 1
logfile = /var/log/pgbouncer/pgbouncer.log
EOF

printf '"postgres" "AdminPass_Preprod_2026!"\n"app_user" "AppPass_2026!"\n' \
  > /etc/pgbouncer/userlist.txt
chmod 600 /etc/pgbouncer/userlist.txt
systemctl enable pgbouncer --now

psql -h 127.0.0.1 -p 6432 -U postgres -d preprod_db -c "SELECT version();"
echo "✅ pgBouncer running on 6432"
```

---

## Week 5: Application Deployment to PREPROD

### Restore Database from Azure / QA

```bash
# Option A — restore from Azure pg_dump export (if fresh copy needed)
pg_dump \
  "host=<azure-host>.postgres.database.azure.com port=5432 dbname=prod_db \
   user=adminuser sslmode=require" \
  --no-owner --no-acl --format=custom \
  -f /backup/azure-prod-$(date +%Y%m%d).pgdump

# Restore to PREPROD
pg_restore \
  -h 10.30.0.110 -U postgres -d preprod_db \
  --no-owner --no-acl \
  /backup/azure-prod-$(date +%Y%m%d).pgdump

# Validate row counts
psql -h 10.30.0.110 -U postgres -d preprod_db -c \
  "SELECT schemaname, tablename, n_live_tup
   FROM pg_stat_user_tables ORDER BY n_live_tup DESC LIMIT 20;"
```

### Deploy Applications

```bash
# Create namespace and secrets
kubectl create namespace preprod
kubectl create secret generic postgres-creds -n preprod \
  --from-literal=POSTGRES_HOST="10.30.0.100" \
  --from-literal=POSTGRES_PORT="6432" \
  --from-literal=POSTGRES_DB="preprod_db" \
  --from-literal=POSTGRES_USER="app_user" \
  --from-literal=POSTGRES_PASSWORD="AppPass_2026!"

# Deploy via ArgoCD
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: preprod-app
  namespace: argocd
spec:
  project: preprod
  source:
    repoURL: https://github.com/your-org/k8s-manifests
    targetRevision: preprod
    path: environments/preprod
  destination:
    server: https://kubernetes.default.svc
    namespace: preprod
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

kubectl rollout status deployment -n preprod --timeout=300s
echo "✅ Applications deployed to PREPROD"
```

---

## Week 6: Load Testing — Phase 1 (1 000 users)

### Run k6 Load Test

```bash
# Install k6
dnf install -y https://dl.k6.io/rpm/repo.rpm
dnf install -y k6

PREPROD_IP=$(kubectl get svc api-gateway -n preprod \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

cat > /tmp/preprod-load-1k.js << 'EOF'
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '2m', target: 100  },
    { duration: '3m', target: 100  },
    { duration: '2m', target: 500  },
    { duration: '3m', target: 500  },
    { duration: '2m', target: 1000 },
    { duration: '5m', target: 1000 },
    { duration: '2m', target: 0    },
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],
    http_req_failed:   ['rate<0.01'],
  },
};

export default function () {
  const res = http.get(`http://${__ENV.TARGET}/health`);
  check(res, { 'status 200': (r) => r.status === 200 });
  sleep(1);
}
EOF

k6 run --env TARGET=${PREPROD_IP} /tmp/preprod-load-1k.js
```

---

## Week 7: Load Testing — Phase 2 (3 000 users) + Failover

### 3 000 User Stress Test

```bash
cat > /tmp/preprod-stress-3k.js << 'EOF'
export const options = {
  stages: [
    { duration: '3m', target: 1000 },
    { duration: '5m', target: 1000 },
    { duration: '3m', target: 2000 },
    { duration: '5m', target: 2000 },
    { duration: '3m', target: 3000 },
    { duration: '10m', target: 3000 },
    { duration: '3m', target: 0    },
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],
    http_req_failed:   ['rate<0.01'],
  },
};
// ... same test body
EOF

k6 run --env TARGET=${PREPROD_IP} /tmp/preprod-stress-3k.js
```

### Patroni Failover Drill

```bash
echo "=== PATRONI FAILOVER DRILL ==="
patronictl -c /etc/patroni/patroni.yml list

# Graceful switchover (planned — e.g., for patching)
patronictl -c /etc/patroni/patroni.yml switchover preprod-postgres \
  --master pg-preprod-01 --candidate pg-preprod-02 --force

sleep 10
patronictl -c /etc/patroni/patroni.yml list
# pg-preprod-02 should now be Leader

# Crash simulation (stop patroni on current leader)
# First find who is leader:
LEADER=$(patronictl -c /etc/patroni/patroni.yml list -f tsv | grep Leader | awk '{print $1}')
ssh ${LEADER} "systemctl stop patroni"
sleep 20

patronictl -c /etc/patroni/patroni.yml list
# Remaining node should be promoted automatically

# Validate no data loss
psql -h 10.30.0.100 -p 6432 -U postgres -d preprod_db \
  -c "SELECT count(*) FROM orders;"   # Count should match pre-failover value

# Bring failed node back
ssh ${LEADER} "systemctl start patroni"
sleep 20
patronictl -c /etc/patroni/patroni.yml list  # Should show 3 nodes again
echo "✅ Failover drill complete"
```

---

## Week 8: Validation & PREPROD Sign-Off

### Sign-Off Checklist

```
PREPROD SIGN-OFF CHECKLIST
══════════════════════════════════════════════════════════════

Infrastructure                                         Pass/Fail
─────────────────────────────────────────────────────────────
[ ] 12 K8s nodes all Ready (3M + 9W)                  ____
[ ] Anti-affinity rules active (vSphere DRS)           ____
[ ] vSAN storage accessible (PV provision test)        ____
[ ] MetalLB LB IPs assigned                            ____
[ ] Patroni: 1 Leader + 2 Replicas, lag < 1MB         ____
[ ] pgBouncer: accepting connections on VIP 10.30.0.100 ____

Database                                               Pass/Fail
─────────────────────────────────────────────────────────────
[ ] Data restored, row counts match Azure              ____
[ ] Replication lag consistently < 100ms               ____
[ ] Patroni switchover (planned) successful            ____
[ ] Patroni crash failover < 30 s, zero data loss      ____
[ ] Veeam backup job completed successfully            ____

Application                                            Pass/Fail
─────────────────────────────────────────────────────────────
[ ] All pods Running, no OOMKilled                     ____
[ ] Smoke tests: health, auth, transactions OK         ____
[ ] ArgoCD sync clean                                  ____

Load Testing                                           Pass/Fail
─────────────────────────────────────────────────────────────
[ ] 1 000 user test: p95 < 500ms, error < 0.1%        ____
[ ] 3 000 user test: p95 < 500ms, error < 0.1%        ____
[ ] No memory leaks (stable memory over 10-min peak)   ____
[ ] DB connections < 200 at peak (pgBouncer working)   ____

SIGN-OFF
─────────────────────────────────────────────────────────────
Infrastructure: _______________________ Date: ___________
DBA:            _______________________ Date: ___________
App Team:       _______________________ Date: ___________
Performance:    _______________________ Date: ___________

RECOMMENDATION: [ ] PROCEED TO PROD    [ ] EXTEND PREPROD
```

---

**Next:** [07-PROD-Detailed-Implementation.md](./07-PROD-Detailed-Implementation.md)  
**Data migration detail:** [08-Migration-Procedures.md](./08-Migration-Procedures.md)  
**Rollback:** [09-Rollback-Procedures.md](./09-Rollback-Procedures.md)  
**Troubleshooting:** [14-Troubleshooting-Errors.md](./14-Troubleshooting-Errors.md)  
**Index:** [00-VxRail-Complete-Index.md](./00-VxRail-Complete-Index.md)
