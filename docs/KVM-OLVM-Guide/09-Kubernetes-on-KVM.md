# 09 — Kubernetes on KVM/OLVM

> Deploy a production Kubernetes cluster inside KVM VMs (managed by OLVM). This replicates AKS — Azure's managed Kubernetes service — entirely on-premises.

---

## Architecture

```
OLVM LAYER (VM management)
  ├── kvm-host-01    running: k8s-cp-01, k8s-wk-01, k8s-wk-02
  ├── kvm-host-02    running: k8s-cp-02, k8s-wk-03, k8s-wk-04
  └── kvm-host-03    running: k8s-cp-03, k8s-wk-05, k8s-wk-06

K8S LAYER (inside VMs)
  ├── Control Planes (3 VMs)
  │   k8s-cp-01 (10.0.1.10)  k8s-cp-02 (10.0.1.11)  k8s-cp-03 (10.0.1.12)
  │   ↕ HAProxy VIP: 10.0.1.5:6443
  └── Workers (6 VMs)
      k8s-wk-01..06 (10.0.1.20-25)
      ├── namespace: dev      (wk-01)
      ├── namespace: qa       (wk-02, wk-03)
      ├── namespace: preprod  (wk-04)
      └── namespace: prod     (wk-05, wk-06)
```

---

## Step 1: Provision K8s VMs in OLVM

### Option A: Via OLVM Web UI

```
Screenshot: Compute > Virtual Machines > New VM

Create each VM with these settings:
  Template: Blank
  OS: Ubuntu 22.04 (or Red Hat Enterprise Linux 9)
  Memory: 16384 MB (control plane) / 65536 MB (worker)
  vCPU: 8 (control plane) / 16 (worker)
  Disk:
    - Interface: VirtIO-SCSI
    - Size: 100 GB (CP) / 200 GB (worker)
    - Storage Domain: netapp-data
    - Disk Type: Pre-allocated (performance)
  Network: vm-network (VLAN 100)
  High Availability: Yes (for workers), No (control plane — managed by K8s itself)
```

### Option B: OLVM REST API (Batch Creation)

```bash
BASE_URL="https://olvm-engine.internal/ovirt-engine/api"
AUTH="admin@internal:OLVMAdmin2026!"

# Function to create VM via OLVM API
create_vm() {
  local NAME=$1 VCPUS=$2 MEM_MB=$3 DISK_GB=$4
  
  cat > /tmp/vm-payload.xml << EOF
<vm>
  <name>${NAME}</name>
  <cluster><name>OnPrem-Cluster</name></cluster>
  <template><name>Blank</name></template>
  <os><type>other_linux</type></os>
  <cpu><topology sockets="1" cores="${VCPUS}" threads="2"/></cpu>
  <memory>$((MEM_MB * 1024 * 1024))</memory>
  <high_availability><enabled>true</enabled></high_availability>
</vm>
EOF
  
  VM_ID=$(curl -sk -u "$AUTH" \
    -X POST "$BASE_URL/vms" \
    -H "Content-Type: application/xml" \
    -d @/tmp/vm-payload.xml | \
    grep -oP '(?<=<vm id=")[^"]+')
  
  echo "Created VM: $NAME (ID: $VM_ID)"
  
  # Add disk
  curl -sk -u "$AUTH" \
    -X POST "$BASE_URL/vms/$VM_ID/diskattachments" \
    -H "Content-Type: application/xml" \
    -d "<disk_attachment>
          <bootable>true</bootable>
          <interface>virtio_scsi</interface>
          <disk>
            <name>${NAME}-os</name>
            <format>raw</format>
            <provisioned_size>$((DISK_GB * 1024 * 1024 * 1024))</provisioned_size>
            <storage_domains><storage_domain><name>netapp-data</name></storage_domain></storage_domains>
          </disk>
        </disk_attachment>" > /dev/null
  
  echo "Disk attached to $NAME"
}

# Create all K8s VMs
create_vm k8s-cp-01 8 16384 100
create_vm k8s-cp-02 8 16384 100
create_vm k8s-cp-03 8 16384 100
create_vm k8s-wk-01 16 65536 200
create_vm k8s-wk-02 16 65536 200
create_vm k8s-wk-03 16 65536 200
create_vm k8s-wk-04 16 65536 200
create_vm k8s-wk-05 16 65536 200
create_vm k8s-wk-06 16 65536 200
```

