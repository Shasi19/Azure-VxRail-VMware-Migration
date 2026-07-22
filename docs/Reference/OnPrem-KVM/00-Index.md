# On-Premises KVM Deployment Guide

> **Approach**: Physical servers run the KVM hypervisor. Guest VMs run Kubernetes nodes.  
> This gives VM-level isolation, snapshot-based DR, and easy resource rebalancing without touching hardware.

---

## Architecture Overview

```
┌────────────────────────────────────────────────────────────────────────┐
│                     PHYSICAL HOST LAYER (3+ servers)                   │
│  Host-1 (192.168.10.11)  Host-2 (192.168.10.12)  Host-3 (192.168.10.13)│
│  KVM + libvirt            KVM + libvirt            KVM + libvirt        │
│  64 vCPU / 512 GB RAM     64 vCPU / 512 GB RAM     64 vCPU / 512 GB RAM │
└───────────────────────────────┬────────────────────────────────────────┘
                                │  Virtual Machines (QCOW2 / NetApp NFS)
┌───────────────────────────────▼────────────────────────────────────────┐
│                     VM LAYER (12 VMs total)                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐        │
│  │ K8s Control x3  │  │  K8s Worker x6  │  │  Infra VMs x3   │        │
│  │ 10.0.1.10-12    │  │  10.0.1.20-25   │  │ DB, MinIO, etc  │        │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘        │
└───────────────────────────────┬────────────────────────────────────────┘
                                │  Kubernetes
┌───────────────────────────────▼────────────────────────────────────────┐
│              KUBERNETES LAYER (4 namespaces = 4 environments)           │
│   dev  │  qa  │  preprod  │  prod                                      │
│   AKS-equivalent workloads per namespace                                │
└────────────────────────────────────────────────────────────────────────┘
```

## Why KVM?

| Feature | KVM Advantage |
|---------|--------------|
| **VM snapshots** | Freeze a full environment before risky upgrades |
| **Live migration** | Move a VM between hosts without downtime (`virsh migrate`) |
| **Resource isolation** | Hard CPU/RAM limits per VM — dev can't starve prod |
| **Template cloning** | Stamp out new VMs in minutes from a golden image |
| **Familiar tooling** | Same QCOW2/libvirt stack used in most enterprise data centres |

---

## Document Index

| # | File | Contents |
|---|------|----------|
| 01 | [KVM Host Setup](01-KVM-Host-Setup.md) | Install KVM, libvirt, configure bridge networking on physical hosts |
| 02 | [VM Provisioning](02-VM-Provisioning.md) | Create and tune VMs for K8s control plane, workers, and infra nodes |
| 03 | [Network Configuration](03-Network-Configuration.md) | Virtual bridges, VLANs, MetalLB IP pool, DNS, firewall rules |
| 04 | [Kubernetes Setup](04-Kubernetes-Setup.md) | kubeadm HA cluster inside VMs, CNI (Calico), ingress, cert-manager |
| 05 | [Storage Setup](05-Storage-Setup.md) | MinIO object store, NetApp NFS StorageClass, persistent volume setup |
| 06 | [Database Setup](06-Database-Setup.md) | PostgreSQL+Patroni HA, MongoDB ReplicaSet, PgBouncer, HAProxy, Redis |
| 07 | [Platform Services](07-Platform-Services.md) | Harbor registry, ArgoCD GitOps, GitLab CI, Vault secrets |
| 08 | [Observability and Security](08-Observability-Security.md) | Prometheus, Grafana, ELK, Jaeger, cert-manager, NetworkPolicy |
| 09 | [Backup and DR](09-Backup-DR.md) | Velero K8s backup, Bacula file backup, KVM snapshots, etcd backup |

---

## Hardware Requirements

### Minimum (Development/Proof of Concept)

| Role | Count | vCPU | RAM | Disk |
|------|-------|------|-----|------|
| KVM Physical Host | 2 | 32 cores | 256 GB | 2 TB NVMe |
| Shared NFS (NetApp or similar) | 1 | — | — | 10 TB |

### Recommended (Production-grade 4-env)

| Role | Count | CPU Cores | RAM | Disk |
|------|-------|-----------|-----|------|
| KVM Host (hypervisor) | 3 | 64 physical | 512 GB | 4 TB NVMe |
| NetApp AFF A250 (shared storage) | 1 HA pair | — | — | 50 TB |
| Out-of-band switch | 1 | — | — | — |
| 10 GbE switches (bonded) | 2 | — | — | — |

### VM Allocation Per Host

| VM Name | Role | vCPU | RAM | Disk | Host |
|---------|------|------|-----|------|------|
| k8s-cp-01 | K8s Control Plane | 8 | 16 GB | 100 GB | Host-1 |
| k8s-cp-02 | K8s Control Plane | 8 | 16 GB | 100 GB | Host-2 |
| k8s-cp-03 | K8s Control Plane | 8 | 16 GB | 100 GB | Host-3 |
| k8s-wk-01..06 | K8s Workers | 16 | 64 GB | 200 GB | Spread |
| infra-db-01 | PostgreSQL primary + MongoDB | 16 | 64 GB | 500 GB | Host-1 |
| infra-db-02 | PostgreSQL replica + MongoDB | 16 | 64 GB | 500 GB | Host-2 |
| infra-db-03 | PostgreSQL replica + MongoDB | 16 | 64 GB | 500 GB | Host-3 |
| infra-minio-01..03 | MinIO (distributed) | 8 | 32 GB | 2 TB | Spread |

---

## IP Address Plan

| Subnet | Range | Usage |
|--------|-------|-------|
| Host Management | 192.168.10.0/24 | KVM physical hosts, IPMI |
| VM Network | 10.0.1.0/24 | K8s nodes, infra VMs |
| K8s Pod CIDR | 10.244.0.0/16 | Calico pod network |
| K8s Service CIDR | 10.96.0.0/12 | ClusterIP services |
| MetalLB Pool | 10.0.2.10–10.0.2.50 | LoadBalancer IPs |
| Storage | 10.0.3.0/24 | NetApp, MinIO |

---

## Setup Order

```
1. Install KVM on physical hosts           [01-KVM-Host-Setup.md]
2. Create and boot VMs                     [02-VM-Provisioning.md]
3. Configure networking inside VMs        [03-Network-Configuration.md]
4. Bootstrap Kubernetes cluster            [04-Kubernetes-Setup.md]
5. Deploy storage (MinIO + NFS)            [05-Storage-Setup.md]
6. Deploy databases (PG + Mongo)           [06-Database-Setup.md]
7. Deploy platform services (Harbor etc)  [07-Platform-Services.md]
8. Deploy observability + security        [08-Observability-Security.md]
9. Configure backup and DR                 [09-Backup-DR.md]
10. Run migration from Azure               [../Volume-2-Migration-Strategy/]
```

---

*Classification: Internal | Version: 1.0 | Date: July 2026*
