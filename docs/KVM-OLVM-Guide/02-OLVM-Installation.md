# 02 — OLVM Installation

> **OLVM** (Oracle Linux Virtualization Manager) is Oracle's enterprise KVM management platform based on oVirt. It provides a centralised web UI, REST API, and HA engine for managing multiple KVM hosts.

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         OLVM ENGINE SERVER                                │
│   olvm-engine.internal (dedicated server — NOT a KVM host)               │
│                                                                           │
│   ┌────────────────┐  ┌──────────────┐  ┌────────────────────────────┐  │
│   │  oVirt Engine  │  │  PostgreSQL  │  │  Keycloak (SSO/Auth)       │  │
│   │  (WildFly app) │  │  (embedded)  │  │  (LDAP/AD integration)     │  │
│   └────────────────┘  └──────────────┘  └────────────────────────────┘  │
│   Port 443 (HTTPS)  Port 8443  REST API: /ovirt-engine/api              │
└───────────────────────────────┬──────────────────────────────────────────┘
                                │  VDSM Agent (port 54321)
        ┌───────────────────────┼───────────────────────┐
        |                       |                       |
┌───────┴──────┐       ┌────────┴─────┐       ┌────────┴─────┐
│  KVM Host-1  │       │  KVM Host-2  │       │  KVM Host-3  │
│  OL9/RHEL9   │       │  OL9/RHEL9   │       │  OL9/RHEL9   │
│  VDSM+libvirt│       │  VDSM+libvirt│       │  VDSM+libvirt│
│  10.0.1.11   │       │  10.0.1.12   │       │  10.0.1.13   │
└──────────────┘       └──────────────┘       └──────────────┘
```

---

## Requirements

### OLVM Engine Server

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 4 cores | 8 cores |
| RAM | 8 GB | 16 GB |
| Disk | 50 GB | 100 GB SSD |
| OS | Oracle Linux 9 | Oracle Linux 9 |
| Network | 1 GbE | 10 GbE |

### KVM Hosts (oVirt Nodes)

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 16 cores (VT-x/AMD-V) | 64 cores |
| RAM | 64 GB | 512 GB |
| Disk | 100 GB for OS | 100 GB OS + NVMe for VMs |
| OS | Oracle Linux 9 | Oracle Linux 9 (OLVM Host) |
| Network | 2x 10 GbE | 2x 25 GbE (bonded) |

---

## Part 1: OLVM Engine Installation

### Step 1.1: Prepare the Engine Server

```bash
# Install Oracle Linux 9 on the dedicated engine server
# Set hostname
hostnamectl set-hostname olvm-engine.internal

# Add engine server to /etc/hosts on all servers
echo "10.0.1.10  olvm-engine.internal  olvm-engine" >> /etc/hosts

# Update OS
dnf update -y

# Disable firewalld temporarily during install (re-enable after)
systemctl stop firewalld
systemctl disable firewalld
# Note: OLVM install script configures firewall rules; re-enable after setup

# Set SELinux to Enforcing
setenforce 1
sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
```

### Step 1.2: Enable OLVM Repository

```bash
# Enable Oracle Linux repos for OLVM
# Option A: Oracle Linux with UEK
dnf install -y oraclelinux-developer-release-el9
dnf config-manager --enable ol9_developer

# Option B: Using Oracle Linux Virtualization Manager repo
dnf install -y \
  https://resources.ovirt.org/pub/yum-repo/ovirt-release44.rpm

# Or for OLVM specifically (Oracle's distribution):
# Follow Oracle documentation at:
# https://docs.oracle.com/en/virtualization/oracle-linux-virtualization-manager/

# Install OLVM / oVirt engine
dnf install -y ovirt-engine

# Verify package installed
rpm -qa | grep ovirt-engine
```

### Step 1.3: Run Engine Setup

```bash
# Run the interactive setup wizard
engine-setup

# The wizard will ask for the following (recommended answers shown):
#
# Configure Engine on this host (Yes/No): Yes
# Configure Image I/O Proxy on this host: Yes
# Configure WebSocket Proxy on this host: Yes
# Configure Data Warehouse on this host: Yes (for metrics/reports)
#
# HTTP port (80): 80
# HTTPS port (443): 443
#
# Engine admin password: [set strong password]
# Application mode: Both (Virt + Gluster)
#
# Default Data Center storage type: NFS (or iSCSI for SAN environments)
#
# Configure local NFS storage (Yes): Yes (for ISO domain initially)
# Local domain path: /var/lib/exports/iso
#
# Engine FQDN: olvm-engine.internal
# Configure firewall: Yes
#
# Confirm install (oK): oK

# Setup takes ~10-15 minutes
# At the end it will print: "Execution of setup completed successfully"
```

### Step 1.4: Verify Engine is Running

```bash
# Check all OLVM services
systemctl status ovirt-engine
systemctl status ovirt-engine-notifier