---

## Step 2: Configure VMs for Kubernetes

Run on **every K8s VM** (SSH in after OS installation):

```bash
# Disable swap (mandatory for K8s)
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/' /etc/fstab

# Load kernel modules
cat > /etc/modules-load.d/k8s.conf << 'EOF'
br_netfilter
overlay
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
EOF

for mod in br_netfilter overlay ip_vs ip_vs_rr ip_vs_wrr ip_vs_sh; do
  modprobe $mod
done

# Sysctl parameters
cat > /etc/sysctl.d/k8s.conf << 'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.netfilter.nf_conntrack_max      = 524288
EOF
sysctl --system

# Install containerd (container runtime)
# Ubuntu:
apt install -y containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd

# RHEL/OL:
# dnf install -y containerd
# (same config steps above)
```

---

## Step 3: Set Up HA Load Balancer (keepalived + HAProxy)

Run on **all 3 control plane VMs**:

```bash
# Ubuntu:
apt install -y haproxy keepalived
# RHEL/OL:
dnf install -y haproxy keepalived

# HAProxy config (identical on all 3 CPs)
cat >> /etc/haproxy/haproxy.cfg << 'EOF'
frontend k8s-api
    bind *:6443
    mode tcp
    default_backend k8s-control-planes

backend k8s-control-planes
    mode tcp
    balance roundrobin
    option tcp-check
    server cp01 10.0.1.10:6443 check fall 3 rise 2
    server cp02 10.0.1.11:6443 check fall 3 rise 2
    server cp03 10.0.1.12:6443 check fall 3 rise 2
EOF
systemctl enable --now haproxy

# keepalived — floating VIP 10.0.1.5

# On k8s-cp-01 (MASTER):
cat > /etc/keepalived/keepalived.conf << 'EOF'
global_defs {
  notification_email {
    admin@company.com
  }
  router_id K8S_VIP
}

vrrp_script check_haproxy {
  script "killall -0 haproxy"
  interval 2
  weight 2
}

vrrp_instance VI_K8S {
  state MASTER
  interface enp1s0     # change to your network interface name
  virtual_router_id 51
  priority 110
  advert_int 1
  authentication {
    auth_type PASS
    auth_pass K8sVIP2026
  }
  virtual_ipaddress {
    10.0.1.5/24
  }
  track_script {
    check_haproxy
  }
}
EOF

# On k8s-cp-02: change state=BACKUP, priority=100
# On k8s-cp-03: change state=BACKUP, priority=90

systemctl enable --now keepalived

# Verify VIP is up on cp-01
ip addr show enp1s0 | grep 10.0.1.5
```

---

## Step 4: Install kubeadm, kubelet, kubectl

Run on **all 9 K8s VMs**:

```bash
# Ubuntu / Debian
apt install -y apt-transport-https ca-certificates curl gpg

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | \
  gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' \
  > /etc/apt/sources.list.d/kubernetes.list

apt update
apt install -y kubelet=1.29.* kubeadm=1.29.* kubectl=1.29.*
apt-mark hold kubelet kubeadm kubectl
systemctl enable kubelet

# RHEL / Oracle Linux
cat > /etc/yum.repos.d/kubernetes.repo << 'EOF'
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key
EOF

dnf install -y kubelet-1.29.* kubeadm-1.29.* kubectl-1.29.*
dnf versionlock add kubelet kubeadm kubectl
systemctl enable kubelet
```

---

## Step 5: Bootstrap the Cluster

```bash
# Run ONLY on k8s-cp-01 first
kubeadm init \
  --control-plane-endpoint "10.0.1.5:6443" \
  --upload-certs \
  --pod-network-cidr "10.244.0.0/16" \
  --service-cidr "10.96.0.0/12" \
  --kubernetes-version v1.29.0 \
  --node-name k8s-cp-01

# SAVE THE ENTIRE OUTPUT — it contains join commands

# Set up kubectl on cp-01
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

kubectl get nodes
```

---

## Step 6: Install Calico CNI

