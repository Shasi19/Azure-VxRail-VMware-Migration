# Procurement Guide — What You Need to Buy

> **Principle:** Your 6-node VxRail gives you compute + storage. Everything below fills in the gaps: networking, licensing, management tools, and Azure connectivity for migration data transfer.

---

## 1. Summary — What You Already Have vs. What You Need

```
ALREADY HAVE (from VxRail purchase):
  ✅ 6 ESXi hypervisors (compute)
  ✅ vSAN distributed storage
  ✅ vCenter Server
  ✅ VxRail Manager
  ✅ VMware vSphere Enterprise Plus license (bundled with VxRail)
  ✅ VMware vSAN license (bundled with VxRail)
  ✅ 10 GbE or 25 GbE NICs on each node
  ✅ Internal cabling (SFP+ for vSAN traffic, typically pre-cabled by Dell)

NEED TO PROCURE (checklist below):
  ❗ Top-of-Rack switches (if not already sized for VLAN segmentation)
  ❗ Azure site-to-site VPN or ExpressRoute (for migration data transfer)
  ❗ TLS certificates (wildcard for internal domains)
  ❗ Additional IP address range / DHCP reservation
  ❗ Software tools (govc, kubectl, Helm, Ansible)
  ❗ Backup storage (NAS or external disk for Velero + DB dumps)
  ❗ DNS server (VM — no hardware needed)
  ❗ Jump host VM (no hardware — just a VM on VxRail)
```

---

## 2. Networking — Top-of-Rack (ToR) Switches

> **Critical:** VxRail nodes connect to ToR switches. If your current switches don't support VLAN trunking for multiple port groups (K8s nodes, databases, services), you either need new switches or reconfiguration.

### 2.1 What to Check on Your Current Switches

```
Does your current switch support:
  ✅ 802.3ad LACP (for bonded NICs from VxRail)
  ✅ 802.1Q VLAN trunking (for DVS port groups)
  ✅ Jumbo frames / MTU 9000 (for vSAN traffic)
  ✅ STP / RSTP (loop prevention)
  ✅ Enough SFP+ / QSFP ports for all VxRail uplinks
  ✅ Sufficient bandwidth (6 nodes × 2 × 25 GbE = 300 Gbps if all saturated)
```

### 2.2 Recommended Switches (if purchasing new)

#### Option A — Dell PowerSwitch (recommended for Dell VxRail)
Dell VxRail is validated with Dell PowerSwitch for zero-touch integration:

| Model | Ports | Speed | Use Case | Est. Price |
|-------|-------|-------|----------|-----------|
| **Dell PowerSwitch S5248F-ON** | 48× 25 GbE SFP28 + 6× 100 GbE QSFP28 | 25 GbE | Primary ToR switch for 6 VxRail nodes | $12,000–$18,000 |
| **Dell PowerSwitch S5224F-ON** | 24× 25 GbE + 4× 100 GbE | 25 GbE | Smaller secondary switch | $8,000–$12,000 |
| **Dell PowerSwitch N3248TE-ON** | 48× 10 GbE + 4× 100 GbE | 10 GbE | Budget option if nodes are 10 GbE | $5,000–$8,000 |

**Recommended setup: 2× S5248F-ON for redundancy (one per switch stack)**

#### Option B — Cisco Catalyst (common enterprise choice)

| Model | Ports | Speed | Est. Price |
|-------|-------|-------|-----------|
| Cisco Catalyst 9300-48UXM | 48× mGig + 4× 25 GbE | 10/25 GbE | $15,000–$25,000 |
| Cisco Nexus 93180YC-FX | 48× 25 GbE + 6× 100 GbE | 25 GbE | $20,000–$35,000 |

#### Option C — Use Existing Switches (if they meet requirements above)

If existing switches support VLAN trunking and LACP, you only need configuration changes — no new hardware.

### 2.3 Switch Configuration Requirements