# Check database
su - postgres -c "psql -c '\l'" | grep engine

# Test web access
curl -k https://olvm-engine.internal/ovirt-engine/
# Should return HTTP 200 with HTML

# Check engine logs
tail -f /var/log/ovirt-engine/engine.log

echo "OLVM Engine is running at https://olvm-engine.internal/ovirt-engine"
echo "Login: admin@internal  Password: <what you set in engine-setup>"
```

---

## Part 2: Configure OLVM Web UI

*Screenshot: Open https://olvm-engine.internal/ovirt-engine in a browser — you will see the OLVM login screen*

### Access and Initial Login

```
URL: https://olvm-engine.internal/ovirt-engine
Username: admin@internal
Password: <set during engine-setup>
```

### Configure Data Center

```
1. Navigate: Compute > Data Centers
2. Click "New"
3. Name: OnPrem-DC
4. Storage Type: NFS (or Shared — for multi-host)
5. Compatibility Version: 4.7 (latest)
6. Click OK
```

### Configure Cluster

```
1. Navigate: Compute > Clusters
2. Click "New"
3. Data Center: OnPrem-DC
4. Name: OnPrem-Cluster
5. CPU Type: Intel Skylake Server (or match your actual CPU)
6. Enable KSM (Kernel Same-page Merging): Yes
7. Enable Memory Balloon: Yes
8. Scheduling Policy: evenly_distributed
9. Click OK
```

---

## Part 3: Add KVM Hosts to OLVM

### Step 3.1: Prepare KVM Hosts

Run on **each KVM host** before adding to OLVM:

```bash
# Install Oracle Linux 9 on each host
# Set hostname
hostnamectl set-hostname kvm-host-01.internal  # Change per host

# Add engine and hosts to /etc/hosts
cat >> /etc/hosts << 'EOF'
10.0.1.10  olvm-engine.internal
10.0.1.11  kvm-host-01.internal
10.0.1.12  kvm-host-02.internal
10.0.1.13  kvm-host-03.internal
EOF

# Update OS
dnf update -y

# Install VDSM (Virtual Desktop Server Manager — OLVM's agent)
# Option A: Let OLVM install it automatically (recommended)
# OLVM will SSH in and install VDSM when you add the host in the UI

# Option B: Pre-install manually
dnf install -y \
  https://resources.ovirt.org/pub/yum-repo/ovirt-release44.rpm
dnf install -y vdsm vdsm-gluster

# Set up SSH key access from engine to hosts
# The engine uses SSH key (not password) to manage hosts
# During "Add Host" in OLVM UI, it will automatically copy its SSH key

# Verify hardware virtualisation
virt-host-validate

# Open required firewall ports (VDSM)
firewall-cmd --permanent --add-port=54321/tcp   # VDSM
firewall-cmd --permanent --add-port=16514/tcp   # libvirt TLS
firewall-cmd --permanent --add-port=5900-6923/tcp # VNC console
firewall-cmd --permanent --add-port=49152-49216/tcp # VM migration
firewall-cmd --reload
```

### Step 3.2: Add Host in OLVM UI

```
Screenshot: In OLVM web UI, navigate to Compute > Hosts

1. Click "New"
2. Host Cluster: OnPrem-Cluster
3. Name: kvm-host-01
4. Hostname/IP: 10.0.1.11
5. Authentication:
   - Username: root
   - Password: <root password>
   (OLVM will copy its SSH key to the host automatically)
6. Advanced Options:
   - Configure Power Management: Yes (if you have IPMI/iDRAC)
   - Automatically configure host firewall: Yes
7. Click OK

OLVM will:
  - SSH into the host
  - Install VDSM
  - Configure libvirt
  - Register the host
  - Run validation checks
  - Change host status to "Up" (may take 3-5 minutes)

Repeat for kvm-host-02 and kvm-host-03
```

### Step 3.3: Verify Hosts via CLI

```bash
# Use OLVM REST API to check host status
curl -k -u admin@internal:<password> \
  https://olvm-engine.internal/ovirt-engine/api/hosts \
  -H "Accept: application/json" | python3 -m json.tool | grep -E '(name|status)'

# Or use ovirt-shell (install with: pip3 install ovirt-engine-sdk-python)
python3 << 'EOF'
import ovirtsdk4 as sdk
conn = sdk.Connection(
    url='https://olvm-engine.internal/ovirt-engine/api',
    username='admin@internal',
    password='<password>',
    insecure=True
)
hosts = conn.system_service().hosts_service().list()
for h in hosts:
    print(f"{h.name}: {h.status}")
conn.close()
EOF
```

---

## Part 4: Configure Storage Domains

### 4a. NFS Storage Domain (NetApp)

```
Screenshot: Navigate to Storage > Domains > New Domain

