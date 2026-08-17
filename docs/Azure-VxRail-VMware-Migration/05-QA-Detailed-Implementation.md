# QA Phase — Detailed Implementation Guide

**Weeks 1–3: Deploy, Migrate & Validate on 3-Node Kubernetes Cluster**

---

## 📊 QA Phase Flowchart

```
QA PHASE — COMPLETE FLOW (Weeks 1–3)
══════════════════════════════════════════════════════════════════════════════

  [PREREQUISITE: 04-Pre-Migration-Checklist.md ALL GATES PASSED]
                          │
                          ▼
  ┌─────────────────────────────────────────────────────────────────────┐
  │  WEEK 1 — INFRASTRUCTURE BUILD                                      │
  │                                                                     │
  │  Day 1–2: Master Nodes                  Day 2 (parallel): Workers  │
  │  ┌──────────────────────────┐           ┌────────────────────────┐  │
  │  │ ① Create 3 Master VMs    │           │ ① Create 3 Worker VMs  │  │
  │  │   (vCenter govc clone)   │           │   12vCPU/48GB/200GB    │  │
  │  │ ② Configure OL9 on each  │           │ ② Configure OL9        │  │
  │  │   (hostname, static IP,  │           │   (hostname, IP, swap, │  │
  │  │   swap off, kernel mods) │           │    kernel mods, sysctl)│  │
  │  │ ③ Install containerd     │           │ ③ Install containerd   │  │
  │  │ ④ Install K8s 1.34       │           │ ④ Install K8s 1.34     │  │
  │  │ ⑤ kubeadm init (master1) │           │ ⑤ WAIT for Calico CNI  │  │
  │  │ ⑥ Join masters 2 & 3     │           │                        │  │
  │  └──────────────────────────┘           └────────────────────────┘  │
  │                   │                                │               │
  │  Day 3–4: Network & Storage             After CNI ready:           │
  │  ┌──────────────────────────────┐       ┌────────────────────────┐  │
  │  │ ⑦ Deploy Calico CNI          │       │ ⑥ kubeadm join workers │  │
  │  │ ⑧ Deploy vSphere CSI driver  │──────▶│ ⑦ Label worker nodes   │  │
  │  │ ⑨ Deploy MetalLB LoadBalancer│       │ ⑧ Apply kubelet quotas │  │
  │  │ ⑩ Configure CoreDNS          │       └────────────────────────┘  │
  │  └──────────────────────────────┘                                   │
  │                   │                                                 │
  │  Verify: kubectl get nodes → 6 nodes ALL Ready                      │
  └───────────────────────────────────────────────────────────────────  ┘
                          │
                          ▼
  ┌─────────────────────────────────────────────────────────────────────┐
  │  WEEK 2 — DATABASE & APPLICATION MIGRATION                          │
  │                                                                     │
  │  Day 8–9: PostgreSQL 15 Setup           Day 10–12: App Deploy       │
  │  ┌──────────────────────────────┐       ┌────────────────────────┐  │
  │  │ ⑪ Create PostgreSQL 15 VM    │       │ ⑬ Create QA namespace  │  │
  │  │    8vCPU/32GB/600GB          │       │ ⑭ Create Secrets/CMs   │  │
  │  │ ⑫ Restore from Azure dump    │       │ ⑮ Deploy apps via ArgoCD│  │
  │  │    pg_dump → pg_restore      │       │ ⑯ Smoke test endpoints  │  │
  │  │    Validate row counts       │       └────────────────────────┘  │
  │  └──────────────────────────────┘                                   │
  └───────────────────────────────────────────────────────────────────  ┘
                          │
                          ▼
  ┌─────────────────────────────────────────────────────────────────────┐
  │  WEEK 3 — VALIDATION & SIGN-OFF                                     │
  │                                                                     │
  │  ⑰ Full regression test suite (automated)                           │
  │  ⑱ Load test: 200 concurrent users (k6)                             │
  │  ⑲ Performance baseline: p95 latency, error rate, DB query times    │
  │  ⑳ Security scan: Trivy, RBAC audit, network policy review          │
  │  ㉑ User acceptance testing (UAT with app team)                     │
  │  ㉒ Document issues/lessons learned                                  │
  │  ㉓ QA SIGN-OFF checklist — get all approvals                        │
  └───────────────────────────────────────────────────────────────────  ┘
                          │
                 ◆ ALL SIGN-OFFS OBTAINED?
                /          \
             YES              NO
              │                │
   [Proceed to            [Extend QA,
   PREPROD Week 4]        fix issues,
                          retest]
```

