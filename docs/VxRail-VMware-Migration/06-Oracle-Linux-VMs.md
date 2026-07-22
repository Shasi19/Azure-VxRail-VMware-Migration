# Oracle Linux 9 VMs on VxRail — Complete Guide

> **Your environment uses Oracle Linux (OL) VMs, not Ubuntu.** All commands in this guide are OL9-specific. Use this as the reference whenever other docs in this repo show Ubuntu/apt commands.

---

## Quick Command Reference: Ubuntu → Oracle Linux 9

| Task | Ubuntu (apt) | Oracle Linux 9 (dnf) |
|------|-------------|----------------------|
| Update package list | `apt update` | `dnf check-update` |
| Install package | `apt install -y pkg` | `dnf install -y pkg` |
| Install multiple | `apt install -y a b c` | `dnf install -y a b c` |
| Hold package version | `apt-mark hold kubelet` | `dnf versionlock add kubelet` |
| Remove package | `apt remove pkg` | `dnf remove pkg` |
| Add repo key | `apt-key add -` | `rpm --import key.gpg` |
| Add repo | `/etc/apt/sources.list.d/` | `/etc/yum.repos.d/` |
| Enable firewall rule | `ufw allow 6443/tcp` | `firewall-cmd --permanent --add-port=6443/tcp` |
| Reload firewall | `ufw reload` | `firewall-cmd --reload` |
| Check firewall | `ufw status` | `firewall-cmd --list-all` |
| Network config | `/etc/netplan/*.yaml` | `nmcli` / `/etc/sysconfig/network-scripts/` |
| NIC name (VMware) | `ens192` | `ens192` (same on OL9 with VMware VMXNET3) |
| Package lock tool | `apt-mark` | `dnf-plugin-versionlock` |
| VMware guest tools | `open-vm-tools` | `open-vm-tools` (same package name, dnf) |
| vSphere guest type | `ubuntu64Guest` | `oracleLinux9_64Guest` |
| SELinux | AppArmor | SELinux (enforcing by default) |
| Init system | systemd | systemd (same) |
| NTP | chrony (apt) | chrony (dnf) |

---

## 1. Oracle Linux VM Template on VxRail

### 1.1 Download Oracle Linux 9 ISO

```bash
# From jumphost — download OL9 ISO
wget https://yum.oracle.com/ISOS/OracleLinux/OL9/u4/x86_64/OracleLinux-R9-U4-x86_64-dvd.iso \
  -O /tmp/OracleLinux-9.4-x86_64.iso

# Or use Oracle's minimal ISO (smaller download)
wget https://yum.oracle.com/ISOS/OracleLinux/OL9/u4/x86_64/OracleLinux-R9-U4-x86_64-boot.iso \
  -O /tmp/OracleLinux-9.4-boot.iso

# Upload to vSAN datastore
govc datastore.upload -ds=vsanDatastore \
  /tmp/OracleLinux-9.4-x86_64.iso \
  iso/OracleLinux-9.4-x86_64.iso
```

### 1.2 Create Base VM in vCenter

```bash
# Create VM with Oracle Linux guest type
govc vm.create \
  -c=4 \
  -m=8192 \
  -disk=60GB \
  -net="PG-K8s-Nodes" \
  -g=oracleLinux9_64Guest \
  -on=false \
  ol9-base-template

# Attach ISO for installation
govc vm.cdrom.add -vm=ol9-base-template -type=cdrom
govc vm.cdrom.insert -vm=ol9-base-template \
  -device="CD/DVD drive 1" \
  "vsanDatastore/iso/OracleLinux-9.4-x86_64.iso"

# Power on — complete install via vCenter console
govc vm.power -on ol9-base-template
```

### 1.3 Oracle Linux 9 Installation Settings (via vCenter Console)