```
# For each VxRail node uplink (example: Dell PowerSwitch OS10 syntax)

# LACP bond port (VxRail uses LACP by default)
interface ethernet 1/1/1
  description VxRail-1-vmnic0
  no shutdown
  switchport mode trunk
  switchport trunk allowed vlan 10,20,30,40,80,90
  flowcontrol receive off
  mtu 9216     # jumbo frames for vSAN

interface ethernet 1/1/2
  description VxRail-1-vmnic1
  no shutdown
  switchport mode trunk
  switchport trunk allowed vlan 10,20,30,40,80,90
  flowcontrol receive off
  mtu 9216

# LACP port-channel for both uplinks (redundancy)
interface port-channel 10
  description VxRail-1-Bond
  switchport mode trunk
  switchport trunk allowed vlan 10,20,30,40,80,90
  mtu 9216

# Repeat for all 6 VxRail nodes (port-channels 10-60)
```

---

## 3. Azure Connectivity — For Migration Data Transfer

During migration, you need to transfer data from Azure (PostgreSQL dumps, MongoDB dumps, container images) to your on-prem VxRail. Options:

### 3.1 Option A — Azure Site-to-Site VPN (Recommended for most)

**Cost:** ~$150–$500/month during migration (can cancel after)
**Speed:** 100 Mbps–10 Gbps depending on SKU
**Setup time:** 1–3 days

```
Azure Portal:
  Virtual Network Gateway (VpnGw1 or higher) → connect to on-prem IPsec VPN device

On-prem VPN device options:
  ├── If you have an existing firewall (Palo Alto, Cisco ASA, FortiGate) — use it
  ├── If not, deploy a VPN-capable appliance:
  │     Cisco ISR 4321 (~$3,000) or
  │     Fortinet FortiGate 60F (~$1,000) or
  │     pfSense on a VM (free + cheap hardware)
  └── Or use Azure VPN Gateway + a software router on VxRail VM
```

#### Azure VPN Gateway SKUs

| SKU | Max Bandwidth | Est. Monthly Cost |
|-----|--------------|------------------|
| VpnGw1 | 650 Mbps | ~$150/month |
| VpnGw2 | 1 Gbps | ~$300/month |
| VpnGw3 | 1.25 Gbps | ~$500/month |
| VpnGw1AZ (zone redundant) | 650 Mbps | ~$200/month |

**For migration only:** VpnGw1 is sufficient for pg_dump transfers and image pulls.

### 3.2 Option B — Azure ExpressRoute (If Already Available)

If your organization already has an ExpressRoute connection to Azure:
- **Use it** — fastest option, no public internet for data transfer
- Verify bandwidth is sufficient: a 100 GB PostgreSQL dump takes ~15 minutes on 1 Gbps

### 3.3 Option C — Azure Data Transfer (No VPN, Internet)

If VPN setup is too complex:
- Use `az storage` to download dumps to a local machine, then `scp` to VxRail
- Use `pg_dump | gzip` + `scp` directly
- **Risk:** Slower, depends on internet bandwidth, less secure

---

## 4. TLS Certificates

You need HTTPS certificates for Harbor, ArgoCD, MinIO, Prometheus/Grafana, and Kubernetes ingress.

### 4.1 Option A — Internal CA (No Cost, Recommended for Isolated Environments)

Deploy `step-ca` (Smallstep) or use `openssl` to build your own Certificate Authority:

```bash
# No purchase needed — deploy as a VM on VxRail
# Covers: *.internal.company.com
# See 11-Initial-Setup-Before-Migration.md for step-ca setup
```

### 4.2 Option B — Commercial Wildcard Certificate (Easy, ~$100–$500/year)

Buy a wildcard cert from a public CA and use it for all services:

| Provider | Wildcard Cert Price | Notes |
|----------|--------------------|-|
| DigiCert | ~$600/year | Enterprise support |
| Sectigo (Comodo) | ~$100–200/year | Budget-friendly |
| GlobalSign | ~$400/year | Well-trusted |

Buy: `*.internal.company.com` — covers `harbor.internal.company.com`, `argocd.internal.company.com`, etc.

### 4.3 Option C — Let's Encrypt (Free, Needs Public DNS)

Works only if `company.com` has public DNS and you can do DNS-01 challenges. Not suitable for purely internal addresses.

---

## 5. Software Licenses

### 5.1 Already Included with VxRail