---

## Overview

| Phase | Duration | VMs | Specs | Focus | Gate |
|-------|----------|-----|-------|-------|------|
| QA | Weeks 1–3 + 1 buffer | 3 Masters + 3 Workers | 12vCPU/48GB/200GB per worker | Testing & Validation | QA Sign-Off |

**Environment Details**:

| Resource | Value | Notes |
|----------|-------|-------|
| Kubernetes Cluster | k8s-qa | |
| Network VLAN | 100 (10.50.0.0/16) | |
| Workers | k8s-qa-worker-01..03 | 10.50.1.101–103 |
| Masters | k8s-qa-master-01..03 | 10.50.0.10–12 |
| API VIP | 10.50.0.100 | HAProxy load-balanced |
| PostgreSQL | pg-qa-01 (10.30.0.100) | 8vCPU/32GB/600GB |
| Storage per worker | 200 GB thin provisioned | +100% buffer |
| Target Load | 200 concurrent users | Smoke + regression test |

---

## Week 1: Infrastructure Setup

### Day 1–2: Master Node Provisioning & K8s Initialization

#### Step 1: Deploy Master VMs in vSphere

```bash
# On vCenter jump host — create 3 QA master VMs
# WHY govc CLI: Scriptable, repeatable, no manual clicking in vCenter UI
for i in 01 02 03; do
  govc vm.clone \
    -vm    "/Datacenter/vm/Templates/ol9-k8s-template" \
    -ds    "vsanDatastore" \
    -pool  "/Datacenter/host/VxRail-Cluster/Resources/QA-Masters" \
    -net   "VLAN-100-QA" \
    -name  "k8s-qa-master-${i}" \
    -m     32768 \     # 32 GB RAM — enough for etcd + API server + scheduler
    -c     8 \         # 8 vCPUs — control plane components are multi-threaded
    -disk  "150GB" \   # 150 GB: OS(50) + etcd data(50) + logs/buffer(50)
    -on=false
done

# Anti-affinity: spread masters across physical VxRail hosts
govc cluster.rule.create \
  -name "qa-master-anti-affinity" -enable -affinity=false \
  "k8s-qa-master-01" "k8s-qa-master-02" "k8s-qa-master-03"

# Power on
for i in 01 02 03; do govc vm.power -on "k8s-qa-master-${i}"; done
echo "⏳ Waiting for VMs to boot (60s)..."
sleep 60
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

### Day 2 (Parallel): Provision & Configure QA Worker Nodes

> **Why provision workers now?** While master-3 is joining, start VM provisioning in vSphere.
> Workers can be configured up to the `kubeadm join` step before Calico is ready.
> Join them to the cluster AFTER Calico CNI is deployed (Step 7).

```
QA WORKER NODE PROVISIONING FLOW
════════════════════════════════════════════════════════════════════

  ┌─────────────────────────────────────────────────────────────┐
  │  vCenter — Clone 3 Worker VMs from OL9 template             │
  └─────────────────────────────┬───────────────────────────────┘
                                │
                     ┌──────────▼──────────────┐
                     │  Power on all 3 workers  │
                     └──────────┬──────────────┘
                                │ (run steps below on EACH worker)
          ┌─────────────────────┼─────────────────────┐
          ▼                     ▼                     ▼
  worker-01 (10.50.1.101)  worker-02 (10.50.1.102)  worker-03 (10.50.1.103)
  ┌────────────────────┐   ┌────────────────────┐   ┌────────────────────┐
  │ ① Set hostname     │   │ ① Set hostname     │   │ ① Set hostname     │
  │ ② Static IP        │   │ ② Static IP        │   │ ② Static IP        │
  │ ③ Disable swap     │   │ ③ Disable swap     │   │ ③ Disable swap     │
  │ ④ Kernel modules   │   │ ④ Kernel modules   │   │ ④ Kernel modules   │
  │ ⑤ sysctl params    │   │ ⑤ sysctl params    │   │ ⑤ sysctl params    │
  │ ⑥ Install containd │   │ ⑥ Install containd │   │ ⑥ Install containd │
  │ ⑦ Install K8s 1.34 │   │ ⑦ Install K8s 1.34 │   │ ⑦ Install K8s 1.34 │
  │ ⑧ kubeadm join     │   │ ⑧ kubeadm join     │   │ ⑧ kubeadm join     │
  │   (after Calico)   │   │   (after Calico)   │   │   (after Calico)   │
  └────────────────────┘   └────────────────────┘   └────────────────────┘
          │                         │                         │
          └─────────────────────────▼─────────────────────────┘
                                    │
                    ┌───────────────▼──────────────────┐
                    │  kubectl get nodes (on master)    │
                    │  NAME                STATUS       │
                    │  k8s-qa-master-01    Ready        │
                    │  k8s-qa-master-02    Ready        │
                    │  k8s-qa-master-03    Ready        │
                    │  k8s-qa-worker-01    Ready  ←new  │
                    │  k8s-qa-worker-02    Ready  ←new  │
                    │  k8s-qa-worker-03    Ready  ←new  │
                    └──────────────────────────────────┘
