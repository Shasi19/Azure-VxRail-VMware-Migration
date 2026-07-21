# KVM and OLVM Complete Guide

> A comprehensive reference for setting up **KVM** (Kernel-based Virtual Machine) and **OLVM** (Oracle Linux Virtualization Manager) for on-premises infrastructure equivalent to Azure AKS + managed services.

---

## What is KVM?

KVM (Kernel-based Virtual Machine) is a **type-1 hypervisor built into the Linux kernel**. When you enable KVM, your Linux server becomes a bare-metal hypervisor. Each VM runs as a regular Linux process (managed by QEMU), with hardware-accelerated virtualisation via Intel VT-x or AMD-V.

```
┌────────────────────────────────────────────────────────────┐
│                 Physical Server (Hardware)                  │
│  CPU: Intel VT-x / AMD-V    RAM: 512 GB    NVMe: 4 TB      │
├────────────────────────────────────────────────────────────┤
│                 Linux Kernel + KVM Module                   │
│            /dev/kvm   ← hardware acceleration               │
├────────────────────────────────────────────────────────────┤
│  QEMU Process   QEMU Process   QEMU Process   QEMU Process  │
│  (VM: k8s-cp01) (VM: k8s-wk01) (VM: db-01)  (VM: harbor)  │
└────────────────────────────────────────────────────────────┘
```

## What is OLVM?

**Oracle Linux Virtualization Manager (OLVM)** is Oracle's enterprise KVM management platform. It is based on **oVirt** (which Red Hat Enterprise Virtualization is also based on). OLVM provides:

- A **web-based UI** to manage dozens of KVM hosts and hundreds of VMs
- **Live migration** of VMs between hosts
- **Storage domain management** (NFS, iSCSI, FC, GlusterFS)
- **High availability** — automatically restart VMs on another host if a host fails
- **Network management** — logical networks, VLANs, bonding
- **REST API and Ansible integration**

```
┌───────────────────────────────────────────────────────────────────┐
│                     OLVM Engine (Management Server)                │
│   olvm-engine.internal  — Web UI :443  REST API :443/ovirt-engine  │
│   PostgreSQL (embedded)  Keycloak (SSO)  DWH (metrics)             │
└───────────────────────────┬───────────────────────────────────────┘
                            │  oVirt-VDSM agent (port 54321)
        ┌───────────────────┼───────────────────┐
        |                   |                   |
   KVM Host-1          KVM Host-2          KVM Host-3
  (VDSM agent)        (VDSM agent)        (VDSM agent)
   10.0.1.11           10.0.1.12           10.0.1.13
   VMs running         VMs running         VMs running
```

---

## Document Index

| # | File | Contents |
|---|------|----------|
| 01 | [KVM Installation](01-KVM-Installation.md) | Install KVM on Oracle Linux / RHEL / Ubuntu; verify; first VM |
| 02 | [OLVM Installation](02-OLVM-Installation.md) | Deploy OLVM engine + add KVM hosts; storage domains; networks |
| 03 | [KVM Networking](03-KVM-Networking.md) | Linux bridges, VLANs, bonding, OVS, SR-IOV, firewall |
| 04 | [KVM Storage](04-KVM-Storage.md) | Local disk, LVM, NFS, iSCSI, Ceph; snapshots; performance |
| 05 | [KVM Security](05-KVM-Security.md) | sVirt, SELinux, AppArmor, TLS, VM isolation, audit logging |
| 06 | [KVM Best Practices](06-KVM-Best-Practices.md) | NUMA, hugepages, CPU pinning, live migration, overcommit |
| 07 | [Creating VMs](07-Creating-VMs.md) | virt-install, virt-manager, cloud-init, OLVM UI, templates |
| 08 | [OLVM HTTPS Certificate](08-OLVM-HTTPS-Certificate.md) | Replace self-signed cert with CA-signed; Let's Encrypt; renewal |
| 09 | [Kubernetes on KVM](09-Kubernetes-on-KVM.md) | Kubernetes deployment inside KVM VMs; HA control plane; multi-env |
| 10 | [OLVM Backup](10-OLVM-Backup.md) | VM backup via OLVM, engine-backup, export domains, Velero |
| 11 | [Monitoring and Logging](11-Monitoring-Logging.md) | Prometheus, Grafana, ELK, libvirt-exporter, OLVM DWH |
| 12 | [Backup and Recovery](12-Backup-Recovery.md) | Disk snapshots, dirty bitmaps, Bacula, MinIO, DR runbook |

---

## KVM vs OLVM: When to Use Which

| Feature | Bare KVM (virsh/virt-manager) | OLVM (Enterprise) |
|---------|------------------------------|-------------------|
| **Scale** | 1-3 hosts, handful of VMs | 3-100+ hosts, 1000s of VMs |
| **UI** | virt-manager (local GUI only) | Full web UI accessible anywhere |
| **HA** | Manual intervention needed | Automatic VM restart on host failure |
| **Live Migration** | Manual virsh commands | One-click in UI or scheduled |
| **Storage** | Manual NFS/LVM setup | Unified storage domain management |
| **Networking** | Manual bridge config | Logical networks managed centrally |
| **API** | Limited | Full REST API, Ansible, Terraform |
| **Learning curve** | Low | Medium (requires OL/RHEL familiarity) |
| **Cost** | Free (open source) | Free (Oracle Linux subscription optional) |
| **Best for** | Dev/QA, small teams | Production, enterprise, multi-team |

---

## Azure to On-Prem Service Mapping

| Azure Service | KVM/OLVM Equivalent |
|--------------|---------------------|
| Azure Kubernetes Service (AKS) | Kubernetes inside KVM/OLVM VMs |
| Azure Container Registry (ACR) | Harbor (runs as a VM or K8s deployment) |
| Azure Cosmos DB | MongoDB ReplicaSet (VM or K8s) |
| Azure PostgreSQL | PostgreSQL + Patroni HA (VM or K8s) |
| Azure Storage Account | MinIO distributed object store |
| Azure Monitor + App Insights | Prometheus + Grafana + ELK Stack |
| Azure VNet + Subnets | Linux bridges + VLAN tagging |
| Azure NSG | nftables / Calico NetworkPolicy |
| Azure Key Vault | HashiCorp Vault |
| Azure AD | Keycloak (built into OLVM) |

---

*Classification: Internal | Version: 1.0 | Date: July 2026*
