# 04 — Kubernetes Setup (KVM)

> **Goal**: Bootstrap a 3-control-plane HA Kubernetes cluster inside the VMs.  
> This is equivalent to AKS — the managed Azure Kubernetes Service.

---

## Architecture

```
                    Virtual IP: 10.0.1.5 (HAProxy)
                         |
          ┌──────────────┼──────────────┐
          |              |              |
     k8s-cp-01     k8s-cp-02     k8s-cp-03
     10.0.1.10     10.0.1.11     10.0.1.12
     etcd + API    etcd + API    etcd + API
          |              |              |
          └──────────────┼──────────────┘
                         |
       ┌─────────────────┴──────────────────┐
       |         Worker Nodes               |
  k8s-wk-01..06  (10.0.1.20 – 10.0.1.25)
```

---

## Step 0: Install HAProxy for API Server VIP

Run on **one dedicated VM** (or on Host-1 directly) to provide a virtual IP for the K8s API:

```bash
# On a load balancer VM or Host-1
apt install -y haproxy

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
# Use the HAProxy VM IP (e.g. 10.0.1.5) as the control plane endpoint
```

---

## Step 1: Install kubeadm, kubelet, kubectl on All K8s VMs

Run on **all 9 K8s VMs** (3 control planes + 6 workers):

```bash
# Add Kubernetes apt repo
apt install -y apt-transport-https ca-certificates curl gpg

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | \
  gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' \
  > /etc/apt/sources.list.d/kubernetes.list

apt update
apt install -y kubelet=1.29.* kubeadm=1.29.* kubectl=1.29.*

# Pin versions (prevent accidental upgrades)
apt-mark hold kubelet kubeadm kubectl

# Enable kubelet
systemctl enable kubelet
```

---

## Step 2: Initialise First Control Plane (k8s-cp-01 only)

```bash
# Run ONLY on k8s-cp-01
kubeadm init \
  --control-plane-endpoint "10.0.1.5:6443" \
  --upload-certs \
  --pod-network-cidr 10.244.0.0/16 \
  --service-cidr 10.96.0.0/12 \
  --kubernetes-version v1.29.0 \
  --node-name k8s-cp-01

# SAVE the output — it contains join commands for other control planes and workers
# It will look like:
#   kubeadm join 10.0.1.5:6443 --token <token> \
#     --discovery-token-ca-cert-hash sha256:<hash> \
#     --control-plane --certificate-key <cert-key>

# Set up kubectl for root user on cp-01
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# Verify
kubectl get nodes
# cp-01 should show NotReady (CNI not installed yet)
```

---

## Step 3: Install Calico CNI

```bash
# Run on k8s-cp-01
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml

cat > /tmp/calico-config.yaml << 'EOF'
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

kubectl create -f /tmp/calico-config.yaml

# Wait for Calico to start
kubectl wait --for=condition=Ready pods -l k8s-app=calico-node -n calico-system --timeout=120s

# Now cp-01 should show Ready
kubectl get nodes
```

---

## Step 4: Join Other Control Planes (k8s-cp-02 and k8s-cp-03)

```bash
# Use the join command from Step 2 output (the --control-plane variant)
# Example (replace tokens with actual values from init output):

kubeadm join 10.0.1.5:6443 \
  --token <token-from-init> \
  --discovery-token-ca-cert-hash sha256:<hash-from-init> \
  --control-plane \
  --certificate-key <cert-key-from-init> \
  --node-name k8s-cp-02   # k8s-cp-03 on the third node

# Set up kubectl on each control plane
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
```

---

## Step 5: Join Worker Nodes (k8s-wk-01 to k8s-wk-06)

```bash
# Use the worker join command from Step 2 output (no --control-plane flag)
# Example:

kubeadm join 10.0.1.5:6443 \
  --token <token-from-init> \
  --discovery-token-ca-cert-hash sha256:<hash-from-init>

# Run on each of k8s-wk-01 through k8s-wk-06
```

---

## Step 6: Label Nodes for Environment Scheduling

```bash
# Label workers so pods go to the right nodes
kubectl label node k8s-wk-01 env=dev   workload=app
kubectl label node k8s-wk-02 env=qa    workload=app
kubectl label node k8s-wk-03 env=qa    workload=app
kubectl label node k8s-wk-04 env=preprod workload=app
kubectl label node k8s-wk-05 env=prod  workload=app
kubectl label node k8s-wk-06 env=prod  workload=app

# Taint prod workers so only prod pods schedule there
kubectl taint nodes k8s-wk-05 k8s-wk-06 env=prod:NoSchedule

# Verify labels
kubectl get nodes --show-labels
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

# Verify
kubectl get svc -n ingress-nginx
# Should show EXTERNAL-IP = 10.0.2.20 (MetalLB)
```

---

## Step 9: Install cert-manager (TLS Certificates)

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true \
  --version v1.14.0

kubectl get pods -n cert-manager

# Create a self-signed ClusterIssuer for internal certs
cat > /tmp/cluster-issuer.yaml << 'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: internal-ca
spec:
  ca:
    secretName: internal-ca-secret
EOF

kubectl apply -f /tmp/cluster-issuer.yaml
```

---

## Step 10: Verify Cluster Health

```bash
# All nodes Ready
kubectl get nodes -o wide

# All system pods Running
kubectl get pods -n kube-system
kubectl get pods -n calico-system

# Cluster info
kubectl cluster-info

# Test pod deployment
kubectl run test-pod --image=nginx --restart=Never -n dev
kubectl wait --for=condition=Ready pod/test-pod -n dev --timeout=60s
kubectl exec test-pod -n dev -- curl -s localhost | head -5
kubectl delete pod test-pod -n dev

# Check MetalLB
kubectl get pods -n metallb-system

echo "Kubernetes cluster is healthy"
```

---

## Troubleshooting

| Symptom | Command | Fix |
|---------|---------|-----|
| Node NotReady | `kubectl describe node <name>` | Check CNI pods: `kubectl get pods -n calico-system` |
| Pod CrashLoopBackOff | `kubectl logs <pod> -n <ns>` | Check resource limits, image pull errors |
| API unreachable | `curl -k https://10.0.1.5:6443/healthz` | Check HAProxy, check etcd: `etcdctl endpoint health` |
| Image pull fails | `kubectl describe pod <name>` | Add Harbor creds: `kubectl create secret docker-registry` |
| Calico not starting | `kubectl get pods -n calico-system` | Check `br_netfilter` loaded: `lsmod | grep br_netfilter` |

---

## Cluster Snapshot (KVM Advantage)

```bash
# Take a snapshot of all K8s node VMs after cluster is healthy
# Run on each KVM host
for VM in $(virsh list --name | grep k8s); do
  virsh snapshot-create-as "$VM" \
    "k8s-healthy-$(date +%Y%m%d)" \
    --description "K8s cluster healthy, pre-app-install" \
    --disk-only --atomic
done
```

---

*Next: [05-Storage-Setup.md](05-Storage-Setup.md)*