```

#### Step 6b: Create Worker VMs in vSphere

```bash
# On vCenter jump host — clone 3 QA worker VMs
# WHY clone from template: Ensures identical OS baseline; faster than manual install
# VM Specs: 12 vCPU / 48 GB RAM / 200 GB disk (buffered for future growth)

for i in 01 02 03; do
  govc vm.clone \
    -vm    "/Datacenter/vm/Templates/ol9-k8s-template" \
    -ds    "vsanDatastore" \
    -pool  "/Datacenter/host/VxRail-Cluster/Resources/QA-Workers" \
    -net   "VLAN-100-QA" \
    -name  "k8s-qa-worker-${i}" \
    -m     49152 \         # 48 GB RAM (12 × 4 GB pages; buffered vs 32 GB baseline)
    -c     12 \            # 12 vCPUs (50% buffer over 8 vCPU minimum)
    -disk  "200GB" \       # 200 GB thin-provisioned (vs 100 GB baseline; holds 3yr of images/logs)
    -on=false

  echo "✅ VM created: k8s-qa-worker-${i}"
done

# Add anti-affinity rule — each worker on a different physical VxRail host
# WHY: If one host fails, not all workers go down simultaneously
govc cluster.rule.create \
  -name "qa-worker-anti-affinity" \
  -enable \
  -affinity=false \
  "k8s-qa-worker-01" "k8s-qa-worker-02" "k8s-qa-worker-03"

# Power on all workers
for i in 01 02 03; do
  govc vm.power -on "k8s-qa-worker-${i}"
  echo "⏳ Powering on k8s-qa-worker-${i}..."
done
echo "✅ All 3 QA workers powered on"
```

#### Step 6c: Configure Each Worker Node OS

> Run the following on **each worker** (k8s-qa-worker-01, 02, 03).
> Change `NODE_NUM` and `NODE_IP` for each node.

```bash
# ──────────────────────────────────────────────────
# VARIABLES — change per node:
#   worker-01: NODE_NUM=01  NODE_IP=10.50.1.101
#   worker-02: NODE_NUM=02  NODE_IP=10.50.1.102
#   worker-03: NODE_NUM=03  NODE_IP=10.50.1.103
# ──────────────────────────────────────────────────
NODE_NUM="01"
NODE_IP="10.50.1.101"
GATEWAY="10.50.0.1"
DNS_PRIMARY="10.20.0.53"      # Internal DNS server
HOSTNAME="k8s-qa-worker-${NODE_NUM}"

# ── STEP 1: Set Hostname ──
hostnamectl set-hostname "${HOSTNAME}"
echo "✅ Hostname set to: $(hostname)"

# ── STEP 2: Configure Static IP ──
# WHY static IP: K8s node registration uses IP; DHCP leases can change after reboot
# and break cluster communication
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
dns=${DNS_PRIMARY};8.8.8.8
EOF

chmod 600 /etc/NetworkManager/system-connections/eth0.nmconnection
nmcli connection reload
nmcli connection up eth0
echo "✅ Static IP configured: ${NODE_IP}"

# Add /etc/hosts entries for all cluster nodes (local resolution fallback)
# WHY: If DNS is briefly unavailable, K8s nodes still reach each other
cat >> /etc/hosts << EOF

# VxRail K8s QA Cluster
10.50.0.10   k8s-qa-master-01
10.50.0.11   k8s-qa-master-02
10.50.0.12   k8s-qa-master-03
10.50.0.100  k8s-qa-api   k8s-qa-api.internal   # HA VIP
10.50.1.101  k8s-qa-worker-01
10.50.1.102  k8s-qa-worker-02
10.50.1.103  k8s-qa-worker-03
EOF