```bash
# On k8s-cp-01
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

kubectl wait --for=condition=Ready pods -l k8s-app=calico-node \
  -n calico-system --timeout=180s
```

---

## Step 7: Join Other Control Planes and Workers

```bash
# On k8s-cp-02 and k8s-cp-03 (use command from kubeadm init output):
kubeadm join 10.0.1.5:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH> \
  --control-plane \
  --certificate-key <CERT-KEY> \
  --node-name k8s-cp-02

# On each worker (k8s-wk-01 through k8s-wk-06):
kubeadm join 10.0.1.5:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>

# Verify from k8s-cp-01
kubectl get nodes -o wide
```

---

## Step 8: Label Nodes for Multi-Environment Scheduling

```bash
kubectl label node k8s-wk-01 env=dev   workload=app
kubectl label node k8s-wk-02 env=qa    workload=app
kubectl label node k8s-wk-03 env=qa    workload=app
kubectl label node k8s-wk-04 env=preprod workload=app
kubectl label node k8s-wk-05 env=prod  workload=app
kubectl label node k8s-wk-06 env=prod  workload=app

# Taint prod: only pods with toleration=prod:NoSchedule can land here
kubectl taint nodes k8s-wk-05 k8s-wk-06 env=prod:NoSchedule

for NS in dev qa preprod prod; do
  kubectl create namespace $NS
  kubectl label namespace $NS environment=$NS
done
```

---

## Step 9: OLVM HA for K8s VMs

OLVM adds an extra layer: if the KVM host running a K8s worker crashes, OLVM restarts the VM on another host.

```
Screenshot: In OLVM UI > Compute > Virtual Machines > k8s-wk-05 > Edit

High Availability tab:
  Highly Available: YES
  Priority: High (for prod workers)
  Memory guaranteed: 32768 MB (minimum memory never ballooned away)

With fencing configured on KVM hosts, OLVM will:
1. Detect kvm-host-03 is down (watchdog timeout)
2. STONITH (Shoot The Other Node In The Head) via IPMI
3. Restart k8s-wk-05 and k8s-wk-06 on kvm-host-01 or kvm-host-02
4. K8s detects nodes are back up
5. K8s reschedules pods

Total failover: ~3-5 minutes for VM restart + pod reschedule
```

---

## Step 10: Upgrade Kubernetes (Zero Downtime)

```bash
# KVM advantage: snapshot before upgrade
virsh snapshot-create-as k8s-cp-01 "pre-upgrade-1.30" --disk-only --atomic

# Upgrade control planes one at a time
# On k8s-cp-01:
apt-mark unhold kubeadm && apt install -y kubeadm=1.30.* && apt-mark hold kubeadm
kubeadm upgrade plan
kubeadm upgrade apply v1.30.0

apt-mark unhold kubelet kubectl
apt install -y kubelet=1.30.* kubectl=1.30.*
apt-mark hold kubelet kubectl
systemctl daemon-reload && systemctl restart kubelet

# Upgrade workers one at a time (drain first)
kubectl drain k8s-wk-01 --ignore-daemonsets --delete-emptydir-data
ssh admin@10.0.1.20 "apt-mark unhold kubeadm kubelet kubectl && \
  apt install -y kubeadm=1.30.* kubelet=1.30.* kubectl=1.30.* && \
  kubeadm upgrade node && \
  systemctl daemon-reload && systemctl restart kubelet"
kubectl uncordon k8s-wk-01
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Nodes NotReady | CNI not installed | Check `kubectl get pods -n calico-system` |
| VIP not responding | keepalived not running | `systemctl status keepalived`; check `ip addr show enp1s0` |
| Pods stuck Pending | Node taint mismatch | Check `kubectl describe pod <pod>` for taint toleration error |
| K8s node lost after host failure | OLVM didn't restart VM | Check OLVM HA settings; verify fence agent configured |
| etcd leader election looping | Clock skew between nodes | `chronyc tracking` on all nodes; fix NTP |
| kubeadm init fails | Swap not disabled | `swapoff -a`; verify with `free -h` |
| Cannot join cluster | Token expired | Re-run `kubeadm token create --print-join-command` on cp-01 |

---

*Next: [10-OLVM-Backup.md](10-OLVM-Backup.md)*
