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
# (See 10-Kubernetes-vSphere.md section 2 for haproxy.cfg content)

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

---

## 2. Oracle Linux 9 — Complete Anaconda Installer Walkthrough

> This section walks you through EVERY screen of the OL9 installer when installing via the vCenter console.

### 2.1 Pre-Installation: Access the vCenter Console

```
1. Log in to vCenter: https://vcenter.internal.company.com/ui
2. Navigate to: VMs → ol9-base-template → Launch Web Console
3. VM should be booting from ISO (OracleLinux-9.4-x86_64.iso)
4. You will see the Oracle Linux boot menu
```

### 2.2 Boot Menu (First Screen)

```
+--------------------------------------------------------------+
|  Oracle Linux 9.4                                            |
|                                                              |
|  > Install Oracle Linux 9.4                                  |
|    Test this media & install Oracle Linux 9.4                |
|    Troubleshooting -->                                        |
+--------------------------------------------------------------+

ACTION: Press ENTER on "Install Oracle Linux 9.4"
```

### 2.3 Language Selection

```
+--------------------------------------------------------------+
|  WELCOME TO ORACLE LINUX 9.4                                 |
|                                                              |
|  What language would you like to use during the              |
|  installation process?                                       |
|                                                              |
|  English (United States) ← Select this                      |
|  [Continue]                                                  |
+--------------------------------------------------------------+

ACTION: Select "English (United States)" → Click Continue
```

### 2.4 Installation Summary Hub (Main Screen)

```
+--------------------------------------------------------------+
|  INSTALLATION SUMMARY                                        |
|                                                              |
|  LOCALIZATION                                                |
|  [!] Date & Time        Asia/Kolkata                        |
|  [!] Keyboard           English (US)                        |
|      Language Support   English (US)                        |
|                                                              |
|  SOFTWARE                                                    |
|  [!] Connect to Red Hat  ← SKIP (click, select "No thanks") |
|  [!] Installation Source Closest mirror                     |
|  [!] Software Selection  Minimal Install ← IMPORTANT        |
|                                                              |
|  SYSTEM                                                      |
|  [!] Installation Destination  ← Click to configure disk    |
|  [!] Network & Host Name        ← Click to configure        |
|      Security Policy   No profile selected                  |
|                                                              |
|  [!] Root Password      ← Set or disable                    |
|  [!] User Creation      ← Create oracle user                |
+--------------------------------------------------------------+

ACTION: Configure each section marked [!] before clicking "Begin Installation"
```

### 2.5 Date & Time

```
ACTION: Click "Date & Time"
  → Region: Asia
  → City: Kolkata  (or your region)
  → Enable "Network Time" toggle: ON
  → NTP Servers: click gear icon → add 10.0.1.5 (your internal NTP)
  → Click Done
```

### 2.6 Software Selection — CRITICAL

```
ACTION: Click "Software Selection"

Left panel — Base Environment:
  > Select: "Minimal Install"   ← No GUI, no extra packages
    (Do NOT select "Server with GUI" — wastes RAM)

Right panel — Additional Software:
  > Check: "Standard"           ← Basic system tools
  > Check: "System Tools"       ← iostat, netstat, etc.
  (Leave everything else unchecked)

→ Click Done
```

### 2.7 Installation Destination — Disk Partitioning

```
ACTION: Click "Installation Destination"

Select Disk:
  → You will see the vSAN virtual disk (e.g., "VMware Virtual disk, 60 GiB")
  → Click the disk to select it (blue checkmark appears)

Storage Configuration:
  → Select: "Custom"  (to see and control partitions)
  → Click Done

Manual Partitioning Screen:
  → Click "Click here to create them automatically" for auto layout
  → OR create manually (recommended):
```

**Partition Layout for Server VMs (no GUI, no separate /home):**