1. Name: netapp-data
2. Domain Function: Data
3. Storage Type: NFS
4. Host (to use for mount): kvm-host-01
5. Export Path: 10.0.3.10:/vol/olvm_data
6. NFS Version: v4.1
7. Mount Options: rsize=65536,wsize=65536,hard,intr
8. Click OK

OLVM will mount the NFS share and initialise the storage domain.
```

### 4b. iSCSI Storage Domain

```bash
# First, discover iSCSI targets from OLVM hosts
iscsiadm -m discovery -t sendtargets -p 10.0.3.20
iscsiadm -m node -T iqn.2026-01.com.storage:olvm-data -l

# Then in OLVM UI:
# Storage > Domains > New Domain
# Storage Type: iSCSI
# Click "Discover Targets"
# Enter iSCSI portal IP: 10.0.3.20
# Select the LUN
# Click OK
```

### 4c. ISO Domain (for installation media)

```
Screenshot: Storage > Domains > New Domain

1. Name: iso-domain
2. Domain Function: ISO
3. Storage Type: NFS
4. Export Path: 10.0.3.10:/vol/olvm_iso
5. Click OK

Upload ISO files:
  engine-iso-uploader list
  engine-iso-uploader upload --nfs-server=10.0.3.10:/vol/olvm_iso ubuntu-22.04.iso
```

---

## Part 5: Configure Logical Networks

```
Screenshot: Network > Networks > New Network

Create these networks:
1. ovirtmgmt    — management network (already exists, mapped to bond0)
2. vm-network   — for VM traffic (VLAN 100)
3. storage-net  — for storage/migration (VLAN 200)
4. migration    — for live VM migration (VLAN 300)

For each network, assign it to the cluster:
  Network > Networks > [network name] > Clusters tab > Assign
```

```bash
# Verify networks are configured on host
virsh net-list --all

# On a KVM host, check OLVM has configured the bridge
ip link show | grep -E '(bond|vlan|bridge)'

# Check VDSM-managed networks
cat /var/run/vdsm/netinfo.json | python3 -m json.tool
```

---

## Part 6: OLVM High Availability Setup

### Enable Fence Agents (Power Management)

```
Screenshot: Compute > Hosts > [host] > Edit

Power Management tab:
  Enable: Yes
  Type: ipmilan
  Address: 192.168.10.11 (IPMI IP)
  Username: ipmi_admin
  Password: ipmi_password
  Options: lanplus=1

This enables OLVM to power-cycle hosts that become unresponsive,
allowing it to safely restart VMs on other hosts (fencing).
```

### Enable HA for VMs

```
Screenshot: Compute > Virtual Machines > [VM] > Edit > High Availability tab

  Highly Available: Yes
  Priority: Medium (or High for critical VMs)

When the host running this VM fails:
  1. OLVM detects the host is down (via fencing)
  2. Powers off the host via IPMI (to prevent split-brain)
  3. Restarts the VM on another host in the cluster
  Typical failover time: 2-4 minutes
```

---

## Part 7: OLVM REST API Usage

```bash
# List all VMs
curl -k -u admin@internal:<pwd> \
  https://olvm-engine.internal/ovirt-engine/api/vms \
  -H "Accept: application/json" | python3 -m json.tool

# Start a VM
VM_ID="<vm-uuid>"
curl -k -u admin@internal:<pwd> \
  -X POST \
  https://olvm-engine.internal/ovirt-engine/api/vms/$VM_ID/start \
  -H "Content-Type: application/json" \
  -d '{"action": {}}'

# Get VM stats
curl -k -u admin@internal:<pwd> \
  https://olvm-engine.internal/ovirt-engine/api/vms/$VM_ID/statistics \
  -H "Accept: application/json" | python3 -m json.tool

# Migrate a VM to another host
curl -k -u admin@internal:<pwd> \
  -X POST \
  https://olvm-engine.internal/ovirt-engine/api/vms/$VM_ID/migrate \
  -H "Content-Type: application/json" \
  -d '{"host": {"name": "kvm-host-02"}}'
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Host stuck in "Installing" | SSH key copy failed | Manually copy engine SSH key: `ssh-copy-id root@kvm-host-01` |
| Host "Non Responsive" | Network/VDSM issue | `systemctl restart vdsmd` on the host |
| Storage domain "Inactive" | NFS mount failed | Check NFS export policy; `showmount -e 10.0.3.10` |
| VM migration failed | Incompatible CPU model | Set cluster CPU to `host-model` in cluster settings |
| "Cannot add host" | Firewall blocking port 22 | `firewall-cmd --add-service=ssh --permanent; firewall-cmd --reload` |
| Engine web UI not loading | ovirt-engine service down | `systemctl restart ovirt-engine; tail -f /var/log/ovirt-engine/engine.log` |
| "Fence agent not configured" | Power management not set | Configure IPMI in host settings (required for HA fencing) |

---

*Next: [03-KVM-Networking.md](03-KVM-Networking.md)*
