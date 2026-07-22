# Reference Guides — Index

> These guides are **optional reading** and not required for the VxRail migration.
> Your primary migration guide is in [`../VxRail-VMware-Migration/`](../VxRail-VMware-Migration/00-Index.md).

---

## What Is In This Reference Section

| Directory | Purpose | When Useful |
|-----------|---------|------------|
| [KVM-OLVM-Guide](KVM-OLVM-Guide/00-Index.md) | Deep-dive: KVM hypervisor + Oracle Linux Virtualization Manager. Installation, networking, storage, security, VM creation, K8s on KVM, backup, monitoring. | If you consider KVM as an alternative hypervisor in future |
| [OnPrem-KVM](OnPrem-KVM/00-Index.md) | Step-by-step migration guide for KVM-based on-prem infra (not VxRail) | If you migrate a KVM environment |
| [OnPrem-BareMetal](OnPrem-BareMetal/00-Index.md) | Step-by-step migration guide for bare-metal servers (no hypervisor) | If you migrate a bare-metal environment |
| [Volume-1-Executive-Architecture](Volume-1-Executive-Architecture/) | Executive summary, Azure architecture docs, target architecture, component guide | Executive presentations, architecture reviews |
| [Volume-2-Migration-Strategy](Volume-2-Migration-Strategy/) | General migration strategy, Gantt charts, risk register, multi-env plan | Planning and stakeholder alignment |
| [Volume-3-Infrastructure-Setup](Volume-3-Infrastructure-Setup/) | Network and compute configuration (generic, not VxRail-specific) | Generic infra reference |
| [Volume-4-Kubernetes-Platform](Volume-4-Kubernetes-Platform/) | Generic K8s setup + detailed commands reference | K8s command reference |
| [Volume-5-Database-Migration](Volume-5-Database-Migration/) | PostgreSQL HA migration (generic Patroni guide) | DB team reference |
| [Volume-6-Application-Migration](Volume-6-Application-Migration/) | App containerization, Helm charts, ArgoCD, GitLab CI | App team reference |
| [Volume-7-Monitoring-Security](Volume-7-Monitoring-Security/) | Prometheus, Grafana, ELK, Vault, NetworkPolicy | Monitoring team reference |
| [Volume-8-GoLive-Operations](Volume-8-GoLive-Operations/) | Go-live runbook, rollback plan, daily ops, Azure decommission | Ops team reference |

---

## KVM-OLVM Guide Contents

| # | File | Contents |
|---|------|---------|
| 00 | [Index](KVM-OLVM-Guide/00-Index.md) | KVM vs OLVM comparison, Azure service mapping |
| 01 | [KVM Installation](KVM-OLVM-Guide/01-KVM-Installation.md) | Install KVM on OL9/RHEL9, SELinux, verify |
| 02 | [OLVM Installation](KVM-OLVM-Guide/02-OLVM-Installation.md) | Engine setup, add hosts, storage, HA, REST API |
| 03 | [KVM Networking](KVM-OLVM-Guide/03-KVM-Networking.md) | Linux bridge, bonding, VLANs, OVS, SR-IOV |
| 04 | [KVM Storage](KVM-OLVM-Guide/04-KVM-Storage.md) | QCOW2, LVM, NFS, iSCSI, snapshots, performance |
| 05 | [KVM Security](KVM-OLVM-Guide/05-KVM-Security.md) | sVirt, SELinux, TLS, VM isolation, audit logging |
| 06 | [KVM Best Practices](KVM-OLVM-Guide/06-KVM-Best-Practices.md) | CPU pinning, NUMA, hugepages, live migration |
| 07 | [Creating VMs](KVM-OLVM-Guide/07-Creating-VMs.md) | virt-install, cloud-init, bulk creation, templates |
| 08 | [OLVM HTTPS Cert](KVM-OLVM-Guide/08-OLVM-HTTPS-Certificate.md) | Internal CA, Let's Encrypt, auto-renewal |
| 09 | [K8s on KVM](KVM-OLVM-Guide/09-Kubernetes-on-KVM.md) | Provision VMs in OLVM, kubeadm HA, Calico |
| 10 | [OLVM Backup](KVM-OLVM-Guide/10-OLVM-Backup.md) | engine-backup, OVA export, snapshot schedule |
| 11 | [Monitoring and Logging](KVM-OLVM-Guide/11-Monitoring-Logging.md) | node_exporter, libvirt-exporter, ELK, alerts |
| 12 | [Backup and Recovery](KVM-OLVM-Guide/12-Backup-Recovery.md) | Cold backup, dirty bitmaps, Bacula, MinIO, DR |
