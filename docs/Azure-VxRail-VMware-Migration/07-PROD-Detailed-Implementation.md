# PROD Environment — Detailed Implementation Guide

**Phase 4 | Weeks 9–16 | Kubernetes Cluster + Patroni HA + pglogical + Zero-Downtime Cutover**

> **Prerequisite:** PREPROD sign-off complete (Gate 2 passed)
> **VLAN 120** (10.52.0.0/16) for K8s | **VLAN 30** (10.30.0.0/24) for DB
> **Core Principle:** Azure stays live until the DNS switch — no downtime at any point.

---

## Phase Flowchart

```
PROD PHASE — COMPLETE FLOW (Weeks 9–16)
═══════════════════════════════════════════════════════════════════════════════

  ╔══════════════════════════════════╗     ╔══════════════════════════════════╗
  ║  AZURE (LIVE — 100% traffic)     ║     ║  ON-PREM (being built in shadow) ║
  ║  AKS + PostgreSQL still primary  ║     ║  Week 9–10: Build infra          ║
  ╚══════════════════╤═══════════════╝     ║  Week 10–11: pglogical sync      ║
                     │ pglogical WAL       ║  Week 11–13: Deploy apps         ║
                     │ stream (Week 10+)   ║  Week 14–15: 10% canary + test   ║
                     └────────────────────▶╚══════════════════════════════════╝
                                                         │
       ┌─────────────────────────────────────────────────┘
       │
       ▼  WEEK 9–10: INFRASTRUCTURE BUILD
  ┌────────────────┐  ┌────────────────┐  ┌────────────────────────────────┐
  │  ① 3 Master VMs│  │  ② 12 Worker   │  │  ③ 3 DB VMs                   │
  │  8vCPU/32G/150G│  │  VMs           │  │  32vCPU/128G/1.5TB             │
  │  Configure OL9 │  │  24vCPU/96G/   │  │  PG15 + Patroni HA            │
  │  K8s 1.34 init │  │  300G          │  │  etcd cluster                  │
  │  HAProxy VIP   │  │  Configure OL9 │  │  pgBouncer VIP 10.30.0.200     │
  └────────┬───────┘  │  K8s 1.34      │  └────────────────────────────────┘
           │          │  kubeadm join  │
           └──────────┴────────────────┘
                      │ Calico CNI + CSI + MetalLB
                      ▼
       Verify: 15 nodes Ready | Patroni: 1 Leader + 2 Replicas

       ▼  WEEK 10–11: pglogical LIVE REPLICATION
  ┌─────────────────────────────────────────────────────────────────────────┐
  │  Azure PG ──publication──▶  pglogical WAL stream  ──subscription──▶    │
  │  On-prem PG (lag < 50 ms, monitored every 5 min)                        │
  └─────────────────────────────────────────────────────────────────────────┘

       ▼  WEEK 11–13: APP DEPLOY (shadow mode, 0% user traffic)
       ▼  WEEK 14–15: DUAL-RUN (10% canary → 72-hr parallel run)

       ▼  WEEK 16: CUTOVER (Friday 4 PM → Saturday 4 AM)
  ┌──────────────────────────────────────────────────────────────────────┐
  │  T+00:00 Maintenance mode on Azure (block new writes)                │
  │  T+00:10 Wait pglogical lag = 0                                      │
  │  T+00:15 Drop subscription → on-prem PG is now standalone           │
  │  T+00:20 DNS switch: api.company.com → on-prem MetalLB IP           │
  │  T+00:30 Smoke tests → ✅ LIVE                                       │
  └────────────────────────────────────────────────┬─────────────────────┘
                                                   │
                                        ◆ All checks pass?
                                       /              \
                                     YES               NO (< 30 min)
                                      │                 │
                                  72-hr hypercare    ROLLBACK:
                                  Azure standby      DNS → Azure
                                  Decommission plan  RTO < 30 min
```

---

## VM Inventory — Complete Reference

```
┌─────────────────────────────────────────────────────────────────────────────┐
│              PROD VM INVENTORY (18 VMs total)                               │
├───────────────────────┬───────────────┬────────────────┬────────────────────┤
│ VM Name               │ IP            │ Specs          │ Role               │
├───────────────────────┼───────────────┼────────────────┼────────────────────┤
│ k8s-prod-master-01    │ 10.52.0.10    │ 8vCPU/32G/150G │ K8s control-plane  │
│ k8s-prod-master-02    │ 10.52.0.11    │ 8vCPU/32G/150G │ K8s control-plane  │
│ k8s-prod-master-03    │ 10.52.0.12    │ 8vCPU/32G/150G │ K8s control-plane  │
│ HAProxy API VIP       │ 10.52.0.100   │ —              │ K8s API endpoint   │
├───────────────────────┼───────────────┼────────────────┼────────────────────┤
│ k8s-prod-worker-01    │ 10.52.1.101   │ 24vCPU/96G/300G│ Application pods   │
│ k8s-prod-worker-02    │ 10.52.1.102   │ 24vCPU/96G/300G│ Application pods   │
│ k8s-prod-worker-03    │ 10.52.1.103   │ 24vCPU/96G/300G│ Application pods   │
│ k8s-prod-worker-04    │ 10.52.1.104   │ 24vCPU/96G/300G│ Application pods   │
│ k8s-prod-worker-05    │ 10.52.1.105   │ 24vCPU/96G/300G│ Application pods   │
│ k8s-prod-worker-06    │ 10.52.1.106   │ 24vCPU/96G/300G│ Application pods   │
│ k8s-prod-worker-07    │ 10.52.1.107   │ 24vCPU/96G/300G│ Application pods   │
│ k8s-prod-worker-08    │ 10.52.1.108   │ 24vCPU/96G/300G│ Application pods   │
│ k8s-prod-worker-09    │ 10.52.1.109   │ 24vCPU/96G/300G│ Application pods   │
│ k8s-prod-worker-10    │ 10.52.1.110   │ 24vCPU/96G/300G│ Application pods   │
│ k8s-prod-worker-11    │ 10.52.1.111   │ 24vCPU/96G/300G│ Application pods   │
│ k8s-prod-worker-12    │ 10.52.1.112   │ 24vCPU/96G/300G│ Application pods   │
├───────────────────────┼───────────────┼────────────────┼────────────────────┤
│ pg-prod-01            │ 10.30.0.120   │ 32vCPU/128G/1.5T│ Patroni Leader   │
│ pg-prod-02            │ 10.30.0.121   │ 32vCPU/128G/1.5T│ Patroni Replica  │
│ pg-prod-03            │ 10.30.0.122   │ 32vCPU/128G/1.5T│ Patroni Replica  │
│ pgBouncer VIP         │ 10.30.0.200   │ —              │ DB connection pool │
└───────────────────────┴───────────────┴────────────────┴────────────────────┘

Sizing rationale (with growth buffer):
  Workers  24vCPU/96GB/300GB  — 30% over current peak; 300 GB = 3-yr image/PV growth
  DB nodes 32vCPU/128GB/1.5TB — shared_buffers=32GB caches hot dataset;
                                  1 TB data + 400 GB WAL = 7 days PITR retention
```

