# Initial Setup Guide — Everything Before Migration Starts

> **Do ALL of this BEFORE touching Azure or starting migration.** This is your on-prem foundation. Migration depends on every item here being stable.

---

## Setup Order (Dependencies Matter)

```
Step 1  ─── VxRail/vCenter Health Verification
Step 2  ─── Physical Network (ToR switch VLANs)
Step 3  ─── vCenter: Datacenter, Cluster, DVS Port Groups
Step 4  ─── vSAN: Storage Policies
Step 5  ─── Deploy Jump Host VM (management workstation)
Step 6  ─── DNS Server VM
Step 7  ─── NTP Verification
Step 8  ─── Internal CA (TLS Certificates)
Step 9  ─── Azure Connectivity (VPN)
Step 10 ─── VM Template (Oracle Linux 9 cloud image)
Step 11 ─── Create All Phase 1 VMs
Step 12 ─── Install Tools on All VMs
Step 13 ─── Backup Infrastructure
Step 14 ─── Monitoring Baseline (pre-migration)
Step 15 ─── Final Readiness Gate
```

---

## Step 1: VxRail / vCenter Health Verification

Do this before anything else. Your infrastructure must be 100% healthy before adding workloads.

### 1.1 Log in to VxRail Manager

```
URL: https://vxrail-manager.internal.company.com
Default creds: admin / VMware1!  (changed at setup time — get from your IT team)
```

Check:
- All 6 nodes: **Status = Healthy** (green)
- vSAN Health: **All green** (no warnings)
- No pending updates or alerts

### 1.2 Log in to vCenter

```
URL: https://vcenter.internal.company.com/ui
Username: administrator@vsphere.local
Password: (set at VxRail deployment time)
```

Run health checks:

```bash
# From your workstation with govc
export GOVC_URL=https://vcenter.internal.company.com
export GOVC_USERNAME=administrator@vsphere.local
export GOVC_PASSWORD='YourPassword'
export GOVC_INSECURE=0

# Test
govc about

# Check all hosts are connected and not in maintenance mode
govc host.info '*' | grep -E "Name:|State:|Connection"
# All should show: Connection state: connected

# Check vSAN cluster health
govc datastore.info '*' | grep -E "Name:|Type:|Free:|Capacity:"
# vsanDatastore should show healthy free space

# Check existing VMs
govc find . -type m | wc -l
# Note the count — these are existing workloads you must not disrupt
```

### 1.3 Verify vSphere HA and DRS Are Enabled

```bash
# In vCenter UI:
# Cluster > Configure > vSphere Availability > Edit
#   ✅ vSphere HA: ON
#   Admission control: 25% CPU/Memory reserved

# Cluster > Configure > vSphere DRS > Edit
#   ✅ DRS: ON
#   Automation level: Fully Automated (moves VMs automatically on imbalance)
#   Migration threshold: 3 (conservative)
```

---

## Step 2: Physical Network — Configure Switch VLANs

> **Before creating DVS port groups in vCenter, the physical ToR switch must already have VLANs trunked to all VxRail uplinks.**

### 2.1 Identify Your Switch Model and Access

```bash
# Log into your ToR switch CLI
# Dell PowerSwitch example:
ssh admin@switch1.internal.company.com

# Cisco Catalyst example:
ssh admin@switch1.internal.company.com
```

### 2.2 Create VLANs

```
Dell PowerSwitch OS10:
  configure terminal
  vlan 20
    name K8s-Nodes
  vlan 30
    name Databases
  vlan 40
    name Services
  exit

Cisco IOS/IOS-XE:
  vlan 20
    name K8s-Nodes
  vlan 30
    name Databases
  vlan 40
    name Services
```

### 2.3 Trunk VLANs to VxRail Uplink Ports

```
Dell PowerSwitch OS10 (one VxRail node = 2 uplink ports in LACP):

interface ethernet 1/1/1
  description VxRail-1-vmnic0
  no shutdown
  switchport mode trunk
  switchport trunk allowed vlan 10,20,30,40,80,90
  mtu 9216

interface ethernet 1/1/2
  description VxRail-1-vmnic1
  no shutdown
  switchport mode trunk
  switchport trunk allowed vlan 10,20,30,40,80,90
  mtu 9216

port-channel 10
  description VxRail-1-LACP
  switchport mode trunk
  switchport trunk allowed vlan 10,20,30,40,80,90

# Repeat for VxRail-2 through VxRail-6 (port-channels 20-60)
```

### 2.4 Verify VLAN Connectivity

```bash
# Check VLANs are active on switch
show vlan brief         # Dell
show vlan              # Cisco

# Check port-channel is up
show port-channel summary   # both
```

---

## Step 3: vCenter — DVS Port Groups

### 3.1 Create DVS Port Groups for Migration VMs

> **Do NOT touch the existing VxRail DVS system port groups** (Management, vSAN, vMotion). Only ADD new port groups.

```bash
# Use govc to create port groups on the existing VxRail DVS
export GOVC_URL=https://vcenter.internal.company.com
export GOVC_USERNAME=administrator@vsphere.local
export GOVC_PASSWORD='YourPassword'
export GOVC_DATACENTER=Datacenter

# Find your DVS name (it's created by VxRail during setup)
govc find . -type n | grep -i dvs

# Create port groups (replace VxRail-DVS with actual DVS name from above)
DVS_NAME="VxRail-DVS"    # ← Update this

# PG-K8s-Nodes (VLAN 20) — for all K8s master and worker VMs
govc dvs.portgroup.add -dvs="${DVS_NAME}" -type=earlyBinding \
  -nports=256 -vlan=20 "PG-K8s-Nodes"

# PG-Databases (VLAN 30) — for DB VMs
govc dvs.portgroup.add -dvs="${DVS_NAME}" -type=earlyBinding \
  -nports=128 -vlan=30 "PG-Databases"

# PG-Services (VLAN 40) — for Harbor, MinIO, monitoring
govc dvs.portgroup.add -dvs="${DVS_NAME}" -type=earlyBinding \
  -nports=64 -vlan=40 "PG-Services"

# Verify
govc dvs.portgroup.info -dc="Datacenter" "${DVS_NAME}"
```