| Mount Point | Size | File System | Purpose |
|------------|------|-------------|---------|
| `/boot/efi` | 600 MB | EFI System Partition | UEFI boot loader |
| `/boot` | 1 GB | xfs | Kernel files |
| `swap` | Equal to RAM (8 GB) | swap | Emergency swap (K8s nodes: disable after install) |
| `/` | Remaining (~50 GB) | xfs | Root filesystem — all data here |

```
Why no separate /var or /home?
  - Server VMs have dedicated purposes (DB, K8s node, etc.)
  - Separate partitions add complexity without benefit for our use case
  - Container data goes on persistent volumes (vSAN PVCs), not /var
  - If /var fills up on K8s nodes, it's a container log issue — handle with log rotation
```

```
ACTION (in Manual Partitioning):
  Click "+" → Mount Point: /boot/efi  → Desired Capacity: 600 MiB → Add
  Click "+" → Mount Point: /boot      → Desired Capacity: 1 GiB   → Add
  Click "+" → Mount Point: swap       → Desired Capacity: 8 GiB   → Add
  Click "+" → Mount Point: /          → Desired Capacity: (leave blank for remaining) → Add

  For each partition, set:
    Device Type: Standard Partition (not LVM — simpler for template cloning)
    File System: xfs (for / and /boot), EFI System Partition (for /boot/efi)

→ Click Done → Accept Changes
```

### 2.8 Network & Host Name

```
ACTION: Click "Network & Host Name"

Left panel — interfaces:
  → You see "ens192" (VMware VMXNET3)
  → Toggle switch: ON (blue)

Host Name (bottom bar):
  → Type: ol9-template
  → Click Apply

Configure button (top right):
  → IPv4 Settings tab:
      Method: Manual
      Click Add:
        Address: 10.0.1.200
        Netmask:  24
        Gateway:  10.0.1.1
      DNS Servers: 10.0.1.5
      Search domains: internal.company.com
  → General tab:
      Check "Automatically connect to this network"
  → Click Save

→ Click Done
```

### 2.9 Root Password

```
ACTION: Click "Root Password"
  → Select "Lock root account" ← recommended for security
    (This disables root SSH login. Use sudo via the oracle user instead.)
  → Click Done
```

### 2.10 User Creation

```
ACTION: Click "User Creation"
  Full name: oracle
  User name: oracle
  Check: "Make this user administrator" (adds to wheel group → sudo)
  Password: TemplatePass2026!
    (You will change this per-VM after cloning — this is just for the template)
  → Click Done
```

### 2.11 Connect to Red Hat — SKIP

```
ACTION: Click "Connect to Red Hat"
  → Select "No, I prefer to register at a later time" or skip entirely
  → Oracle Linux uses its own ULN/yum repos, not Red Hat
  → Click Done
```

### 2.12 Begin Installation

```
ACTION: Click "Begin Installation" (bottom right)

Installation progress screen:
  → Packages being installed (takes 5-15 minutes depending on ISO type)
  → Watch: "Installing: kernel..." and "Installing: glibc..." etc.

When complete:
  → "Oracle Linux is now successfully installed"
  → Click "Reboot System"
```

### 2.13 Post-Reboot: First Login

```
Login screen appears (text console):
  ol9-template login: oracle
  Password: TemplatePass2026!

Verify:
  $ whoami
  oracle

  $ sudo whoami
  root

  $ ip addr show ens192
  (should show 10.0.1.200)

  $ ping -c 3 10.0.1.1
  (gateway ping should work)
```

---

## 3. Post-Install Template Hardening (Complete)

Run this entire script after first login on the template VM:

```bash
#!/bin/bash
# Oracle Linux 9 template hardening script
# Run as: sudo bash ol9-template-setup.sh

set -euo pipefail
echo "=== OL9 Template Setup Start ==="

# 1. Update all packages
echo "[1/15] Updating packages..."
dnf update -y

# 2. Install essential tools
echo "[2/15] Installing essential tools..."
dnf install -y \
  open-vm-tools \
  chrony \
  bind-utils \
  net-tools \
  tcpdump \
  curl \
  wget \
  vim \
  git \
  bash-completion \
  policycoreutils-python-utils \
  python3 \
  tar \
  unzip \
  jq \
  htop \
  iotop \
  sysstat \
  lsof \
  strace \
  tcpdump \
  nc \
  socat

# 3. Enable and start open-vm-tools
echo "[3/15] Configuring VMware tools..."
systemctl enable --now vmtoolsd
vmware-checkvm && echo "VMware environment detected OK"

# 4. Configure NTP with chrony
echo "[4/15] Configuring NTP..."
cat > /etc/chrony.conf << 'CHRONY'
server 10.0.1.5 iburst prefer
server pool.ntp.org iburst
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
CHRONY
systemctl enable --now chronyd
chronyc makestep
sleep 2
chronyc tracking

# 5. Configure SSH — disable root, enable key-based auth
echo "[5/15] Hardening SSH..."
cat > /etc/ssh/sshd_config.d/99-hardening.conf << 'SSHCFG'
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
X11Forwarding no
MaxAuthTries 5
ClientAliveInterval 300
ClientAliveCountMax 2
Banner /etc/issue.net
SSHCFG

echo "Authorized access only. All activity is monitored." > /etc/issue.net
systemctl restart sshd

# 6. Configure firewalld
echo "[6/15] Configuring firewall..."
systemctl enable --now firewalld
firewall-cmd --permanent --set-default-zone=public
firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --remove-service=dhcpv6-client
firewall-cmd --reload

# 7. Set SELinux to Permissive (required for K8s nodes)
echo "[7/15] Setting SELinux to Permissive..."
# Permissive logs violations but does not block — safer for K8s
setenforce 0
sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
getenforce  # Should return Permissive

# 8. Disable swap (REQUIRED for Kubernetes)
echo "[8/15] Disabling swap..."
swapoff -a
# Comment out swap line in fstab permanently
sed -i 's/^[^#].*swap.*/#&/' /etc/fstab
grep swap /etc/fstab  # Confirm it is commented out

# 9. Kernel parameters for Kubernetes
echo "[9/15] Setting kernel parameters..."
cat > /etc/modules-load.d/k8s.conf << 'MODULES'
overlay
br_netfilter
MODULES
modprobe overlay
modprobe br_netfilter

cat > /etc/sysctl.d/99-k8s.conf << 'SYSCTL'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
vm.swappiness                       = 0
net.ipv4.conf.all.forwarding        = 1
SYSCTL
sysctl --system

# 10. Set timezone
echo "[10/15] Setting timezone..."
timedatectl set-timezone Asia/Kolkata
timedatectl status

# 11. Configure /etc/hosts with local entries
echo "[11/15] Configuring /etc/hosts..."
cat >> /etc/hosts << 'HOSTS'
10.0.1.5    dns-server-01.internal.company.com dns-server-01
10.0.1.10   vcenter.internal.company.com vcenter
10.0.1.20   jump-host.internal.company.com jump-host
HOSTS

# 12. Set DNS resolver
echo "[12/15] Setting DNS resolver..."
nmcli connection modify ens192 ipv4.dns "10.0.1.5"
nmcli connection modify ens192 ipv4.dns-search "internal.company.com"
nmcli connection up ens192

# 13. Disable unnecessary services
echo "[13/15] Disabling unneeded services..."
systemctl disable --now postfix 2>/dev/null || true
systemctl disable --now avahi-daemon 2>/dev/null || true
systemctl disable --now bluetooth 2>/dev/null || true

# 14. Set proper ulimits for DB/K8s
echo "[14/15] Setting system limits..."
cat > /etc/security/limits.d/99-oracle.conf << 'LIMITS'
*    soft nofile 65536
*    hard nofile 65536
*    soft nproc  65536
*    hard nproc  65536
oracle soft memlock unlimited
oracle hard memlock unlimited
LIMITS

# 15. Clean up for template
echo "[15/15] Cleaning up for template..."
dnf clean all
rm -f /etc/machine-id
rm -f /var/lib/dbus/machine-id
truncate -s 0 /etc/machine-id
rm -f /tmp/yum.log
history -c

echo "=== Template hardening COMPLETE ==="
echo "Next steps:"
echo "  1. Power off: sudo poweroff"
echo "  2. In vCenter: remove NIC MAC → Convert to Template"
```