---

## Week 9: Provision Master VMs

### Step 1: Create 3 Master VMs

```bash
# On vCenter jump host
for i in 01 02 03; do
  govc vm.clone \
    -vm    "/Datacenter/vm/Templates/ol9-k8s-template" \
    -ds    "vsanDatastore" \
    -pool  "/Datacenter/host/VxRail-Cluster/Resources/PROD-Masters" \
    -net   "VLAN-120-PROD" \
    -name  "k8s-prod-master-${i}" \
    -m     32768 \    # 32 GB RAM — etcd + API server + scheduler/controller headroom
    -c     8 \        # 8 vCPUs — control-plane components are CPU-intensive on large clusters
    -disk  "150GB"    # OS 50 GB + etcd data 50 GB + audit logs/buffer 50 GB
  echo "✅ Created k8s-prod-master-${i}"
done

# Anti-affinity: each master on a different physical VxRail host
govc cluster.rule.create \
  -name "prod-master-anti-affinity" -enable -affinity=false \
  "k8s-prod-master-01" "k8s-prod-master-02" "k8s-prod-master-03"

for i in 01 02 03; do govc vm.power -on "k8s-prod-master-${i}"; done
sleep 60 && echo "✅ Masters powered on"
```

### Step 2: Configure OS on Each Master (run on master-01, 02, 03)

```bash
# ── Change per node ──
# master-01: NODE_NUM=01  NODE_IP=10.52.0.10
# master-02: NODE_NUM=02  NODE_IP=10.52.0.11
# master-03: NODE_NUM=03  NODE_IP=10.52.0.12
NODE_NUM="01"
NODE_IP="10.52.0.10"
GATEWAY="10.52.0.1"
DNS="10.20.0.53"

# Hostname
hostnamectl set-hostname "k8s-prod-master-${NODE_NUM}"

# Static IP — WHY: K8s node registration is IP-based; DHCP causes re-registration
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

# /etc/hosts — all 18 VMs in the PROD cluster
cat >> /etc/hosts << EOF
# PROD K8s Cluster
10.52.0.10  k8s-prod-master-01
10.52.0.11  k8s-prod-master-02
10.52.0.12  k8s-prod-master-03
10.52.0.100 k8s-prod-api
10.52.1.101 k8s-prod-worker-01
10.52.1.102 k8s-prod-worker-02
10.52.1.103 k8s-prod-worker-03
10.52.1.104 k8s-prod-worker-04
10.52.1.105 k8s-prod-worker-05
10.52.1.106 k8s-prod-worker-06
10.52.1.107 k8s-prod-worker-07
10.52.1.108 k8s-prod-worker-08
10.52.1.109 k8s-prod-worker-09
10.52.1.110 k8s-prod-worker-10
10.52.1.111 k8s-prod-worker-11
10.52.1.112 k8s-prod-worker-12
# DB Cluster (VLAN 30)
10.30.0.120 pg-prod-01
10.30.0.121 pg-prod-02
10.30.0.122 pg-prod-03
10.30.0.200 pg-prod-vip
EOF

# Disable swap — REQUIRED by Kubernetes
swapoff -a && sed -i '/swap/d' /etc/fstab

# Kernel modules for K8s networking
cat > /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
EOF
modprobe overlay && modprobe br_netfilter

# sysctl — bridge filtering + IP forward
cat > /etc/sysctl.d/99-k8s.conf << EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
vm.overcommit_memory                = 1
kernel.panic                        = 10
kernel.panic_on_oops                = 1
fs.inotify.max_user_instances       = 8192
fs.inotify.max_user_watches         = 524288
net.core.somaxconn                  = 32768
EOF
sysctl --system

# containerd — CRI runtime
dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
dnf install -y containerd.io
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
# Enable systemd cgroup — required for OL9
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable containerd --now

# Kubernetes 1.34 — pin exact version to match across all nodes
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

echo "✅ Master k8s-prod-master-${NODE_NUM} (${NODE_IP}) OS ready"
```

### Step 3: Initialise Cluster (master-01 only)