```
During Anaconda installer:
  Language: English
  Time & Date: Your timezone (e.g., Asia/Kolkata)
  Software: Minimal Install  ← important, no GUI
  Network & Hostname:
    - Enable ens192
    - Set temporary IP (e.g., 10.0.1.200/24)
    - Gateway: 10.0.1.1
    - DNS: 10.0.1.5
    - Hostname: ol9-template
  Root Password: Disabled (use sudo user only)
  User Creation:
    - Username: oracle
    - Password: TemplatePass2026!
    - Make this user administrator: ✅
  Installation Destination:
    - Select vSAN disk
    - Automatic partitioning
  Begin Installation → Reboot
```

### 1.4 Post-Install Template Customization

```bash
# SSH to the base VM
ssh oracle@10.0.1.200

# 1. Enable Oracle Linux repos (Unbreakable Enterprise Kernel + EPEL)
sudo dnf install -y oracle-epel-release-el9
sudo dnf install -y oraclelinux-developer-release-el9
sudo dnf config-manager --enable ol9_baseos_latest ol9_appstream ol9_UEKR7

# 2. Full system update
sudo dnf update -y

# 3. Install baseline packages
sudo dnf install -y \
  curl wget vim htop net-tools bind-utils \
  nfs-utils chrony open-vm-tools \
  cloud-init cloud-utils-growpart \
  python3 python3-pip \
  bash-completion \
  socat conntrack-tools \
  ipset ipvsadm \
  lsof tcpdump

# 4. Enable VMware Tools
sudo systemctl enable vmtoolsd
sudo systemctl start vmtoolsd

# 5. Configure NTP with chrony
sudo tee /etc/chrony.conf << 'EOF'
server 10.0.1.5 iburst
server pool.ntp.org iburst
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
EOF
sudo systemctl enable chronyd
sudo systemctl start chronyd

# 6. Configure cloud-init for VMware OVF datasource
sudo tee /etc/cloud/cloud.cfg.d/99-vxrail.cfg << 'EOF'
datasource_list: ['VMwareGuestInfo', 'OVF', 'ConfigDrive', 'None']
EOF

# 7. Harden SSH
sudo sed -i 's/#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# 8. Configure SELinux (keep enforcing — do NOT disable)
getenforce   # Should show Enforcing
# For K8s nodes, set to Permissive during install, re-enable after
# NOTE: for K8s specifically we will set to permissive in the K8s prep script

# 9. Install dnf-versionlock (for K8s package pinning)
sudo dnf install -y dnf-plugins-core python3-dnf-plugin-versionlock

# 10. Set SELinux to permissive for K8s nodes (re-enabled after setup)
# (Only on K8s VMs — not database or service VMs)
# sudo setenforce 0
# sudo sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

# 11. Clean cloud-init so it re-runs on cloned VMs
sudo cloud-init clean --logs
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id
sudo ln -s /etc/machine-id /var/lib/dbus/machine-id

# 12. Zero out free space for better thin provisioning compression (optional)
# sudo dd if=/dev/zero of=/tmp/zero_file bs=4M 2>/dev/null; rm /tmp/zero_file

# Shut down
sudo shutdown -h now
```

### 1.5 Convert to vCenter Template

```bash
# After VM is powered off
govc vm.markastemplate ol9-base-template
echo "Oracle Linux 9 template ready for cloning"
```

---

## 2. Clone VMs from OL9 Template

### 2.1 Create All Phase 1 VMs