### 3.2 Configure Port Group Security (Critical for MetalLB)

```bash
# In vCenter UI:
# Networking > VxRail-DVS > PG-K8s-Nodes > Configure > Settings > Security > Edit
#   Promiscuous mode: Reject     (default)
#   MAC address changes: Accept  ← MUST SET (MetalLB ARP)
#   Forged transmits: Accept     ← MUST SET (MetalLB VIP + keepalived)

# Repeat for PG-Databases and PG-Services (less critical but set for consistency)
```

---

## Step 4: vSAN Storage Policies

Create these storage policies in vCenter. They control redundancy and performance of VMs and PVCs.

```
vCenter UI: Policies and Profiles > VM Storage Policies > Create VM Storage Policy

Policy 1: k8s-dev-qa
  Rule 1 (Storage Rule):
    Provider: vSAN
    Failures to tolerate: 0
    Failure tolerance method: RAID-1 (Mirroring)
    Space efficiency: Deduplication and compression
  ✅ Save

Policy 2: k8s-production
  Rule 1 (Storage Rule):
    Provider: vSAN
    Failures to tolerate: 1
    Failure tolerance method: RAID-1 (Mirroring)
  ✅ Save

Policy 3: k8s-databases
  Rule 1 (Storage Rule):
    Provider: vSAN
    Failures to tolerate: 1
    Failure tolerance method: RAID-5/6 (Erasure Coding)
    (Only available if cluster has 4+ nodes — your 6-node cluster qualifies)
  ✅ Save
```

---

## Step 5: Deploy Jump Host VM

The jump host is your management workstation inside the VxRail environment. All govc, kubectl, and Ansible commands run from here.

### 5.1 Create the Jump Host VM via vCenter UI

```
vCenter > New Virtual Machine
  Name: jumphost-01
  Location: /Datacenter/vm/Management
  Host: any VxRail node (e.g., VxRail-1)
  Storage: vsanDatastore, Policy: k8s-dev-qa
  OS: Ubuntu Linux 64-bit
  Hardware:
    CPU: 4 vCPU
    Memory: 8 GB
    Disk: 100 GB (thin provisioned)
    NIC: PG-K8s-Nodes (VLAN 20) or PG-Management (VLAN 10)
```

### 5.2 Install Oracle Linux 9 on Jump Host

```bash
# Attach Oracle Linux 9 ISO via vCenter (upload ISO to vsanDatastore first):
govc datastore.upload -ds=vsanDatastore ubuntu-22.04.4-live-server-amd64.iso iso/ubuntu-22.04.iso

# Set static IP after install: 10.0.1.50 (management VLAN)
# hostname: jumphost-01
# user: ubuntu
```

### 5.3 Install All Management Tools

```bash
# SSH to jumphost-01
ssh oracle@10.0.1.50

# Run the full tools installation
sudo apt update && sudo apt upgrade -y
sudo dnf install -y git curl wget vim htop unzip jq python3-pip \
  net-tools nfs-common sshpass cloud-image-utils

# govc
curl -L -o - "https://github.com/vmware/govmomi/releases/latest/download/govc_Linux_x86_64.tar.gz" \
  | sudo tar -C /usr/local/bin -xvzf - govc

# kubectl 1.29
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list
# Install kubectl (OL9)
curl -LO https://dl.k8s.io/release/v1.29.0/bin/linux/amd64/kubectl
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# k9s — terminal UI for Kubernetes
curl -sS https://webinstall.dev/k9s | bash

# Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# PostgreSQL client
sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
sudo dnf -qy module disable postgresql
sudo dnf install -y postgresql15

# MongoDB tools
wget -qO - https://www.mongodb.org/static/pgp/server-7.0.asc | sudo apt-key add -
echo "deb [ arch=amd64 ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" \
  | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
# MongoDB shell on OL9
sudo tee /etc/yum.repos.d/mongodb-org-7.0.repo << 'REPO'
[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/9/mongodb-org/7.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-7.0.asc
REPO
sudo dnf install -y mongodb-mongosh mongodb-database-tools

# MinIO client
sudo wget https://dl.min.io/client/mc/release/linux-amd64/mc -O /usr/local/bin/mc
sudo chmod +x /usr/local/bin/mc

# Ansible
sudo dnf install -y ansible

# Velero
VELERO_VERSION=v1.13.0
curl -fsSL https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VERSION}/velero-${VELERO_VERSION}-linux-amd64.tar.gz \
  | sudo tar -C /usr/local/bin -xzf - --strip-components=1 velero-${VELERO_VERSION}-linux-amd64/velero

echo "All tools installed."
```

### 5.4 Generate SSH Key Pair

```bash
# On jumphost — this key goes to all VxRail VMs
ssh-keygen -t ed25519 -C "vxrail-migration-key" -f ~/.ssh/vxrail_key -N ""
cat ~/.ssh/vxrail_key.pub
# Copy this public key — add to cloud-init user-data for all VMs
```

---

## Step 6: DNS Server VM

Internal DNS is critical. Without it, Kubernetes nodes cannot resolve each other, etcd breaks, and cert-manager cannot issue certs.

