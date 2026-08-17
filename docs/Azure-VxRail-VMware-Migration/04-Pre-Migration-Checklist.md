# Pre-Migration Checklist

**11-Phase Readiness Validation & Sign-Off Document**

---

## Gate Decision Flowchart

```
┌──────────────┐
│ ① Readiness  │
└──────┬───────┘
       ▼
┌──────────────┐
│ ② Validate   │
└──────┬───────┘
       ▼
◆ All checks pass? ──YES──▶ Proceed to QA
       │
       NO
       ▼
   Remediate / Re-test
```

---

## Flowchart 1 — 11-Phase Gate Progression

```
╔═══════════════════════════════════════════════════════════════════╗
║               11-PHASE GATE PROGRESSION                          ║
╚════════════════════════════╤══════════════════════════════════════╝
                             │
    ┌────────────────────────▼──────────────────────────┐
    │  PHASE 0 · Project Readiness (Week -2)             │
    │  Charter signed │ Team assembled │ Budget approved  │
    └────────────────────────┬──────────────────────────┘
                             │
                    ◆ GATE 0 PASS?
                    ├── FAIL ──▶ ┌──────────────────────┐
                    │            │ Escalate to sponsor  │
                    │            │ Re-run checklist     │
                    │            └──────────────────────┘
                    PASS
                             │
    ┌────────────────────────▼──────────────────────────┐
    │  PHASE 1 · Infrastructure Procurement (Week -1)    │
    │  VxRail capacity │ Networking VLANs │ DNS zones    │
    └────────────────────────┬──────────────────────────┘
                             │
                    ◆ GATE 1 PASS?
                    ├── FAIL ──▶ Procurement team action
                    PASS
                             │
    ┌────────────────────────▼──────────────────────────┐
    │  PHASE 2 · Network Readiness (Week 0)              │
    │  VLANs live │ Firewall rules │ VPN tunnels up       │
    └────────────────────────┬──────────────────────────┘
                             │
                    ◆ GATE 2 PASS?
                    ├── FAIL ──▶ Network team remediation
                    PASS
                             │
    ┌────────────────────────▼──────────────────────────┐
    │  PHASE 3 · VM Provisioning                         │
    │  All VMs created │ Oracle Linux 9 configured       │
    └────────────────────────┬──────────────────────────┘
                             │
                    ◆ GATE 3 PASS?
                    ├── FAIL ──▶ Re-provision / fix cloud-init
                    PASS
                             │
    ┌────────────────────────▼──────────────────────────┐
    │  PHASE 4 · Kubernetes Setup                        │
    │  kubeadm init │ CNI live │ CSI working             │
    └────────────────────────┬──────────────────────────┘
                             │
                    ◆ GATE 4 PASS?
                    ├── FAIL ──▶ Fix kubeadm / CNI issues
                    PASS
                             │
    ┌────────────────────────▼──────────────────────────┐
    │  PHASE 5 · Database Setup                          │
    │  Patroni 3-node cluster │ pglogical installed      │
    └────────────────────────┬──────────────────────────┘
                             │
                    ◆ GATE 5 PASS?
                    ├── FAIL ──▶ Fix Patroni config / etcd
                    PASS
                             │
    ┌────────────────────────▼──────────────────────────┐
    │  PHASE 6 · Harbor & Image Migration                │
    │  Harbor live │ All images pushed │ Pull policy set │
    └────────────────────────┬──────────────────────────┘
                             │
                    ◆ GATE 6 PASS?
                    ├── FAIL ──▶ Fix registry / TLS certs
                    PASS
                             │
    ┌────────────────────────▼──────────────────────────┐
    │  PHASE 7 · QA Environment Migration                │
    │  Apps deployed │ DB migrated (pg_dump) │ Tests pass│
    └────────────────────────┬──────────────────────────┘
                             │
                    ◆ GATE 7 PASS?
                    ├── FAIL ──▶ Rollback QA, fix & retry
                    PASS
                             │
    ┌────────────────────────▼──────────────────────────┐
    │  PHASE 8 · PREPROD Environment Migration           │
    │  pglogical replication │ Performance validated     │
    └────────────────────────┬──────────────────────────┘
                             │
                    ◆ GATE 8 PASS?
                    ├── FAIL ──▶ Rollback PREPROD, investigate
                    PASS
                             │
    ┌────────────────────────▼──────────────────────────┐
    │  PHASE 9 · PROD Cutover (Maintenance Window)       │
    │  DNS flipped │ DB promoted │ Validation passed     │
    └────────────────────────┬──────────────────────────┘
                             │
                    ◆ GATE 9 PASS?
                    ├── FAIL ──▶ PROD rollback (< 2 hours)
                    PASS
                             │
    ┌────────────────────────▼──────────────────────────┐
    │  PHASE 10 · Post-Migration Stabilisation           │
    │  Monitoring │ Veeam verified │ Azure decommission  │
    └────────────────────────┬──────────────────────────┘
                             │
                    ◆ GATE 10 PASS?
                    ├── FAIL ──▶ Extend hypercare period
                    PASS
                             │
                             ▼
                    ✅ MIGRATION COMPLETE
```