```bash
#!/bin/bash
# create-ol9-vms.sh — clone OL9 VMs for Phase 1

export GOVC_URL=https://vcenter.internal.company.com
export GOVC_USERNAME=administrator@vsphere.local
export GOVC_PASSWORD="${VCENTER_PASSWORD}"
export GOVC_DATACENTER=Datacenter
export GOVC_DATASTORE=vsanDatastore

TEMPLATE="ol9-base-template"

# NAME|CPUS|MEM_MB|DISK_GB|HOST|FOLDER|NETWORK
PHASE1_VMS=(
  "k8s-master-1|4|8192|80|vxrail-1.internal.company.com|K8s|PG-K8s-Nodes"
  "k8s-master-2|4|8192|80|vxrail-2.internal.company.com|K8s|PG-K8s-Nodes"
  "k8s-master-3|4|8192|80|vxrail-3.internal.company.com|K8s|PG-K8s-Nodes"
  "k8s-worker-1|8|16384|100|vxrail-4.internal.company.com|K8s|PG-K8s-Nodes"
  "k8s-worker-2|8|16384|100|vxrail-4.internal.company.com|K8s|PG-K8s-Nodes"
  "db-dev-01|4|8192|200|vxrail-1.internal.company.com|Databases|PG-Databases"
  "db-qa-01|4|8192|200|vxrail-2.internal.company.com|Databases|PG-Databases"
  "mongo-dev-01|2|4096|100|vxrail-1.internal.company.com|Databases|PG-Databases"
  "mongo-qa-01|2|4096|100|vxrail-2.internal.company.com|Databases|PG-Databases"
  "minio-01|4|8192|50|vxrail-5.internal.company.com|Services|PG-Services"
  "harbor-01|4|8192|50|vxrail-6.internal.company.com|Services|PG-Services"
  "monitoring-01|4|16384|50|vxrail-6.internal.company.com|Services|PG-Services"
)

for entry in "${PHASE1_VMS[@]}"; do
  IFS='|' read -r NAME CPUS MEM DISK HOST FOLDER NETWORK <<< "$entry"
  echo "Creating: $NAME on $HOST"
  govc folder.create "/Datacenter/vm/${FOLDER}" 2>/dev/null || true
  govc vm.clone \
    --vm="$TEMPLATE" \
    --name="$NAME" \
    --folder="/Datacenter/vm/${FOLDER}" \
    --host="$HOST" \
    --datastore=vsanDatastore \
    --on=false
  govc vm.change --vm="$NAME" --cpu="$CPUS" --memory="$MEM"
  govc vm.disk.change --vm="$NAME" --disk.label="Hard disk 1" --size="${DISK}GB"
  govc vm.change -vm="$NAME" -e "disk.EnableUUID=TRUE"
  echo "  Created: $NAME"
done
```

### 2.2 Configure Static IPs with cloud-init on OL9

OL9 uses `NetworkManager` (not Netplan). The cloud-init network config uses nmcli format:

```bash
#!/bin/bash
# inject-cloud-init-ol9.sh

VM_NAME=$1
HOSTNAME=$2
IP=$3
PREFIX=24
GATEWAY="10.0.3.1"    # adjust per subnet
DNS="10.0.1.5"
SSH_PUBKEY="ssh-ed25519 AAAAC3... vxrail-migration-key"

mkdir -p /tmp/cloud-init/${VM_NAME}

# user-data for OL9 (uses dnf, not apt)
cat > /tmp/cloud-init/${VM_NAME}/user-data << USERDATA
#cloud-config
hostname: ${HOSTNAME}
fqdn: ${HOSTNAME}.internal.company.com

users:
  - name: oracle
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ${SSH_PUBKEY}

# OL9 uses dnf not apt
package_update: false   # We will run dnf manually after boot

runcmd:
  # Set hostname
  - hostnamectl set-hostname ${HOSTNAME}.internal.company.com
  # Configure SELinux permissive for K8s nodes
  - setenforce 0 || true
  # Enable VMware Tools
  - systemctl enable --now vmtoolsd
  # Disable swap permanently
  - swapoff -a
  - sed -i '/swap/d' /etc/fstab
  # Load required kernel modules
  - modprobe overlay
  - modprobe br_netfilter
  # Kernel networking params
  - echo 'net.bridge.bridge-nf-call-iptables = 1' >> /etc/sysctl.d/k8s.conf
  - echo 'net.bridge.bridge-nf-call-ip6tables = 1' >> /etc/sysctl.d/k8s.conf
  - echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.d/k8s.conf
  - sysctl --system
  # Start NTP
  - systemctl enable --now chronyd

power_state:
  mode: reboot
  delay: "+1"
USERDATA

# network-config for OL9 (uses NetworkManager format)
cat > /tmp/cloud-init/${VM_NAME}/network-config << NETCFG
version: 2
ethernets:
  ens192:
    dhcp4: false
    addresses:
      - ${IP}/${PREFIX}
    gateway4: ${GATEWAY}
    nameservers:
      addresses: [${DNS}]
      search: [internal.company.com]
NETCFG

cat > /tmp/cloud-init/${VM_NAME}/meta-data << METADATA
instance-id: ${VM_NAME}
local-hostname: ${HOSTNAME}
METADATA

cloud-localds /tmp/cloud-init/${VM_NAME}-seed.iso \
  /tmp/cloud-init/${VM_NAME}/user-data \
  /tmp/cloud-init/${VM_NAME}/meta-data \
  --network-config /tmp/cloud-init/${VM_NAME}/network-config

# Upload ISO and attach to VM
govc datastore.upload -ds=vsanDatastore \
  /tmp/cloud-init/${VM_NAME}-seed.iso \
  "cloud-init/${VM_NAME}-seed.iso"

govc vm.cdrom.add -vm="$VM_NAME" -type=cdrom 2>/dev/null || true
govc vm.cdrom.insert -vm="$VM_NAME" -device="CD/DVD drive 1" \
  "vsanDatastore/cloud-init/${VM_NAME}-seed.iso"

govc vm.power -on "$VM_NAME"
echo "Powered on: $VM_NAME ($IP)"
```

