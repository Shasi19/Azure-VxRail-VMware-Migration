# VxRail VMware Migration — Master Index

> **Read the files in the order shown below.** Each file is numbered to match the sequence of work.  
> **Infrastructure:** 6-node Dell VxRail HCI + VMware vSphere | **VM OS:** Oracle Linux 9  
> **Backup:** Veeam Backup and Replication | **Phase 1:** Dev + QA | **Phase 2:** PreProd + Prod

---

## Files in Reading Order

| # | File | What It Covers | When |
|---|------|---------------|------|
| 00 | [**00-Index.md**](00-Index.md) | This file — navigation and master timeline | Start |
| 01 | [**01-Architecture-Overview.md**](01-Architecture-Overview.md) | Current Azure architecture, current VxRail on-prem, target architecture, procurement list, why every component is used | Day 0 — Read First |
| 02 | [**02-Current-Infra-Inventory.md**](02-Current-Infra-Inventory.md) | Audit your VxRail cluster — model ID scripts, hardware worksheet, resource counts | Day 0 |
| 03 | [**03-Procurement-Guide.md**](03-Procurement-Guide.md) | What to order — switches, NAS, VPN, licenses with prices and lead times | Day 0–Week 2 |
| 04 | [**04-Initial-Setup-Before-Migration.md**](04-Initial-Setup-Before-Migration.md) | 15-step foundation — DNS/BIND9, NTP, internal CA, Azure VPN, jump host, Ansible, readiness gate | Weeks 5–8 |
| 05 | [**05-Infrastructure-Assessment.md**](05-Infrastructure-Assessment.md) | vSphere CPU/RAM/vSAN capacity audit, cluster readiness checklist | Week 8 |
| 06 | [**06-Oracle-Linux-VMs.md**](06-Oracle-Linux-VMs.md) | Oracle Linux 9 VM template creation, dnf vs apt commands, cloud-init, K8s on OL9, SELinux, firewalld | Weeks 9–10 |
| 07 | [**07-VM-Provisioning-vSphere.md**](07-VM-Provisioning-vSphere.md) | Create all 27 VMs with govc CLI, bulk clone script, DRS anti-affinity rules | Week 10 |
| 08 | [**08-Network-vSphere.md**](08-Network-vSphere.md) | DVS port groups, VLANs, MetalLB L2 mode, keepalived VIP, firewalld rules | Week 10–11 |
| 09 | [**09-Storage-vSAN.md**](09-Storage-vSAN.md) | vSAN storage policies (FTT-0/1/RAID-5), vSphere CSI driver, StorageClasses per env, MinIO | Week 11 |
| 10 | [**10-Kubernetes-vSphere.md**](10-Kubernetes-vSphere.md) | kubeadm 3-master HA, vSphere CCM, Calico CNI, MetalLB, verification scripts | Weeks 11–12 |
| 11 | [**11-Veeam-Backup.md**](11-Veeam-Backup.md) | Veeam B&R v12 setup, VM backup jobs, Veeam Agent on OL9, Kasten K10 for K8s, restore procedures | Week 12 |
| 12 | [**12-Migration-Execution.md**](12-Migration-Execution.md) | Master step-by-step commands — Harbor, ArgoCD, PostgreSQL, MongoDB migration, app deploy, DNS cutover | Weeks 13–24 |
| 13 | [**13-Phase1-Dev-QA.md**](13-Phase1-Dev-QA.md) | Phase 1 week-by-week — Dev+QA infra → DB migration → app deploy → validation → sign-off | Weeks 13–20 |
| 14 | [**14-Phase2-PreProd-Prod.md**](14-Phase2-PreProd-Prod.md) | Phase 2 — Patroni HA, pglogical live replication, maintenance window cutover, Azure decommission | Weeks 21–30 |
| 15 | [**15-Cutover-Runbook.md**](15-Cutover-Runbook.md) | DNS cutover scripts, smoke tests, rollback decision tree, 72h post-cutover monitoring | Weeks 20 + 28 |
| 16 | [**16-Patching-Cycles.md**](16-Patching-Cycles.md) | Monthly/Quarterly/Semi-annual/Annual patch cycles — OS, K8s, DB, VxRail, Veeam, Helm charts | Ongoing |
| 17 | [**17-Troubleshooting-Errors.md**](17-Troubleshooting-Errors.md) | Error catalog — vSphere, K8s, PostgreSQL, MongoDB, Harbor, DNS, Veeam, VPN — every error with fix | Reference |
| 18 | [**18-Visual-Setup-Guide.md**](18-Visual-Setup-Guide.md) | Screen-by-screen visual reference — VxRail Manager, vCenter, Anaconda installer, kubectl outputs, Harbor, ArgoCD, Grafana, Veeam UI | Reference |

---