---

## Flowchart 2 — Readiness Decision Tree

```
                        START: Pre-Migration Readiness?
                                      │
              ┌───────────────────────┼───────────────────────┐
              ▼                       ▼                       ▼
    ◆ Infrastructure          ◆ Database                ◆ Application
      ready?                   ready?                    ready?
              │                       │                       │
    ┌───NO────┴────YES──┐   ┌───NO────┴────YES──┐   ┌───NO───┴────YES──┐
    │                   │   │                   │   │                  │
    ▼                   ▼   ▼                   ▼   ▼                  ▼
 Provision         ┌────┐ Setup DB         ┌────┐ Fix config      ┌────┐
 VxRail / K8s      │ ✅ │ Patroni+pglogical│ ✅ │ / images        │ ✅ │
 (Phases 3-6)      └────┘ (Phase 5)        └────┘ (Phase 6-7)     └────┘
                                                         │
                   All three ✅ ?
                         │
                   YES ──▶ ◆ Security sign-off received?
                         │
                   ├──NO──▶ Security team review (Phase 2)
                   │
                   YES
                         │
                         ▼
                   ◆ Business stakeholders approved?
                         │
                   ├──NO──▶ Change Advisory Board meeting
                   │
                   YES
                         │
                         ▼
                   ✅ READY TO PROCEED
```


## Executive Summary

This document contains the complete pre-flight checklist required before starting any phase of the Azure-to-On-Premises migration. All items must be completed, validated, and signed off before proceeding.

**Total Checklist Items**: 150+  
**Estimated Completion Time**: 2-3 weeks  
**Sign-Off Required**: Leadership, Infrastructure, Database, Network, Security teams

---

## Phase 0: Project Readiness (Week -2)

### 0.1 Steering Committee & Approvals
- [ ] Project charter approved by leadership
- [ ] Executive sponsor assigned
- [ ] Change management committee formed
- [ ] Risk register created and reviewed
- [ ] Budget approved for on-premises infrastructure
- [ ] Timeline and milestones accepted

**Sign-Off**: _____________________________ (Date: _______)

### 0.2 Team Composition & Training
- [ ] Project manager assigned and active
- [ ] Infrastructure lead identified
- [ ] Database administrator assigned
- [ ] Network engineer assigned
- [ ] Security officer assigned
- [ ] QA lead assigned
- [ ] All team members trained on Kubernetes 1.34
- [ ] All team members trained on Oracle Linux 9
- [ ] All team members trained on vSphere/VxRail
- [ ] All team members trained on PostgreSQL Patroni HA
- [ ] All team members trained on pglogical replication
- [ ] All team members trained on Veeam backup procedures

**Sign-Off**: _____________________________ (Date: _______)

### 0.3 Documentation Review
- [ ] Current Azure architecture documented
- [ ] Target on-premises architecture approved
- [ ] Migration procedures reviewed
- [ ] Rollback procedures reviewed and tested
- [ ] Disaster recovery plan reviewed
- [ ] Communication plan finalized
- [ ] All documentation version controlled (Git)

**Sign-Off**: _____________________________ (Date: _______)

---

## Phase 1: Infrastructure Validation (Week -1.5)