---

## 3. Kubernetes on Oracle Linux 9

### 3.1 OL9 Node Preparation Script

```bash
#!/bin/bash
# k8s-node-prep-ol9.sh — run as root/sudo on each K8s node

set -e
echo "Preparing Oracle Linux 9 node for Kubernetes..."

# 1. Disable swap
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# 2. SELinux — set permissive for Kubernetes
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

# 3. Load kernel modules
cat > /etc/modules-load.d/k8s.conf << 'EOF'
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# 4. Kernel networking parameters
cat > /etc/sysctl.d/99-kubernetes.conf << 'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# 5. Install containerd (container runtime)
dnf config-manager --add-repo \
  https://download.docker.com/linux/centos/docker-ce.repo
dnf install -y containerd.io

# Configure containerd with systemd cgroup driver
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd

# 6. Add Kubernetes repo for OL/RHEL
cat > /etc/yum.repos.d/kubernetes.repo << 'EOF'
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

# 7. Install kubeadm, kubelet, kubectl
dnf install -y --disableexcludes=kubernetes \
  kubelet-1.29.0 kubeadm-1.29.0 kubectl-1.29.0

# Pin versions to prevent accidental upgrade
dnf versionlock add kubelet kubeadm kubectl

# 8. Enable kubelet
systemctl enable kubelet

# 9. Firewalld — open required ports
# (Or you can disable firewalld on K8s nodes if using NetworkPolicy for security)
systemctl enable --now firewalld

# Control plane ports
firewall-cmd --permanent --add-port=6443/tcp       # K8s API server
firewall-cmd --permanent --add-port=2379-2380/tcp  # etcd
firewall-cmd --permanent --add-port=10250/tcp       # Kubelet API
firewall-cmd --permanent --add-port=10251/tcp       # kube-scheduler
firewall-cmd --permanent --add-port=10252/tcp       # kube-controller-manager
firewall-cmd --permanent --add-port=10257/tcp       # kube-controller-manager
firewall-cmd --permanent --add-port=10259/tcp       # kube-scheduler

# Worker node ports
firewall-cmd --permanent --add-port=10250/tcp       # Kubelet API
firewall-cmd --permanent --add-port=30000-32767/tcp # NodePort services

# Calico / pod network
firewall-cmd --permanent --add-port=179/tcp         # BGP
firewall-cmd --permanent --add-port=4789/udp        # VXLAN
firewall-cmd --permanent --add-port=5473/tcp        # Calico Typha

# MetalLB
firewall-cmd --permanent --add-port=7946/tcp
firewall-cmd --permanent --add-port=7946/udp

# Allow all from K8s subnets
firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address="10.0.3.0/24" accept'
firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address="10.0.4.0/24" accept'
firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address="192.168.0.0/16" accept'
firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address="10.96.0.0/12" accept'
firewall-cmd --reload

echo "OL9 K8s node preparation complete. Ready for kubeadm."
```