## Step-by-Step Migration Flow

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                   VXRAIL MIGRATION — 32-WEEK MASTER FLOW                     ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║  STAGE 0 — DISCOVERY AND PLANNING  (Weeks 1–4)                               ║
║  ┌─────────────────────────────────────────────────────────────────────┐     ║
║  │  Step 1. Read 01-Architecture-Overview.md                           │     ║
║  │          Understand: Azure now, VxRail now, Target state            │     ║
║  │  Step 2. Audit VxRail cluster  →  02-Current-Infra-Inventory.md     │     ║
║  │  Step 3. Raise procurement     →  03-Procurement-Guide.md           │     ║
║  │          ORDER SWITCH/NAS NOW (8-week hardware lead time)           │     ║
║  │  Step 4. Get approvals: Change Request for migration project        │     ║
║  └─────────────────────────────────────────────────────────────────────┘     ║
║                                │                                             ║
║                                ▼                                             ║
║  STAGE 1 — HARDWARE DELIVERY BUFFER  (Weeks 5–8)                             ║
║  ┌─────────────────────────────────────────────────────────────────────┐     ║
║  │  Step 5. Receive and rack new hardware (switch, NAS)                │     ║
║  │  Step 6. Configure on-prem foundations → 04-Initial-Setup.md        │     ║
║  │          DNS, NTP, internal CA, Azure VPN, jump host, Ansible       │     ║
║  │  Step 7. vSphere resource assessment → 05-Infrastructure-Assessment │     ║
║  └─────────────────────────────────────────────────────────────────────┘     ║
║                                │                                             ║
║                                ▼                                             ║
║  STAGE 2 — INFRASTRUCTURE BUILD  (Weeks 9–12)                                ║
║  ┌─────────────────────────────────────────────────────────────────────┐     ║
║  │  Step 8.  Create Oracle Linux 9 VM template → 06-Oracle-Linux-VMs   │     ║
║  │  Step 9.  Clone all 27 VMs via govc → 07-VM-Provisioning-vSphere    │     ║
║  │  Step 10. Configure DVS VLANs + firewalld → 08-Network-vSphere      │     ║
║  │  Step 11. Set up vSAN CSI + StorageClasses → 09-Storage-vSAN        │     ║
║  │  Step 12. Build K8s HA cluster (kubeadm) → 10-Kubernetes-vSphere    │     ║
║  │  Step 13. Configure Veeam backup jobs → 11-Veeam-Backup             │     ║
║  │  Step 14. Deploy Harbor, ArgoCD, Prometheus → 12-Migration-Execution│     ║
║  │           *** Buffer Week 12: Fix any infra errors ***              │     ║
║  └─────────────────────────────────────────────────────────────────────┘     ║
║                                │                                             ║
║                                ▼                                             ║
║  STAGE 3 — PHASE 1: DEV + QA MIGRATION  (Weeks 13–20)                        ║
║  ┌─────────────────────────────────────────────────────────────────────┐     ║
║  │  Step 15. Migrate Dev PostgreSQL (pg_dump + pg_restore)             │     ║
║  │  Step 16. Migrate Dev MongoDB (mongodump + mongorestore)            │     ║
║  │  Step 17. Deploy Dev app workloads to K8s                           │     ║
║  │  Step 18. Dev validation + sign-off (2 weeks)                       │     ║
║  │  Step 19. Repeat for QA environment                                 │     ║
║  │  Step 20. Dev + QA DNS cutover → 15-Cutover-Runbook.md              │     ║
║  │           *** Buffer Weeks 19–20: Rework + approvals ***            │     ║
║  │           → Detailed: 13-Phase1-Dev-QA.md                           │     ║
║  └─────────────────────────────────────────────────────────────────────┘     ║
║                                │                                             ║
║                                ▼                                             ║
║  STAGE 4 — PHASE 2: PREPROD + PROD MIGRATION  (Weeks 21–30)                  ║
║  ┌─────────────────────────────────────────────────────────────────────┐     ║
║  │  Step 21. Migrate PreProd (Patroni HA + MongoDB RS)                 │     ║
║  │  Step 22. PreProd validation + approval gate (2 weeks)              │     ║
║  │  Step 23. Start pglogical LIVE replication: Prod PostgreSQL         │     ║
║  │  Step 24. Deploy Prod apps to K8s (parallel with Azure)             │     ║
║  │  Step 25. Load test + performance validation on on-prem             │     ║
║  │  Step 26. Maintenance window: Prod DNS cutover                      │     ║
║  │           *** Buffer Weeks 29–30: Hypercare + Azure on standby ***  │     ║
║  │           → Detailed: 14-Phase2-PreProd-Prod.md + 15-Cutover-Runbook│     ║
║  └─────────────────────────────────────────────────────────────────────┘     ║
║                                │                                             ║
║                                ▼                                             ║
║  STAGE 5 — STABILIZATION + AZURE DECOMMISSION  (Weeks 31–32)                 ║
║  ┌─────────────────────────────────────────────────────────────────────┐     ║
║  │  Step 27. 72h monitoring — confirm all production traffic on-prem   │     ║
║  │  Step 28. Azure resource decommission (staged, keep VPN last)       │     ║
║  │  Step 29. Establish patch cycles → 16-Patching-Cycles.md            │     ║
║  │  Step 30. Handover ops runbook to team                              │     ║
║  └─────────────────────────────────────────────────────────────────────┘     ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