### 1.1 On-Premises VxRail Cluster Validation
- [ ] 6 Dell VxRail nodes physically installed
- [ ] All nodes powered on and accessible
- [ ] iDRAC interfaces configured (192.168.1.100-105)
- [ ] Serial numbers recorded for warranty tracking
- [ ] Physical cable inspection completed
- [ ] Network cables tested (10GbE ports)
- [ ] Power redundancy verified (2+ power supplies per node)
- [ ] Cooling capacity verified for full load
- [ ] UPS battery backup present and tested

**Validation Results**:
- Node 1 iDRAC: _________________ Status: ✓ / ✗
- Node 2 iDRAC: _________________ Status: ✓ / ✗
- Node 3 iDRAC: _________________ Status: ✓ / ✗
- Node 4 iDRAC: _________________ Status: ✓ / ✗
- Node 5 iDRAC: _________________ Status: ✓ / ✗
- Node 6 iDRAC: _________________ Status: ✓ / ✗

**Sign-Off**: _____________________________ (Date: _______)

### 1.2 vSphere Installation & Configuration
- [ ] ESXi 8.0 U1 installed on all 6 nodes
- [ ] vCenter Server 8.0 U1 deployed (VM or appliance)
- [ ] vCenter license(s) obtained and registered
- [ ] ESXi license(s) obtained and registered
- [ ] vSAN license obtained and registered
- [ ] NTP configured and synchronized across all hosts
- [ ] DNS configured on vCenter and ESXi hosts
- [ ] vSphere Cluster created with all 6 nodes
- [ ] Cluster HA enabled (4-node quorum configured)
- [ ] DRS enabled (balanced mode)
- [ ] vSAN enabled and health check passed
- [ ] Storage class definition template created

**vSphere Cluster Status**:
```
Cluster Name: _________________
vCenter Version: ______________
ESXi Version: _________________
Total Hosts: 6   Healthy: _____   Status: ✓ / ✗
vSAN Status: ___________________
HA Status: _____________________
DRS Status: _____________________
```

**Sign-Off**: _____________________________ (Date: _______)

### 1.3 Storage (vSAN) Validation
- [ ] vSAN datastore created and healthy
- [ ] Total total capacity: 247.66 TB (156.8 TB used, 90.86 TB free) confirmed
- [ ] FTT=1 (Fault Tolerance) configured
- [ ] Compression enabled
- [ ] Deduplication enabled
- [ ] Encryption enabled (AES-256)
- [ ] Daily health checks scheduled
- [ ] Storage performance baseline established
- [ ] Snapshot storage policy created
- [ ] Backup storage allocation planned (50 TB)

**vSAN Storage Metrics**:
- Total Capacity: _________ TB
- Used Capacity: _________ TB
- Compression Ratio: _________ %
- Dedupe Ratio: _________ %
- Health Status: _________ (Good / Warning / Critical)

**Sign-Off**: _____________________________ (Date: _______)

---

## Phase 2: Network Infrastructure Validation (Week -1)

### 2.1 Physical Network
- [ ] Core switch installed and configured
- [ ] Leaf switches (2x) installed with LACP
- [ ] All 10GbE cables tested and verified
- [ ] Jumbo frames (MTU 9000) enabled on all switches
- [ ] Link aggregation (LACP) configured per node
- [ ] Network redundancy validated (all paths tested)
- [ ] Out-of-band (1GbE) management network isolated
- [ ] Network monitoring tools installed (Nagios/Zabbix)

**Network Diagram**:
```
[Reviewed and approved]
Date: _____________ By: _________________
```

**Sign-Off**: _____________________________ (Date: _______)

### 2.2 VLAN Configuration
- [ ] VLAN 10 (vSAN): 10.5.0.0/24 created and tagged
- [ ] VLAN 20 (Management): 10.20.0.0/24 created
- [ ] VLAN 100 (QA): 10.50.0.0/16 created
- [ ] VLAN 110 (PREPROD): 10.51.0.0/16 created
- [ ] VLAN 120 (PROD): 10.52.0.0/16 created
- [ ] VLAN 30 (Database): 10.30.0.0/24 created
- [ ] VLAN 40 (Backup/Monitoring): 10.40.0.0/24 created
- [ ] Router configured for inter-VLAN routing
- [ ] VLAN routing tested between all zones
- [ ] Gateway IPs assigned and responding to ping