---

## 4. Network Configuration on Oracle Linux 9

OL9 uses **NetworkManager** (`nmcli`) instead of Netplan.

### 4.1 Set Static IP with nmcli

```bash
# Configure ens192 with static IP (run after cloud-init or manually)
NIC="ens192"
IP="10.0.3.11"
PREFIX="24"
GW="10.0.3.1"
DNS="10.0.1.5"

# Modify connection
nmcli con mod "$NIC" ipv4.addresses "${IP}/${PREFIX}"
nmcli con mod "$NIC" ipv4.gateway "$GW"
nmcli con mod "$NIC" ipv4.dns "$DNS"
nmcli con mod "$NIC" ipv4.method manual
nmcli con mod "$NIC" connection.autoconnect yes

# Apply
nmcli con down "$NIC" && nmcli con up "$NIC"

# Verify
ip addr show $NIC
ip route show
```

### 4.2 keepalived on OL9

```bash
# Install keepalived (via dnf)
sudo dnf install -y keepalived

# Config is the same as Ubuntu — only installation command differs
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
  state MASTER
  interface ens192
  virtual_router_id 51
  priority 101
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

# Install HAProxy
sudo dnf install -y haproxy

# Config is identical — same haproxy.cfg as Ubuntu version
# (See 07-Kubernetes-vSphere.md section 2 for haproxy.cfg content)

# Enable firewalld for VRRP multicast
sudo firewall-cmd --permanent --add-rich-rule='rule protocol value="vrrp" accept'
sudo firewall-cmd --reload

sudo systemctl enable --now keepalived haproxy
```

---

## 5. PostgreSQL 15 on Oracle Linux 9

```bash
# Install PostgreSQL 15 from official PostgreSQL repo
sudo dnf install -y \
  https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm

# Disable built-in OL9 postgresql module (conflicts with pgdg)
sudo dnf -qy module disable postgresql

# Install
sudo dnf install -y postgresql15-server postgresql15 postgresql15-contrib

# Initialize database cluster
sudo /usr/pgsql-15/bin/postgresql-15-setup initdb

# Configure remote access
sudo sed -i "s/#listen_addresses.*/listen_addresses = '*'/" \
  /var/lib/pgsql/15/data/postgresql.conf

# pg_hba.conf — OL9 default location
sudo tee -a /var/lib/pgsql/15/data/pg_hba.conf << 'EOF'
host    all    all    10.0.3.0/24    scram-sha-256
host    all    all    10.0.4.0/24    scram-sha-256
host    all    all    10.0.5.0/24    scram-sha-256
EOF

# Firewall
sudo firewall-cmd --permanent --add-service=postgresql
sudo firewall-cmd --reload

# SELinux — allow PostgreSQL to listen on port 5432
sudo semanage port -a -t postgresql_port_t -p tcp 5432 2>/dev/null || true

# Enable and start
sudo systemctl enable postgresql-15
sudo systemctl start postgresql-15

# Create DB and user
sudo -u postgres /usr/pgsql-15/bin/psql << 'SQL'
CREATE DATABASE dev_db;
CREATE USER dev_user WITH ENCRYPTED PASSWORD 'DevPostgres2026!';
GRANT ALL PRIVILEGES ON DATABASE dev_db TO dev_user;
SQL
```

---

## 6. MongoDB 7.0 on Oracle Linux 9