```bash
# WHY --control-plane-endpoint = HAProxy VIP: workers and admins always
# connect to 10.52.0.100 which routes to any healthy master
kubeadm init \
  --control-plane-endpoint "10.52.0.100:6443" \
  --upload-certs \
  --pod-network-cidr "10.220.0.0/16" \
  --service-cidr    "10.221.0.0/16" \
  --kubernetes-version "v1.34.0" \
  --cri-socket unix:///run/containerd/containerd.sock

mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# ── SAVE the two join commands from kubeadm output ──
# 1. --control-plane  (for master-02 and master-03)
# 2. plain           (for all 12 workers)
echo "✅ Cluster initialised; copy both join commands before proceeding"
```

### Step 4: Join Masters 02 and 03

```bash
# Run on master-02 then master-03
kubeadm join 10.52.0.100:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane \
  --certificate-key <cert-key> \
  --cri-socket unix:///run/containerd/containerd.sock

mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# Verify on master-01 (NotReady until Calico is deployed)
kubectl get nodes
```

---

## Week 9: Provision Worker VMs

### Step 5: Create 12 Worker VMs

```bash
# 24 vCPU / 96 GB RAM / 300 GB disk — 30% headroom over current production peak
# WHY 300 GB disk: 150 GB container images + 100 GB PersistentVolumes + 50 GB buffer
for i in $(seq -f "%02g" 1 12); do
  govc vm.clone \
    -vm    "/Datacenter/vm/Templates/ol9-k8s-template" \
    -ds    "vsanDatastore" \
    -pool  "/Datacenter/host/VxRail-Cluster/Resources/PROD-Workers" \
    -net   "VLAN-120-PROD" \
    -name  "k8s-prod-worker-${i}" \
    -m     98304 \    # 96 GB RAM
    -c     24 \       # 24 vCPUs
    -disk  "300GB"
  echo "✅ Created k8s-prod-worker-${i}"
done

# Distribute workers across all 6 physical VxRail hosts (2 workers per host)
govc cluster.rule.create \
  -name "prod-worker-anti-affinity" -enable -affinity=false \
  $(for i in $(seq -f "k8s-prod-worker-%02g" 1 12); do echo -n "$i "; done)

for i in $(seq -f "%02g" 1 12); do govc vm.power -on "k8s-prod-worker-${i}"; done
sleep 90 && echo "✅ All 12 PROD workers powered on"
```

### Step 6: Configure OS on Each Worker (run on worker-01 through 12)

```bash
# IP map:
#  worker-01=10.52.1.101  worker-02=10.52.1.102  worker-03=10.52.1.103
#  worker-04=10.52.1.104  worker-05=10.52.1.105  worker-06=10.52.1.106
#  worker-07=10.52.1.107  worker-08=10.52.1.108  worker-09=10.52.1.109
#  worker-10=10.52.1.110  worker-11=10.52.1.111  worker-12=10.52.1.112

NODE_NUM="01"           # change per node 01..12
NODE_IP="10.52.1.101"  # change per node
GATEWAY="10.52.0.1"
DNS="10.20.0.53"

hostnamectl set-hostname "k8s-prod-worker-${NODE_NUM}"

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

# /etc/hosts — same as masters above (copy the full block)
cat >> /etc/hosts << EOF
10.52.0.10  k8s-prod-master-01
10.52.0.11  k8s-prod-master-02
10.52.0.12  k8s-prod-master-03
10.52.0.100 k8s-prod-api
10.52.1.101 k8s-prod-worker-01
10.52.1.102 k8s-prod-worker-02
10.52.1.103 k8s-prod-worker-03
10.52.1.104 k8s-prod-worker-04
10.52.1.105 k8s-prod-worker-05
10.52.1.106 k8s-prod-worker-06
10.52.1.107 k8s-prod-worker-07
10.52.1.108 k8s-prod-worker-08
10.52.1.109 k8s-prod-worker-09
10.52.1.110 k8s-prod-worker-10
10.52.1.111 k8s-prod-worker-11
10.52.1.112 k8s-prod-worker-12
10.30.0.120 pg-prod-01
10.30.0.121 pg-prod-02
10.30.0.122 pg-prod-03
10.30.0.200 pg-prod-vip
EOF

# Disable swap
swapoff -a && sed -i '/swap/d' /etc/fstab

# Kernel modules
cat > /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
EOF
modprobe overlay && modprobe br_netfilter

# sysctl — extra tuning for production workloads
cat > /etc/sysctl.d/99-k8s.conf << EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
vm.overcommit_memory                = 1
kernel.panic                        = 10
kernel.panic_on_oops                = 1
net.core.somaxconn                  = 65535
net.ipv4.tcp_max_syn_backlog        = 16384
fs.file-max                         = 2097152
fs.inotify.max_user_instances       = 8192
fs.inotify.max_user_watches         = 524288
net.ipv4.tcp_keepalive_time         = 300
net.ipv4.tcp_keepalive_intvl        = 30
net.ipv4.tcp_keepalive_probes       = 3
EOF
sysctl --system

# containerd
dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
dnf install -y containerd.io
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable containerd --now

# Kubernetes 1.34
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

echo "✅ Worker k8s-prod-worker-${NODE_NUM} (${NODE_IP}) ready for join"
```

### Step 7: Deploy Calico CNI, then Join Workers

