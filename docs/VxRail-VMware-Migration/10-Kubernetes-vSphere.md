# Kubernetes on VMware vSphere (VxRail)

## Architecture

```
VxRail DVS (VLAN 20 — PG-K8s-Nodes)
├── 10.0.3.11  k8s-master-1  (VMware VM — vCPU:4, RAM:8GB)
├── 10.0.3.12  k8s-master-2  (VMware VM — vCPU:4, RAM:8GB)
├── 10.0.3.13  k8s-master-3  (VMware VM — vCPU:4, RAM:8GB)
├── 10.0.3.100 k8s-api VIP   (keepalived — floats on masters)
├── 10.0.4.21  k8s-worker-1  (VMware VM — vCPU:8, RAM:16GB)
├── ...
└── Storage: vSphere CSI Driver → vSAN Datastore
```

---

## 1. Pre-Install VM Requirements

Run on every K8s VM before installing Kubernetes:

```bash
# Run as root on every K8s node (masters + workers)
cat << 'SETUP' > /usr/local/bin/k8s-node-prep.sh
#!/bin/bash
set -e

# 1. Disable swap permanently
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# 2. Load kernel modules
tee /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# 3. Kernel parameters for Kubernetes
tee /etc/sysctl.d/99-k8s.conf << EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# 4. Install containerd (container runtime) — Oracle Linux 9 (dnf)
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf install -y containerd.io

# Configure containerd with systemd cgroup driver (required for K8s 1.22+)
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# 5. Install kubeadm, kubelet, kubectl 1.29 — Oracle Linux 9 RPM repo
cat > /etc/yum.repos.d/kubernetes.repo << 'KREPO'
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
KREPO
dnf install -y --disableexcludes=kubernetes kubelet-1.29.0 kubeadm-1.29.0 kubectl-1.29.0
dnf versionlock add kubelet kubeadm kubectl

# 6. Enable kubelet
systemctl enable kubelet

echo "Node preparation complete. Ready for kubeadm."
SETUP

chmod +x /usr/local/bin/k8s-node-prep.sh
bash /usr/local/bin/k8s-node-prep.sh
```

---

## 2. keepalived on All 3 Masters

Install and configure keepalived BEFORE running kubeadm (the VIP must exist for the init command to use it):

```bash
# On all 3 masters
sudo dnf install -y keepalived haproxy

# keepalived (master-1 — STATE MASTER, priority 101)
sudo tee /etc/keepalived/keepalived.conf << 'EOF'
global_defs {
  router_id k8s-master-1
  enable_script_security
}

vrrp_script chk_haproxy {
  script "killall -0 haproxy"
  interval 2
  weight 2
}

vrrp_instance VI_1 {
  state MASTER            # BACKUP on master-2 (priority 100), master-3 (priority 99)
  interface ens192        # VMware VMXNET3 adapter
  virtual_router_id 51
  priority 101
  advert_int 1
  authentication {
    auth_type PASS
    auth_pass K8sHA2026!
  }
  virtual_ipaddress {
    10.0.3.100/24
  }
  track_script {
    chk_haproxy
  }
}
EOF

# HAProxy as API server proxy (load balances to all 3 masters)
sudo tee /etc/haproxy/haproxy.cfg << 'EOF'
global
  log /dev/log local0
  maxconn 2048
  daemon

defaults
  mode tcp
  log global
  option tcplog
  option dontlognull
  timeout connect 5s
  timeout client 30s
  timeout server 30s

frontend k8s-api
  bind *:6443
  default_backend k8s-masters

backend k8s-masters
  balance roundrobin
  option tcp-check
  server master-1 10.0.3.11:6443 check
  server master-2 10.0.3.12:6443 check
  server master-3 10.0.3.13:6443 check
EOF

sudo systemctl enable keepalived haproxy
sudo systemctl start keepalived haproxy

# Verify VIP is present on master-1
ip addr show ens192 | grep "10.0.3.100"
```

---

## 3. Initialize Kubernetes Cluster

### 3.1 kubeadm Init (master-1 ONLY)