### 6.1 Create DNS VM

```bash
# Quick VM via govc
govc vm.clone \
  --vm="ubuntu-22.04-template" \
  --name="dns-01" \
  --host="vxrail-1.internal.company.com" \
  --datastore=vsanDatastore \
  --on=false
govc vm.change --vm="dns-01" --cpu=2 --memory=2048
```

### 6.2 Install BIND9 (DNS Server)

```bash
# On dns-01 VM (IP: 10.0.1.5)
ssh oracle@10.0.1.5

sudo dnf install -y bind bind-utils

# Main config — forward zone
sudo tee /etc/bind/named.conf.local << 'EOF'
zone "internal.company.com" {
    type master;
    file "/etc/bind/db.internal.company.com";
};

zone "0.10.in-addr.arpa" {
    type master;
    file "/etc/bind/db.10.0.reverse";
};
EOF

# Forward zone file
sudo tee /etc/bind/db.internal.company.com << 'EOF'
$TTL 300
@   IN SOA dns-01.internal.company.com. admin.company.com. (
        2026072201 ; Serial
        300        ; Refresh
        60         ; Retry
        604800     ; Expire
        300 )      ; Minimum TTL

; Name Servers
@   IN NS dns-01.internal.company.com.

; Infrastructure
dns-01          IN A 10.0.1.5
jumphost-01     IN A 10.0.1.50
vcenter         IN A 10.0.1.10   ; vCenter IP

; K8s Control Plane
k8s-master-1    IN A 10.0.3.11
k8s-master-2    IN A 10.0.3.12
k8s-master-3    IN A 10.0.3.13
k8s-api         IN A 10.0.3.100  ; VIP

; K8s Workers
k8s-worker-1    IN A 10.0.4.21
k8s-worker-2    IN A 10.0.4.22
k8s-worker-3    IN A 10.0.4.23
k8s-worker-4    IN A 10.0.4.24
k8s-worker-5    IN A 10.0.4.25
k8s-worker-6    IN A 10.0.4.26

; Databases
db-dev-01       IN A 10.0.5.11
db-qa-01        IN A 10.0.5.12
db-preprod-01   IN A 10.0.5.13
db-preprod-02   IN A 10.0.5.14
db-prod-01      IN A 10.0.5.15
db-prod-02      IN A 10.0.5.16
db-prod-03      IN A 10.0.5.17
mongo-dev-01    IN A 10.0.5.21
mongo-qa-01     IN A 10.0.5.22
mongo-preprod-01 IN A 10.0.5.23
mongo-preprod-02 IN A 10.0.5.24
mongo-prod-01   IN A 10.0.5.25
mongo-prod-02   IN A 10.0.5.26
mongo-prod-03   IN A 10.0.5.27

; Services
minio-01        IN A 10.0.6.11
harbor-01       IN A 10.0.6.12
monitoring-01   IN A 10.0.6.13

; App endpoints (MetalLB IPs)
app-dev         IN A 10.0.4.200
app-qa          IN A 10.0.4.201
app-preprod     IN A 10.0.4.202
app-prod        IN A 10.0.4.210

; CNAME shortcuts
harbor          IN CNAME harbor-01
minio           IN CNAME minio-01
monitoring      IN CNAME monitoring-01
argocd          IN CNAME k8s-api
EOF

# Start BIND9
sudo systemctl enable bind9 && sudo systemctl restart bind9
sudo named-checkconf && sudo named-checkzone internal.company.com /etc/bind/db.internal.company.com

# Test
nslookup k8s-master-1.internal.company.com 127.0.0.1
nslookup harbor.internal.company.com 127.0.0.1
```

---

## Step 7: NTP Verification

All VMs need synchronized time. etcd and K8s will break if clocks drift > 2 seconds.

```bash
# On each VM (configure via cloud-init for new VMs)
sudo dnf install -y chrony

sudo tee /etc/chrony/chrony.conf << 'EOF'
# Use your corporate NTP server or public pools
server ntp1.internal.company.com iburst
server time.cloudflare.com iburst
server pool.ntp.org iburst

driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
EOF

sudo systemctl enable chrony && sudo systemctl restart chrony

# Verify sync (should show '*' next to the active source)
chronyc sources -v
chronyc tracking | grep "System time"
```

---

## Step 8: Internal Certificate Authority (TLS for All Services)

Using `step-ca` (Smallstep) — enterprise-grade internal CA, easy to operate.

### 8.1 Deploy step-ca on a Dedicated VM

```bash
# On a small VM: ca-01 (2 vCPU, 4 GB RAM, 50 GB disk, IP: 10.0.1.6)
ssh oracle@10.0.1.6

# Install step CA and CLI
wget https://dl.smallstep.com/gh-release/certificates/gh-release-header/v0.25.0/step-ca_0.25.0_amd64.deb
sudo dpkg -i step-ca_0.25.0_amd64.deb

wget https://dl.smallstep.com/gh-release/cli/gh-release-header/v0.25.0/step_0.25.0_amd64.deb
sudo dpkg -i step_0.25.0_amd64.deb

# Initialize the CA
sudo step ca init \
  --name="VxRail Internal CA" \
  --dns="ca-01.internal.company.com,10.0.1.6" \
  --address=":443" \
  --provisioner="admin@company.com" \
  --deployment-type="standalone"
# Saves certs to ~/.step/

sudo systemctl enable step-ca
sudo systemctl start step-ca
```

### 8.2 Issue Wildcard Certificate for Services