**VLAN Validation**:
| VLAN | CIDR | Gateway | Status | Tested |
|------|------|---------|--------|--------|
| 10 | 10.5.0.0/24 | 10.5.0.1 | ✓ | ✓ |
| 20 | 10.20.0.0/24 | 10.20.0.1 | ✓ | ✓ |
| 100 | 10.50.0.0/16 | 10.50.0.1 | ✓ | ✓ |
| 110 | 10.51.0.0/16 | 10.51.0.1 | ✓ | ✓ |
| 120 | 10.52.0.0/16 | 10.52.0.1 | ✓ | ✓ |
| 30 | 10.30.0.0/24 | 10.30.0.1 | ✓ | ✓ |
| 40 | 10.40.0.0/24 | 10.40.0.1 | ✓ | ✓ |

**Sign-Off**: _____________________________ (Date: _______)

### 2.3 Firewall Configuration
- [ ] Firewall rules between VLANs configured
- [ ] Azure VPN/ExpressRoute gateway configured
- [ ] Hybrid connectivity tested (on-prem ↔ Azure)
- [ ] Firewall rules for database access created (5432)
- [ ] Firewall rules for API ingress created (443)
- [ ] Firewall rules for inter-cluster isolation created
- [ ] Outbound rules for package management (DNF) allowed
- [ ] Outbound rules for backup traffic allowed
- [ ] Firewall logs configured for audit

**Firewall Connectivity Test Results**:
- On-Prem to Azure: ✓ (latency: _____ ms)
- On-Prem to Internet: ✓ (for OS updates)
- Cluster to Database VLAN: ✓
- Cluster to Backup VLAN: ✓
- Cluster to Internet APIs: ✓

**Sign-Off**: _____________________________ (Date: _______)

---

## Phase 3: Database Infrastructure Preparation (Week -1)

### 3.1 PostgreSQL Preparation (On-Premises)
- [ ] Oracle Linux 9 VM template created (PostgreSQL server)
- [ ] PostgreSQL 14 repository configured (dnf)
- [ ] PostgreSQL 14 installation tested on template
- [ ] PostgreSQL roles and users tested
- [ ] Database creation and restoration tested
- [ ] WAL archiving path prepared (/backup/wal)
- [ ] NFS mount for backup storage prepared
- [ ] pg_basebackup tested on template
- [ ] pglogical extension package available
- [ ] PostgreSQL client tools installed (psql, pgbench)

**PostgreSQL Validation**:
- Version Tested: PostgreSQL 14.__ ✓
- pg_basebackup: Works ✓
- pglogical extension: Available ✓
- Backup path accessible: ✓
- Restoration tested: ✓

**Sign-Off**: _____________________________ (Date: _______)

### 3.2 Database Backup Export from Azure
- [ ] PostgreSQL full backup exported from Azure
- [ ] Backup file size: _________ GB
- [ ] Backup compressed: ✓ (gzip)
- [ ] Backup checksummed (MD5): _________________
- [ ] Backup transferred to on-premises (via VPN)
- [ ] Transfer time: _________ hours
- [ ] Transfer verified (checksum match): ✓
- [ ] Backup storage location: /backup/azure-pg-export
- [ ] Cosmos DB data exported (if applicable)

**Backup Details**:
- PostgreSQL Database Size: _________ GB (uncompressed)
- Compressed Size: _________ GB
- Number of Tables: _________
- Number of Indexes: _________
- Export Date: _________________

**Sign-Off**: _____________________________ (Date: _______)

---

## Phase 4: Container Image Preparation (Week -1)

### 4.1 Container Registry (Harbor)
- [ ] Harbor VM deployed (8 vCPU, 32 GB RAM)
- [ ] Harbor 2.8+ installed and configured
- [ ] Harbor database initialized
- [ ] Harbor storage backend (vSAN) configured
- [ ] Harbor admin credentials stored securely
- [ ] Harbor HTTPS certificate installed
- [ ] Harbor LDAP/OIDC authentication configured
- [ ] Harbor projects created (qa, preprod, prod)
- [ ] Harbor image pull secrets created