| Software | License Included |
|----------|----------------|
| VMware ESXi | ✅ vSphere Enterprise Plus (bundled) |
| VMware vCenter Server | ✅ Standard (bundled) |
| VMware vSAN | ✅ Enterprise or Advanced (bundled) |
| VxRail Manager | ✅ Included with hardware support |
| VMware HCX (migration tool) | ❓ Check with Dell — sometimes bundled with VxRail |

### 5.2 Open-Source Tools (Free)

| Tool | Purpose | Download |
|------|---------|---------|
| Kubernetes (kubeadm) | Container orchestration | kubernetes.io |
| Calico | K8s networking (CNI) | projectcalico.org |
| MetalLB | Bare-metal load balancer | metallb.universe.tf |
| Harbor | Container registry | goharbor.io |
| ArgoCD | GitOps deployment | argo-cd.readthedocs.io |
| Prometheus + Grafana | Monitoring | prometheus.io |
| MinIO | Object storage | min.io |
| Patroni | PostgreSQL HA | github.com/patroni |
| MongoDB 7.0 Community | Document DB | mongodb.com |
| PostgreSQL 15 | Relational DB | postgresql.org |
| Velero | K8s backup | velero.io |
| govc | vSphere CLI | github.com/vmware/govmomi |
| Helm | K8s package manager | helm.sh |
| step-ca | Internal CA | smallstep.com |

### 5.3 Optional Commercial Tools

| Tool | Purpose | Cost | Notes |
|------|---------|------|-------|
| Rancher (SUSE) | K8s management UI | $25k+/year | Easier cluster management |
| Red Hat OpenShift | Enterprise K8s | $30k+/year | Replaces kubeadm entirely |
| VMware Tanzu | K8s on vSphere (native) | Add-on license | Tighter vSphere integration than kubeadm |
| Datadog | Monitoring + APM | $15–$23/host/month | Better than open-source for enterprise |
| PagerDuty | Incident alerting | $21/user/month | Replace manual alerting |
| HashiCorp Vault Enterprise | Secrets mgmt | $50k+/year | Community edition is free |
| Portworx | K8s storage | $20k+/year | Alternative to vSphere CSI |
| GitLab EE | CI/CD + registry | $29/user/month | Replaces ACR CI/CD |

---

## 6. Backup Storage