```bash
# On jumphost — get wildcard cert for *.internal.company.com
step ca certificate \
  "*.internal.company.com" \
  wildcard.crt wildcard.key \
  --ca-url=https://ca-01.internal.company.com \
  --root=~/.step/certs/root_ca.crt \
  --san="*.internal.company.com" \
  --san="internal.company.com"

# Store as K8s TLS secret (usable in all namespaces via cert-manager or manual)
kubectl create secret tls wildcard-tls \
  --cert=wildcard.crt \
  --key=wildcard.key \
  --namespace=default
```

### 8.3 Trust the CA on All VMs and Jump Host

```bash
# Ubuntu — trust internal CA
sudo cp ~/.step/certs/root_ca.crt /usr/local/share/ca-certificates/vxrail-internal-ca.crt
sudo update-ca-certificates

# Verify
curl https://harbor.internal.company.com/api/v2.0/health
# Should succeed without -k flag once CA is trusted
```

---

## Step 9: Azure VPN Connectivity

For migration, you need to pull data from Azure to on-prem. Set up a site-to-site VPN.

### 9.1 Create Azure VPN Gateway

```bash
# Run from Azure CLI (on jumphost after az login)
az login

# Create VPN Gateway in Azure (in each environment's VNet, or centrally in Hub)
az network vnet-gateway create \
  --name vpn-gateway-hub \
  --resource-group rg-hub-we-001 \
  --vnet Sub-AFRPS-AF-INT \
  --public-ip-address vpn-gw-pip \
  --gateway-type Vpn \
  --vpn-type RouteBased \
  --sku VpnGw1 \
  --location westeurope

# Note the public IP after creation
az network public-ip show --name vpn-gw-pip --resource-group rg-hub-we-001 \
  --query ipAddress -o tsv
```

### 9.2 Configure On-Prem VPN (on existing firewall or pfSense VM)

```bash
# If using pfSense on a VxRail VM:
# Deploy pfSense OVA on VxRail
# Configure WAN (public IP) and LAN (10.0.1.x)

# IPsec tunnel to Azure:
# Phase 1: IKEv2, AES-256, SHA-256, DH Group 2
# Phase 2: AES-256, SHA-256
# Local subnet: 10.0.0.0/8 (all VxRail VLANs)
# Remote subnet: Azure VNet CIDR (e.g., 10.1.0.0/16)
# Pre-shared key: generate with: openssl rand -hex 32
```

### 9.3 Create Azure Local Network Gateway

```bash
# Configure Azure side with on-prem public IP and subnet
az network local-gateway create \
  --name onprem-local-gw \
  --resource-group rg-hub-we-001 \
  --gateway-ip-address YOUR.ONPREM.PUBLIC.IP \
  --local-address-prefixes 10.0.0.0/8

# Create VPN connection
az network vpn-connection create \
  --name azure-to-onprem \
  --resource-group rg-hub-we-001 \
  --vnet-gateway1 vpn-gateway-hub \
  --local-gateway2 onprem-local-gw \
  --shared-key "YourSharedKey123!"

# Verify connection status (takes 5-10 minutes to establish)
az network vpn-connection show \
  --name azure-to-onprem \
  --resource-group rg-hub-we-001 \
  --query connectionStatus -o tsv
```

### 9.4 Test Azure Connectivity from VxRail

```bash
# From jumphost, test reaching Azure private IPs
ping 10.1.0.4   # Azure VM private IP (example)

# Test PostgreSQL connection over VPN
psql "host=your-dev-pg.postgres.database.azure.com port=5432 user=pgadmin sslmode=require" \
  -c "SELECT version();"

# Test Cosmos DB connection over VPN
mongosh "mongodb://account:key@your-cosmos.mongo.cosmos.azure.com:10255/dev-cosmos?ssl=true"
```

---

## Step 10: VM Template (Oracle Linux 9)

All K8s and DB VMs will be cloned from this template.

```bash
# Download Oracle Linux 9 ISO
wget https://releases.ubuntu.com/22.04/ubuntu-22.04.4-live-server-amd64.iso

# Upload to vSAN
govc datastore.upload -ds=vsanDatastore \
  ubuntu-22.04.4-live-server-amd64.iso iso/ubuntu-22.04.iso

# Create base VM
govc vm.create \
  -c=2 -m=4096 -disk=30GB \
  -net="PG-K8s-Nodes" \
  -g=oracleLinux9_64Guest \
  -on=false \
  ubuntu-22.04-base

# Attach ISO
govc vm.cdrom.add -vm=ubuntu-22.04-base -type=cdrom
govc vm.cdrom.insert -vm=ubuntu-22.04-base -device="CD/DVD drive 1" "vsanDatastore/iso/ubuntu-22.04.iso"

# Power on and install Ubuntu via vCenter console
# During install: set root/ubuntu password, enable SSH, install OpenSSH
govc vm.power -on ubuntu-22.04-base

echo "Complete Ubuntu install via vCenter console, then run post-install steps below"
```

### Post-Install Template Customization

```bash
# SSH to the base VM after Ubuntu install
ssh oracle@10.0.1.100   # temporary IP during template setup

# Install VMware Tools and cloud-init
sudo apt update && sudo apt upgrade -y
sudo dnf install -y open-vm-tools cloud-init cloud-utils-growpart

# Configure cloud-init datasources (VMware uses OVF or ConfigDrive)
sudo tee /etc/cloud/cloud.cfg.d/99-vxrail.cfg << 'EOF'
datasource_list: ['OVF', 'ConfigDrive', 'None']
EOF

# Install baseline packages all VMs need
sudo dnf install -y \
  curl wget vim htop net-tools nfs-common \
  chrony ufw fail2ban \
  python3-pip socat conntrack

# Configure NTP (point to your DNS server that has NTP)
sudo tee /etc/chrony/chrony.conf << 'EOF'
server 10.0.1.5 iburst
server pool.ntp.org iburst
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
EOF
sudo systemctl enable chrony

# Harden SSH
sudo sed -i 's/#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# Clean cloud-init so it re-runs on clone
sudo cloud-init clean --logs
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id
sudo ln -s /etc/machine-id /var/lib/dbus/machine-id

# Shutdown cleanly
sudo shutdown -h now
```

