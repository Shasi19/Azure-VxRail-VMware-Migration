# Visual Setup Guide — Screen-by-Screen Reference

> **Purpose:** This guide provides visual representations of every major UI screen, terminal output, and configuration dialog you will encounter during setup. Use this alongside the step-by-step guides to confirm you are in the right place and seeing the right thing.

---

## Table of Contents

1. [VxRail Manager — Health Dashboard](#1-vxrail-manager--health-dashboard)
2. [VxRail Manager — Update Wizard](#2-vxrail-manager--update-wizard)
3. [vCenter — Login Screen](#3-vcenter--login-screen)
4. [vCenter — Hosts and Clusters View](#4-vcenter--hosts-and-clusters-view)
5. [vCenter — Create Datacenter and Cluster](#5-vcenter--create-datacenter-and-cluster)
6. [vCenter — Distributed Virtual Switch (DVS)](#6-vcenter--distributed-virtual-switch-dvs)
7. [vCenter — Create DVS Port Groups (VLANs)](#7-vcenter--create-dvs-port-groups-vlans)
8. [vCenter — Storage Policies](#8-vcenter--storage-policies)
9. [vCenter — vSAN Health Dashboard](#9-vcenter--vsan-health-dashboard)
10. [vCenter — Create VM from Template](#10-vcenter--create-vm-from-template)
11. [vCenter — VM Hardware Settings](#11-vcenter--vm-hardware-settings)
12. [Oracle Linux 9 — Boot Menu](#12-oracle-linux-9--boot-menu)
13. [Oracle Linux 9 — Anaconda Installation Summary](#13-oracle-linux-9--anaconda-installation-summary)
14. [Oracle Linux 9 — Software Selection Screen](#14-oracle-linux-9--software-selection-screen)
15. [Oracle Linux 9 — Disk Partitioning Screen](#15-oracle-linux-9--disk-partitioning-screen)
16. [Oracle Linux 9 — Network and Hostname Screen](#16-oracle-linux-9--network-and-hostname-screen)
17. [Oracle Linux 9 — Post-Install Terminal](#17-oracle-linux-9--post-install-terminal)
18. [kubectl — Healthy Cluster Output](#18-kubectl--healthy-cluster-output)
19. [kubectl — Pod Status Views](#19-kubectl--pod-status-views)
20. [Harbor — Web UI](#20-harbor--web-ui)
21. [ArgoCD — Application Dashboard](#21-argocd--application-dashboard)
22. [Grafana — K8s Overview Dashboard](#22-grafana--k8s-overview-dashboard)
23. [Veeam — Backup Console](#23-veeam--backup-console)
24. [Veeam — Backup Job Status](#24-veeam--backup-job-status)
25. [govc — CLI Output Reference](#25-govc--cli-output-reference)

---

## 1. VxRail Manager — Health Dashboard

> **URL:** `https://vxrail-manager.internal.company.com`  
> **What you want to see:** All nodes green, vSAN healthy, no alerts.

```
+--------------------------------------------------------------------------------------------------------------------------+
|  DELL VxRail Manager  v8.x.xxx        [admin v]  [?]  [Alerts: 0]                                            [Logout]   |
+--------------------------------------------------------------------------------------------------------------------------+
|                                                                                                                          |
|  [Dashboard]  [Update]  [Networking]  [Storage]  [Security]  [Support]                                                  |
|                                                                                                                          |
+------------------------+--------+--------+--------+--------+--------+--------+-------------------------------------------+
|                        |                                                      |                                          |
|  CLUSTER HEALTH        |                   CLUSTER SUMMARY                   |   ALERTS                                 |
|  +-----------+         |                                                      |   No active alerts                       |
|  |           |         |   Nodes Online:        6 / 6                        |                                          |
|  |   [PASS]  |         |   vSAN Capacity:       23.4 TB / 46.1 TB            |                                          |
|  |  HEALTHY  |         |   vSAN Health:         Healthy                      |                                          |
|  |           |         |   vCenter:             Connected                    |                                          |
|  +-----------+         |   Last Health Check:   2 minutes ago                |                                          |
|                        |   Cluster ID:          VxRail-Cluster-01            |                                          |
|                        |                                                      |                                          |
+------------------------+--------+--------+--------+--------+--------+--------+------------------------------------------+
|                                                                                                                          |
|  NODE STATUS                                                                                                             |
|                                                                                                                          |
|  +------------------+  +------------------+  +------------------+  +------------------+  +------------------+  +------+ |
|  | VxRail Node 1    |  | VxRail Node 2    |  | VxRail Node 3    |  | VxRail Node 4    |  | VxRail Node 5    |  | ...  | |
|  | esxi-01          |  | esxi-02          |  | esxi-03          |  | esxi-04          |  | esxi-05          |  |      | |
|  | [*] HEALTHY      |  | [*] HEALTHY      |  | [*] HEALTHY      |  | [*] HEALTHY      |  | [*] HEALTHY      |  | [*]  | |
|  | CPU:  23%        |  | CPU:  18%        |  | CPU:  31%        |  | CPU:  12%        |  | CPU:  28%        |  |      | |
|  | RAM:  61%        |  | RAM:  55%        |  | RAM:  72%        |  | RAM:  48%        |  | RAM:  67%        |  |      | |
|  | Disk: OK         |  | Disk: OK         |  | Disk: OK         |  | Disk: OK         |  | Disk: OK         |  |      | |
|  | NIC:  UP         |  | NIC:  UP         |  | NIC:  UP         |  | NIC:  UP         |  | NIC:  UP         |  |      | |
|  +------------------+  +------------------+  +------------------+  +------------------+  +------------------+  +------+ |
|                                                                                                                          |
|  [*] = Green indicator = Healthy    [!] = Yellow = Warning    [X] = Red = Critical                                      |
+--------------------------------------------------------------------------------------------------------------------------+
```

> **If you see any node showing [!] or [X]:** Do NOT proceed with migration. Resolve all warnings first via `VxRail Manager → Support → Run Diagnostics`.

---

## 2. VxRail Manager — Update Wizard

> **Navigation:** VxRail Manager → Update → Check for Updates

```
+--------------------------------------------------------------------------------------------------------------------------+
|  DELL VxRail Manager  — Update                                                                                           |
+--------------------------------------------------------------------------------------------------------------------------+
|                                                                                                                          |
|  Current Version:  VxRail 8.0.210     ESXi: 8.0 Update 2c     vCenter: 8.0.2                                           |
|                                                                                                                          |
|  +------------------------------------------------------------------------------------------------------+                |
|  | AVAILABLE UPDATE                                                                                     |                |
|  |                                                                                                      |                |
|  |  Bundle: VxRail 8.0.300                                                                             |                |
|  |  Includes:                                                                                           |                |
|  |    - ESXi 8.0 Update 3a (security patches + bug fixes)                                              |                |
|  |    - iDRAC firmware 7.10.30.10                                                                      |                |
|  |    - NIC drivers 22.40.5                                                                            |                |
|  |    - vSAN 8.0 patch                                                                                 |                |
|  |  Release Notes: [View]                                                                               |                |
|  |                                                                                                      |                |
|  |  Estimated Duration: 4-6 hours (rolling update, no downtime)                                        |                |
|  |  Update Method:  [o] Rolling Update (recommended)  [ ] Parallel Update (NOT for production)         |                |
|  |                                                                                                      |                |
|  |  Schedule:  [ ] Run now   [o] Schedule for: [2026-07-26 01:00]                                      |                |
|  |                                                                                                      |                |
|  |  Notification email:  [your-team@company.com              ]                                         |                |
|  |                                                                                                      |                |
|  |  [Preflight Check]  <-- ALWAYS click this first                                                     |                |
|  |  [Start Update]                                                                                      |                |
|  +------------------------------------------------------------------------------------------------------+                |
|                                                                                                                          |
|  IMPORTANT: Never click "Start Update" without running "Preflight Check" first.                                         |
|  Preflight checks vSAN health, network connectivity, and host readiness before patching.                                 |
+--------------------------------------------------------------------------------------------------------------------------+
```

---

## 3. vCenter — Login Screen

> **URL:** `https://vcenter.internal.company.com/ui`  
> **Credentials:** `administrator@vsphere.local` / `<your-password>`

```
+----------------------------------------------------------+
|                                                          |
|             VMware vSphere Client                        |
|                                                          |
|  +----------------------------------------------------+  |
|  |                                                    |  |
|  |   Username:  [administrator@vsphere.local      ]  |  |
|  |                                                    |  |
|  |   Password:  [**************************       ]  |  |
|  |                                                    |  |
|  |   [ ] Use Windows session authentication           |  |
|  |                                                    |  |
|  |   [        LOGIN        ]                          |  |
|  |                                                    |  |
|  +----------------------------------------------------+  |
|                                                          |
|  vCenter Server: vcenter.internal.company.com           |
|  Version: 8.0.2                                         |
+----------------------------------------------------------+

TIP: If login fails with "invalid credentials":
  - Check caps lock
  - Try: administrator@vsphere.local (not just "administrator")
  - Password set during VxRail deployment wizard
```

---

## 4. vCenter — Hosts and Clusters View

> **Navigation:** Menu → Hosts and Clusters  
> **What you want to see:** All 6 ESXi hosts connected (green) under one cluster.

```
+--------------------------------------------------------------------------------------------------------------------------+
|  vSphere Client                [Menu v]  [Search]                                    [admin v]  [?]                     |
+----------------------------------------------------------+---------------------------------------------------------------+
|                                                          |                                                               |
|  NAVIGATOR                                              |  SUMMARY   MONITOR   CONFIGURE   PERMISSIONS   HOSTS   VMs    |
|                                                          |                                                               |
|  v [vc] vcenter.internal.company.com                    |  Cluster: VxRail-Cluster                                      |
|    v [DC] Datacenter                                    |                                                               |
|      v [C] VxRail-Cluster        <-- click this         |  +-------------------+  +-------------------+                 |
|          [H] esxi-01.internal...  (Connected)           |  | Total Hosts: 6    |  | Total VMs: 27     |                 |
|          [H] esxi-02.internal...  (Connected)           |  | CPU Cores: 384    |  | Powered On: 27    |                 |
|          [H] esxi-03.internal...  (Connected)           |  | Memory: 3.07 TB   |  | Powered Off: 0    |                 |
|          [H] esxi-04.internal...  (Connected)           |  +-------------------+  +-------------------+                 |
|          [H] esxi-05.internal...  (Connected)           |                                                               |
|          [H] esxi-06.internal...  (Connected)           |  CLUSTER FEATURES                                             |
|                                                          |  [v] vSphere HA:         ON                                  |
|  v [n] Networks                                         |  [v] vSphere DRS:        ON (Fully Automated)                |
|    [DVS] VxRail-DVS                                     |  [v] vSAN:               ON                                  |
|      [PG] PG-Management (VLAN 10)                       |                                                               |
|      [PG] PG-K8s-Nodes (VLAN 20)   <-- should exist    |  RESOURCE SUMMARY                                             |
|      [PG] PG-Databases (VLAN 30)   <-- should exist    |  CPU Usage:       [ ####                    ]  23%            |
|      [PG] PG-Services (VLAN 40)    <-- should exist    |  Memory Usage:    [ #######                 ]  61%            |
|      [PG] vSAN (VLAN 80)                                |  Storage:         [ ###########             ]  51%            |
|      [PG] vMotion (VLAN 90)                             |                                                               |
+----------------------------------------------------------+---------------------------------------------------------------+

WHAT TO LOOK FOR:
  [H] with green dot = host Connected and healthy
  [H] with red dot   = host Disconnected (PROBLEM - fix before proceeding)
  [H] with wrench    = host in Maintenance Mode (OK during patching, not otherwise)
```

---

## 5. vCenter — Create Datacenter and Cluster

> **Navigation:** Right-click `vcenter.internal.company.com` → New Datacenter

```
STEP 1: Create Datacenter
+---------------------------------------------+
|  New Datacenter                             |
|                                             |
|  Datacenter name: [Datacenter             ] |
|                                             |
|  [  CANCEL  ]            [    OK    ]       |
+---------------------------------------------+

STEP 2: Create Cluster (right-click Datacenter → New Cluster)
+----------------------------------------------------------+
|  New Cluster                                             |
|                                                          |
|  Cluster name:  [VxRail-Cluster                      ]  |
|                                                          |
|  SERVICES                                               |
|  [v] vSphere DRS     Automation Level: [Fully Automated]|
|  [v] vSphere HA                                         |
|  [v] vSAN                                               |
|                                                          |
|  [  CANCEL  ]                  [    CREATE    ]          |
+----------------------------------------------------------+

TIP: VxRail Manager auto-creates these during initial deployment.
     Only do this manually if setting up a standalone vCenter.
```

---

## 6. vCenter — Distributed Virtual Switch (DVS)

> **Navigation:** Menu → Networking → right-click Datacenter → Distributed Switch → New Distributed Switch

```
+--------------------------------------------------------------------------------------------------------------------------+
|  vSphere Client — Networking                                                                                             |
+----------------------------------+-------------------------------------------------------------------------------------------+
|  NAVIGATOR                       |  VxRail-DVS                                                                           |
|                                  |                                                                                        |
|  v [DC] Datacenter               |  TOPOLOGY VIEW                                                                         |
|    v [DVS] VxRail-DVS  <--here  |                                                                                        |
|        [PG] PG-Management        |  +---------------------------+                                                         |
|        [PG] PG-K8s-Nodes         |  |     VxRail-DVS            |                                                         |
|        [PG] PG-Databases         |  |   (Distributed Switch)    |                                                         |
|        [PG] PG-Services          |  +--+--+--+--+--+--+--+--+--+                                                         |
|        [PG] vSAN-Traffic         |     |  |  |  |  |  |  |  |                                                            |
|        [PG] vMotion-Traffic      |   UP1 UP2 UP1 UP2 UP1 UP2 ...    (uplinks from each ESXi host)                        |
|                                  |     |  |  |  |  |  |  |  |                                                            |
|  [Actions v]                     |  esxi-01 esxi-02 esxi-03 esxi-04 esxi-05 esxi-06                                      |
|    Add Distributed Port Group    |  vmnic0  vmnic0  vmnic0  vmnic0  vmnic0  vmnic0                                        |
|    Edit Settings                 |  vmnic1  vmnic1  vmnic1  vmnic1  vmnic1  vmnic1                                        |
|    Manage Hosts                  |                                                                                        |
|                                  |  Port Groups:                                                                          |
|                                  |  NAME               VLAN  PORTS  UPLINK POLICY                                        |
|                                  |  PG-Management      10    128    Active-Active LACP                                    |
|                                  |  PG-K8s-Nodes       20    128    Active-Active LACP                                    |
|                                  |  PG-Databases       30    128    Active-Active LACP                                    |
|                                  |  PG-Services        40    128    Active-Active LACP                                    |
|                                  |  vSAN-Traffic       80    128    Dedicated uplinks                                     |
|                                  |  vMotion-Traffic    90    128    Dedicated uplinks                                     |
+----------------------------------+-------------------------------------------------------------------------------------------+
```

---

## 7. vCenter — Create DVS Port Groups (VLANs)

> **Navigation:** Networking → VxRail-DVS → Actions → Add Distributed Port Group

```
WIZARD SCREEN 1 — Select the type
+----------------------------------------------------------+
|  Add Distributed Port Group                              |
|                                                          |
|  1 Select port group type                               |
|  2 General settings                                      |
|  3 Security settings                                     |
|  4 Ready to complete                                     |
|                                                          |
|  Port group type:                                        |
|  (o) Create a distributed port group                     |
|  ( ) Early binding      ( ) Late binding                 |
|                                                          |
|  [BACK]     [NEXT]      [CANCEL]                         |
+----------------------------------------------------------+

WIZARD SCREEN 2 — General settings
+----------------------------------------------------------+
|  General settings                                        |
|                                                          |
|  Name:             [PG-K8s-Nodes                     ]  |  <-- type the name
|  Number of ports:  [128                              ]  |
|  Network I/O Control: [Default                       ]  |
|                                                          |
|  VLAN                                                    |
|  VLAN type:  [VLAN                      v]              |
|  VLAN ID:    [20                         ]  <-- VLAN ID  |
|                                                          |
|  [BACK]     [NEXT]      [CANCEL]                         |
+----------------------------------------------------------+

WIZARD SCREEN 3 — Security (for K8s nodes only)
+----------------------------------------------------------+
|  Security                                                |
|                                                          |
|  Promiscuous mode:      [Reject    v]                   |
|  MAC address changes:   [Accept    v]  <-- change to Accept  |
|  Forged transmits:      [Accept    v]  <-- change to Accept  |
|                                                          |
|  NOTE: "Accept" is REQUIRED for MetalLB LoadBalancer     |
|  and keepalived VIP to work correctly.                   |
|                                                          |
|  [BACK]     [NEXT]      [CANCEL]                         |
+----------------------------------------------------------+

WIZARD SCREEN 4 — Ready to complete
+----------------------------------------------------------+
|  Ready to complete                                       |
|                                                          |
|  Name:                PG-K8s-Nodes                      |
|  VLAN type:           VLAN                               |
|  VLAN ID:             20                                 |
|  Number of ports:     128                                |
|  Promiscuous mode:    Reject                             |
|  MAC address changes: Accept                             |
|  Forged transmits:    Accept                             |
|                                                          |
|  [BACK]    [FINISH]    [CANCEL]                          |
+----------------------------------------------------------+

Repeat for all port groups:
  PG-Management (VLAN 10)  — Security: all Reject (default)
  PG-K8s-Nodes  (VLAN 20)  — Security: MAC + Forged = Accept
  PG-Databases  (VLAN 30)  — Security: all Reject
  PG-Services   (VLAN 40)  — Security: all Reject
```

---

## 8. vCenter — Storage Policies

> **Navigation:** Menu → Policies and Profiles → VM Storage Policies → Create

```
POLICY CREATION WIZARD
+--------------------------------------------------------------------------------------------------------------------------+
|  Create VM Storage Policy                                                                                                |
+--------------------------------------------------------------------------------------------------------------------------+
|  1 Name and description   2 Policy structure   3 vSAN   4 Storage compatibility   5 Review and finish                  |
+--------------------------------------------------------------------------------------------------------------------------+

SCREEN 1 — Name
+----------------------------------------------------------+
|  Name:        [vsan-dev-qa                           ]  |
|  Description: [Dev and QA - no fault tolerance       ]  |
|  [NEXT]                                                  |
+----------------------------------------------------------+

SCREEN 2 — Policy structure
+----------------------------------------------------------+
|  Enable rules for "vSAN" storage:  [v]                  |
|  [NEXT]                                                  |
+----------------------------------------------------------+

SCREEN 3 — vSAN rules  (THIS IS THE KEY SCREEN)
+----------------------------------------------------------+
|  vSAN Rules                                              |
|                                                          |
|  Availability                                            |
|  Failures to tolerate:           [0           v]         |  <-- 0 for dev-qa
|  Failure tolerance method:       [No data redundancy v]  |
|                                                          |
|  Advanced Policy Rules                                   |
|  Number of disk stripes per obj: [1           v]         |
|  Flash read cache reservation:   [0           v]         |
|  Object space reservation:       [0%          v]         |
|                                                          |
|  [BACK]   [NEXT]                                         |
+----------------------------------------------------------+

For vsan-production:
  Failures to tolerate:       1
  Failure tolerance method:   RAID-1 (Mirroring)

For vsan-databases:
  Failures to tolerate:       1
  Failure tolerance method:   RAID-5 (Erasure Coding)
  Number of disk stripes:     4

SCREEN 4 — Storage compatibility
+----------------------------------------------------------+
|  Compatible datastores:                                  |
|  NAME           TYPE    CAPACITY   FREE     STATUS       |
|  vsanDatastore  vSAN    23.4 TB    11.2 TB  Compatible   |
|                                                          |
|  (Should show vsanDatastore as Compatible)               |
|  [BACK]   [NEXT]                                         |
+----------------------------------------------------------+
```

---

## 9. vCenter — vSAN Health Dashboard

> **Navigation:** Cluster → Monitor → vSAN → Health  
> **Goal:** All checks green before starting migration.

```
+--------------------------------------------------------------------------------------------------------------------------+
|  VxRail-Cluster — vSAN Health                                      [RUN HEALTH CHECK]                                   |
+--------------------------------------------------------------------------------------------------------------------------+
|                                                                                                                          |
|  Last check: 5 minutes ago                                                                                               |
|                                                                                                                          |
|  STATUS         CATEGORY                     CHECK NAME                                    RESULT                        |
|  ------------   ---------------------------  ----------------------------------------      --------                      |
|  [v] PASSED     Cluster                      vSAN cluster membership                       OK                            |
|  [v] PASSED     Cluster                      vSAN disk balance                             OK                            |
|  [v] PASSED     Cluster                      vSAN cluster configuration consistency        OK                            |
|  [v] PASSED     Network                      vSAN network health                           OK                            |
|  [v] PASSED     Network                      All hosts have a vSAN network adapter         OK                            |
|  [v] PASSED     Network                      Network latency check (vSAN)                  OK (avg: 0.2ms)               |
|  [v] PASSED     Physical disk               All flash cache disk                           OK                            |
|  [v] PASSED     Physical disk               Basic disk check for vSAN                      OK                            |
|  [v] PASSED     Physical disk               Disk capacity utilization                      OK (51% used)                 |
|  [v] PASSED     Data                        vSAN object health                             OK                            |
|  [v] PASSED     Data                        vSAN resync                                    OK (no resync in progress)    |
|  [!] WARNING    Online health               vSAN Build Recommendation                      Info (non-critical)           |
|  [v] PASSED     Online health               Customer Experience Improvement Program        OK                            |
|                                                                                                                          |
|  SUMMARY: 12 PASSED  1 WARNING  0 CRITICAL                                                                              |
|                                                                                                                          |
+--------------------------------------------------------------------------------------------------------------------------+

NOTE: The "vSAN Build Recommendation" warning is INFORMATIONAL only (it just says there's a newer version).
      It does NOT need to be resolved before migration.
      Any RED/CRITICAL items MUST be resolved before proceeding.
```

---

## 10. vCenter — Create VM from Template

> **Navigation:** Templates → right-click `ol9-base-template` → New VM from This Template

```
CLONE VM WIZARD — Screen 1
+----------------------------------------------------------+
|  Clone Virtual Machine from Template                     |
|                                                          |
|  1 Select a name and folder                             |
|  2 Select a compute resource                             |
|  3 Select storage                                        |
|  4 Select clone options                                  |
|  5 Ready to complete                                     |
+----------------------------------------------------------+

SCREEN 1 — Name and Folder
+----------------------------------------------------------+
|  Virtual machine name: [k8s-master-1                ]   |
|                                                          |
|  Select a location:                                      |
|  v [DC] Datacenter                                       |
|    v [Folder] K8s-ControlPlane  <-- select this         |
|                                                          |
|  [BACK]   [NEXT]                                         |
+----------------------------------------------------------+

SCREEN 2 — Compute resource
+----------------------------------------------------------+
|  Select compute resource:                                |
|  v [C] VxRail-Cluster      <-- select the cluster        |
|                                                          |
|  DRS will automatically place VM on best host.           |
|  [BACK]   [NEXT]                                         |
+----------------------------------------------------------+

SCREEN 3 — Storage
+----------------------------------------------------------+
|  Select storage:                                         |
|  NAME           TYPE   CAPACITY   FREE      POLICY       |
|  vsanDatastore  vSAN   23.4 TB    11.2 TB   [select v]   |
|                                                          |
|  VM Storage Policy: [vsan-production v]  <-- set this   |
|  Select datastore:  vsanDatastore                        |
|  [BACK]   [NEXT]                                         |
+----------------------------------------------------------+

SCREEN 4 — Clone options
+----------------------------------------------------------+
|  Clone options:                                          |
|  [ ] Customize the virtual machine's hardware           |
|  [ ] Customize the guest OS                             |
|  [v] Power on virtual machine after creation            |
|                                                          |
|  [BACK]   [NEXT]                                         |
+----------------------------------------------------------+
```

---

## 11. vCenter — VM Hardware Settings

> **Navigation:** Right-click VM → Edit Settings

```
+--------------------------------------------------------------------------------------------------------------------------+
|  Edit Settings — k8s-master-1                                                                             [ADD NEW DEVICE]|
+--------------------------------------------------------------------------------------------------------------------------+
|  VIRTUAL HARDWARE    VM OPTIONS    SDRS RULES    vApp OPTIONS                                                            |
+--------------------------------------------------------------------------------------------------------------------------+
|                                                                                                                          |
|  CPU               [4          ]  v  (expand for more options)                                                          |
|                    Reservation: 0 MHz   Limit: Unlimited   Shares: Normal                                               |
|                                                                                                                          |
|  Memory            [8192       ] MB  v                                                                                  |
|                    [v] Reserve all guest memory (All locked)  <-- check this for DB VMs                                 |
|                                                                                                                          |
|  Hard disk 1       [60         ] GB   [vsan-production v]     [Thin Provision v]                                        |
|                    Storage: vsanDatastore                                                                                |
|                                                                                                                          |
|  Network adapter 1  [PG-K8s-Nodes                     v]     [VMXNET3 v]     [v] Connect                              |
|                    MAC Address: [00:50:56:xx:xx:xx]  v                                                                  |
|                    Adapter type: VMXNET3 (best performance, required for vSphere CSI)                                   |
|                                                                                                                          |
|  CD/DVD Drive 1    [Client Device v]  [ ] Connect at power on                                                           |
|                                                                                                                          |
|  Video card        [Default settings v]                                                                                  |
|                                                                                                                          |
|  VMCI device       Present                                                                                               |
|                                                                                                                          |
|  VM Options tab -> Advanced -> Configuration Parameters:                                                                 |
|  disk.enableUUID = TRUE     <-- MUST be set for K8s/vSphere CSI                                                         |
|                                                                                                                          |
|  [CANCEL]                                              [OK]                                                              |
+--------------------------------------------------------------------------------------------------------------------------+

KEY POINT: Always verify disk.enableUUID = TRUE in VM Options > Advanced > Configuration Parameters
           for ALL K8s VMs (masters + workers). Without this, vSphere CSI PVCs will not mount.
```

---

## 12. Oracle Linux 9 — Boot Menu

> **How to access:** Open vCenter Console on the VM → watch for boot menu after ISO boot

```
+----------------------------------------------------------+
|                                                          |
|            Oracle Linux 9.4                              |
|                                                          |
|  +----------------------------------------------+       |
|  |                                              |       |
|  |  > Install Oracle Linux 9.4           <---   |       |  <- Press ENTER here
|  |    Test this media & install OL 9.4          |       |
|  |    Troubleshooting -->                       |       |
|  |                                              |       |
|  +----------------------------------------------+       |
|                                                          |
|  Press [Tab] to edit options                            |
|  Press [c] for command line                             |
|                                                          |
+----------------------------------------------------------+

TIP: If you don't press anything within 60 seconds,
     the installer auto-starts. Press any key to pause.

After pressing ENTER — you will see the Anaconda loading screen:
+----------------------------------------------------------+
|                                                          |
|  Loading vmlinuz.................                        |
|  Loading initrd.img.......................               |
|  Probing hardware devices...                            |
|  Starting Anaconda installer...                         |
|                                                          |
+----------------------------------------------------------+
```

---

## 13. Oracle Linux 9 — Anaconda Installation Summary

> **This is the main installer hub.** Complete ALL sections marked with (!) before clicking Begin Installation.

```
+--------------------------------------------------------------------------------------------------------------------------+
|  ORACLE LINUX 9.4 INSTALLATION                                                                          [HELP]           |
+--------------------------------------------------------------------------------------------------------------------------+
|                                                                                                                          |
|  INSTALLATION SUMMARY                                                                                                    |
|                                                                                                                          |
|  LOCALIZATION                                                                                                            |
|  +--------------------------------+  +--------------------------------+  +--------------------------------+              |
|  | [keyboard] Keyboard            |  | [clock] Date & Time            |  | [world] Language Support       |              |
|  | English (US)                   |  | Asia/Kolkata timezone          |  | English (United States)        |              |
|  |                                |  | NTP: ON                        |  |                                |              |
|  +--------------------------------+  +--------------------------------+  +--------------------------------+              |
|                                                                                                                          |
|  SOFTWARE                                                                                                                |
|  +--------------------------------+  +--------------------------------+                                                  |
|  | (!) Connect to Red Hat         |  | [box] Software Selection       |                                                  |
|  | Skip this (click -> No thanks) |  | Minimal Install   <-- select   |                                                  |
|  +--------------------------------+  +--------------------------------+                                                  |
|                                                                                                                          |
|  SYSTEM                                                                                                                  |
|  +--------------------------------+  +--------------------------------+  +--------------------------------+              |
|  | (!) Installation Destination   |  | (!) Network & Host Name        |  | [shield] Security Policy      |              |
|  | Automatic partitioning         |  | ens192: ON                     |  | No profile selected           |              |
|  | Click to configure  <--        |  | Click to configure  <--        |  |                               |              |
|  +--------------------------------+  +--------------------------------+  +--------------------------------+              |
|                                                                                                                          |
|  USER SETTINGS                                                                                                           |
|  +--------------------------------+  +--------------------------------+                                                  |
|  | (!) Root Password              |  | (!) User Creation              |                                                  |
|  | LOCK root account              |  | oracle (administrator)         |                                                  |
|  |                                |  |                                |                                                  |
|  +--------------------------------+  +--------------------------------+                                                  |
|                                                                                                                          |
|  (!) = Requires attention before you can begin installation                                                              |
|                                                                                                                          |
|                                                [Begin Installation]  <-- only active when all (!) resolved               |
+--------------------------------------------------------------------------------------------------------------------------+
```

---

## 14. Oracle Linux 9 — Software Selection Screen

> **Click:** Software Selection on the Installation Summary

```
+--------------------------------------------------------------------------------------------------------------------------+
|  SOFTWARE SELECTION                                                                           [Done]  [Cancel]           |
+--------------------------------------------------------------------------------------------------------------------------+
|                                                                                                                          |
|  BASE ENVIRONMENT                          |  ADD-ONS FOR SELECTED ENVIRONMENT                                           |
|  (select ONE)                              |  (check 0 or more)                                                          |
|                                            |                                                                             |
|  ( ) Server with GUI                       |  [v] Standard                                                               |
|      (includes GNOME desktop — DON'T use)  |  [v] System Tools                                                           |
|                                            |  [ ] Development Tools                                                      |
|  (o) Minimal Install  <-- SELECT THIS      |  [ ] Security Tools                                                         |
|      No GUI, core system only              |  [ ] Container Management                                                   |
|                                            |  [ ] Headless Management                                                    |
|  ( ) Server                               |  [ ] Network File System Client                                              |
|  ( ) Workstation                          |  [ ] Scientific Support                                                      |
|  ( ) Custom Operating System             |  [ ] Debugging Tools                                                          |
|  ( ) Virtualization Host                  |  [ ] Performance Tools                                                       |
|                                            |                                                                             |
|                                            |                                                                             |
|  WHY Minimal Install?                                                                                                    |
|  - Less disk space used                                                                                                  |
|  - Smaller attack surface (fewer packages = fewer vulnerabilities)                                                       |
|  - Faster boot time                                                                                                      |
|  - All needed packages installed manually via dnf                                                                        |
+--------------------------------------------------------------------------------------------------------------------------+
```

---

## 15. Oracle Linux 9 — Disk Partitioning Screen

> **Click:** Installation Destination → Custom → Done

```
+--------------------------------------------------------------------------------------------------------------------------+
|  INSTALLATION DESTINATION                                                                     [Done]  [Cancel]           |
+--------------------------------------------------------------------------------------------------------------------------+
|  LOCAL STANDARD DISKS                                                                                                    |
|                                                                                                                          |
|  +---------------------------+                                                                                           |
|  | VMware Virtual disk       |  <-- your vSAN disk (60 GB)                                                              |
|  | 60 GiB                    |  Click to select (checkmark appears)                                                     |
|  | Free space: 60 GiB        |                                                                                           |
|  +---------------------------+                                                                                           |
|                                                                                                                          |
|  STORAGE CONFIGURATION                                                                                                   |
|  (o) Automatic   <-- or select Custom for manual layout                                                                  |
|  ( ) Custom                                                                                                              |
|                                                                                                                          |
|  [Done]                                                                                                                  |
+--------------------------------------------------------------------------------------------------------------------------+

--- IF YOU SELECTED CUSTOM ---
+--------------------------------------------------------------------------------------------------------------------------+
|  MANUAL PARTITIONING                                                                          [Done]  [Cancel]           |
+--------------------------------------------------------------------------------------------------------------------------+
|  New mount points will use the following partitioning scheme:  [Standard Partition v]                                    |
|                                                                                                                          |
|  ORACLE LINUX 9 INSTALLATION                                                                                             |
|  +--------------------------------------------+------------------------------------------------------------------+      |
|  |  NEW ORACLE LINUX 9 INSTALLATION           |  DETAILS                                                         |      |
|  |  Click here to create them automatically.  |  Mount point: [/boot/efi    ]                                    |      |
|  |  <-- Click this first for auto layout      |  Desired capacity: [600 MiB   ]                                  |      |
|  |                                            |  Device type: [Standard Partition v]                             |      |
|  | /boot/efi   600 MiB   EFI System           |  File system: [EFI System Partition v]                           |      |
|  | /boot         1 GiB   xfs                  |                                                                  |      |
|  | swap          8 GiB   swap                 |  [Update Settings]                                               |      |
|  | /            50 GiB   xfs                  |                                                                  |      |
|  |                                            |                                                                  |      |
|  |  [+] [-] to add/remove partitions          |                                                                  |      |
|  +--------------------------------------------+------------------------------------------------------------------+      |
|                                                                                                                          |
|  Available space: 0 MiB     Total space: 60 GiB                                                                         |
|                                                                                                                          |
|  [Done]  (click Done → Accept Changes popup → click Accept)                                                             |
+--------------------------------------------------------------------------------------------------------------------------+
```

---

## 16. Oracle Linux 9 — Network and Hostname Screen

> **Click:** Network & Host Name on Installation Summary

```
+--------------------------------------------------------------------------------------------------------------------------+
|  NETWORK & HOST NAME                                                                          [Done]  [Cancel]           |
+--------------------------------------------------------------------------------------------------------------------------+
|                                                                                                                          |
|  INTERFACES                   |  ens192                                                                                 |
|  +-------------------------+  |  Connected: YES                                                                         |
|  | ens192                  |  |  MAC Address: 00:50:56:xx:xx:xx                                                         |
|  | 10.0.1.200              |  |  Link speed: 10000 Mb/s (10 GbE / VMXNET3)                                             |
|  | Connected               |  |                                                                                         |
|  |  [Toggle: ON/OFF]  ON   |  |  IPv4 Address:  10.0.1.200/24  (set manually - see below)                              |
|  +-------------------------+  |  DNS: 10.0.1.5                                                                          |
|                               |                                                                                         |
|                               |  [Configure...]  <-- click this to set static IP                                       |
+--------------------------------------------------------------------------------------------------------------------------+

CONFIGURE ens192 — IPv4 SETTINGS
+----------------------------------------------------------+
|  ens192 — Network configuration                         |
|                                                          |
|  General  |  Ethernet  |  IPv4 Settings  |  IPv6 ...    |
|                                                          |
|  IPv4 Settings tab:                                      |
|  Method: [Manual                      v]  <-- IMPORTANT  |
|                                                          |
|  Addresses:                                              |
|  ADDRESS         NETMASK    GATEWAY                      |
|  10.0.1.200      24         10.0.1.1                     |
|  [Add]  [Delete]                                         |
|                                                          |
|  DNS servers:  [10.0.1.5                             ]  |
|  Search domains: [internal.company.com               ]  |
|                                                          |
|  General tab:                                            |
|  [v] Automatically connect to this network              |
|  [v] All users may connect to this network              |
|                                                          |
|  [Cancel]             [Save]                             |
+----------------------------------------------------------+

HOST NAME (bottom of the Network screen):
+----------------------------------------------------------+
|  Host name: [ol9-template                           ]   |
|             [Apply]  <-- click Apply after typing        |
+----------------------------------------------------------+
```

---

## 17. Oracle Linux 9 — Post-Install Terminal

> **Expected output after running the hardening script and verifying the template.**

```
[oracle@ol9-template ~]$ sudo systemctl status vmtoolsd
* vmtoolsd.service - Service for virtual machines hosted on VMware
     Loaded: loaded (/usr/lib/systemd/system/vmtoolsd.service; enabled; vendor preset: enabled)
     Active: active (running) since Mon 2026-07-22 14:30:01 IST; 5min ago
   Main PID: 1234 (vmtoolsd)
      Tasks: 3 (limit: 23456)
     Memory: 12.3M
        CPU: 0.120s
     CGroup: /system.slice/vmtoolsd.service
             `-1234 /usr/bin/vmtoolsd

[oracle@ol9-template ~]$ getenforce
Permissive          <-- SELinux set to Permissive (required for K8s)

[oracle@ol9-template ~]$ free -h
               total        used        free      shared  buff/cache   available
Mem:           7.5Gi       800Mi       5.8Gi        12Mi       900Mi       6.5Gi
Swap:             0B          0B          0B         <-- Swap DISABLED (required for K8s)

[oracle@ol9-template ~]$ ip addr show ens192
2: ens192: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether 00:50:56:ab:cd:ef brd ff:ff:ff:ff:ff:ff
    inet 10.0.1.200/24 brd 10.0.1.255 scope global noprefixroute ens192
       valid_lft forever preferred_lft forever

[oracle@ol9-template ~]$ chronyc tracking
Reference ID    : 0A000105 (10.0.1.5)
Stratum         : 3
Ref time (UTC)  : Tue Jul 22 08:47:31 2026
System time     : 0.000034521 seconds fast of NTP time
RMS offset      : 0.000456789 seconds
Frequency       : 4.567 ppm slow
Residual freq   : 0.001 ppm
Skew            : 0.456 ppm
Root delay      : 0.008 seconds
Root dispersion : 0.001 seconds
Update interval : 64.4 seconds
Leap status     : Normal             <-- NTP working correctly

[oracle@ol9-template ~]$ sudo lsmod | grep -E "overlay|br_netfilter"
br_netfilter           32768  0               <-- loaded (required for K8s)
bridge                307200  1 br_netfilter
overlay                147456  0               <-- loaded (required for containerd)

[oracle@ol9-template ~]$ cat /proc/sys/net/ipv4/ip_forward
1                                              <-- ip_forward enabled (required for K8s)
```

---

## 18. kubectl — Healthy Cluster Output

> **Expected output from `kubectl get nodes -o wide` on a healthy cluster.**

```
[oracle@jump-host ~]$ kubectl get nodes -o wide
NAME           STATUS   ROLES           AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                    KERNEL-VERSION   CONTAINER-RUNTIME
k8s-master-1   Ready    control-plane   10d   v1.29.0   10.0.3.11     <none>        Oracle Linux Server 9.4     5.15.0-xxx       containerd://1.7.x
k8s-master-2   Ready    control-plane   10d   v1.29.0   10.0.3.12     <none>        Oracle Linux Server 9.4     5.15.0-xxx       containerd://1.7.x
k8s-master-3   Ready    control-plane   10d   v1.29.0   10.0.3.13     <none>        Oracle Linux Server 9.4     5.15.0-xxx       containerd://1.7.x
k8s-worker-1   Ready    <none>          10d   v1.29.0   10.0.4.21     <none>        Oracle Linux Server 9.4     5.15.0-xxx       containerd://1.7.x
k8s-worker-2   Ready    <none>          10d   v1.29.0   10.0.4.22     <none>        Oracle Linux Server 9.4     5.15.0-xxx       containerd://1.7.x
k8s-worker-3   Ready    <none>          10d   v1.29.0   10.0.4.23     <none>        Oracle Linux Server 9.4     5.15.0-xxx       containerd://1.7.x
k8s-worker-4   Ready    <none>          10d   v1.29.0   10.0.4.24     <none>        Oracle Linux Server 9.4     5.15.0-xxx       containerd://1.7.x
k8s-worker-5   Ready    <none>          10d   v1.29.0   10.0.4.25     <none>        Oracle Linux Server 9.4     5.15.0-xxx       containerd://1.7.x
k8s-worker-6   Ready    <none>          10d   v1.29.0   10.0.4.26     <none>        Oracle Linux Server 9.4     5.15.0-xxx       containerd://1.7.x

KEY:
  STATUS Ready        = healthy, accepting pods
  STATUS NotReady     = problem (check: kubectl describe node <name>)
  STATUS SchedulingDisabled = node is cordoned (intentional during maintenance)
  ROLES control-plane = master node (runs API server, etcd, scheduler)
  ROLES <none>        = worker node (runs your application pods)

[oracle@jump-host ~]$ kubectl get pods -n kube-system
NAME                                    READY   STATUS    RESTARTS   AGE
calico-kube-controllers-xxx             1/1     Running   0          10d    <- Calico network policy
calico-node-xxxxx (x6)                  1/1     Running   0          10d    <- One per node
coredns-xxxxxxxxxx (x2)                 1/1     Running   0          10d    <- DNS for pods
etcd-k8s-master-1                       1/1     Running   0          10d    <- etcd database
etcd-k8s-master-2                       1/1     Running   0          10d
etcd-k8s-master-3                       1/1     Running   0          10d
kube-apiserver-k8s-master-1             1/1     Running   0          10d    <- API server
kube-apiserver-k8s-master-2             1/1     Running   0          10d
kube-apiserver-k8s-master-3             1/1     Running   0          10d
kube-controller-manager-k8s-master-1   1/1     Running   0          10d    <- Controller
kube-proxy-xxxxx (x9)                   1/1     Running   0          10d    <- One per node
kube-scheduler-k8s-master-1            1/1     Running   0          10d    <- Scheduler

ALL pods should show:  READY 1/1 and STATUS Running
```

---

## 19. kubectl — Pod Status Views

> **Checking pods in your application namespaces.**

```
--- HEALTHY state ---
[oracle@jump-host ~]$ kubectl get pods -n dev
NAME                          READY   STATUS    RESTARTS   AGE
api-deployment-xxx-yyy        1/1     Running   0          2d      <- your app
frontend-xxx-yyy              1/1     Running   0          2d
postgres-dev-0                1/1     Running   0          5d
mongodb-dev-0                 1/1     Running   0          5d

--- PROBLEM states to recognize ---
api-deployment-xxx-yyy        0/1     Pending         0       5m    <- no node can run it
api-deployment-xxx-yyy        0/1     ImagePullBackOff 0      5m    <- can't pull image from Harbor
api-deployment-xxx-yyy        0/1     CrashLoopBackOff 5      5m    <- starts and crashes, K8s retrying
api-deployment-xxx-yyy        0/1     OOMKilled        0      5m    <- ran out of memory, increase limits
api-deployment-xxx-yyy        0/1     Terminating      0      10m   <- stuck deleting (use --force to delete)
api-deployment-xxx-yyy        0/1     Init:0/1         0      2m    <- init container not done yet

--- GETTING MORE INFO ---
[oracle@jump-host ~]$ kubectl describe pod api-deployment-xxx-yyy -n dev
# Look at Events section at the bottom:
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  BackOff           2m    kubelet            Back-off pulling image "harbor.internal.company.com/app:latest"
  Warning  Failed            2m    kubelet            Failed to pull image: ... unauthorized
  # FIX: kubectl create secret docker-registry harbor-secret -n dev ...

[oracle@jump-host ~]$ kubectl logs api-deployment-xxx-yyy -n dev
# Shows application logs — look for database connection errors, startup errors

[oracle@jump-host ~]$ kubectl logs api-deployment-xxx-yyy -n dev --previous
# Shows logs from previous crashed container (useful for CrashLoopBackOff)
```

---

## 20. Harbor — Web UI

> **URL:** `https://harbor.internal.company.com`  
> **Default login:** `admin` / `HarborAdmin2026!`

```
+--------------------------------------------------------------------------------------------------------------------------+
|  Harbor                                                   [Projects] [Logs] [Administration]   [admin v]   [?]          |
+--------------------------------------------------------------------------------------------------------------------------+
|                                                                                                                          |
|  PROJECTS                                      [NEW PROJECT]                                                            |
|                                                                                                                          |
|  +----------------------------------------------------------+                                                           |
|  | NAME          ACCESS LEVEL   REPOS   MEMBERS   CREATION  |                                                           |
|  | migration     Private        15      4         2026-07-01 |  <- your migrated images from ACR                       |
|  | library       Public         2       1         2026-07-01 |  <- default public project                               |
|  +----------------------------------------------------------+                                                           |
|                                                                                                                          |
|  Click on "migration" project to see repositories:                                                                      |
|                                                                                                                          |
|  REPOSITORIES in project: migration                                                                                      |
|  +------------------------------------------------------------------+                                                   |
|  | REPOSITORY              ARTIFACTS   PULLS  LAST MODIFIED         |                                                   |
|  | migration/api-service   3 tags      145    2026-07-22 14:30      |  <- docker push was successful                   |
|  | migration/frontend      5 tags      89     2026-07-22 14:28      |                                                   |
|  | migration/worker        2 tags      23     2026-07-22 14:25      |                                                   |
|  +------------------------------------------------------------------+                                                   |
|                                                                                                                          |
|  Click on repository to see tags:                                                                                        |
|  ARTIFACTS in migration/api-service:                                                                                     |
|  +--------------------------------------------------------------------+                                                 |
|  | TAG      PULLED      PUSHED          OS/ARCH      SIZE    SIGNED   |                                                 |
|  | latest   45 times    1 hour ago      linux/amd64  234 MB  No       |                                                 |
|  | v1.2.3   34 times    2 days ago      linux/amd64  231 MB  No       |                                                 |
|  | v1.2.2   10 times    5 days ago      linux/amd64  228 MB  No       |                                                 |
|  +--------------------------------------------------------------------+                                                 |
|                                                                                                                          |
|  Copy command: docker pull harbor.internal.company.com/migration/api-service:latest                                     |
+--------------------------------------------------------------------------------------------------------------------------+
```

---

## 21. ArgoCD — Application Dashboard

> **URL:** `https://argocd.internal.company.com`  
> **Login:** `admin` / `<ArgoCD admin password>`

```
+--------------------------------------------------------------------------------------------------------------------------+
|  ArgoCD                                             [Applications] [Settings] [User Info]     [admin v]   [?]           |
+--------------------------------------------------------------------------------------------------------------------------+
|                                                                                                                          |
|  APPLICATIONS                   [NEW APP]  [SYNC ALL]  [REFRESH ALL]                                                   |
|                                                                                                                          |
|  Filter: All  Synced  OutOfSync  Healthy  Degraded  Progressing                                                        |
|                                                                                                                          |
|  +----------------------------+  +----------------------------+  +----------------------------+                          |
|  |  app-dev                   |  |  app-qa                    |  |  app-prod                  |                          |
|  |  [green] SYNCED            |  |  [green] SYNCED            |  |  [green] SYNCED            |                          |
|  |  [green] Healthy           |  |  [green] Healthy           |  |  [green] Healthy           |                          |
|  |                            |  |                            |  |                            |                          |
|  |  Namespace: dev            |  |  Namespace: qa             |  |  Namespace: prod           |                          |
|  |  Repo: github.com/...      |  |  Repo: github.com/...      |  |  Repo: github.com/...      |                          |
|  |  Branch: dev               |  |  Branch: qa                |  |  Branch: main              |                          |
|  |  Last sync: 2m ago         |  |  Last sync: 5m ago         |  |  Last sync: 1h ago         |                          |
|  |  [SYNC] [REFRESH]          |  |  [SYNC] [REFRESH]          |  |  [SYNC] [REFRESH]          |                          |
|  +----------------------------+  +----------------------------+  +----------------------------+                          |
|                                                                                                                          |
|  STATUS MEANINGS:                                                                                                        |
|  [green] SYNCED      = Git repo and K8s cluster are identical (good)                                                    |
|  [yellow] OutOfSync  = Git repo has changes not yet applied to K8s (click SYNC to apply)                               |
|  [red] Degraded      = App is unhealthy (pods crashing, etc. — check pod logs)                                         |
|  [blue] Progressing  = Sync in progress, wait for it to complete                                                        |
|                                                                                                                          |
+--------------------------------------------------------------------------------------------------------------------------+

CLICK ON "app-dev" to see detailed resource tree:
+----------------------------------------------------------+
|  app-dev  [SYNCED] [Healthy]                 [SYNC][...]  |
|                                                          |
|  RESOURCES TREE                                          |
|  v [Application] app-dev                                 |
|    v [Deployment] api-deployment     [green] Healthy    |
|        v [ReplicaSet] api-xxx-yyy                        |
|            [Pod] api-xxx-yyy-aaa     [green] Running    |
|            [Pod] api-xxx-yyy-bbb     [green] Running    |
|    v [Service] api-service           [green] Healthy    |
|    v [Ingress] api-ingress           [green] Healthy    |
|    v [PVC] api-data                  [green] Bound      |
|                                                          |
|  All resources green = everything deployed correctly     |
+----------------------------------------------------------+
```

---

## 22. Grafana — K8s Overview Dashboard

> **URL:** `https://monitoring.internal.company.com` or MetalLB IP  
> **Login:** `admin` / `GrafanaAdmin2026!`

```
+--------------------------------------------------------------------------------------------------------------------------+
|  Grafana       [Dashboards v]  [Explore]  [Alerting]  [Configuration]                        [admin v]   [?]           |
+--------------------------------------------------------------------------------------------------------------------------+
|  Dashboard: Kubernetes / Compute Resources / Cluster                                                       [Last 1h v]  |
+--------------------------------------------------------------------------------------------------------------------------+
|                                                                                                                          |
|  CPU UTILISATION                                     MEMORY UTILISATION                                                 |
|  +---------------------------------------------+    +---------------------------------------------+                    |
|  | 100%|                                        |    | 100%|                                        |                    |
|  |  80%|                               .-.      |    |  80%|            .--.                        |                    |
|  |  60%|          .----.          .--./   \     |    |  60%|         .-/    \-.                     |                    |
|  |  40%|       .-/      \---.  .-/   \     \    |    |  40%|       ./          \--..---.            |                    |
|  |  20%|    .-/              \/       \     \.  |    |  20%|      /                    \            |                    |
|  |   0%+---+----------------+----------+------  |    |   0%+---+-------------------------+------    |                    |
|  |     14:00           15:00          16:00     |    |     14:00           15:00          16:00     |                    |
|  +---------------------------------------------+    +---------------------------------------------+                    |
|  Current: 23.4%   Request: 18.2%   Limit: 80%       Current: 61.2%   Request: 55.1%   Limit: 90%                       |
|                                                                                                                          |
|  NODE OVERVIEW TABLE                                                                                                     |
|  +------------------------------------------------------------------------+                                             |
|  | NODE          CPU REQ  CPU USE  MEM REQ  MEM USE  DISK USE  PODS       |                                             |
|  | k8s-master-1  800m     234m     4Gi      2.1Gi    45%       12/110     |                                             |
|  | k8s-master-2  800m     198m     4Gi      1.9Gi    42%       11/110     |                                             |
|  | k8s-master-3  800m     210m     4Gi      2.0Gi    43%       12/110     |                                             |
|  | k8s-worker-1  4000m    1200m    8Gi      5.2Gi    38%       22/110     |  <- Dev workloads                          |
|  | k8s-worker-5  8000m    3400m    16Gi     11.2Gi   52%       31/110     |  <- Prod workloads                         |
|  | k8s-worker-6  8000m    3100m    16Gi     10.8Gi   48%       28/110     |  <- Prod workloads                         |
|  +------------------------------------------------------------------------+                                             |
|                                                                                                                          |
|  ALERTS                                                                                                                  |
|  [green] 0 firing    [yellow] 1 pending    (pending = about to fire but not yet)                                        |
+--------------------------------------------------------------------------------------------------------------------------+
```

---

## 23. Veeam — Backup Console

> **Access:** Open Veeam Backup & Replication on Windows Server (veeam-server-01)

```
+--------------------------------------------------------------------------------------------------------------------------+
|  Veeam Backup & Replication                                                                                              |
+--------------------------------------------------------------------------------------------------------------------------+
|  [Home] [Backup Infrastructure] [Jobs] [History] [Files] [Configuration]                                               |
+---------------------------+--------------------------------------------------------------------------------------------------+
|                           |                                                                                              |
|  VIEWS                    |  HOME                                                                                        |
|  [*] Home                 |                                                                                              |
|  [ ] Backup Infrastructure|  INFRASTRUCTURE STATUS                                                                      |
|  [ ] Jobs                 |  +--------------------------+  +------------------------+  +---------------------------+     |
|  [ ] History              |  | Backup Servers           |  | Backup Repositories    |  | Managed Servers           |     |
|  [ ] Files                |  | 1 server (this)          |  | 1 repo (NAS-Primary)   |  | 1 (vcenter.int...)        |     |
|  [ ] Configuration        |  | Status: OK               |  | Free: 15.2 TB          |  | Status: Connected         |     |
|                           |  +--------------------------+  +------------------------+  +---------------------------+     |
|  LAST 24H SUMMARY         |                                                                                              |
|  Jobs run:       8        |  LATEST JOB ACTIVITY                                                                        |
|  Successful:     8        |  +-----------------------------------------------------------------------+                  |
|  Warnings:       0        |  | NAME                  LAST RUN              RESULT    DURATION         |                  |
|  Failed:         0        |  | Backup-Prod           Today 00:47            Success   1h 23m           |                  |
|                           |  | Backup-PreProd        Today 01:12            Success   48m              |                  |
|  Protected VMs:  27       |  | Backup-QA             Today 02:37            Success   22m              |                  |
|  Backup Size:    4.2 TB   |  | Backup-Dev            Today 02:51            Success   19m              |                  |
|                           |  +-----------------------------------------------------------------------+                  |
|                           |                                                                                              |
+---------------------------+--------------------------------------------------------------------------------------------------+

WHAT TO LOOK FOR:
  Result: Success (green) = backup completed without errors
  Result: Warning (yellow) = backup completed but some VMs had issues (check log)
  Result: Failed  (red)    = backup did not complete — investigate immediately
```

---

## 24. Veeam — Backup Job Status (Drill Down)

> **Click on a job name to see per-VM status.**

```
+--------------------------------------------------------------------------------------------------------------------------+
|  Backup-Prod — Job Statistics                                                                                            |
+--------------------------------------------------------------------------------------------------------------------------+
|  Started: Today 00:00    Ended: 01:23    Duration: 1h 23m    Status: Success                                            |
|                                                                                                                          |
|  VM PROCESSING STATUS                                                                                                    |
|  +-------------------------------------------------------------------------+                                           |
|  | VM NAME         STATUS    PROCESSING  SIZE      SPEED    DURATION       |                                           |
|  | k8s-worker-5    Success   HotAdd      45.2 GB   312 MB/s  2m 25s        |                                           |
|  | k8s-worker-6    Success   HotAdd      43.8 GB   298 MB/s  2m 27s        |                                           |
|  | db-prod-01      Success   HotAdd      312 GB    287 MB/s  18m 11s       |  <- PostgreSQL primary                   |
|  | db-prod-02      Success   HotAdd      311 GB    291 MB/s  17m 58s       |                                           |
|  | db-prod-03      Success   HotAdd      309 GB    285 MB/s  18m 5s        |                                           |
|  | mongo-prod-01   Success   HotAdd      287 GB    276 MB/s  17m 21s       |  <- MongoDB primary                      |
|  | mongo-prod-02   Success   HotAdd      284 GB    280 MB/s  17m 2s        |                                           |
|  | mongo-prod-03   Success   HotAdd      283 GB    279 MB/s  16m 59s       |                                           |
|  | harbor-01       Success   HotAdd      78.3 GB   305 MB/s  4m 17s        |                                           |
|  | minio-01        Success   HotAdd      156 GB    292 MB/s  8m 56s        |                                           |
|  +-------------------------------------------------------------------------+                                           |
|                                                                                                                          |
|  PROCESSING METHOD — HotAdd                                                                                              |
|  HotAdd = Veeam mounts VM disks directly via ESXi host                                                                  |
|  (no network copy = faster backup, doesn't use your LAN bandwidth)                                                      |
|                                                                                                                          |
|  PRE/POST SCRIPTS                                                                                                        |
|  Pre-freeze script: /opt/scripts/pre-freeze.sh   Status: Completed (0.3s)                                               |
|  Post-thaw script:  /opt/scripts/post-thaw.sh    Status: Completed (0.2s)                                               |
+--------------------------------------------------------------------------------------------------------------------------+
```

---

## 25. govc — CLI Output Reference

> **Expected output from common govc commands run from the jump host.**

```
--- govc about (verify connection) ---
[oracle@jump-host ~]$ export GOVC_URL=https://vcenter.internal.company.com
[oracle@jump-host ~]$ export GOVC_USERNAME=administrator@vsphere.local
[oracle@jump-host ~]$ export GOVC_PASSWORD='YourPassword'
[oracle@jump-host ~]$ govc about

FullName:     VMware vCenter Server 8.0.2 build-xxxxxxxx
Name:         VMware vCenter Server
Vendor:       VMware, Inc.
Version:      8.0.2
Build:        xxxxxxxx
OS type:      linux-x64
API type:     VirtualCenter
API version:  8.0.2.0
Product ID:   vpx
UUID:         xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx


--- govc host.info (all 6 hosts should be Connected) ---
[oracle@jump-host ~]$ govc host.info '*'
Name:              esxi-01.internal.company.com
  Path:            /Datacenter/host/VxRail-Cluster/esxi-01.internal.company.com
  Manufacturer:    Dell Inc.
  Logical CPUs:    64 CPUs @ 3200MHz
  Processor type:  Intel(R) Xeon(R) Silver 4316 CPU @ 2.30GHz
  CPU usage:       1345 MHz (1.0%)
  Memory:          524287MB
  Memory usage:    213401 MB (40.7%)
  Boot time:       2026-07-12 08:23:45.123456 +0000 UTC
  State:           connected                        <- should be "connected"
  Overall status:  green                            <- should be "green"

Name:              esxi-02.internal.company.com
...


--- govc vm.info (check a single VM) ---
[oracle@jump-host ~]$ govc vm.info k8s-master-1
Name:           k8s-master-1
  Path:         /Datacenter/vm/K8s-ControlPlane/k8s-master-1
  UUID:         xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  Guest name:   Oracle Linux 9 (64-bit)             <- should show oracleLinux9 not ubuntu
  Memory:       8192MB
  CPU:          4 vCPU(s)
  Power state:  poweredOn                           <- should be poweredOn
  Boot time:    2026-07-20 09:15:00 +0000 UTC
  IP address:   10.0.3.11                           <- confirms VMware Tools working + IP correct
  Host:         esxi-03.internal.company.com        <- which ESXi host it's running on
  Extra configuration:
    disk.enableUUID = TRUE                          <- CRITICAL for K8s/CSI — must be TRUE


--- govc datastore.info (check vSAN) ---
[oracle@jump-host ~]$ govc datastore.info vsanDatastore
Name:        vsanDatastore
  Path:      /Datacenter/datastore/vsanDatastore
  Type:      vsan
  URL:       ds:///vmfs/volumes/vsan:xxxxxxxxxxxxxxxx/
  Capacity:  46.1 GB
  Free:      22.5 TB (48.8%)             <- healthy free space


--- govc find (list all VMs) ---
[oracle@jump-host ~]$ govc find . -type m | sort
/Datacenter/vm/Dev/db-dev-01
/Datacenter/vm/Dev/k8s-worker-1
/Datacenter/vm/Dev/mongo-dev-01
/Datacenter/vm/Infrastructure/dns-server-01
/Datacenter/vm/Infrastructure/jump-host
/Datacenter/vm/K8s-ControlPlane/k8s-master-1
/Datacenter/vm/K8s-ControlPlane/k8s-master-2
/Datacenter/vm/K8s-ControlPlane/k8s-master-3
...
(all 27 VMs listed)
```

---

## Quick Reference — What "Good" Looks Like

| System | Where to Check | Healthy State |
|--------|---------------|---------------|
| VxRail Manager | Dashboard | All nodes green, 0 alerts |
| vCenter hosts | Hosts and Clusters | All 6 hosts: Connected, Status: green |
| vSAN | Cluster → Monitor → vSAN → Health | All checks green/yellow-info |
| K8s nodes | `kubectl get nodes` | All nodes: STATUS Ready |
| K8s system pods | `kubectl get pods -n kube-system` | All: 1/1 Running |
| Application pods | `kubectl get pods -n dev/qa/prod` | All: 1/1 Running |
| Harbor | Web UI → Projects | Images visible, no scan errors |
| ArgoCD | Web UI → Applications | All apps: Synced + Healthy |
| Veeam | Home dashboard | Last 24h: 0 failed jobs |
| DNS | `nslookup vcenter.internal.company.com` | Returns 10.0.1.10 |
| NTP | `chronyc tracking` | Reference: 10.0.1.5, Leap status: Normal |
| Grafana | K8s overview dashboard | CPU < 80%, RAM < 90%, 0 firing alerts |