**Harbor Configuration**:
- Harbor URL: https://harbor.internal
- Storage Backend: vSAN (100 GB allocated)
- Projects Created: qa, preprod, prod ✓
- User Auth: LDAP ✓
- Status: ✓

**Sign-Off**: _____________________________ (Date: _______)

### 4.2 Container Images
- [ ] All application container images built
- [ ] Container images tagged with version
- [ ] Container images pushed to Harbor
- [ ] Container images scanned for vulnerabilities
- [ ] Container image SBOMs (Software Bill of Materials) generated
- [ ] Base images (CentOS/Debian) updated
- [ ] Oracle Linux 9 base image available
- [ ] K8s system image repository mirrored (optional)

**Container Image Inventory**:
- Total Images: _________
- Scanned for Vulnerabilities: ________ / _________
- High Severity Issues: _________
- Medium Severity Issues: _________
- Low Severity Issues: _________

**Sign-Off**: _____________________________ (Date: _______)

---

## Phase 5: SSL/TLS Certificates
- [ ] Root CA certificate obtained
- [ ] Intermediate CA certificate obtained (if needed)
- [ ] Wildcard certificate for *.internal.company.com
- [ ] API server certificate (kubernetes.default.svc)
- [ ] Ingress TLS certificate (api.company.com)
- [ ] PostgreSQL certificate (optional, for client auth)
- [ ] Harbor registry certificate
- [ ] All certificates stored in secure vault (HashiCorp Vault)
- [ ] Certificate rotation policy defined (90 days before expiry)
- [ ] Certificate renewal process documented

**Certificate Inventory**:
| Certificate | Expiry | Status | Stored |
|-------------|--------|--------|--------|
| Root CA | _______ | Valid ✓ | Vault ✓ |
| Wildcard *.internal | _______ | Valid ✓ | Vault ✓ |
| API Server | _______ | Valid ✓ | Vault ✓ |

**Sign-Off**: _____________________________ (Date: _______)

---

## Phase 6: Backup Infrastructure
- [ ] Veeam Backup Server VM deployed (8 vCPU, 32 GB)
- [ ] Veeam backup repository configured (500 GB NAS)
- [ ] Veeam licenses obtained and installed
- [ ] Veeam PostgreSQL agent installed
- [ ] Veeam backup jobs created (daily)
- [ ] First backup completed successfully
- [ ] Restore test performed successfully
- [ ] Backup verification scheduled (daily)
- [ ] Off-site backup replication configured (if Azure)

**Veeam Configuration**:
- Backup Server: VM at 10.40.0.10 ✓
- Repository Capacity: 500 GB ✓
- First Backup: ✓ (Date: _______)
- Restore Test: ✓ (Successful)
- Daily Verification: ✓ (Scheduled)

**Sign-Off**: _____________________________ (Date: _______)

---

## Phase 7: Monitoring & Observability Setup
- [ ] Prometheus VM deployed (4 vCPU, 16 GB)
- [ ] Prometheus configured (30s scrape interval)
- [ ] Grafana VM deployed (4 vCPU, 8 GB)
- [ ] Grafana data source connected to Prometheus
- [ ] Dashboard templates imported
- [ ] Alerting rules configured (AlertManager)
- [ ] ELK stack (3 VMs) deployed
- [ ] Elasticsearch cluster initialized
- [ ] Kibana dashboards created
- [ ] Log shipping configured (Fluentd)

**Monitoring Stack Status**:
- Prometheus: http://prometheus.internal ✓
- Grafana: http://grafana.internal ✓
- Kibana: http://kibana.internal ✓
- Alerts: Configured ✓
- Log shipping: Active ✓

**Sign-Off**: _____________________________ (Date: _______)

---

## Phase 8: Connectivity Validation
- [ ] On-premises to Azure connectivity (VPN/ExpressRoute)
- [ ] Latency test: _________ ms
- [ ] Bandwidth test: _________ Mbps
- [ ] Packet loss: _________ %
- [ ] DNS resolution from on-prem to Azure: ✓
- [ ] DNS resolution from Azure to on-prem: ✓
- [ ] Database connectivity test (psql from on-prem to Azure): ✓
- [ ] Application registry connectivity (ACR/Docker Hub): ✓

