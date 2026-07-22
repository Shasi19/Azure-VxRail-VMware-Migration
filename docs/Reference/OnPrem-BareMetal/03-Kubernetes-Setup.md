# 03 — Kubernetes Setup (Bare-Metal)

> **Goal**: Bootstrap a 3-control-plane HA Kubernetes cluster directly on physical servers.  
> Steps are nearly identical to KVM — the difference is there are no VM provisioning steps before this.

---

## Step 0: HA Load Balancer for API Server (Choose One)

You need a virtual IP (VIP) for the K8s API endpoint that survives individual control plane failures.

### Option A: keepalived + HAProxy (Recommended for Bare-Metal)

Run on **all 3 control plane servers**:

```bash
apt install -y keepalived haproxy

# HAProxy config (same on all 3 control plane servers)
cat >> /etc/haproxy/haproxy.cfg << 'EOF'
frontend k8s-api
    bind *:6443
    mode tcp
    default_backend k8s-masters

backend k8s-masters
    mode tcp
    balance roundrobin
    option tcp-check
    server cp01 10.0.1.10:6443 check fall 3 rise 2
    server cp02 10.0.1.11:6443 check fall 3 rise 2
    server cp03 10.0.1.12:6443 check fall 3 rise 2
EOF

systemctl enable --now haproxy

# keepalived — provides the floating VIP 10.0.1.5
# MASTER config (on server-cp-01)
cat > /etc/keepalived/keepalived.conf << 'EOF'
vrrp_instance VI_1 {
    state MASTER
    interface bond0.100
    virtual_router_id 51
    priority 110
    authentication {
        auth_type PASS
        auth_pass k8svip2026
    }
    virtual_ipaddress {
        10.0.1.5/24
    }
}
EOF
# BACKUP config (on server-cp-02 and cp-03): change state to BACKUP, priority to 100 and 90

systemctl enable --now keepalived

# Verify VIP is up on cp-01
ip addr show bond0.100 | grep 10.0.1.5
```

---

## Step 1: Install kubeadm, kubelet, kubectl

Run on **all 9 K8s servers** (3 control planes + 6 workers):

```bash
apt install -y apt-transport-https ca-certificates curl gpg

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | \
  gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' \
  > /etc/apt/sources.list.d/kubernetes.list

apt update
apt install -y kubelet=1.29.* kubeadm=1.29.* kubectl=1.29.*
apt-mark hold kubelet kubeadm kubectl

systemctl enable kubelet
```

---

## Step 2: Initialise First Control Plane (server-cp-01 only)

```bash
kubeadm init \
  --control-plane-endpoint "10.0.1.5:6443" \
  --upload-certs \
  --pod-network-cidr 10.244.0.0/16 \
  --service-cidr 10.96.0.0/12 \
  --kubernetes-version v1.29.0 \
  --node-name server-cp-01

# Save the output — it contains join tokens
# Set up kubectl
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

kubectl get nodes
```

---

## Step 3: Install Calico CNI

```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml

cat > /tmp/calico.yaml << 'EOF'
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: 10.244.0.0/16
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
EOF

kubectl create -f /tmp/calico.yaml
kubectl wait --for=condition=Ready pods -l k8s-app=calico-node -n calico-system --timeout=180s
kubectl get nodes
```

---

## Step 4: Join Other Control Planes

```bash
# On server-cp-02 and server-cp-03 — use join command from Step 2 output
kubeadm join 10.0.1.5:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane \
  --certificate-key <cert-key> \
  --node-name server-cp-02    # server-cp-03 on third

mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
```

---

## Step 5: Join Worker Nodes

```bash
# On server-wk-01 through server-wk-06
kubeadm join 10.0.1.5:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

---

## Step 6: Label and Taint Nodes

```bash
# Label workers by environment
kubectl label node server-wk-01 env=dev   workload=app
kubectl label node server-wk-02 env=qa    workload=app
kubectl label node server-wk-03 env=qa    workload=app
kubectl label node server-wk-04 env=preprod workload=app
kubectl label node server-wk-05 env=prod  workload=app
kubectl label node server-wk-06 env=prod  workload=app

# Taint prod nodes — only prod pods schedule here
kubectl taint nodes server-wk-05 server-wk-06 env=prod:NoSchedule

# Label DB nodes (for DaemonSets, exporters)
kubectl label node server-db-01 role=infra db=primary
kubectl label node server-db-02 role=infra db=replica
kubectl label node server-db-03 role=infra db=replica

# Verify
kubectl get nodes -o wide --show-labels
```

---

## Step 7: Create Environment Namespaces

```bash
for NS in dev qa preprod prod; do
  kubectl create namespace $NS
  kubectl label namespace $NS environment=$NS
done
kubectl get namespaces
```

---

## Step 8: Install NGINX Ingress Controller

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.loadBalancerIP=10.0.2.20

kubectl get svc -n ingress-nginx
# EXTERNAL-IP should be 10.0.2.20 (MetalLB)
```

---

## Step 9: Install cert-manager

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true \
  --version v1.14.0

kubectl get pods -n cert-manager

# Self-signed cluster issuer
cat > /tmp/issuer.yaml << 'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
EOF

kubectl apply -f /tmp/issuer.yaml
```

---

## Step 10: Verify Cluster

```bash
# Nodes
kubectl get nodes -o wide
# All should be Ready

# System pods
kubectl get pods -n kube-system
kubectl get pods -n calico-system

# Cluster info
kubectl cluster-info

# Quick test
kubectl run nginx-test --image=nginx -n dev --restart=Never
kubectl wait --for=condition=Ready pod/nginx-test -n dev --timeout=60s
kubectl delete pod nginx-test -n dev

echo "Cluster is healthy"
```

---

## Bare-Metal Specific: Node Failure Recovery

Unlike KVM (where you can revert a snapshot), on bare-metal you drain and replace nodes:

```bash
# Drain a failed node
kubectl drain server-wk-05 --ignore-daemonsets --delete-emptydir-data --force

# Remove from cluster
kubectl delete node server-wk-05

# On the replaced/repaired server, re-join
# First get a new join token (old ones expire after 24h)
kubeadm token create --print-join-command

# Run the printed command on the repaired server
```

---

*Next: [04-Storage-Setup.md](04-Storage-Setup.md)*