# ── STEP 3: Disable Swap ──
# WHY REQUIRED by Kubernetes: K8s scheduler makes resource decisions based on
# actual memory; swap makes memory limits unreliable and causes OOMKiller storms
swapoff -a
# Make permanent across reboots
sed -i '/swap/d' /etc/fstab
echo "✅ Swap disabled permanently"

# ── STEP 4: Load Kernel Modules ──
# WHY overlay: containerd uses overlayfs for container layer storage
# WHY br_netfilter: iptables needs to see bridged traffic for K8s pod networking
cat > /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter
echo "✅ Kernel modules loaded: overlay, br_netfilter"

# Verify modules loaded
lsmod | grep -E "overlay|br_netfilter"

# ── STEP 5: Configure sysctl (Kernel Network Parameters) ──
# WHY net.bridge.*: Without these, iptables rules for K8s NetworkPolicy
# don't apply to bridged traffic between pods
# WHY ip_forward: Allows the node to forward packets between pod network
# and external network (required for pod-to-internet traffic)
cat > /etc/sysctl.d/99-k8s.conf << EOF
# Kubernetes required settings
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1

# Performance tuning for worker nodes
vm.overcommit_memory = 1          # Allow K8s to overcommit memory (needed by scheduler)
kernel.panic         = 10         # Auto-reboot on kernel panic (avoid stuck node)
kernel.panic_on_oops = 1          # Treat kernel oops as panic (safer for cluster)
net.core.somaxconn   = 32768      # Larger connection queue for high-traffic pods
net.ipv4.tcp_max_syn_backlog = 8096
fs.inotify.max_user_instances = 8192   # For many pods watching config files
fs.inotify.max_user_watches   = 524288 # Required by many K8s operators
EOF

sysctl --system
echo "✅ sysctl parameters applied"

# ── STEP 6: Install containerd ──
# WHY containerd: CRI (Container Runtime Interface) required by K8s 1.34
# containerd replaced Docker as the preferred runtime since K8s 1.24
dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
dnf install -y containerd.io

# Generate default config
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# Enable SystemdCgroup — REQUIRED for Oracle Linux 9 (uses systemd cgroup driver)
# WHY: If kubelet uses systemd but containerd uses cgroupfs, there will be resource
# accounting conflicts and pods will fail with cgroup errors
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl enable containerd --now
systemctl status containerd --no-pager | grep -E "Active|Main"
echo "✅ containerd installed and running"

# ── STEP 7: Install Kubernetes 1.34 ──
# WHY specific version: Pin to 1.34.x to match master nodes exactly
# Mismatched versions cause API compatibility issues
cat > /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.34/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.34/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

# Install K8s packages (pinned to 1.34)
dnf install -y --disableexcludes=kubernetes \
  kubelet-1.34.0 \
  kubeadm-1.34.0 \
  kubectl-1.34.0

# Enable kubelet (don't start yet — kubeadm join starts it)
# WHY enable but not start: kubelet without a cluster config will crash-loop
systemctl enable kubelet
echo "✅ Kubernetes 1.34 installed (kubelet enabled, not started yet)"

# Verify versions
kubeadm version
kubelet --version
kubectl version --client

echo ""
echo "✅ Worker node ${HOSTNAME} (${NODE_IP}) is ready for kubeadm join"
echo "   Wait until Calico CNI is deployed on masters before joining!"
```

#### Step 6d: Join Worker Nodes to QA Cluster

> **Important:** Run this ONLY after Step 7 (Calico CNI) is deployed and pods are Ready.
> Workers that join before CNI show `NotReady` and pods will be stuck `Pending`.

```bash
# On k8s-qa-master-01 — generate a fresh join token
# WHY fresh token: default tokens expire after 24h; always generate new one
JOIN_CMD=$(kubeadm token create --print-join-command)
echo "Join command:"
echo "${JOIN_CMD}"
# Example:
# kubeadm join 10.50.0.100:6443 --token abc123xyz \
#   --discovery-token-ca-cert-hash sha256:a1b2c3...