```bash
# On master-01 — deploy Calico BEFORE joining workers
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
      cidr: 10.220.0.0/16
      encapsulation: VXLANCrossSubnet
EOF

kubectl wait --for=condition=Ready pod -l k8s-app=calico-node \
  -n calico-system --timeout=300s
echo "✅ Calico CNI ready — now join workers"

# Generate fresh join token
JOIN_CMD=$(kubeadm token create --print-join-command)
echo "Join command: ${JOIN_CMD}"

# Run on EACH of the 12 workers:
${JOIN_CMD} \
  --cri-socket unix:///run/containerd/containerd.sock \
  --node-name $(hostname)

# On master-01 — verify all 15 nodes
kubectl get nodes -o wide
# Expected: 3 masters + 12 workers all Ready

# Label workers and taint masters
for i in $(seq -f "%02g" 1 12); do
  kubectl label node "k8s-prod-worker-${i}" \
    node-role.kubernetes.io/worker="" \
    environment=prod
done
for m in 01 02 03; do
  kubectl taint nodes "k8s-prod-master-${m}" \
    node-role.kubernetes.io/control-plane:NoSchedule --overwrite
done
echo "✅ PROD K8s cluster: 3 masters + 12 workers = 15 nodes Ready"
```

### Step 8: Deploy vSphere CSI and MetalLB

```bash
# vSphere CSI — vSAN-backed PersistentVolumes
kubectl create secret generic vsphere-config-secret -n kube-system \
  --from-literal=csi-vsphere.conf='
[Global]
cluster-id = "k8s-prod"
insecure-flag = "true"
[VirtualCenter "10.20.0.10"]
user = "administrator@vsphere.local"
password = "<vcenter-password>"
datacenters = "DC-OnPrem"
port = "443"
[Network]
public-network = "VLAN-120-PROD"'

kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/vsphere-csi-driver/master/manifests/vanilla/deploy/vsphere-csi-controller-deployment.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/vsphere-csi-driver/master/manifests/vanilla/deploy/vsphere-csi-node-ds.yaml

# PROD StorageClass — RAID-1 policy, retain on delete
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: vsan-prod
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: csi.vsphere.volume
parameters:
  storagePolicyName: "PROD-vSAN-RAID1"
reclaimPolicy: Retain        # WHY Retain: never auto-delete production data
allowVolumeExpansion: true
EOF

# MetalLB LoadBalancer
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml
sleep 30

cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: prod-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.52.200.0/24    # Reserved PROD LoadBalancer IP range
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: prod-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - prod-pool
EOF
echo "✅ CSI + MetalLB deployed"
```

---

## Week 9: Provision Database VMs (Patroni HA)

### Step 9: Create 3 DB VMs

```bash
# 32 vCPU / 128 GB RAM / 1.5 TB disk per node
# WHY 128 GB: shared_buffers=32 GB caches the hot working set;
#   PostgreSQL reads from RAM not disk for repeat queries → 10x faster
# WHY 1.5 TB: 1 TB data + 400 GB WAL = 7 days PITR + 100 GB OS/logs

for i in 01 02 03; do
  govc vm.clone \
    -vm    "/Datacenter/vm/Templates/ol9-base-template" \
    -ds    "vsanDatastore" \
    -pool  "/Datacenter/host/VxRail-Cluster/Resources/PROD-DB" \
    -net   "VLAN-30-DATABASE" \
    -name  "pg-prod-${i}" \
    -m     131072 \   # 128 GB RAM
    -c     32 \       # 32 vCPUs — parallel queries, vacuums, pg_dump
    -disk  "1500GB"   # 1 TB data partition + 400 GB WAL + 100 GB OS
  echo "✅ Created pg-prod-${i}"
done
for i in 01 02 03; do govc vm.power -on "pg-prod-${i}"; done
sleep 60
```

### Step 10: Configure OS on Each DB Node (run on pg-prod-01, 02, 03)

```bash
# pg-prod-01=10.30.0.120  pg-prod-02=10.30.0.121  pg-prod-03=10.30.0.122
NODE_NUM="01"
NODE_IP="10.30.0.120"
GATEWAY="10.30.0.1"
DNS="10.20.0.53"

hostnamectl set-hostname "pg-prod-${NODE_NUM}"

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
10.30.0.120 pg-prod-01
10.30.0.121 pg-prod-02
10.30.0.122 pg-prod-03
10.30.0.200 pg-prod-vip
EOF

# OS tuning for PostgreSQL
cat >> /etc/sysctl.d/99-postgresql.conf << EOF
vm.swappiness         = 1          # Near-zero swap — swap kills PG latency
vm.dirty_ratio        = 10
vm.dirty_background_ratio = 3
kernel.shmmax         = 137438953472   # 128 GB
kernel.shmall         = 33554432
net.core.somaxconn    = 65535
EOF
sysctl --system

# Prepare dedicated data disk (/dev/sdb = 1.5 TB vSAN disk)
mkfs.xfs -f /dev/sdb
mkdir -p /data/patroni /data/wal
echo "/dev/sdb /data xfs defaults,noatime,nodiratime 0 0" >> /etc/fstab
mount -a
useradd -r -s /bin/bash postgres 2>/dev/null || true
chown -R postgres:postgres /data
echo "✅ DB node pg-prod-${NODE_NUM} OS configured"
```

### Step 11: Install PostgreSQL 15 + etcd + Patroni

```bash
# Run on ALL THREE DB nodes

# PostgreSQL 15
dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
dnf -qy module disable postgresql
dnf install -y postgresql15-server postgresql15-contrib postgresql15-pglogical

# etcd v3.5.9
ETCD_VER="v3.5.9"
wget -q https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz
tar xzf etcd-${ETCD_VER}-linux-amd64.tar.gz
mv etcd-${ETCD_VER}-linux-amd64/etcd /usr/local/bin/
mv etcd-${ETCD_VER}-linux-amd64/etcdctl /usr/local/bin/
useradd --no-create-home --shell /bin/false etcd 2>/dev/null || true
mkdir -p /var/lib/etcd /etc/etcd
chown -R etcd:etcd /var/lib/etcd /etc/etcd

# Patroni
pip3 install patroni[etcd] psycopg2-binary

echo "✅ PG15 + etcd + Patroni installed on $(hostname)"
```

