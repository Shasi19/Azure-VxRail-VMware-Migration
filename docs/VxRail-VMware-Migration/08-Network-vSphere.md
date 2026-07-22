# Network Configuration — VMware DVS on VxRail

## Overview

VxRail comes with a pre-configured Distributed Virtual Switch (DVS) managed by vCenter.
All VM networking is defined through **Port Groups** on this DVS — no per-host config needed.

```
VxRail DVS (Distributed Virtual Switch)
├── Uplink: 25 GbE LACP bonded (vmnic0 + vmnic1 per host)
├── PG-Management    (VLAN 10)  — ESXi/vCenter management
├── PG-K8s-Nodes     (VLAN 20)  — K8s VMs (masters + workers)
├── PG-Databases     (VLAN 30)  — DB VMs
├── PG-Services      (VLAN 40)  — Harbor, MinIO, monitoring
└── (vSAN and vMotion VMkernels use dedicated VLANs 80/90 — pre-configured by VxRail)
```

---

## 1. Create Port Groups on VxRail DVS

### 1.1 Via vCenter UI

```
vCenter → Networking → VxRail-DVS → Actions → Add Distributed Port Group

For each port group:
  Name: PG-K8s-Nodes
  Number of ports: 128
  VLAN type: VLAN
  VLAN ID: 20

  Name: PG-Databases
  VLAN ID: 30

  Name: PG-Services
  VLAN ID: 40
```

### 1.2 Via govc CLI

```bash
export GOVC_URL=https://vcenter.internal.company.com
export GOVC_USERNAME=administrator@vsphere.local
export GOVC_PASSWORD="${VCENTER_PASSWORD}"
export GOVC_DATACENTER=Datacenter

DVS="VxRail-DVS"

# Create port groups
for PG_SPEC in \
  "PG-K8s-Nodes:20" \
  "PG-Databases:30" \
  "PG-Services:40"; do
  
  PG_NAME=$(echo $PG_SPEC | cut -d: -f1)
  VLAN_ID=$(echo $PG_SPEC | cut -d: -f2)
  
  govc dvs.portgroup.add \
    -dvs="${DVS}" \
    -type=earlyBinding \
    -nports=128 \
    -vlan="${VLAN_ID}" \
    "${PG_NAME}"
  
  echo "Created port group: $PG_NAME (VLAN $VLAN_ID)"
done
```

---

## 2. Physical Switch Requirements

VxRail's physical switch (ToR — Top of Rack) must have these VLANs trunked:

```
# On your physical switch (Cisco, Dell, Juniper — adapt syntax):

interface GigabitEthernet1/0/1   # Uplink from VxRail-1
  description VxRail-1-Uplink
  switchport mode trunk
  switchport trunk allowed vlan 10,20,30,40,80,90
  channel-group 1 mode active    # LACP if bonded uplinks

# Repeat for all 6 nodes' uplinks
```

---

## 3. Firewall / Security Group Rules

VxRail DVS supports Port Group security policies. For K8s nodes:

### 3.1 Port Group Security Policy

```
vCenter → PG-K8s-Nodes → Settings → Security
  Promiscuous mode: Reject        (default)
  MAC address changes: Accept     (needed for MetalLB gratuitous ARP)
  Forged transmits: Accept        (needed for MetalLB and keepalived VIPs)
```

> **Important:** MetalLB in ARP mode requires **Forged transmits: Accept** and **MAC address changes: Accept** on the port group, otherwise VIP advertisement will be silently dropped by DVS.

### 3.2 Host-Based Firewall on K8s Nodes (firewalld — Oracle Linux 9)

```bash
# Apply on all K8s nodes — masters and workers
# Run via ssh loop or Ansible
# Oracle Linux 9 uses firewalld, NOT ufw

NODES=(10.0.3.11 10.0.3.12 10.0.3.13 10.0.4.21 10.0.4.22)

for NODE in "${NODES[@]}"; do
ssh oracle@"$NODE" 'sudo bash -s' << 'SCRIPT'
# Enable firewalld
systemctl enable --now firewalld

# SSH from management subnet
firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address="10.0.1.0/24" port port=22 protocol=tcp accept'

# Kubernetes API server
firewall-cmd --permanent --add-port=6443/tcp

# etcd (control plane only)
firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address="10.0.3.0/24" port port="2379-2380" protocol=tcp accept'

# Kubelet API
firewall-cmd --permanent --add-port=10250/tcp

# NodePort services (accessed by load balancer and internal users)
firewall-cmd --permanent --add-port=30000-32767/tcp

# Calico BGP + VXLAN
firewall-cmd --permanent --add-port=179/tcp
firewall-cmd --permanent --add-port=4789/udp
firewall-cmd --permanent --add-port=5473/tcp

# MetalLB member communication
firewall-cmd --permanent --add-port=7946/tcp
firewall-cmd --permanent --add-port=7946/udp

# Allow all inter-node traffic within K8s subnets
firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address="10.0.3.0/24" accept'
firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address="10.0.4.0/24" accept'
firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address="192.168.0.0/16" accept'
firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address="10.96.0.0/12" accept'

# VRRP for keepalived
firewall-cmd --permanent --add-rich-rule='rule protocol value="vrrp" accept'

firewall-cmd --reload
firewall-cmd --list-all
SCRIPT
done
```