# ── On EACH worker node (01, 02, 03) — run the join command ──
# Replace with actual token from master output
kubeadm join 10.50.0.100:6443 \
  --token <token-from-master> \
  --discovery-token-ca-cert-hash sha256:<hash-from-master> \
  --cri-socket unix:///run/containerd/containerd.sock \
  --node-name $(hostname)

# Expected output on each worker:
# [preflight] Running pre-flight checks
# [preflight] Reading configuration from the cluster...
# [kubelet-start] Starting the kubelet
# [kubelet-start] Waiting for the kubelet to perform the TLS Bootstrap...
# This node has joined the cluster:
# * Certificate signing request was sent to apiserver and a response was received.
# * The Kubelet was informed of the new secure connection details.

# ── On k8s-qa-master-01 — verify all nodes joined ──
kubectl get nodes -o wide
# Expected (after ~60 seconds for CNI to initialize on each worker):
# NAME                  STATUS   ROLES           AGE    VERSION   INTERNAL-IP
# k8s-qa-master-01     Ready    control-plane   1d     v1.34.0   10.50.0.10
# k8s-qa-master-02     Ready    control-plane   1d     v1.34.0   10.50.0.11
# k8s-qa-master-03     Ready    control-plane   1d     v1.34.0   10.50.0.12
# k8s-qa-worker-01     Ready    <none>          5m     v1.34.0   10.50.1.101
# k8s-qa-worker-02     Ready    <none>          4m     v1.34.0   10.50.1.102
# k8s-qa-worker-03     Ready    <none>          3m     v1.34.0   10.50.1.103

# Label worker nodes (for pod scheduling via nodeSelector / nodeAffinity)
for i in 01 02 03; do
  kubectl label node "k8s-qa-worker-${i}" \
    node-role.kubernetes.io/worker="" \
    environment=qa \
    workload-type=application
done

# Taint master nodes — prevent non-system pods from landing on masters
# WHY: Masters run etcd + API server; workload pods compete for resources
for master in k8s-qa-master-01 k8s-qa-master-02 k8s-qa-master-03; do
  kubectl taint nodes "${master}" \
    node-role.kubernetes.io/control-plane:NoSchedule --overwrite
done

# Apply resource reservations to protect node OS/kubelet from pod starvation
# WHY: Without reservations, a misbehaving pod can consume all node memory
# and crash kubelet itself, making the node NotReady
cat > /tmp/kubelet-config-patch.yaml << 'EOF'
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
systemReserved:
  cpu: 500m       # Reserve 0.5 CPU core for OS and kubelet
  memory: 1Gi     # Reserve 1 GB for OS processes
kubeReserved:
  cpu: 500m       # Reserve 0.5 CPU for kubelet and K8s components
  memory: 2Gi     # Reserve 2 GB for kubelet, container runtime
evictionHard:
  memory.available: "500Mi"     # Start evicting pods if < 500 MB free
  nodefs.available: "10%"       # Evict if disk < 10% free
  nodefs.inodesFree: "5%"       # Evict if inodes < 5% free
evictionSoft:
  memory.available: "1Gi"       # Warn if < 1 GB free
evictionSoftGracePeriod:
  memory.available: "2m"        # Allow 2 min before hard eviction
maxPods: 110      # Default; increase to 250 for high-density workers if needed
EOF
# Apply on each worker by placing in /var/lib/kubelet/config.yaml
# (Consult kubeadm docs for patching kubelet config post-join)

# Verify cluster health — all 6 nodes should be Ready
kubectl get nodes
kubectl get pods -A | grep -v Running | grep -v Completed
# Only system pods should exist; no pending/failed pods
echo "✅ QA cluster complete: 3 masters + 3 workers"
```

---

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
# - Storage: 600 GB (data 500GB + OS/log 100GB — with buffer)
# - Network: VLAN 30 (10.30.0.0/24)
# - IP: 10.30.0.100

# Install PostgreSQL on OL9
sudo dnf install -y postgresql15-server postgresql15-contrib

# Initialize database
sudo /usr/pgsql-15/bin/postgresql-15-setup initdb

# Configure for network access
sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /var/lib/pgsql/15/data/postgresql.conf

# Configure pg_hba.conf for network access
echo "host    all             all             10.50.0.0/16            md5" | sudo tee -a /var/lib/pgsql/15/data/pg_hba.conf

# Start PostgreSQL
sudo systemctl enable postgresql-15
sudo systemctl start postgresql-15

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
   - Check: `sudo systemctl status postgresql-15` (service running?)
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