```bash
# Create kubeadm config (run ONLY on master-1)
cat > /root/kubeadm-config.yaml << 'EOF'
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: 10.0.3.11    # This master's own IP
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
  kubeletExtraArgs:
    cloud-provider: external    # Required for vSphere Cloud Controller Manager
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.29.0
controlPlaneEndpoint: "10.0.3.100:6443"    # VIP — all nodes join through this
networking:
  podSubnet: "192.168.0.0/16"
  serviceSubnet: "10.96.0.0/12"
etcd:
  local:
    dataDir: /var/lib/etcd
apiServer:
  extraArgs:
    cloud-provider: external
  certSANs:
    - 10.0.3.100          # VIP
    - 10.0.3.11           # master-1
    - 10.0.3.12           # master-2
    - 10.0.3.13           # master-3
    - k8s-api.internal.company.com
controllerManager:
  extraArgs:
    cloud-provider: external
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
EOF

kubeadm init \
  --config=/root/kubeadm-config.yaml \
  --upload-certs \
  2>&1 | tee /root/kubeadm-init.log

# Save the join commands from the output!
# kubeadm join 10.0.3.100:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash> --control-plane --certificate-key <cert-key>
# kubeadm join 10.0.3.100:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>

# Set up kubectl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### 3.2 Join master-2 and master-3

```bash
# On master-2 and master-3 (use the control-plane join command from kubeadm init output)
# Also needs --config for cloud-provider setting

cat > /root/kubeadm-join.yaml << 'EOF'
apiVersion: kubeadm.k8s.io/v1beta3
kind: JoinConfiguration
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
  kubeletExtraArgs:
    cloud-provider: external
EOF

# Join (replace with actual token/hash from kubeadm init output)
kubeadm join 10.0.3.100:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane \
  --certificate-key <cert-key> \
  --config=/root/kubeadm-join.yaml
```

### 3.3 Join Workers

```bash
# On each worker node (same join config for cloud-provider)
cat > /root/kubeadm-join.yaml << 'EOF'
apiVersion: kubeadm.k8s.io/v1beta3
kind: JoinConfiguration
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
  kubeletExtraArgs:
    cloud-provider: external
EOF

kubeadm join 10.0.3.100:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --config=/root/kubeadm-join.yaml
```

---

## 4. Install Calico CNI

```bash
# From master-1 with kubectl access
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml

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

# Wait for Calico to be ready
kubectl wait --namespace calico-system \
  --for=condition=ready pod \
  --selector=k8s-app=calico-node \
  --timeout=120s

kubectl get nodes
# All nodes should show Ready
```

---

## 5. vSphere Cloud Controller Manager (CCM)

The CCM labels nodes with vSphere zone/region metadata, enabling vSphere-aware scheduling:

```bash
# Create vSphere CCM config secret
kubectl create configmap cloud-config \
  --namespace=kube-system \
  --from-literal=vsphere.conf="
[Global]
secret-name = \"vsphere-cloud-credentials\"
secret-namespace = \"kube-system\"