---

## Extended 32-Week Project Timeline

> **Why 32 weeks?** Original estimate was 18 weeks. Added: 4 weeks procurement buffer, 2 weeks
> approvals, 2 weeks people/training, 3 weeks error rework, 2 weeks hypercare, 1 week
> Azure decommission. This is a realistic timeline — do not compress Prod cutover.

```
WEEK  ACTIVITY                                           MILESTONE
────  ─────────────────────────────────────────────────  ──────────────────────────
 1    Architecture review, team alignment                
 2    vSphere/vSAN audit (02-Current-Infra-Inventory)   
 3    Procurement order placed (switch, NAS, licenses)   ORDER PLACED ★
 4    Change Request submitted for approval             
 5    CR approval (target: end of week 5)               
 6    Hardware delivery window starts                   
 7    Hardware delivery continues / racking             
 8    Hardware racked + cabled; Foundation setup begins  HARDWARE READY ★
 9    DNS/NTP/CA/VPN/jump host setup                    
10    Ansible playbooks, readiness gate pass            
11    OL9 template + VM cloning (all 27 VMs)            
12    Network VLANs, K8s HA cluster build               
13    CSI driver, Veeam backup config, Harbor deploy     INFRA COMPLETE ★
14    Buffer week — fix infra errors (expected: 2–3)    
15    Dev PostgreSQL + MongoDB migration                 
16    Dev application deployment to K8s                 
17    Dev integration testing                           
18    Dev sign-off + approvals                          
19    QA PostgreSQL + MongoDB migration                 
20    QA application deployment + testing               
21    Buffer week — rework QA issues                    
22    Dev + QA DNS cutover (maintenance window)         PHASE 1 COMPLETE ★
23    PreProd Patroni HA setup + data migration         
24    PreProd MongoDB RS + app deployment               
25    PreProd load testing + approval                   
26    Buffer — PreProd rework if needed                 
27    PreProd DNS cutover                               PREPROD LIVE ★
28    Prod pglogical live replication START             
29    Prod app deployed to K8s (parallel with Azure)    
30    Prod performance validation + load test           
31    Maintenance window: Prod DNS cutover              PROD CUTOVER ★
32    72h hypercare + Azure on cold standby             
     → If stable: Azure decommission                   PROJECT COMPLETE ★
```

### Buffer Weeks Explained

| Buffer Week | Risk Being Buffered | What Happens If Buffer Needed |
|-------------|--------------------|-----------------------------|
| Weeks 5–7 | Hardware delivery delay (common — 4–8 weeks lead) | Procurement started Week 3; delivery by Week 7 expected |
| Week 14 | Infrastructure build errors (K8s, CNI, CSI issues) | Fix issues from 17-Troubleshooting-Errors.md |
| Week 21 | QA migration rework (DB schema issues, app errors) | Resolve before Phase 1 sign-off |
| Week 26 | PreProd issues (HA failover, pglogical replication) | Extra time before Prod |
| Week 32 | Post-cutover Prod issues (hypercare period) | Azure kept as fallback for 72h |

### Approval Gates (Required Before Proceeding)

```
GATE 1 (End Week 4):  Architecture + Procurement approved by management
GATE 2 (End Week 13): Infrastructure complete — all K8s nodes healthy, Veeam configured
GATE 3 (End Week 22): Dev+QA migration complete — QA sign-off by QA team lead
GATE 4 (End Week 27): PreProd sign-off — performance test passed, manager approved
GATE 5 (End Week 31): Prod cutover — CTO/management sign-off REQUIRED
```

---

## VM Allocation (All 27 VMs)