### Step 12: Configure etcd Cluster

```bash
# On pg-prod-01 — change ETCD_NAME + IPs for 02 and 03
cat > /etc/etcd/etcd.conf << EOF
ETCD_NAME="pg-prod-01"
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_LISTEN_PEER_URLS="http://10.30.0.120:2380"
ETCD_LISTEN_CLIENT_URLS="http://10.30.0.120:2379,http://127.0.0.1:2379"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://10.30.0.120:2380"
ETCD_ADVERTISE_CLIENT_URLS="http://10.30.0.120:2379"
ETCD_INITIAL_CLUSTER_TOKEN="prod-etcd"
ETCD_INITIAL_CLUSTER="pg-prod-01=http://10.30.0.120:2380,pg-prod-02=http://10.30.0.121:2380,pg-prod-03=http://10.30.0.122:2380"
ETCD_INITIAL_CLUSTER_STATE="new"
EOF
# pg-prod-02: change ETCD_NAME="pg-prod-02", all .120 → .121
# pg-prod-03: change ETCD_NAME="pg-prod-03", all .120 → .122

cat > /etc/systemd/system/etcd.service << EOF
[Unit]
Description=etcd
After=network.target
[Service]
Type=notify
User=etcd
EnvironmentFile=/etc/etcd/etcd.conf
ExecStart=/usr/local/bin/etcd
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable etcd --now

# Verify — run from any node
etcdctl --endpoints=http://10.30.0.120:2379,http://10.30.0.121:2379,http://10.30.0.122:2379 \
  endpoint health
```

### Step 13: Configure Patroni

```bash
# On pg-prod-01 (change name + listen IPs for 02 and 03)
mkdir -p /etc/patroni
cat > /etc/patroni/patroni.yml << 'EOF'
scope: prod-postgres
namespace: /service/
name: pg-prod-01           # ← pg-prod-02 / pg-prod-03 on other nodes

dcs:
  etcd3:
    hosts:
      - 10.30.0.120:2379
      - 10.30.0.121:2379
      - 10.30.0.122:2379

restapi:
  listen: 10.30.0.120:8008   # ← .121 / .122 on other nodes
  connect_address: 10.30.0.120:8008

postgresql:
  listen: 10.30.0.120:5432   # ← .121 / .122 on other nodes
  connect_address: 10.30.0.120:5432
  data_dir: /data/patroni
  pgpass: /tmp/.pgpass_prod

  authentication:
    replication:
      username: replicator
      password: "ProdRepl_Secure_2026!"
    superuser:
      username: postgres
      password: "ProdAdmin_Secure_2026!"
    rewind:
      username: rewind_user
      password: "ProdRewind_2026!"

  parameters:
    # Tuned for 128 GB RAM — double everything from PREPROD
    shared_buffers:            32GB    # 25% of 128 GB — caches hot data in RAM
    effective_cache_size:      96GB    # Tells planner how much OS cache exists
    work_mem:                  128MB   # Per sort/hash; 32 parallel = 4 GB peak
    maintenance_work_mem:      4GB     # VACUUM, CREATE INDEX speed
    max_connections:           600     # pgBouncer handles app conns; PG stays low
    max_wal_size:              8GB     # Allow more WAL before forced checkpoint
    min_wal_size:              2GB
    checkpoint_completion_target: 0.9 # Spread checkpoint I/O smoothly
    wal_level:                 logical # WHY logical: required for pglogical replication
    max_wal_senders:           15      # Replicas + pglogical slots
    wal_keep_size:             2GB
    max_replication_slots:     15
    synchronous_commit:        on
    synchronous_standby_names: 'ANY 1 (pg-prod-02,pg-prod-03)'
    hot_standby:               on
    hot_standby_feedback:      on
    # Logging
    log_min_duration_statement: 50     # Stricter in prod — log queries > 50 ms
    log_checkpoints:           on
    log_connections:           on
    log_disconnections:        on
    log_lock_waits:            on
    log_temp_files:            0
    log_autovacuum_min_duration: 250ms
    shared_preload_libraries: 'pg_stat_statements,pglogical,auto_explain'
    auto_explain.log_min_duration: 1000  # Explain plans for queries > 1 s
    # pglogical — needed for live replication to on-prem
    wal_level: logical

  pg_hba:
    - host replication replicator 10.30.0.0/24 scram-sha-256
    - host all postgres           10.30.0.0/24 scram-sha-256
    - host all rewind_user        10.30.0.0/24 scram-sha-256
    - host all all                10.52.0.0/16 scram-sha-256  # PROD K8s VLAN
    - host all all                127.0.0.1/32 trust

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    master_start_timeout: 300
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        wal_level: logical
  post_bootstrap: |
    psql -c "CREATE ROLE replicator REPLICATION LOGIN ENCRYPTED PASSWORD 'ProdRepl_Secure_2026!'"
    psql -c "CREATE ROLE rewind_user LOGIN ENCRYPTED PASSWORD 'ProdRewind_2026!'"
    psql -c "GRANT EXECUTE ON FUNCTION pg_catalog.pg_ls_dir(text, boolean, boolean) TO rewind_user"
    psql -c "GRANT EXECUTE ON FUNCTION pg_catalog.pg_stat_file(text, boolean) TO rewind_user"
    psql -c "GRANT EXECUTE ON FUNCTION pg_catalog.pg_read_binary_file(text) TO rewind_user"
    psql -c "GRANT EXECUTE ON FUNCTION pg_catalog.pg_read_binary_file(text, bigint, bigint, boolean) TO rewind_user"
    psql -c "CREATE DATABASE prod_db OWNER postgres"
    psql -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements"
    psql -c "CREATE EXTENSION IF NOT EXISTS pglogical"

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
EOF

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

# Start pg-prod-01 FIRST → becomes Leader
systemctl enable patroni --now && sleep 20
# Then start pg-prod-02 and pg-prod-03 → become Replicas

# Verify
patronictl -c /etc/patroni/patroni.yml list
# + Cluster: prod-postgres +---------+----+-----------+
# | Member    | Role    | State   | TL | Lag in MB |
# | pg-prod-01 | Leader  | running |  1 |           |
# | pg-prod-02 | Replica | running |  1 |         0 |
# | pg-prod-03 | Replica | running |  1 |         0 |
```