[VirtualCenter \"vcenter.internal.company.com\"]
datacenters = \"Datacenter\"

[Labels]
region = k8s-region
zone = k8s-zone
"

kubectl create secret generic vsphere-cloud-credentials \
  --namespace=kube-system \
  --from-literal=vcenter.internal.company.com.username=k8s-csi-user@vsphere.local \
  --from-literal=vcenter.internal.company.com.password=CSIuser2026!

# Deploy CCM
CCM_VERSION="v1.29.0"
kubectl apply -f "https://raw.githubusercontent.com/kubernetes/cloud-provider-vsphere/release-1.29/releases/v${CCM_VERSION}/vsphere-cloud-controller-manager.yaml"

# Verify
kubectl get pods -n kube-system | grep vsphere
```

---

## 6. Install MetalLB and Storage Classes

```bash
# MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml

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

# Storage Classes (after vSphere CSI installed — see 09-Storage-vSAN.md)
kubectl apply -f storageclass-vsan.yaml

# Verify
kubectl get nodes -o wide
kubectl get storageclasses
kubectl get pods -A | grep -v Running | grep -v Completed
```

---

## 7. Cluster Verification

```bash
#!/bin/bash
# k8s-verify.sh — comprehensive cluster health check

echo "===== Kubernetes Cluster Health ====="
echo ""

echo "--- Nodes ---"
kubectl get nodes -o wide

echo ""
echo "--- System Pods ---"
kubectl get pods -n kube-system

echo ""
echo "--- Storage Classes ---"
kubectl get sc

echo ""
echo "--- MetalLB ---"
kubectl get pods -n metallb-system

echo ""
echo "--- vSphere CSI ---"
kubectl get pods -n vmware-system-csi

echo ""
echo "--- Test PVC (vSAN) ---"
cat << 'YAML' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
  namespace: default
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: vsan-dev-qa
  resources:
    requests:
      storage: 1Gi
YAML

sleep 15
kubectl get pvc test-pvc
PVC_STATUS=$(kubectl get pvc test-pvc -o jsonpath='{.status.phase}')
[ "$PVC_STATUS" = "Bound" ] && echo "PVC Test: PASS" || echo "PVC Test: FAIL (status: $PVC_STATUS)"

kubectl delete pvc test-pvc

echo ""
echo "--- API Server HA ---"
curl -sk https://10.0.3.100:6443/healthz && echo "VIP API: PASS" || echo "VIP API: FAIL"
curl -sk https://10.0.3.11:6443/healthz && echo "master-1 API: PASS" || echo "master-1 API: FAIL"
curl -sk https://10.0.3.12:6443/healthz && echo "master-2 API: PASS" || echo "master-2 API: FAIL"
curl -sk https://10.0.3.13:6443/healthz && echo "master-3 API: PASS" || echo "master-3 API: FAIL"

echo ""
echo "===== Check complete ====="
```

---

## 8. Troubleshooting

| Issue | Command | Fix |
|-------|---------|-----|
| Node stays NotReady | `kubectl describe node <name>` | Check `open-vm-tools` installed; check cloud-provider=external in kubelet config |
| PVC stuck Pending | `kubectl describe pvc <name>` | Check `disk.EnableUUID=TRUE` on VM; check CSI controller pod logs |
| kubeadm init fails - port in use | `ss -tulpn | grep 6443` | HAProxy already listening on 6443 — use a different bind address or stop temporarily |
| etcd unhealthy | `etcdctl member list` from master | Check etcd pod logs; ensure all 3 masters joined successfully |
| VIP not floating on master failure | `ip addr show ens192` on all masters | Check keepalived logs; verify `Forged Transmits=Accept` on DVS port group |
| Worker joins but shows NotReady | `kubectl describe node` — taint check | Check containerd is running; check kubelet logs `journalctl -u kubelet -f` |

---

## Kubernetes Cluster — Complete Setup Guide

### K8s Architecture Diagram

```
                   EXTERNAL CLIENTS
                        |
                   [MetalLB VIP]
                   10.0.4.200-220
                        |
              [NGINX Ingress Controller]
                 (DaemonSet on workers)
                        |
          +-------------+-------------+
          |                           |
     [SERVICES]                  [SERVICES]
   Dev/QA namespace          Prod namespace
          |                           |
     [PODS]                      [PODS]
          |                           |
     [PVCs → vSphere CSI → vSAN]

    CONTROL PLANE (HA):
    +-------------+  +-------------+  +-------------+
    | k8s-master-1|  | k8s-master-2|  | k8s-master-3|
    | 10.0.3.11   |  | 10.0.3.12   |  | 10.0.3.13   |
    | API Server  |  | API Server  |  | API Server  |
    | etcd        |  | etcd        |  | etcd        |
    | Scheduler   |  | Scheduler   |  | Scheduler   |
    | Controller  |  | Controller  |  | Controller  |
    +------+------+  +------+------+  +------+------+
           |                |                |
           +--------+-------+--------+-------+
                    |
              [VIP: 10.0.3.100]
           (keepalived + HAProxy)
                    |
       kubectl / kubeadm / ArgoCD

    DATA PLANE (Workers):
    Worker-1 (10.0.4.21) — Dev workloads
    Worker-2 (10.0.4.22) — QA workloads
    Worker-3 (10.0.4.23) — PreProd workloads
    Worker-4 (10.0.4.24) — PreProd workloads
    Worker-5 (10.0.4.25) — Prod workloads (NoSchedule for others)
    Worker-6 (10.0.4.26) — Prod workloads (NoSchedule for others)
```

---

### Step 1: Prepare All K8s Nodes (Masters + Workers)

Run on ALL 9 K8s VMs (3 masters + 6 workers):

```bash
#!/bin/bash
# k8s-node-prep.sh — Run on every K8s VM before kubeadm
set -euo pipefail

echo "=== K8s Node Preparation ==="

# 1. Disable swap (already done in template, verify)
swapoff -a
grep -q swap /etc/fstab && sed -i '/swap/s/^/#/' /etc/fstab
free -h | grep Swap   # Should show 0B

# 2. Load kernel modules
modprobe overlay
modprobe br_netfilter
cat > /etc/modules-load.d/k8s.conf << 'EOF'
overlay
br_netfilter
EOF

# 3. Kernel sysctl
cat > /etc/sysctl.d/99-k8s.conf << 'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# 4. Set SELinux Permissive
setenforce 0
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

# 5. Disable firewalld (K8s manages iptables directly)
systemctl disable --now firewalld

# 6. Add Kubernetes YUM repository
cat > /etc/yum.repos.d/kubernetes.repo << 'EOF'
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

# 7. Install containerd
dnf install -y containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
# Enable SystemdCgroup — REQUIRED for K8s 1.29+
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd

# 8. Install Kubernetes components
dnf install -y kubelet kubeadm kubectl \
  --disableexcludes=kubernetes
systemctl enable --now kubelet

echo "=== Node preparation complete ==="
echo "Verify: kubeadm version && kubectl version --client"
kubeadm version
kubectl version --client
```

---

### Step 2: Install HAProxy on All 3 Masters

```bash
# Run on ALL 3 master nodes
sudo dnf install -y haproxy

sudo tee /etc/haproxy/haproxy.cfg << 'EOF'
global
    log /dev/log local0
    maxconn 2048
    daemon

defaults
    log     global
    mode    tcp
    timeout connect 5s
    timeout client  50s
    timeout server  50s

frontend k8s-api
    bind *:6443
    mode tcp
    option tcplog
    default_backend k8s-api-backends

backend k8s-api-backends
    mode tcp
    option tcp-check
    balance roundrobin
    server master-1 10.0.3.11:6443 check fall 3 rise 2
    server master-2 10.0.3.12:6443 check fall 3 rise 2
    server master-3 10.0.3.13:6443 check fall 3 rise 2
EOF

sudo systemctl enable --now haproxy
sudo systemctl status haproxy
```

---

### Step 3: kubeadm init on master-1

```bash
# Run ONLY on k8s-master-1

# Create kubeadm config
cat > /tmp/kubeadm-config.yaml << 'EOF'
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.29.0
clusterName: vxrail-k8s
controlPlaneEndpoint: "10.0.3.100:6443"   # keepalived VIP
networking:
  serviceSubnet: "10.96.0.0/12"
  podSubnet: "192.168.0.0/16"             # Calico default
  dnsDomain: "cluster.local"
etcd:
  local:
    dataDir: /var/lib/etcd
apiServer:
  certSANs:
    - "10.0.3.100"
    - "10.0.3.11"
    - "10.0.3.12"
    - "10.0.3.13"
    - "k8s-api.internal.company.com"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
EOF

# Initialize cluster
sudo kubeadm init \
  --config=/tmp/kubeadm-config.yaml \
  --upload-certs \
  --v=5 \
  2>&1 | tee /tmp/kubeadm-init.log

# SAVE the output! It contains the join commands for other masters and workers
# Look for lines starting with:
#   "kubeadm join 10.0.3.100:6443 --token ... --discovery-token-ca-cert-hash ..."
#   "kubeadm join 10.0.3.100:6443 --token ... --control-plane --certificate-key ..."

# Configure kubectl on master-1
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Verify API server is up
kubectl get nodes
# k8s-master-1   NotReady   control-plane   30s   v1.29.0
# (NotReady is expected — no CNI installed yet)
```

---

### Step 4: Install Calico CNI

```bash
# Run on master-1 after kubeadm init

kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml

cat > /tmp/calico-install.yaml << 'EOF'
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

kubectl apply -f /tmp/calico-install.yaml

# Wait for Calico to be ready
kubectl wait --for=condition=Ready pods -n calico-system --all --timeout=120s

# Verify master is now Ready
kubectl get nodes
# k8s-master-1   Ready   control-plane   2m   v1.29.0
```

---

### Step 5: Join master-2 and master-3

```bash
# Copy the control-plane join command from kubeadm-init.log
# It looks like:
# kubeadm join 10.0.3.100:6443 \
#   --token <token> \
#   --discovery-token-ca-cert-hash sha256:<hash> \
#   --control-plane \
#   --certificate-key <cert-key>

# Run on k8s-master-2:
sudo kubeadm join 10.0.3.100:6443 \
  --token <TOKEN_FROM_INIT_OUTPUT> \
  --discovery-token-ca-cert-hash sha256:<HASH_FROM_INIT_OUTPUT> \
  --control-plane \
  --certificate-key <CERT_KEY_FROM_INIT_OUTPUT>

# After join completes on master-2:
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Repeat same steps on k8s-master-3

# Verify all 3 masters on master-1:
kubectl get nodes
# NAME           STATUS   ROLES           AGE   VERSION
# k8s-master-1   Ready    control-plane   5m    v1.29.0
# k8s-master-2   Ready    control-plane   2m    v1.29.0
# k8s-master-3   Ready    control-plane   1m    v1.29.0
```

---

### Step 6: Join Worker Nodes

```bash
# Copy the worker join command from kubeadm-init.log:
# kubeadm join 10.0.3.100:6443 \
#   --token <token> \
#   --discovery-token-ca-cert-hash sha256:<hash>

# Run on ALL 6 worker nodes (k8s-worker-1 through k8s-worker-6):
sudo kubeadm join 10.0.3.100:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>

# Verify on master-1:
kubectl get nodes
# All 9 nodes should show Ready
```

---

### Step 7: Label and Taint Worker Nodes by Environment

```bash
# Label workers
kubectl label node k8s-worker-1 environment=dev   app-tier=worker
kubectl label node k8s-worker-2 environment=qa    app-tier=worker
kubectl label node k8s-worker-3 environment=preprod app-tier=worker
kubectl label node k8s-worker-4 environment=preprod app-tier=worker
kubectl label node k8s-worker-5 environment=prod  app-tier=worker
kubectl label node k8s-worker-6 environment=prod  app-tier=worker

# Taint Prod workers — ONLY prod pods can schedule here
kubectl taint node k8s-worker-5 environment=prod:NoSchedule
kubectl taint node k8s-worker-6 environment=prod:NoSchedule

# Verify
kubectl get nodes --show-labels
kubectl describe node k8s-worker-5 | grep Taints
```

---

### Step 8: Create Namespaces

```bash
for NS in dev qa preprod prod monitoring; do
  kubectl create namespace $NS
done

# Label namespaces
kubectl label namespace dev environment=dev
kubectl label namespace qa environment=qa
kubectl label namespace preprod environment=preprod
kubectl label namespace prod environment=prod

kubectl get namespaces
```

---

### Step 9: Install Harbor (Container Registry)

```bash
# Add Harbor Helm repo
helm repo add harbor https://helm.goharbor.io
helm repo update

# Install Harbor
helm install harbor harbor/harbor \
  --namespace harbor \
  --create-namespace \
  --set expose.type=loadBalancer \
  --set expose.tls.enabled=true \
  --set expose.tls.certSource=secret \
  --set expose.tls.secret.secretName=wildcard-tls \
  --set externalURL=https://harbor.internal.company.com \
  --set harborAdminPassword=HarborAdmin2026! \
  --set persistence.persistentVolumeClaim.registry.storageClass=vsan-production \
  --set persistence.persistentVolumeClaim.database.storageClass=vsan-databases

# Wait for pods
kubectl wait --namespace=harbor --for=condition=Ready pods --all --timeout=300s

# Add DNS entry pointing harbor.internal.company.com to the MetalLB LoadBalancer IP
kubectl get svc -n harbor harbor-nginx  # Note the EXTERNAL-IP
```

---

### Step 10: Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Expose via LoadBalancer
kubectl patch svc argocd-server -n argocd \
  -p '{"spec": {"type": "LoadBalancer"}}'

# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Login and change password
ARGOCD_IP=$(kubectl -n argocd get svc argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
argocd login $ARGOCD_IP --insecure --username admin --password <INITIAL_PASSWORD>
argocd account update-password
```

---

### Step 11: Install Prometheus + Grafana

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install kube-prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.persistence.enabled=true \
  --set grafana.persistence.storageClassName=vsan-production \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=vsan-production \
  --set grafana.adminPassword=GrafanaAdmin2026! \
  --set prometheus.service.type=LoadBalancer \
  --set grafana.service.type=LoadBalancer

kubectl get pods -n monitoring
# All pods should be Running within 3-5 minutes
```

---

### Verification: Full Cluster Health Check

```bash
# Run this from master-1 or jump host with kubeconfig

echo "=== K8s Cluster Health Check ==="

echo "--- Nodes ---"
kubectl get nodes -o wide

echo "--- System Pods ---"
kubectl get pods -n kube-system

echo "--- Storage Classes ---"
kubectl get storageclass

echo "--- Calico Status ---"
kubectl get pods -n calico-system

echo "--- MetalLB Status ---"
kubectl get pods -n metallb-system

echo "--- Harbor ---"
kubectl get pods -n harbor

echo "--- ArgoCD ---"
kubectl get pods -n argocd

echo "--- Monitoring ---"
kubectl get pods -n monitoring

echo "--- Namespaces ---"
kubectl get namespaces

echo "=== Check Complete ==="
```