### Convert to vCenter Template

```bash
# After VM is powered off
govc vm.markastemplate ubuntu-22.04-base
```

---

## Step 11: Ansible Inventory for Parallel Node Setup

Once VMs are created, use Ansible to configure all nodes at once.

### 11.1 Create Ansible Inventory

```ini
# /etc/ansible/hosts  (on jumphost)

[k8s_masters]
10.0.3.11 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/vxrail_key hostname=k8s-master-1
10.0.3.12 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/vxrail_key hostname=k8s-master-2
10.0.3.13 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/vxrail_key hostname=k8s-master-3

[k8s_workers_phase1]
10.0.4.21 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/vxrail_key hostname=k8s-worker-1
10.0.4.22 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/vxrail_key hostname=k8s-worker-2

[k8s_nodes:children]
k8s_masters
k8s_workers_phase1

[databases_phase1]
10.0.5.11 ansible_user=ubuntu hostname=db-dev-01
10.0.5.12 ansible_user=ubuntu hostname=db-qa-01
10.0.5.21 ansible_user=ubuntu hostname=mongo-dev-01
10.0.5.22 ansible_user=ubuntu hostname=mongo-qa-01

[services]
10.0.6.11 ansible_user=ubuntu hostname=minio-01
10.0.6.12 ansible_user=ubuntu hostname=harbor-01
10.0.6.13 ansible_user=ubuntu hostname=monitoring-01
```

### 11.2 Test Connectivity

```bash
# From jumphost
ansible all -m ping -i /etc/ansible/hosts

# Set hostnames in parallel
ansible all -i /etc/ansible/hosts -m shell \
  -a "hostnamectl set-hostname {{ hostname }}.internal.company.com" \
  --become

# Verify NTP sync on all nodes
ansible all -i /etc/ansible/hosts -m shell \
  -a "chronyc tracking | grep 'System time'" --become
```

---

## Step 12: vSphere CSI Prerequisites

Before K8s install, enable `disk.EnableUUID` on ALL VMs:

```bash
#!/bin/bash
# enable-disk-uuid.sh — run BEFORE powering on VMs for K8s

ALL_VMS=(
  "k8s-master-1" "k8s-master-2" "k8s-master-3"
  "k8s-worker-1" "k8s-worker-2"
  "k8s-worker-3" "k8s-worker-4" "k8s-worker-5" "k8s-worker-6"
)

for VM in "${ALL_VMS[@]}"; do
  echo "Enabling disk.EnableUUID on $VM..."
  govc vm.change -dc="Datacenter" -vm="$VM" \
    -e "disk.EnableUUID=TRUE"
  echo "  Done: $VM"
done
echo "All VMs have disk.EnableUUID=TRUE"
```

---

## Step 13: Backup Infrastructure

Set up backup BEFORE migration — you need to test backup/restore as part of validation.

### 13.1 NFS Share for Backups (on NAS)

```bash
# On your NAS — create NFS export
# Synology: Control Panel > Shared Folder > Create "k8s-backups"
# Then: File Services > NFS > Enable NFS > Edit "k8s-backups" > Add NFS rule

# On minio-01 VM — mount NFS backup share
sudo mkdir -p /backup/nfs
echo "10.0.1.100:/k8s-backups  /backup/nfs  nfs  rw,hard,intr,_netdev  0 0" \
  | sudo tee -a /etc/fstab
sudo mount -a
df -h /backup/nfs
```

### 13.2 Configure Velero (K8s backup — install AFTER K8s is up)

```bash
# MinIO bucket for Velero (already created in 09-Storage-vSAN.md)
mc alias set vxrail http://10.0.6.11:9000 minio-admin MinIO@VxRail2026!
mc mb vxrail/velero-backup

# Install Velero into K8s cluster
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.9.0 \
  --bucket velero-backup \
  --secret-file /tmp/velero-credentials \
  --use-volume-snapshots=true \
  --backup-location-config \
    region=minio,s3ForcePathStyle=true,s3Url=http://10.0.6.11:9000 \
  --snapshot-location-config \
    region=minio,s3ForcePathStyle=true,s3Url=http://10.0.6.11:9000

# Test backup
velero backup create test-backup --include-namespaces=dev --wait
velero backup describe test-backup
velero backup logs test-backup
```

---

## Step 14: Pre-Migration Baseline Monitoring

Deploy Prometheus + Grafana BEFORE migration to capture baseline metrics.

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set prometheus.prometheusSpec.retention=90d \
  --set grafana.adminPassword=Grafana@VxRail2026! \
  --set grafana.service.type=LoadBalancer \
  --set prometheus.service.type=LoadBalancer

# Get Grafana URL
kubectl get svc -n monitoring kube-prometheus-stack-grafana

# Import vSphere monitoring dashboard
# Grafana > + > Import > ID: 8159 (VMware vSphere ESXi)
# Grafana > + > Import > ID: 1860 (Node Exporter Full)

# Capture baseline metrics for 1 week before migration starts
```

---

## Step 15: Final Readiness Gate

Run this script before starting ANY migration work:

```bash
#!/bin/bash
# pre-migration-readiness.sh