### Step 14: Configure pgBouncer

```bash
dnf install -y pgbouncer

cat > /etc/pgbouncer/pgbouncer.ini << 'EOF'
[databases]
prod_db          = host=10.30.0.120 port=5432 dbname=prod_db
prod_db_readonly = host=10.30.0.121 port=5432 dbname=prod_db

[pgbouncer]
listen_addr       = 0.0.0.0
listen_port       = 6432
auth_type         = scram-sha-256
auth_file         = /etc/pgbouncer/userlist.txt
pool_mode         = transaction
default_pool_size = 80       # Larger than PREPROD — more app replicas
max_client_conn   = 3000
reserve_pool_size = 20
server_idle_timeout = 600
log_connections   = 0        # Disable in prod — high volume
log_disconnections = 0
logfile           = /var/log/pgbouncer/pgbouncer.log
EOF

printf '"postgres" "ProdAdmin_Secure_2026!"\n"app_user" "AppProd_2026!"\n' \
  > /etc/pgbouncer/userlist.txt
chmod 600 /etc/pgbouncer/userlist.txt
systemctl enable pgbouncer --now
echo "✅ Patroni HA + pgBouncer ready on PROD"
```

---

## Week 10–11: pglogical Live Replication

> pglogical streams every INSERT/UPDATE/DELETE from Azure PostgreSQL to on-prem in real time.
> Azure remains the write primary. On-prem stays in sync. At cutover, lag drops to 0,
> we drop the subscription, and on-prem becomes the standalone primary.

```
pglogical REPLICATION FLOW
════════════════════════════════════════════════════════════════════

  AZURE PostgreSQL (Flexible Server)
  ┌───────────────────────────────────────────────────────────────┐
  │  wal_level = logical   (enables logical decoding)             │
  │  max_replication_slots = 10                                   │
  │  pglogical EXTENSION installed                                │
  │  NODE: 'azure-prod-publisher'                                 │
  │  REPLICATION SET: 'prod_all_tables' (all public.* tables)     │
  └───────────────────────┬───────────────────────────────────────┘
                          │  WAL logical decoding stream (TLS)
                          │  Every INSERT / UPDATE / DELETE
                          ▼
  ON-PREM PostgreSQL (Patroni Leader: pg-prod-01)
  ┌───────────────────────────────────────────────────────────────┐
  │  pglogical EXTENSION installed                                │
  │  NODE: 'onprem-prod-subscriber'                               │
  │  SUBSCRIPTION: 'azure_to_onprem_prod'                         │
  │  Status: REPLICATING (lag < 50 ms)                            │
  └───────────────────────────────────────────────────────────────┘
                          │  streaming replication
                          ▼
              pg-prod-02 (Replica) + pg-prod-03 (Replica)
```

### Step 15: Configure pglogical on Azure

```bash
AZURE_HOST="<your-server>.postgres.database.azure.com"
AZURE_ADMIN="adminuser"

# Azure Portal: Server parameters → set:
#   shared_preload_libraries = pglogical
#   wal_level = logical
#   max_replication_slots = 10
#   max_wal_senders = 10
# Then RESTART the Azure PostgreSQL server.

psql "host=${AZURE_HOST} dbname=prod_db user=${AZURE_ADMIN} sslmode=require" << 'SQL'
CREATE EXTENSION IF NOT EXISTS pglogical;

-- Dedicated replication user (least-privilege)
CREATE ROLE repl_user REPLICATION LOGIN
  PASSWORD 'AzureRepl_Secure_2026!';
GRANT USAGE ON SCHEMA pglogical TO repl_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO repl_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO repl_user;

-- Publisher node
SELECT pglogical.create_node(
  node_name := 'azure-prod-publisher',
  dsn       := 'host=<azure-host> port=5432 dbname=prod_db user=repl_user sslmode=require'
);

-- Replicate all tables and sequences
SELECT pglogical.create_replication_set('prod_all_tables');
SELECT pglogical.replication_set_add_all_tables('prod_all_tables', ARRAY['public']);
SELECT pglogical.replication_set_add_all_sequences('prod_all_tables', ARRAY['public']);

SELECT * FROM pglogical.replication_set;
SQL
echo "✅ pglogical publisher configured on Azure"
```

### Step 16: Configure pglogical Subscription on On-Prem