**Connectivity Test Results**:
| Test | Status | Result |
|------|--------|--------|
| Ping to Azure gateway | ✓ | _____ ms |
| VPN tunnel establishment | ✓ | Established |
| DNS resolution | ✓ | Working |
| Database connectivity | ✓ | Connected |
| Bandwidth test (1 GB file) | ✓ | _____ MB/s |

**Sign-Off**: _____________________________ (Date: _______)

---

## Phase 9: Security & Compliance Validation
- [ ] Security audit completed
- [ ] RBAC policies defined (Kubernetes)
- [ ] Network policies defined (no service-to-service by default)
- [ ] Encryption at rest enabled (vSAN AES-256)
- [ ] Encryption in transit enabled (TLS 1.3)
- [ ] Firewall rules reviewed by security team
- [ ] Audit logging configured (all components)
- [ ] Secrets management solution deployed (Vault)
- [ ] Compliance checklist completed (HIPAA/PCI-DSS if applicable)
- [ ] Penetration testing scheduled post-migration

**Security Validation**:
- RBAC: Configured ✓
- Network Policies: Configured ✓
- Encryption at Rest: Enabled ✓
- Encryption in Transit: Enabled ✓
- Audit Logging: Enabled ✓
- Compliance: Reviewed ✓

**Sign-Off**: _____________________________ (Date: _______)

---

## Phase 10: Disaster Recovery Readiness
- [ ] RTO/RPO targets defined and agreed
- [ ] Backup retention policies configured
- [ ] Point-in-time recovery (PITR) tested
- [ ] Disaster recovery runbook created
- [ ] DR failover procedure tested (table-top exercise)
- [ ] DR failback procedure documented
- [ ] Communication plan for DR scenarios created
- [ ] Insurance documentation reviewed
- [ ] Compliance documentation (DR SLAs) filed

**DR Readiness Checklist**:
- RTO Target: 2 hours (Database), 4 hours (Applications) ✓
- RPO Target: 1 hour (Database), 24 hours (Applications) ✓
- Backup Tested: ✓ (Date: _______)
- PITR Tested: ✓ (Date: _______)
- DR Runbook: Complete ✓
- Table-top Exercise: Completed ✓ (Date: _______)

**Sign-Off**: _____________________________ (Date: _______)

---

## Phase 11: Final Readiness Sign-Off

### 11.1 Infrastructure Team Approval
- [ ] All infrastructure components operational
- [ ] Performance baselines established
- [ ] Capacity planning validated
- [ ] Redundancy verified
- [ ] Failover tested

**Infrastructure Sign-Off**: _____________________________ (Date: _______)

### 11.2 Database Team Approval
- [ ] PostgreSQL environment prepared
- [ ] Backup/restore procedures tested
- [ ] PITR verified
- [ ] Patroni HA design reviewed
- [ ] Replication procedures documented

**Database Sign-Off**: _____________________________ (Date: _______)

### 11.3 Network Team Approval
- [ ] All network segments operational
- [ ] Firewall rules verified
- [ ] Hybrid connectivity stable
- [ ] DNS resolution working
- [ ] Load balancing configured

**Network Sign-Off**: _____________________________ (Date: _______)

### 11.4 Security Team Approval
- [ ] Security audit passed
- [ ] RBAC configured
- [ ] Encryption enabled
- [ ] Audit logging active
- [ ] Compliance requirements met

**Security Sign-Off**: _____________________________ (Date: _______)

### 11.5 Executive/Project Manager Approval
- [ ] All phases complete
- [ ] Budget approved
- [ ] Timeline confirmed
- [ ] Risks identified and mitigated
- [ ] Go/No-Go decision: **GO** / **NO-GO**

**Executive Approval**: _____________________________ (Date: _______)
**Project Manager**: _____________________________ (Date: _______)

---

## Next Steps

1. **Week 0**: All sign-offs complete → Proceed to QA phase
2. **Week 1-3**: QA environment implementation
3. **Week 4-8**: PREPROD environment implementation
4. **Week 9-16**: PROD environment implementation

---

**End of Pre-Migration Checklist**

Reference: [00-VxRail-Complete-Index.md](./00-VxRail-Complete-Index.md), [03-Target-State-Architecture.md](./03-Target-State-Architecture.md)