echo "=========================================="
echo "  Pre-Migration Readiness Check"
echo "  $(date)"
echo "=========================================="
PASS=0; FAIL=0

check() {
  local DESC=$1; shift
  if "$@" > /dev/null 2>&1; then
    echo "  ✅ $DESC"
    ((PASS++))
  else
    echo "  ❌ $DESC"
    ((FAIL++))
  fi
}

echo ""
echo "--- Infrastructure ---"
check "vCenter reachable"           govc about
check "All 6 ESXi hosts connected"  bash -c '[ "$(govc host.info "*" | grep -c "Name:")" -eq 6 ]'
check "vSAN datastore accessible"   govc datastore.info vsanDatastore
check "K8s port group exists"       govc dvs.portgroup.info -dc="Datacenter" "PG-K8s-Nodes"
check "DB port group exists"        govc dvs.portgroup.info -dc="Datacenter" "PG-Databases"

echo ""
echo "--- VMs and Templates ---"
check "Ubuntu template exists"      govc find . -type m -name "ubuntu-22.04-base"
check "Jump host reachable"         ping -c 1 -W 2 10.0.1.50
check "DNS server reachable"        nslookup k8s-master-1.internal.company.com 10.0.1.5

echo ""
echo "--- Services ---"
check "Internal CA reachable"       curl -sk https://ca-01.internal.company.com/health
check "NTP synchronized"            chronyc tracking | grep -q "Reference ID"
check "Azure VPN connected"         az network vpn-connection show --name azure-to-onprem \
                                      --resource-group rg-hub-we-001 \
                                      --query connectionStatus -o tsv 2>/dev/null | grep -q Connected

echo ""
echo "--- Tools ---"
check "govc installed"              which govc
check "kubectl installed"           which kubectl
check "helm installed"              which helm
check "az CLI installed"            which az
check "psql installed"              which psql
check "mongodump installed"         which mongodump
check "ansible installed"           which ansible

echo ""
echo "=========================================="
echo "  Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && echo "  ✅ READY TO START MIGRATION" || echo "  ❌ FIX FAILURES BEFORE PROCEEDING"
echo "=========================================="
```

---

## Step 0: VxRail First-Run / Day-1 Deployment Wizard

> If VxRail is already deployed and vCenter is running, skip to Step 1.
> If this is a fresh VxRail cluster, follow these steps first.

### 0.1 What the VxRail Deployment Wizard Does

```
VxRail Manager Deployment Wizard (run once, takes 45-90 minutes):
  1. Discovers all 6 nodes via iDRAC/IPMI
  2. Validates hardware health (BIOS, firmware, disk status)
  3. Collects network config (management IPs, vSAN IPs, vMotion IPs)
  4. Deploys vCenter Server Appliance (VCSA) on the first node
  5. Configures ESXi networking (DVS, VMkernels for vSAN/vMotion)
  6. Creates vSAN disk groups on all nodes
  7. Configures vSphere HA and DRS
  8. Applies firmware baseline
```

### 0.2 Pre-Wizard Network Planning

Before starting the wizard, collect these IP addresses:

| Component | IP Address | Subnet | Gateway | DNS |
|-----------|-----------|--------|---------|-----|
| VxRail Manager | 10.0.1.30 | /24 | 10.0.1.1 | 10.0.1.5 |
| vCenter Server | 10.0.1.10 | /24 | 10.0.1.1 | 10.0.1.5 |
| ESXi Host 1 (mgmt) | 10.0.1.21 | /24 | 10.0.1.1 | 10.0.1.5 |
| ESXi Host 2 (mgmt) | 10.0.1.22 | /24 | 10.0.1.1 | 10.0.1.5 |
| ESXi Host 3 (mgmt) | 10.0.1.23 | /24 | 10.0.1.1 | 10.0.1.5 |
| ESXi Host 4 (mgmt) | 10.0.1.24 | /24 | 10.0.1.1 | 10.0.1.5 |
| ESXi Host 5 (mgmt) | 10.0.1.25 | /24 | 10.0.1.1 | 10.0.1.5 |
| ESXi Host 6 (mgmt) | 10.0.1.26 | /24 | 10.0.1.1 | 10.0.1.5 |
| vSAN VMkernel (each host) | 10.0.80.21-26 | /24 | — | — |
| vMotion VMkernel (each host) | 10.0.90.21-26 | /24 | — | — |
| NTP Server | 10.0.1.5 (or public pool.ntp.org) | — | — | — |

### 0.3 Wizard Walkthrough (Screen by Screen)

```
Screen 1 — Welcome
  → Click "Deploy VxRail" (not "Reimage")

Screen 2 — Network Configuration
  Fill in:
    Management network IP pool (e.g., 10.0.1.20 - 10.0.1.26 for 6 nodes)
    Subnet mask: 255.255.255.0
    Gateway: 10.0.1.1
    DNS: 10.0.1.5
    NTP: pool.ntp.org (or your internal NTP IP)

Screen 3 — vCenter Deployment
  Choose: "Embedded vCenter" (runs on VxRail cluster itself)
  vCenter IP: 10.0.1.10
  vCenter FQDN: vcenter.internal.company.com
  SSO domain: vsphere.local
  SSO password: ChooseStrongPassword123!  ← WRITE THIS DOWN
  Administrator account: administrator@vsphere.local

Screen 4 — vSAN Configuration
  Disk group type: All-Flash (NVMe cache + SSD capacity)
  Choose "Automated" — VxRail Manager picks which disks go to cache/capacity
  Enable: Deduplication and Compression (for All-Flash)
  Enable: Encryption at rest (optional, requires key management)