```bash
# Add MongoDB repo for OL9 (RHEL9-compatible)
sudo tee /etc/yum.repos.d/mongodb-org-7.0.repo << 'EOF'
[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/9/mongodb-org/7.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-7.0.asc
EOF

sudo dnf install -y mongodb-org

# SELinux — allow mongod to use data dir
sudo semanage fcontext -a -t mongod_var_lib_t '/var/lib/mongodb(/.*)?'
sudo restorecon -Rv /var/lib/mongodb 2>/dev/null || true

# SELinux — allow mongod network connections
sudo setsebool -P mongod_can_network_connect_db 1 2>/dev/null || true

# Firewall
sudo firewall-cmd --permanent --add-port=27017/tcp
sudo firewall-cmd --reload

# Config
sudo tee /etc/mongod.conf << 'EOF'
storage:
  dbPath: /var/lib/mongodb
  wiredTiger:
    engineConfig:
      cacheSizeGB: 2
net:
  port: 27017
  bindIp: 0.0.0.0
security:
  authorization: enabled
EOF

sudo systemctl enable mongod && sudo systemctl start mongod

# Verify (mongosh is the same)
mongosh --quiet --eval "db.runCommand({ping:1})"
```

---

## 7. Ansible for OL9 Nodes

### Ansible Inventory (Oracle Linux)

```ini
# /etc/ansible/hosts

[k8s_masters]
10.0.3.11 ansible_user=oracle ansible_ssh_private_key_file=~/.ssh/vxrail_key hostname=k8s-master-1
10.0.3.12 ansible_user=oracle ansible_ssh_private_key_file=~/.ssh/vxrail_key hostname=k8s-master-2
10.0.3.13 ansible_user=oracle ansible_ssh_private_key_file=~/.ssh/vxrail_key hostname=k8s-master-3

[k8s_workers]
10.0.4.21 ansible_user=oracle ansible_ssh_private_key_file=~/.ssh/vxrail_key
10.0.4.22 ansible_user=oracle ansible_ssh_private_key_file=~/.ssh/vxrail_key

[databases]
10.0.5.11 ansible_user=oracle hostname=db-dev-01
10.0.5.12 ansible_user=oracle hostname=db-qa-01
```

### Parallel dnf update on all nodes

```bash
# Update all K8s nodes in parallel
ansible k8s_nodes -i /etc/ansible/hosts \
  -m shell \
  -a "dnf update -y --exclude='kubelet,kubeadm,kubectl'" \
  --become

# Reboot if kernel updated
ansible k8s_nodes -i /etc/ansible/hosts \
  -m reboot \
  -a "reboot_timeout=300" \
  --become

# Verify all back online
ansible k8s_nodes -i /etc/ansible/hosts -m ping
```

---

## 8. Troubleshooting OL9-Specific Issues

| Issue | Symptom | Fix |
|-------|---------|-----|
| SELinux blocking containerd | `journalctl -u containerd` shows AVC denied | `setenforce 0` or add SELinux policy: `audit2allow -a -M my-containerd` |
| firewalld blocking K8s | Pods can't communicate | `firewall-cmd --list-all`; add pod CIDR to trusted zone |
| dnf GPG key error | `dnf install` fails with GPG error | `rpm --import <key-url>` or `dnf install --nogpgcheck` (once) |
| NetworkManager DHCP override | Static IP lost after reboot | Set `NM_CONTROLLED=yes` in `/etc/sysconfig/network-scripts/` |
| PostgreSQL won't start | `systemctl status postgresql-15` AVC denied | `semanage` for port + restorecon for data dir |
| MongoDB port denied | `mongod` not listening | `firewall-cmd --add-port=27017/tcp --permanent && --reload` |
| Hostname not FQDN | K8s node shows short hostname | `hostnamectl set-hostname <full.fqdn>` |
| clock skew errors | etcd logs show "clock skew" | `chronyc makestep`; check `chronyc sources` |