| VM Name | OS | Role | vCPU | RAM | Disk | VxRail Node |
|---------|-----|------|------|-----|------|-------------|
| k8s-master-1 | OL9 | K8s Control Plane | 4 | 8 GB | 80 GB | VxRail-1 |
| k8s-master-2 | OL9 | K8s Control Plane | 4 | 8 GB | 80 GB | VxRail-2 |
| k8s-master-3 | OL9 | K8s Control Plane | 4 | 8 GB | 80 GB | VxRail-3 |
| k8s-worker-1 | OL9 | K8s Worker (Dev+QA) | 8 | 16 GB | 100 GB | VxRail-4 |
| k8s-worker-2 | OL9 | K8s Worker (Dev+QA) | 8 | 16 GB | 100 GB | VxRail-4 |
| k8s-worker-3 | OL9 | K8s Worker (PreProd) | 12 | 32 GB | 150 GB | VxRail-5 |
| k8s-worker-4 | OL9 | K8s Worker (PreProd) | 12 | 32 GB | 150 GB | VxRail-5 |
| k8s-worker-5 | OL9 | K8s Worker (Prod) | 16 | 64 GB | 200 GB | VxRail-6 |
| k8s-worker-6 | OL9 | K8s Worker (Prod) | 16 | 64 GB | 200 GB | VxRail-6 |
| db-dev-01 | OL9 | PostgreSQL Dev | 4 | 8 GB | 200 GB | VxRail-1 |
| db-qa-01 | OL9 | PostgreSQL QA | 4 | 8 GB | 200 GB | VxRail-2 |
| db-preprod-01 | OL9 | PostgreSQL PreProd (Patroni primary) | 4 | 16 GB | 500 GB | VxRail-3 |
| db-preprod-02 | OL9 | PostgreSQL PreProd (Patroni replica) | 4 | 16 GB | 500 GB | VxRail-4 |
| db-prod-01 | OL9 | PostgreSQL Prod (Patroni primary) | 8 | 32 GB | 1 TB | VxRail-4 |
| db-prod-02 | OL9 | PostgreSQL Prod (Patroni replica) | 8 | 32 GB | 1 TB | VxRail-5 |
| db-prod-03 | OL9 | PostgreSQL Prod (Patroni replica) | 8 | 32 GB | 1 TB | VxRail-6 |
| mongo-dev-01 | OL9 | MongoDB Dev (standalone) | 2 | 4 GB | 100 GB | VxRail-1 |
| mongo-qa-01 | OL9 | MongoDB QA (standalone) | 2 | 4 GB | 100 GB | VxRail-2 |
| mongo-preprod-01 | OL9 | MongoDB PreProd RS | 4 | 8 GB | 300 GB | VxRail-3 |
| mongo-preprod-02 | OL9 | MongoDB PreProd RS | 4 | 8 GB | 300 GB | VxRail-5 |
| mongo-prod-01 | OL9 | MongoDB Prod RS | 4 | 16 GB | 500 GB | VxRail-4 |
| mongo-prod-02 | OL9 | MongoDB Prod RS | 4 | 16 GB | 500 GB | VxRail-5 |
| mongo-prod-03 | OL9 | MongoDB Prod RS | 4 | 16 GB | 500 GB | VxRail-6 |
| minio-01 | OL9 | MinIO Object Storage | 4 | 8 GB | 2 TB | VxRail-5 |
| harbor-01 | OL9 | Harbor Container Registry | 4 | 8 GB | 500 GB | VxRail-6 |
| monitoring-01 | OL9 | Prometheus + Grafana | 4 | 16 GB | 500 GB | VxRail-6 |
| vxrail-vbr-01 | Win2022 | Veeam Backup and Replication | 8 | 16 GB | 600 GB | VxRail-6 |

---

## Network / IP Plan

| Subnet | VLAN | Purpose | Range |
|--------|------|---------|-------|
| Management | 10 | vCenter, ESXi mgmt, jump host, DNS, Veeam | 10.0.1.0/24 |
| K8s Control Plane | 30 | 3 masters + keepalived VIP | 10.0.3.0/24 |
| K8s Workers | 40 | 6 workers + MetalLB pool | 10.0.4.0/24 |
| Databases | 50 | PostgreSQL + MongoDB VMs | 10.0.5.0/24 |
| Services | 60 | Harbor, MinIO, Monitoring | 10.0.6.0/24 |

---

## Azure to On-Prem Service Mapping

| Azure | On-Prem Replacement | File |
|-------|---------------------|------|
| AKS | K8s 1.29 kubeadm on OL9 VMs | `10-Kubernetes-vSphere.md` |
| Cosmos DB (MongoDB API) | MongoDB 7.0 ReplicaSet | `12-Migration-Execution.md` |
| Azure Container Registry | Harbor | `12-Migration-Execution.md` |
| Azure PostgreSQL | PostgreSQL 15 + Patroni HA | `12-Migration-Execution.md` |
| Azure Storage Account | MinIO | `09-Storage-vSAN.md` |
| Azure VNet | DVS Port Groups (VLANs) | `08-Network-vSphere.md` |
| Azure Load Balancer | MetalLB + keepalived | `08-Network-vSphere.md` |
| Azure Monitor | Prometheus + Grafana | `12-Migration-Execution.md` |
| Azure Backup / Velero | Veeam B&R v12 + Kasten K10 | `11-Veeam-Backup.md` |
| Azure Update Management | Patch cycles (dnf + kubeadm) | `16-Patching-Cycles.md` |