Screen 5 — Advanced Settings
  vSAN datastore name: vsanDatastore
  Datacenter name: Datacenter
  Cluster name: VxRail-Cluster

Screen 6 — Review & Deploy
  Verify all settings
  Click "Finish"
  → Wait 45-90 minutes for automated deployment
  → Watch progress bar in VxRail Manager UI

Screen 7 — Post-Deployment
  VxRail Manager shows "Cluster Health: Healthy"
  Log in to vCenter: https://10.0.1.10/ui
```

---

## Setup Flow Diagram

```mermaid
flowchart TD
    S0([VxRail Cluster Available]) --> S1[Step 1: Health Check\nvCenter + VxRail Manager]
    S1 --> S2[Step 2: Physical Network\nConfigure switch VLANs]
    S2 --> S3[Step 3: vCenter DVS\nCreate Port Groups per VLAN]
    S3 --> S4[Step 4: vSAN\nStorage Policies]
    S4 --> S5[Step 5: Jump Host VM\nManagement workstation]
    S5 --> S6[Step 6: DNS Server VM\nBIND9 internal DNS]
    S6 --> S7[Step 7: NTP Verification\nAll hosts synced]
    S7 --> S8[Step 8: Internal CA\nstep-ca TLS certificates]
    S8 --> S9[Step 9: Azure VPN\nSite-to-site for data transfer]
    S9 --> S10[Step 10: OL9 VM Template\nBase OS template]
    S10 --> S11[Step 11: Create Phase 1 VMs\nDev and QA VMs]
    S11 --> S12[Step 12: Install Tools\nAll VMs configured]
    S12 --> S13[Step 13: Backup Infra\nVeeam jobs running]
    S13 --> S14[Step 14: Monitoring Baseline\nPrometheus scraping]
    S14 --> S15{Readiness Gate\nAll checks pass?}
    S15 -->|No| FIX[Fix issues]
    FIX --> S15
    S15 -->|Yes| DONE([Ready for Migration])
```

---

## VLAN Reference Table

| VLAN ID | Port Group Name | Subnet | Gateway | Purpose | VMs / Components |
|---------|----------------|--------|---------|---------|-----------------|
| 10 | PG-Management | 10.0.1.0/24 | 10.0.1.1 | ESXi mgmt, vCenter, VxRail Manager | ESXi hosts, vCenter, DNS, Jump Host, Veeam |
| 20 | PG-K8s-Nodes | 10.0.3.0/24 (masters), 10.0.4.0/24 (workers) | 10.0.3.1 / 10.0.4.1 | Kubernetes cluster nodes | k8s-master-1/2/3, k8s-worker-1 through 6 |
| 30 | PG-Databases | 10.0.5.0/24 | 10.0.5.1 | Database VMs — PostgreSQL + MongoDB | db-dev/qa/preprod/prod, mongo-dev/qa/preprod/prod |
| 40 | PG-Services | 10.0.6.0/24 | 10.0.6.1 | Shared services | Harbor, MinIO, Monitoring (Prometheus/Grafana) |
| 80 | vSAN (VMkernel) | 10.0.80.0/24 | — | vSAN storage traffic between hosts | ESXi VMkernel vmk1 (internal use only) |
| 90 | vMotion (VMkernel) | 10.0.90.0/24 | — | VM live migration between hosts | ESXi VMkernel vmk2 (internal use only) |

---

## Step 6 (Expanded): DNS Server VM Setup

### 6.1 Deploy DNS VM

```bash
# Clone from OL9 template (after template is created in Step 10)
govc vm.clone \
  -vm=ol9-base-template \
  -on=false \
  -net="PG-Management" \
  dns-server-01

# Set CPU/RAM
govc vm.change -vm=dns-server-01 -c=2 -m=4096

# Power on
govc vm.power -on dns-server-01

# SSH in
ssh oracle@10.0.1.5
```

### 6.2 Install and Configure BIND9

```bash
# Install BIND
sudo dnf install -y bind bind-utils

# Main named.conf
sudo tee /etc/named.conf << 'EOF'
options {
    listen-on port 53 { 127.0.0.1; 10.0.1.5; };
    directory           "/var/named";
    dump-file           "/var/named/data/cache_dump.db";
    statistics-file     "/var/named/data/named_stats.txt";
    memstatistics-file  "/var/named/data/named_mem_stats.txt";
    recursion yes;
    allow-query         { localhost; 10.0.0.0/8; };
    allow-recursion     { localhost; 10.0.0.0/8; };
    forwarders          { 8.8.8.8; 8.8.4.4; };  # Forward external names to Google DNS
    dnssec-validation no;
};

zone "internal.company.com" IN {
    type master;
    file "internal.company.com.zone";
    allow-update { none; };
};

zone "0.10.in-addr.arpa" IN {
    type master;
    file "10.0.reverse.zone";
    allow-update { none; };
};
EOF

# Forward zone file
sudo tee /var/named/internal.company.com.zone << 'EOF'
$TTL 86400
@   IN SOA  dns-server-01.internal.company.com. admin.company.com. (
            2026072201  ; Serial
            3600        ; Refresh
            900         ; Retry
            604800      ; Expire
            86400 )     ; Minimum TTL
    IN NS   dns-server-01.internal.company.com.

; Infrastructure
dns-server-01    IN A  10.0.1.5
vcenter          IN A  10.0.1.10
jump-host        IN A  10.0.1.20
vxrail-manager   IN A  10.0.1.30
veeam            IN A  10.0.1.40

; K8s Control Plane
k8s-master-1     IN A  10.0.3.11
k8s-master-2     IN A  10.0.3.12
k8s-master-3     IN A  10.0.3.13
k8s-api          IN A  10.0.3.100