---

## 4. keepalived — K8s API VIP (10.0.3.100)

The Kubernetes API server VIP floats across the 3 control plane VMs.

### 4.1 Install on All 3 Masters

```bash
# On master-1, master-2, master-3
sudo apt install -y keepalived

# Configure keepalived — run on EACH master, changing PRIORITY and STATE
# master-1: MASTER, priority 101
# master-2: BACKUP, priority 100
# master-3: BACKUP, priority 99
```

### 4.2 keepalived Config (master-1)

```bash
sudo tee /etc/keepalived/keepalived.conf << 'EOF'
! Configuration for k8s-master-1
global_defs {
  router_id k8s-master-1
}

vrrp_script chk_apiserver {
  script "/usr/bin/curl -sk https://localhost:6443/healthz -o /dev/null && exit 0 || exit 1"
  interval 3
  timeout 10
  fall 2
  rise 2
}

vrrp_instance k8s-vip {
  state MASTER            # BACKUP on master-2 and master-3
  interface ens192        # VMware VMXNET3 NIC on vSphere
  virtual_router_id 51
  priority 101            # 100 on master-2, 99 on master-3
  authentication {
    auth_type PASS
    auth_pass K8sVIPauth2026!
  }
  virtual_ipaddress {
    10.0.3.100/24 dev ens192
  }
  track_script {
    chk_apiserver
  }
}
EOF

sudo systemctl enable keepalived
sudo systemctl start keepalived
```

---

## 5. MetalLB — LoadBalancer Services

MetalLB provides `LoadBalancer` type Services in the bare-metal Kubernetes cluster.

### 5.1 Install MetalLB

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=120s
```

### 5.2 Configure IP Pool and L2 Advertisement

```yaml
# metallb-config.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: k8s-lb-pool
  namespace: metallb-system
spec:
  addresses:
    - 10.0.4.200-10.0.4.220    # IPs advertised by MetalLB on PG-K8s-Nodes VLAN 20
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: k8s-l2-advert
  namespace: metallb-system
spec:
  ipAddressPools:
    - k8s-lb-pool
  interfaces:
    - ens192    # VMware VMXNET3 interface on all K8s nodes
```

```bash
kubectl apply -f metallb-config.yaml
```

> **VMware Requirement:** Port Group `PG-K8s-Nodes` must have **Forged Transmits** and **MAC Address Changes** set to **Accept** (see section 3.1).

---

## 6. Internal DNS Setup

All on-prem VMs need DNS entries. Add these records to your internal DNS server:

```bash
# Add to /etc/bind/db.internal.company.com (or your DNS provider)
# K8s control plane
k8s-master-1        IN A  10.0.3.11
k8s-master-2        IN A  10.0.3.12
k8s-master-3        IN A  10.0.3.13
k8s-api             IN A  10.0.3.100   ; VIP

# K8s workers
k8s-worker-1        IN A  10.0.4.21
k8s-worker-2        IN A  10.0.4.22
k8s-worker-3        IN A  10.0.4.23
k8s-worker-4        IN A  10.0.4.24
k8s-worker-5        IN A  10.0.4.25
k8s-worker-6        IN A  10.0.4.26

# Databases
db-dev-01           IN A  10.0.5.11
db-qa-01            IN A  10.0.5.12
db-preprod-01       IN A  10.0.5.13
db-preprod-02       IN A  10.0.5.14
db-prod-01          IN A  10.0.5.15
db-prod-02          IN A  10.0.5.16
db-prod-03          IN A  10.0.5.17
mongo-dev-01        IN A  10.0.5.21
mongo-qa-01         IN A  10.0.5.22
mongo-preprod-01    IN A  10.0.5.23
mongo-preprod-02    IN A  10.0.5.24
mongo-prod-01       IN A  10.0.5.25
mongo-prod-02       IN A  10.0.5.26
mongo-prod-03       IN A  10.0.5.27

# Services
harbor              IN A  10.0.6.12
minio               IN A  10.0.6.11
monitoring          IN A  10.0.6.13

# App endpoints (MetalLB IPs)
app-dev             IN A  10.0.4.200
app-qa              IN A  10.0.4.201
app-preprod         IN A  10.0.4.202
app-prod            IN A  10.0.4.210
```

---

## 7. Troubleshooting Network

| Problem | Check | Fix |
|---------|-------|-----|
| VMs can't reach each other | `ping` between VMs; check VLAN on port group | Ensure same VLAN on source/dest port groups; check physical switch VLAN trunk |
| MetalLB VIP not responding | `arping -I ens192 10.0.4.200` from worker | Set Forged Transmits=Accept on DVS port group |
| keepalived VIP not floating | `journalctl -u keepalived`; `ip addr show ens192` | Check VRRP priority; ensure `virtual_router_id` matches on all 3 masters |
| K8s nodes can't reach API VIP | `curl -k https://10.0.3.100:6443/healthz` | Check keepalived on masters; check ufw allows 6443 |
| DNS not resolving | `nslookup k8s-master-1.internal.company.com` | Check `/etc/resolv.conf`; verify cloud-init network-config DNS setting |
| vSAN traffic hitting VM NIC | Check VMkernel vmk1 has VLAN 90 and dedicated vmnic | Use vCenter Network I/O Control to prioritize vSAN traffic |