```bash
psql -h 10.30.0.120 -U postgres -d prod_db << 'SQL'
CREATE EXTENSION IF NOT EXISTS pglogical;

-- Subscriber node
SELECT pglogical.create_node(
  node_name := 'onprem-prod-subscriber',
  dsn       := 'host=10.30.0.200 port=6432 dbname=prod_db user=postgres'
);

-- Create subscription — initial full copy + ongoing streaming
SELECT pglogical.create_subscription(
  subscription_name  := 'azure_to_onprem_prod',
  provider_dsn       := 'host=<azure-host> port=5432 dbname=prod_db user=repl_user password=AzureRepl_Secure_2026! sslmode=require',
  replication_sets   := ARRAY['prod_all_tables'],
  synchronize_data   := true,        -- Initial full table copy
  synchronize_structure := true      -- Copy DDL (table schema)
);

-- Monitor status
SELECT * FROM pglogical.show_subscription_status('azure_to_onprem_prod');
SQL
# Initial sync: 2–8 hours depending on DB size
# Status moves: initializing → copying → replicating
echo "✅ pglogical subscription active — monitoring lag..."
```

### Step 17: Monitor Replication Lag

```bash
# Run every 5 minutes via cron
cat > /usr/local/bin/monitor-pg-replication.sh << 'SCRIPT'
#!/bin/bash
LAG_MS=$(psql -h 10.30.0.120 -U postgres -d prod_db -t -c "
  SELECT ROUND(EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) * 1000);" \
  | tr -d ' ')

echo "$(date '+%Y-%m-%d %H:%M:%S') Replication lag: ${LAG_MS}ms"

if [ "${LAG_MS:-9999}" -gt 100 ]; then
  echo "⚠️  WARNING: lag ${LAG_MS}ms > 100ms threshold — investigate!"
fi
SCRIPT
chmod +x /usr/local/bin/monitor-pg-replication.sh
echo "*/5 * * * * postgres /usr/local/bin/monitor-pg-replication.sh \
  >> /var/log/pg-repl-lag.log" >> /etc/crontab

# Manual check
psql -h 10.30.0.120 -U postgres -d prod_db -c "
SELECT subscription_name, status
FROM pglogical.show_subscription_status();"
```

---

## Week 11–13: Application Deployment (Shadow Mode)

```bash
kubectl create namespace prod

kubectl create secret generic postgres-prod-creds -n prod \
  --from-literal=POSTGRES_HOST="10.30.0.200" \
  --from-literal=POSTGRES_PORT="6432" \
  --from-literal=POSTGRES_DB="prod_db" \
  --from-literal=POSTGRES_USER="app_user" \
  --from-literal=POSTGRES_PASSWORD="AppProd_2026!"

# PriorityClass — PROD pods scheduled first, evict QA/PREPROD under pressure
cat <<EOF | kubectl apply -f -
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: prod-critical
value: 1000000
globalDefault: false
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: prod-high
value: 900000
globalDefault: false
EOF

# NetworkPolicy — isolate PROD from other namespaces
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: prod-isolation
  namespace: prod
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
  ingress:
  - from:
    - ipBlock: {cidr: 10.52.0.0/16}   # PROD VLAN only
  egress:
  - to:
    - ipBlock: {cidr: 10.30.0.0/24}   # DB VLAN
    - ipBlock: {cidr: 0.0.0.0/0}
      ports: [{port: 443}]
EOF

# Deploy via ArgoCD (shadow mode — no live traffic)
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prod-app
  namespace: argocd
spec:
  project: prod
  source:
    repoURL: https://github.com/your-org/k8s-manifests
    targetRevision: main
    path: environments/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: prod
  syncPolicy:
    automated:
      prune: false      # Never auto-delete in PROD
      selfHeal: false   # Alert on drift, don't auto-fix
EOF

kubectl rollout status deployment -n prod --timeout=600s
PROD_IP=$(kubectl get svc api-gateway -n prod \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -sf http://${PROD_IP}/health && echo "✅ PROD apps running in shadow mode"
```

---

## Week 14–15: Dual-Run Validation (10% Canary)

```bash
# Route 10% of live traffic to on-prem (DNS weighted routing)
# Remaining 90% still goes to Azure — Azure is still primary
# Monitor on-prem closely; any issues → revert DNS weight to 100% Azure

# Update DNS (example — Azure DNS with weighted records):
az network dns record-set a update \
  -g dns-rg -z company.com -n api \
  --set "metadata.weight=10"   # on-prem record gets 10% weight

# Monitor 10% canary traffic (48 hours minimum)
watch -n 30 'kubectl top pods -n prod | head -20'

# Check error rate on on-prem vs Azure
# Prometheus query: compare http_requests_total{status=~"5.."} for both
```

### Pre-Cutover Validation Script

```bash
cat > /usr/local/bin/pre-cutover-check.sh << 'SCRIPT'
#!/bin/bash
FAIL=0

check() {
  local desc=$1; local cmd=$2; local expect=$3
  result=$(eval "$cmd" 2>/dev/null | tr -d ' \n')
  if [[ "$result" == *"$expect"* ]]; then
    echo "✅ $desc"
  else
    echo "❌ FAIL: $desc (got: $result)"
    ((FAIL++))
  fi
}

echo "=== PRE-CUTOVER VALIDATION $(date) ==="

check "All PROD pods Running" \
  "kubectl get pods -n prod --no-headers | grep -vc Running" "0"

check "Patroni has 1 Leader" \
  "patronictl -c /etc/patroni/patroni.yml list 2>/dev/null | grep -c Leader" "1"

check "pglogical status = replicating" \
  "psql -h 10.30.0.120 -U postgres -d prod_db -t -c \
   \"SELECT status FROM pglogical.show_subscription_status();\"" "replicating"

LAG=$(psql -h 10.30.0.120 -U postgres -d prod_db -t -c \
  "SELECT ROUND(EXTRACT(EPOCH FROM (now()-pg_last_xact_replay_timestamp()))*1000);" \
  | tr -d ' ')
[[ "${LAG:-9999}" -lt 50 ]] && echo "✅ Replication lag: ${LAG}ms" \
  || { echo "⚠️  Lag ${LAG}ms > 50ms threshold"; ((FAIL++)); }

PROD_IP=$(kubectl get svc api-gateway -n prod \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
check "App health endpoint" \
  "curl -sf http://${PROD_IP}/health | jq -r '.status'" "healthy"

echo ""; echo "Failures: ${FAIL}"
[[ $FAIL -eq 0 ]] && echo "✅ READY FOR CUTOVER" || { echo "❌ FIX FAILURES FIRST"; exit 1; }
SCRIPT
chmod +x /usr/local/bin/pre-cutover-check.sh
```