---

## 4. Convert to Template and Clone VMs

### 4.1 Remove MAC Address (Required Before Templating)

```bash
# In vCenter UI:
#   Right-click ol9-base-template VM → Edit Settings
#   Select Network Adapter 1 → expand
#   MAC Address: click "Manual" → clear the MAC address field
#   Click OK

# OR via govc:
govc vm.network.remove -vm=ol9-base-template "Network adapter 1"
govc vm.network.add -vm=ol9-base-template \
  -net="PG-Management" \
  -net.adapter=vmxnet3
```

### 4.2 Power Off and Convert

```bash
# Power off
govc vm.power -off ol9-base-template

# Convert to template
govc vm.markastemplate ol9-base-template

# Verify
govc find . -type m | grep ol9-base-template
# If no output, it's now a template (not shown as VM)

govc find . -type t | grep ol9-base-template
# Should return: /Datacenter/vm/ol9-base-template
```

### 4.3 Bulk Clone All 27 VMs

```bash
#!/bin/bash
# bulk-clone-vms.sh — Clone all 27 VMs from OL9 template
# Run from jump host with GOVC_URL/USER/PASS exported

TEMPLATE="ol9-base-template"
DATASTORE="vsanDatastore"
CLUSTER="VxRail-Cluster"

# VM definition: name, vCPU, RAM_MB, disk_GB, network, IP
declare -A VM_DEFS=(
# K8s Control Plane (3 masters)
  ["k8s-master-1"]="4,8192,60,PG-K8s-Nodes,10.0.3.11"
  ["k8s-master-2"]="4,8192,60,PG-K8s-Nodes,10.0.3.12"
  ["k8s-master-3"]="4,8192,60,PG-K8s-Nodes,10.0.3.13"
# K8s Workers — Dev/QA
  ["k8s-worker-1"]="8,16384,100,PG-K8s-Nodes,10.0.4.21"
  ["k8s-worker-2"]="8,16384,100,PG-K8s-Nodes,10.0.4.22"
# K8s Workers — PreProd
  ["k8s-worker-3"]="8,32768,100,PG-K8s-Nodes,10.0.4.23"
  ["k8s-worker-4"]="8,32768,100,PG-K8s-Nodes,10.0.4.24"
# K8s Workers — Prod
  ["k8s-worker-5"]="16,32768,100,PG-K8s-Nodes,10.0.4.25"
  ["k8s-worker-6"]="16,32768,100,PG-K8s-Nodes,10.0.4.26"
# PostgreSQL VMs
  ["db-dev-01"]="2,8192,100,PG-Databases,10.0.5.11"
  ["db-qa-01"]="2,8192,100,PG-Databases,10.0.5.12"
  ["db-preprod-01"]="4,16384,200,PG-Databases,10.0.5.13"
  ["db-preprod-02"]="4,16384,200,PG-Databases,10.0.5.14"
  ["db-prod-01"]="8,32768,500,PG-Databases,10.0.5.15"
  ["db-prod-02"]="8,32768,500,PG-Databases,10.0.5.16"
  ["db-prod-03"]="8,32768,500,PG-Databases,10.0.5.17"
# MongoDB VMs
  ["mongo-dev-01"]="2,8192,100,PG-Databases,10.0.5.21"
  ["mongo-qa-01"]="2,8192,100,PG-Databases,10.0.5.22"
  ["mongo-preprod-01"]="4,16384,200,PG-Databases,10.0.5.23"
  ["mongo-preprod-02"]="4,16384,200,PG-Databases,10.0.5.24"
  ["mongo-prod-01"]="8,32768,500,PG-Databases,10.0.5.25"
  ["mongo-prod-02"]="8,32768,500,PG-Databases,10.0.5.26"
  ["mongo-prod-03"]="8,32768,500,PG-Databases,10.0.5.27"
# Shared Services
  ["minio-01"]="4,16384,200,PG-Services,10.0.6.11"
  ["harbor-01"]="4,16384,200,PG-Services,10.0.6.12"
  ["monitoring-01"]="4,8192,100,PG-Services,10.0.6.13"
# Infrastructure
  ["jump-host"]="2,4096,60,PG-Management,10.0.1.20"
)

for VM_NAME in "${!VM_DEFS[@]}"; do
  IFS=',' read -r CPU RAM DISK NET IP <<< "${VM_DEFS[$VM_NAME]}"
  
  echo "Cloning $VM_NAME (${CPU}vCPU, ${RAM}MB, ${DISK}GB, $IP)..."
  
  govc vm.clone \
    -vm="$TEMPLATE" \
    -on=false \
    -net="$NET" \
    -ds="$DATASTORE" \
    "$VM_NAME"
  
  # Set CPU and RAM
  govc vm.change -vm="$VM_NAME" -c="$CPU" -m="$RAM"
  
  # Extend disk if > 60GB
  if [ "$DISK" -gt 60 ]; then
    govc vm.disk.change -vm="$VM_NAME" -size="${DISK}GB"
  fi
  
  # Enable disk UUID (REQUIRED for vSphere CSI)
  govc vm.change -vm="$VM_NAME" -e "disk.enableUUID=TRUE"
  
  echo "  Created: $VM_NAME"
done

echo "All VMs cloned. Power them on:"
echo "  govc vm.power -on k8s-master-1 k8s-master-2 k8s-master-3"
```