; K8s Workers
k8s-worker-1     IN A  10.0.4.21
k8s-worker-2     IN A  10.0.4.22
k8s-worker-3     IN A  10.0.4.23
k8s-worker-4     IN A  10.0.4.24
k8s-worker-5     IN A  10.0.4.25
k8s-worker-6     IN A  10.0.4.26

; PostgreSQL
db-dev-01        IN A  10.0.5.11
db-qa-01         IN A  10.0.5.12
db-preprod-01    IN A  10.0.5.13
db-preprod-02    IN A  10.0.5.14
db-prod-01       IN A  10.0.5.15
db-prod-02       IN A  10.0.5.16
db-prod-03       IN A  10.0.5.17

; MongoDB
mongo-dev-01     IN A  10.0.5.21
mongo-qa-01      IN A  10.0.5.22
mongo-preprod-01 IN A  10.0.5.23
mongo-preprod-02 IN A  10.0.5.24
mongo-prod-01    IN A  10.0.5.25
mongo-prod-02    IN A  10.0.5.26
mongo-prod-03    IN A  10.0.5.27

; Shared Services
minio            IN A  10.0.6.11
harbor           IN A  10.0.6.12
monitoring       IN A  10.0.6.13

; App endpoints (MetalLB)
app-dev          IN A  10.0.4.200
app-qa           IN A  10.0.4.201
app-preprod      IN A  10.0.4.202
app-prod         IN A  10.0.4.210
EOF

# Start and enable BIND
sudo systemctl enable --now named

# Test DNS
nslookup vcenter.internal.company.com 10.0.1.5
nslookup k8s-api.internal.company.com 10.0.1.5

# Update all hosts to use this DNS
# Add to /etc/resolv.conf on all VMs:
echo "nameserver 10.0.1.5" | sudo tee /etc/resolv.conf
echo "search internal.company.com" | sudo tee -a /etc/resolv.conf
```

---

## Step 8 (Expanded): Internal CA with step-ca

```bash
# On your Jump Host or a dedicated CA VM (OL9)
# Install step CLI
STEP_VERSION="0.25.0"
wget https://dl.smallstep.com/gh-release/cli/gh-release-header/v${STEP_VERSION}/step_linux_${STEP_VERSION}_amd64.tar.gz
tar -xzf step_linux_${STEP_VERSION}_amd64.tar.gz
sudo mv step_${STEP_VERSION}/bin/step /usr/local/bin/
sudo mv step_${STEP_VERSION}/bin/step-ca /usr/local/bin/

# Initialize CA
step ca init \
  --name="CompanyInternalCA" \
  --dns="ca.internal.company.com" \
  --address=":443" \
  --provisioner="admin@company.com"
# → Creates ~/.step/certs/root_ca.crt and ~/.step/certs/intermediate_ca.crt

# Start CA server
step-ca ~/.step/config/ca.json &

# Issue a wildcard certificate
step ca certificate \
  "*.internal.company.com" \
  wildcard.crt \
  wildcard.key \
  --ca-url https://ca.internal.company.com \
  --root ~/.step/certs/root_ca.crt

# Create K8s secret with wildcard cert
kubectl create secret tls wildcard-tls \
  --cert=wildcard.crt \
  --key=wildcard.key \
  --namespace=kube-system

# Distribute root CA to all VMs so curl/browsers trust it
sudo cp ~/.step/certs/root_ca.crt /etc/pki/ca-trust/source/anchors/company-root-ca.crt
sudo update-ca-trust extract
```

---

## Step 15: Final Readiness Gate Checklist

Before starting Phase 1 migration, ALL items below must be checked:

```
Infrastructure Foundation:
  [ ] vCenter accessible at https://vcenter.internal.company.com
  [ ] All 6 ESXi hosts connected in vCenter (no disconnected hosts)
  [ ] vSAN health: no red/yellow warnings
  [ ] DVS port groups created: PG-Management, PG-K8s-Nodes, PG-Databases, PG-Services
  [ ] Physical switch VLANs trunked (verified by ping test across VLANs)

VMs Running:
  [ ] Jump host VM accessible via SSH
  [ ] DNS server responding: nslookup vcenter.internal.company.com returns correct IP
  [ ] NTP synced: chronyc tracking shows offset < 100ms on all VMs
  [ ] Internal CA issuing certs: step ca health returns OK

Kubernetes:
  [ ] All 9 K8s VMs created (3 masters + 6 workers)
  [ ] kubectl get nodes shows all nodes Ready
  [ ] Calico pods running: kubectl get pods -n calico-system
  [ ] MetalLB running: kubectl get pods -n metallb-system
  [ ] Harbor accessible at https://harbor.internal.company.com
  [ ] ArgoCD accessible at https://argocd.internal.company.com

Databases:
  [ ] All PostgreSQL VMs running, PostgreSQL service active
  [ ] All MongoDB VMs running, replica sets configured
  [ ] Test DB connection from jump host

Backup:
  [ ] Veeam jobs configured for all VMs
  [ ] First backup run completed successfully
  [ ] Test restore verified (restore 1 VM to isolated network)

Azure Connectivity:
  [ ] VPN tunnel established (ping Azure management IP from jump host)
  [ ] Can reach Azure PostgreSQL from jump host (psql connection test)
  [ ] Can pull images from Azure ACR (docker pull test)

Monitoring:
  [ ] Prometheus scraping all targets
  [ ] Grafana dashboards loading
  [ ] Alert manager configured for critical alerts
  [ ] Baseline metrics recorded (CPU, memory, storage before migration)
```