---

## Week 16: Cutover Execution

```
CUTOVER DECISION FLOWCHART
════════════════════════════════════════════════════════════════════

  Friday 3:30 PM — Run pre-cutover-check.sh
  ◆ All checks pass?
     YES → Proceed 4:00 PM    NO → Postpone (next Friday)

  T+00:00  BEGIN — Notify stakeholders, start recording
  T+00:05  Scale down Azure AKS to 0 replicas (stop new writes)
  T+00:10  Watch: lag → 0ms (psql: pg_last_xact_replay_timestamp)
  T+00:15  Drop pglogical subscription (on-prem is now standalone)
           psql: SELECT pglogical.drop_subscription('azure_to_onprem_prod', true)
  T+00:20  DNS switch: api.company.com → on-prem MetalLB IP
  T+00:25  Verify DNS propagation: dig api.company.com
  T+00:30  Smoke tests → ✅ CUTOVER COMPLETE
  T+00:30→T+72:00  Hypercare: check every 15 min for first 24 h
```

```bash
# T+00:05 — Stop Azure writes
az aks command invoke -g myRG -n myAKS \
  --command "kubectl scale deployment --all --replicas=0 -n prod"

# T+00:10 — Wait for lag = 0
while true; do
  LAG=$(psql -h 10.30.0.120 -U postgres -d prod_db -t -c \
    "SELECT COALESCE(ROUND(EXTRACT(EPOCH FROM \
     (now()-pg_last_xact_replay_timestamp()))*1000),0);" | tr -d ' ')
  echo "$(date +%H:%M:%S) lag=${LAG}ms"
  [[ "${LAG}" -lt 5 ]] && break
  sleep 3
done
echo "✅ Lag is 0 — proceeding"

# T+00:15 — Promote on-prem
psql -h 10.30.0.120 -U postgres -d prod_db -c \
  "SELECT pglogical.drop_subscription('azure_to_onprem_prod', true);"

# T+00:20 — Switch DNS
ONPREM_IP=$(kubectl get svc api-gateway -n prod \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
az network dns record-set a update \
  -g dns-rg -z company.com -n api \
  --set "aRecords[0].ipv4Address=${ONPREM_IP}"
sleep 60
dig api.company.com +short   # should return on-prem IP

# T+00:30 — Final validation
/usr/local/bin/pre-cutover-check.sh
echo "🎉 PROD CUTOVER COMPLETE — on-prem is now serving 100% traffic"
```

---

## Post-Cutover: 72-Hour Hypercare

```bash
# Every 15 minutes for first 24 hours
cat > /usr/local/bin/hypercare-check.sh << 'SCRIPT'
#!/bin/bash
echo "=== HYPERCARE CHECK $(date) ==="
kubectl get pods -n prod --no-headers | grep -v "Running\|Completed" | head -10
patronictl -c /etc/patroni/patroni.yml list 2>/dev/null | grep -E "Leader|Replica"
echo "Error rate (last 5m):"
curl -s "http://prometheus:9090/api/v1/query?query=rate(http_requests_total\
{status=~'5..',namespace='prod'}[5m])" | jq -r '.data.result[0].value[1]' 2>/dev/null
SCRIPT
chmod +x /usr/local/bin/hypercare-check.sh
echo "*/15 * * * * root /usr/local/bin/hypercare-check.sh >> /var/log/hypercare.log" \
  >> /etc/crontab
```

---

## Azure Decommission Schedule

| Week | Action |
|------|--------|
| 17–18 | Azure AKS scaled to 0, PostgreSQL read-only, monitor on-prem |
| 19–20 | Delete AKS workloads, remove Azure LB rules |
| 21–22 | Delete AKS cluster, ACR images archived to Harbor |
| 23–24 | Delete Azure PostgreSQL (after 30-day backup retention confirmed) |
| 25–26 | Delete VNet, Storage accounts, networking resources |
| 27–28 | Cancel Azure subscriptions, final cost savings report |

**Estimated savings after decommission:** ~$4 200/month (~$50 400/year)

---

## PROD Success Criteria

| Metric | Target | Measured By |
|--------|--------|-------------|
| Availability | ≥ 99.9% | Prometheus `up` metric |
| API p95 latency | < 500 ms | `http_request_duration_seconds` |
| Error rate (5xx) | < 0.1% | `http_requests_total` |
| Patroni failover | < 30 s | Drill test |
| Backup success | 100% | Veeam job status |
| RTO | < 4 hours | DR drill |
| RPO | < 15 minutes | Backup frequency |

---

**Previous:** [06-PREPROD-Detailed-Implementation.md](./06-PREPROD-Detailed-Implementation.md)
**Cutover detail:** [12-Cutover-Runbook.md](./12-Cutover-Runbook.md)
**Data migration:** [08-Migration-Procedures.md](./08-Migration-Procedures.md)
**Rollback:** [09-Rollback-Procedures.md](./09-Rollback-Procedures.md)
**Index:** [00-VxRail-Complete-Index.md](./00-VxRail-Complete-Index.md)