### 4.4 Post-Clone: Set Static IP on Each VM

After powering on each cloned VM, set its static IP:

```bash
# Run on each VM after first boot (SSH in via DHCP or console)
# Example for k8s-master-1:

VM_HOSTNAME="k8s-master-1"
VM_IP="10.0.3.11"
VM_PREFIX="24"
VM_GATEWAY="10.0.3.1"
VM_DNS="10.0.1.5"

# Set hostname
sudo hostnamectl set-hostname ${VM_HOSTNAME}.internal.company.com

# Configure static IP with nmcli
sudo nmcli connection modify ens192 \
  ipv4.method manual \
  ipv4.addresses "${VM_IP}/${VM_PREFIX}" \
  ipv4.gateway "${VM_GATEWAY}" \
  ipv4.dns "${VM_DNS}" \
  ipv4.dns-search "internal.company.com" \
  connection.autoconnect yes

# Apply changes
sudo nmcli connection up ens192

# Verify
ip addr show ens192
# Should show: inet 10.0.3.11/24

ping -c 2 ${VM_GATEWAY}
ping -c 2 vcenter.internal.company.com
```

### 4.5 Ansible Playbook — Automate IP Setup on All 27 VMs

```yaml
# set-static-ips.yml
# Run: ansible-playbook -i inventory.ini set-static-ips.yml

- name: Set static IPs on all VMs
  hosts: all
  become: yes
  tasks:
    - name: Set hostname
      hostname:
        name: "{{ inventory_hostname }}.internal.company.com"

    - name: Set static IP via nmcli
      community.general.nmcli:
        conn_name: ens192
        type: ethernet
        ip4: "{{ ansible_host }}/24"
        gw4: "{{ gateway }}"
        dns4:
          - 10.0.1.5
        dns4_search:
          - internal.company.com
        state: present
        autoconnect: yes

    - name: Restart network
      command: nmcli connection up ens192

    - name: Verify connectivity
      ping:
```

