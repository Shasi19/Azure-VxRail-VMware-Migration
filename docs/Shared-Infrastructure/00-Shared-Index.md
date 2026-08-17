# Shared Infrastructure Setup Guide

> **Purpose:** Common foundation setup for ALL environments (QA, PREPROD, PROD)  
> **Prerequisites:** VxRail cluster powered on, vCenter accessible  
> **Scope:** vSphere, networking, Kubernetes base, databases, monitoring

---

## 📋 Core Foundation (Complete Before Any Environment Migration)

### Phase 1: VxRail & vSphere (Weeks 1-2)
1. [VxRail 6-Node Cluster Setup](01-VxRail-6Node-Cluster-Setup.md)
   - Cluster health verification
   - vSAN configuration
   - Resource inventory

2. [vSphere Network Configuration](03-vSphere-Network-Configuration.md)
   - Distributed Virtual Switch (DVS)
   - VLAN segmentation
   - Firewall rules (firewalld)
   - Load balancing (MetalLB)

3. [vSAN Storage Configuration](04-vSAN-Storage-Configuration.md)
   - Storage policies (FTT=1, RAID-5)
   - Storage classes
   - Performance tuning

### Phase 2: Operating System & Templates (Week 2-3)
4. [Oracle Linux 9 Template](02-Oracle-Linux-9-Template.md)
   - VM template creation
   - dnf package management
   - SELinux configuration
   - firewalld rules
   - Kubernetes prerequisites

### Phase 3: Kubernetes Foundation (Week 3)
5. [Kubernetes HA Cluster Setup](05-Kubernetes-HA-Cluster-Setup.md)
   - kubeadm bootstrap
   - 3-master HA control plane
   - Calico CNI
   - vSphere Cloud Controller Manager (CCM)
   - Ingress controller (MetalLB)

### Phase 4: Databases & Data Stores (Weeks 3-4)
6. [PostgreSQL Patroni HA](06-PostgreSQL-Patroni-HA.md)
   - Patroni cluster architecture
   - Automatic failover
   - Replication lag monitoring
   - Backup procedures

7. [Cosmos DB → MongoDB Migration](07-Cosmos-DB-Migration-Strategy.md)
   - MongoDB deployment on K8s
   - Data migration from Azure Cosmos DB
   - Connection pooling
   - Backup strategy

### Phase 5: Container & Artifact Management (Week 4)
8. [Harbor Container Registry](08-Harbor-Container-Registry.md)
   - Harbor deployment on K8s
   - Image pushing/pulling
   - Authentication setup
   - Garbage collection

### Phase 6: Observability (Week 4)
9. [Monitoring Stack Setup](09-Monitoring-Stack-Setup.md)
   - Prometheus scraping
   - Grafana dashboards
   - ELK Stack (Elasticsearch, Logstash, Kibana)
   - Alert routing

### Phase 7: Security & Networking (Week 4)
10. [Security, VPN & DNS Configuration](10-Security-VPN-DNS-Configuration.md)
    - VPN to Azure
    - DNS setup (BIND9, CoreDNS)
    - RBAC policies
    - NetworkPolicy rules

### Reference
11. [Common Troubleshooting Guide](11-Common-Troubleshooting-Guide.md)
    - vSphere issues
    - Kubernetes issues
    - Database issues
    - Network issues

---

## 🚀 Quick Start Checklist

**Before starting QA Environment (Week 1):**

- [ ] **Access & Connectivity**
  - [ ] vCenter SSH access working
  - [ ] Jump host available
  - [ ] VPN to Azure stable
  - [ ] Team has admin credentials

- [ ] **Physical Infrastructure**
  - [ ] All 6 VxRail nodes online
  - [ ] vSAN datastore visible
  - [ ] Network switches configured
  - [ ] Capacity: ≥ 96GB RAM, ≥ 3TB storage available

- [ ] **Initial Configuration**
  - [ ] DNS servers configured
  - [ ] NTP synchronized
  - [ ] vCenter with default settings
  - [ ] Basic networking (no DVS yet)

- [ ] **Team Prepared**
  - [ ] vSphere admin assigned
  - [ ] Kubernetes admin assigned
  - [ ] Database admin assigned
  - [ ] Network admin assigned

---

## 📚 Document Reading Order

For each environment, follow this reading order:

1. **This file** (Shared-Infrastructure overview)
2. **Environment-specific files:**
   - [QA Timeline](../QA-Environment/00-QA-Timeline.md)
   - [PREPROD Timeline](../PREPROD-Environment/00-PREPROD-Timeline.md)
   - [PROD Timeline](../PROD-Environment/00-PROD-Timeline.md)
3. **Then refer to Shared-Infrastructure docs as needed**

---

## 🔗 Cross-References

**By Topic:**

| Topic | Document |
|-------|----------|
| Infrastructure | VxRail 6-Node Setup |
| Networking | vSphere Network Config |
| Storage | vSAN Storage Config |
| Compute | Kubernetes HA Setup |
| Database | PostgreSQL Patroni HA |
| Registry | Harbor Container Registry |
| Monitoring | Monitoring Stack Setup |
| Security | Security/VPN/DNS Config |
| Troubleshooting | Common Troubleshooting |

**By Workload Type:**

| Workload | Setup Document | Migration Notes |
|----------|---|---|
| Kubernetes Cluster | Kubernetes HA Setup | Deploy once, reuse for all envs |
| PostgreSQL | PostgreSQL Patroni HA | Deployed per environment |
| MongoDB/Cosmos DB | Cosmos DB Migration | Data migrated per environment |
| Applications | (Environment-specific) | Deployed per environment |
| Monitoring | Monitoring Stack | Deploy per environment |
| Backup | (Veeam, not in this guide) | Configured per environment |

---

## 🎯 Success Criteria

Shared infrastructure is READY when:

✅ **vSphere:**
- vCenter fully operational
- vSAN with > 2.5TB usable storage
- Network DVS with all VLANs configured

✅ **Kubernetes:**
- 3 masters + 3 workers provisioned
- All nodes in "Ready" state
- Pod networking (Calico) functional
- Storage provisioning working

✅ **Databases:**
- PostgreSQL Patroni cluster healthy
- Replication lag < 1 second
- Backup jobs executing

✅ **Observability:**
- Prometheus scraping metrics
- Grafana dashboards loaded
- ELK Stack indexing logs

✅ **Security:**
- VPN to Azure established
- DNS resolution working
- RBAC policies applied
- Firewall rules active

✅ **Team:**
- All admins trained
- Runbooks reviewed
- Access credentials distributed
- Emergency contacts documented

---

## 📞 Support & Issues

**If you encounter issues:**

1. **Check:** Common Troubleshooting Guide
2. **Search:** Kubernetes/vSphere documentation
3. **Ask:** Infrastructure team lead
4. **Escalate:** VMware TAC, Dell VxRail TAC, Kubernetes experts

---

## 📈 Typical Timeline

```
Week 1-2: VxRail + vSphere setup
Week 2-3: Oracle Linux template + network config
Week 3:   Kubernetes cluster build
Week 4:   Databases + Harbor + Monitoring

By end of Week 4: Shared infrastructure READY for QA phase
```

---

## Next Steps

1. ✅ Assign roles to team members
2. ✅ Gather access credentials
3. ✅ Start with VxRail 6-Node Cluster Setup
4. ✅ Follow documents in order

**Get Started:** [VxRail 6-Node Cluster Setup →](01-VxRail-6Node-Cluster-Setup.md)