Kubernetes backups (Velero) and database dumps need external storage — not on vSAN (separate from what you're protecting).

### 6.1 NAS Device (Recommended)

| Device | Capacity | Speed | Price | Notes |
|--------|---------|-------|-------|-------|
| **Synology DS1823xs+** | Up to 192 TB with expansion | 10 GbE | ~$3,000 + drives | NFS shares for Velero + DB backups |
| **QNAP TS-873AeU** | Up to 144 TB | 10 GbE | ~$2,500 + drives | Good 10 GbE support |
| **Dell PowerVault ME5012** | Up to 192 TB | 10 GbE iSCSI | ~$8,000 | Enterprise, Dell support |
| **Existing NAS (if you have one)** | — | — | $0 | Use NFS share |

**Recommended capacity:** 20–30 TB usable for:
- Daily PostgreSQL dumps: ~500 GB × 4 envs = 2 TB
- Weekly full backups: 10 TB
- VM snapshots: 5 TB
- Velero cluster backups: 2 TB
- **Buffer:** always plan for 3x actual data

### 6.2 Configure MinIO as Backup Target (on vSAN)

If you don't want external NAS, MinIO (on VxRail) can serve as backup target too. Acceptable for dev/QA backups but **not recommended for prod** (backup and primary on same hardware).

---

## 7. Management and Operations Tools

These are free software tools to install on your jump host VM:

### 7.1 Jump Host VM — Install These Tools

```bash
# Run on your jump host VM (Ubuntu 22.04 on VxRail)

# govc — VMware vSphere CLI
curl -L -o - "https://github.com/vmware/govmomi/releases/latest/download/govc_Linux_x86_64.tar.gz" \
  | sudo tar -C /usr/local/bin -xvzf - govc

# kubectl — Kubernetes CLI
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Helm — Kubernetes package manager
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# k9s — Terminal K8s UI (great for operations)
curl -sS https://webinstall.dev/k9s | bash

# kubectx + kubens — quick cluster/namespace switching
sudo git clone https://github.com/ahmetb/kubectx /opt/kubectx
sudo ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx
sudo ln -s /opt/kubectx/kubens /usr/local/bin/kubens

# Ansible — for parallel SSH commands to all nodes
sudo apt install -y ansible

# PostgreSQL client (for remote pg_dump)
sudo apt install -y postgresql-client-15

# MongoDB tools (for mongodump)
wget -qO - https://www.mongodb.org/static/pgp/server-7.0.asc | sudo apt-key add -
echo "deb [ arch=amd64 ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" \
  | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
sudo apt update && sudo apt install -y mongodb-mongosh mongodb-database-tools

# Azure CLI (for accessing Azure resources during migration)
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# MinIO client
wget https://dl.min.io/client/mc/release/linux-amd64/mc -O /usr/local/bin/mc
chmod +x /usr/local/bin/mc

# Velero CLI
VELERO_VERSION="v1.13.0"
curl -fsSL https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VERSION}/velero-${VELERO_VERSION}-linux-amd64.tar.gz \
  | tar -xzf - && sudo mv velero-${VELERO_VERSION}-linux-amd64/velero /usr/local/bin/

# cloud-localds (for creating cloud-init ISOs)
sudo apt install -y cloud-image-utils

# step CLI (for internal CA)
wget https://dl.smallstep.com/gh-release/cli/gh-release-header/v0.25.0/step_linux_0.25.0_amd64.tar.gz
tar -xzf step_linux_0.25.0_amd64.tar.gz && sudo mv step_*/bin/step /usr/local/bin/

echo "All tools installed."
```

---

## 8. Complete Procurement Checklist

### 8.1 Hardware (Buy If Needed)

| Item | Need | Reason | Est. Cost |
|------|------|--------|-----------|
| Top-of-Rack switches (2× redundant) | ❓ Check existing | VLAN trunking for DVS port groups | $16,000–$36,000 |
| SFP28 (25 GbE) fiber cables | ❓ Check existing | Connect VxRail to ToR switches | $50–$200 each |
| VPN appliance (if no existing firewall) | ❓ Check existing | Azure connectivity for migration | $1,000–$5,000 |
| NAS for external backup | ❓ Check existing | Velero + DB backups off VxRail | $3,000–$8,000 + drives |
| UPS (uninterruptible power supply) | ❓ Check existing | Protect VxRail during power events | $2,000–$8,000 |

### 8.2 Software Licenses (Buy If Needed)

| Item | Need | Reason | Est. Cost |
|------|------|--------|-----------|
| Wildcard TLS cert (`*.internal.company.com`) | ❓ Optional | HTTPS for all services | $100–$600/year |
| Azure VPN Gateway | ✅ Required | Migration data transfer | $150–$500/month (cancel after) |
| GitLab EE or GitHub Enterprise | ❓ Check existing | ArgoCD needs a Git repo | $0 (community) or $29/user/month |
| PagerDuty / OpsGenie | ❓ Optional | On-call alerting for Prod | $21+/user/month |

### 8.3 Everything Else (Free)

All other tools (Kubernetes, Harbor, ArgoCD, Prometheus, Grafana, MinIO, Patroni, MongoDB, PostgreSQL, Calico, MetalLB, Velero, Helm, govc, kubectl) are open-source with no license cost.

---

## 9. Total Estimated Additional Investment

| Category | Min | Max | Notes |
|----------|-----|-----|-------|
| ToR switches (2× redundant) | $0 | $36,000 | $0 if existing switches work |
| Azure VPN (6 months migration) | $900 | $3,000 | Cancel after migration |
| TLS certificates | $0 | $600/year | $0 if using internal CA |
| NAS backup storage | $0 | $10,000 | $0 if existing NAS available |
| VPN appliance | $0 | $5,000 | $0 if using existing firewall |
| **Total** | **$900** | **$54,600** | Most orgs spend $5,000–$15,000 |

> **Key insight:** If you already have an enterprise-grade switch with VLAN trunking, a firewall that supports IPsec VPN, and a NAS for backups — your additional cost is minimal (just the Azure VPN Gateway during migration).
