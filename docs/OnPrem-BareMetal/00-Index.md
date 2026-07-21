# On-Premises Bare-Metal Deployment Guide

> **Approach**: Kubernetes and all services run **directly on physical servers** — no hypervisor layer.  
> This gives maximum performance (no CPU/memory overhead), simpler architecture, and is preferred when hardware resources are dedicated to one purpose.

---

## Architecture Overview

```
┌────────────────────────────────────────────────────────────────────────┐
│                 PHYSICAL SERVER LAYER (9+ servers)                     │
│                                                                        │
│  ┌────────────────┐  ┌──────────────────┐  ┌───────────────────────┐  │
│  │ Control Plane  │  │  Worker Nodes    │  │  Infrastructure Nodes │  │
│  │  Server-1,2,3  │  │  Server-4 to 9  │  │  DB-1, DB-2, DB-3     │  │
│  │  10.0.1.10-12  │  │  10.0.1.20-25   │  │  10.0.1.30-32         │  │
│  └────────────────┘  └──────────────────┘  └───────────────────────┘  │
│           Direct on hardware — no VMs, no hypervisor                   │
└───────────────────────────────┬────────────────────────────────────────┘
                                │  Kubernetes (kubeadm)
┌───────────────────────────────▼────────────────────────────────────────┐
│              KUBERNETES LAYER (4 namespaces = 4 environments)           │
│   dev  │  qa  │  preprod  │  prod                                      │
└────────────────────────────────────────────────────────────────────────┘
```

## KVM vs Bare-Metal Comparison

| Factor | Bare-Metal | KVM |
|--------|-----------|-----|
| **Performance** | Maximum — no hypervisor tax | ~5-10% overhead |
| **Setup complexity** | Simpler — fewer layers | More complex (VMs, libvirt) |
| **DR snapshots** | No VM snapshots (use Velero) | Full VM snapshots |
| **Resource isolation** | K8s namespaces + taints | Hard VM CPU/RAM limits |
| **Hardware failures** | Node replaced, K8s reschedules | Migrate VMs to another host |
| **Best for** | Max throughput, cost-conscious | Isolation, test environments |

---

## Document Index

| # | File | Contents |
|---|------|----------|
| 01 | [Server Preparation](01-Server-Preparation.md) | OS install, updates, kernel tuning, time sync |
| 02 | [Network Configuration](02-Network-Configuration.md) | NIC bonding, VLANs, static IPs, firewall rules |
| 03 | [Kubernetes Setup](03-Kubernetes-Setup.md) | kubeadm HA cluster directly on servers, CNI, MetalLB |
| 04 | [Storage Setup](04-Storage-Setup.md) | MinIO distributed, NetApp NFS StorageClass |
| 05 | [Database Setup](05-Database-Setup.md) | PostgreSQL+Patroni, MongoDB ReplicaSet |
| 06 | [Platform Services](06-Platform-Services.md) | Harbor, ArgoCD, GitLab CI, Vault, Redis |
| 07 | [Observability and Security](07-Observability-Security.md) | Prometheus, Grafana, ELK, Jaeger, NetworkPolicy |
| 08 | [Backup and DR](08-Backup-DR.md) | Velero, Bacula, etcd backup, runbooks |

---

## Hardware Requirements

### Minimum (Dev/QA only)

| Role | Count | CPU Cores | RAM | Disk |
|------|-------|-----------|-----|------|
| Control Plane | 3 | 8 cores | 32 GB | 500 GB SSD |
| Worker Node | 3 | 16 cores | 64 GB | 1 TB NVMe |
| DB/Infra Node | 1 | 16 cores | 64 GB | 2 TB NVMe |

### Recommended (All 4 Environments — Production Grade)

| Role | Count | CPU Cores | RAM | Disk | Network |
|------|-------|-----------|-----|------|---------|
| Control Plane | 3 | 16 cores | 64 GB | 500 GB NVMe | 10 GbE dual |
| Worker Node | 6 | 32 cores | 128 GB | 2 TB NVMe | 25 GbE dual |
| DB/Infra Node | 3 | 32 cores | 128 GB | 4 TB NVMe | 25 GbE dual |
| NetApp AFF A250 | 1 HA pair | — | — | 50 TB | 10 GbE |
| Top-of-rack switch | 2 | — | — | — | 25/100 GbE |

### Server IP Plan

| Server | Role | IP | Purpose |
|--------|------|----|---------|
| server-cp-01 | K8s Control Plane | 10.0.1.10 | etcd, kube-apiserver |
| server-cp-02 | K8s Control Plane | 10.0.1.11 | etcd, kube-apiserver |
| server-cp-03 | K8s Control Plane | 10.0.1.12 | etcd, kube-apiserver |
| server-wk-01 | K8s Worker (Dev) | 10.0.1.20 | Dev workloads |
| server-wk-02 | K8s Worker (QA) | 10.0.1.21 | QA workloads |
| server-wk-03 | K8s Worker (QA) | 10.0.1.22 | QA workloads |
| server-wk-04 | K8s Worker (PreProd) | 10.0.1.23 | PreProd workloads |
| server-wk-05 | K8s Worker (Prod) | 10.0.1.24 | Prod workloads |
| server-wk-06 | K8s Worker (Prod) | 10.0.1.25 | Prod workloads |
| server-db-01 | DB Primary | 10.0.1.30 | PostgreSQL primary, MongoDB primary |
| server-db-02 | DB Replica | 10.0.1.31 | PostgreSQL replica, MongoDB secondary |
| server-db-03 | DB Replica | 10.0.1.32 | PostgreSQL replica, MongoDB secondary |

---

## Setup Order

```
1. Prepare all servers (OS, firmware, kernel)  [01-Server-Preparation.md]
2. Configure networking (bonds, VLANs)          [02-Network-Configuration.md]
3. Bootstrap Kubernetes cluster                 [03-Kubernetes-Setup.md]
4. Deploy storage (MinIO + NFS)                 [04-Storage-Setup.md]
5. Deploy databases (PG + Mongo)                [05-Database-Setup.md]
6. Deploy platform services                     [06-Platform-Services.md]
7. Deploy observability and security            [07-Observability-Security.md]
8. Configure backup and DR                      [08-Backup-DR.md]
9. Migrate from Azure                           [../Volume-2-Migration-Strategy/]
```

---

*Classification: Internal | Version: 1.0 | Date: July 2026*
