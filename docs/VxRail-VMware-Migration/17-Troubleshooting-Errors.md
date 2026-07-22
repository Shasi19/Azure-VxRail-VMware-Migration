# Troubleshooting Guide — Errors at Every Stage

> This document covers every likely error across all migration stages — infrastructure setup, Kubernetes, database migration, application deployment, DNS cutover, Veeam backup, and patching. For each error: symptom, root cause, and step-by-step fix.

---

## Quick Error Index

| Stage | Common Errors | Jump To |
|-------|--------------|---------|
| vSphere / VxRail | vSAN health, VM creation, DRS | [Section 1](#1-vsphere-and-vxrail-errors) |
| Networking / DVS | VLAN, MetalLB, VIP, firewall | [Section 2](#2-networking-errors) |
| Oracle Linux VMs | Boot, cloud-init, SELinux, dnf | [Section 3](#3-oracle-linux-9-vm-errors) |
| Kubernetes | kubeadm, CNI, CSI, node issues | [Section 4](#4-kubernetes-errors) |
| Harbor / Registry | Push fails, cert errors | [Section 5](#5-harbor-registry-errors) |
| PostgreSQL migration | pg_dump, pg_restore, pglogical | [Section 6](#6-postgresql-migration-errors) |
| MongoDB migration | mongodump, replica set, auth | [Section 7](#7-mongodb-migration-errors) |
| Application | Pod crash, image pull, PVC | [Section 8](#8-application-deployment-errors) |
| DNS Cutover | Propagation, stale cache | [Section 9](#9-dns-cutover-errors) |
| Veeam Backup | Snapshot, agent, K10 | [Section 10](#10-veeam-backup-errors) |
| Azure VPN | Tunnel down, routing | [Section 11](#11-azure-vpn-errors) |
| Patching | Kernel, K8s, DB upgrade | [Section 12](#12-patching-errors) |

---

## 1. vSphere and VxRail Errors

### Error 1.1 — vSAN Health Warning: "Disk group degraded"

```
Symptom: vCenter shows vSAN health: WARNING or CRITICAL
         "One or more disk groups are degraded"
         "Component data is being resynced"

Root Cause:
  - A physical disk is slow/failing
  - A node was rebooted and vSAN is resyncing data
  - Network between nodes has high latency (>5ms)

Fix:
  Step 1: Check which node/disk is affected
  vCenter → vSAN → VxRail-Cluster → Monitor → Physical Disks
  Look for disks with status: Error, Absent, or Degraded

  Step 2: If disk is degraded, check disk health
  # SSH to affected ESXi host
  esxcli vsan storage list | grep -A5 "degraded"

  Step 3: Check network latency between nodes
  # From ESXi host to other hosts
  vmkping -I vmk1 <other-host-vmk-ip>
  # Should be <1ms. >5ms = network problem

  Step 4: If resyncing after reboot — wait
  # Normal: vSAN resyncs within 30–60 min after node reboot
  # Monitor progress: vCenter → vSAN → Resyncing Objects

  Step 5: If a disk has actually failed
  # Contact Dell support (VxRail disk replacement is hot-swap)
  # Do NOT proceed with migration until vSAN is healthy

  Prevention: Never run migration when vSAN shows warnings
```

### Error 1.2 — VM Creation Fails: "Insufficient resources"

```
Symptom: govc vm.clone or vCenter UI shows:
         "The resource 'Memory' is not sufficient for the current operation"
         "Insufficient disk space on datastore"

Root Cause:
  - Not enough free RAM on target ESXi host
  - vSAN datastore below 25% free (vSAN will reject writes)
  - DRS cannot place VM due to affinity rules

Fix:
  Step 1: Check current resource usage
  govc host.info -host=vxrail-1.internal.company.com
  # Look at: Memory (used vs total), CPU (used vs total)

  govc datastore.info -ds=vsanDatastore
  # Check: FreeSpace vs Capacity (must be >25%)

  Step 2: Identify which VMs can be powered off (non-prod)
  # Free up RAM if needed — suspend or power off dev VMs

  Step 3: For vSAN space: check for large snapshots
  # Veeam or manual snapshots can consume hidden space
  govc vm.info -vm="*" | grep -i snapshot

  Step 4: If DRS issue — check anti-affinity rules
  # vCenter → Cluster → Configure → VM/Host Rules
  # Temporarily disable conflicting rules for placement
```

### Error 1.3 — VMs Not Appearing in vCenter After Clone

```
Symptom: govc vm.clone returns success but VM not visible in vCenter UI

Root Cause: Folder path mismatch, or vCenter sync delay

Fix:
  Step 1: Check with govc find
  govc find / -type m -name "vm-name"

  Step 2: Search in correct datacenter
  govc ls -l /Datacenter/vm/
  govc ls -l /Datacenter/vm/K8s/

  Step 3: Refresh vCenter inventory
  # Log out and back in to vCenter Web Client
  # OR right-click Datacenter → Synchronize

  Step 4: If truly missing, re-run clone with verbose output
  GOVC_DEBUG=1 govc vm.clone --vm=template-name --name=vm-name 2>&1 | tee /tmp/govc.log
```

---

## 2. Networking Errors

### Error 2.1 — MetalLB LoadBalancer Service Stuck "Pending"

```
Symptom: kubectl get svc shows EXTERNAL-IP as <pending>
         kubectl describe svc harbor-svc shows "No IPs available in address pool"

Root Cause:
  A) MetalLB not installed
  B) IPAddressPool not created or wrong CIDR
  C) DVS Forged Transmits is set to Reject

Fix:
  Step 1: Verify MetalLB is installed
  kubectl get pods -n metallb-system
  # Should show controller + speaker pods Running

  Step 2: Verify IPAddressPool exists
  kubectl get IPAddressPool -n metallb-system
  kubectl get L2Advertisement -n metallb-system

  Step 3: If pool missing, create it
  kubectl apply -f - << 'EOF'
  apiVersion: metallb.io/v1beta1
  kind: IPAddressPool
  metadata:
    name: vxrail-pool
    namespace: metallb-system
  spec:
    addresses:
    - 10.0.4.200-10.0.4.220
  ---
  apiVersion: metallb.io/v1beta1
  kind: L2Advertisement
  metadata:
    name: vxrail-l2
    namespace: metallb-system
  spec:
    ipAddressPools:
    - vxrail-pool
  EOF

  Step 4: If pool exists but IP not assigned — check DVS settings
  # vCenter → Networking → DVS → PG-K8s-Nodes → Edit
  # Security policy → Forged transmits: ACCEPT
  # Security policy → MAC address changes: ACCEPT

  Step 5: Check MetalLB speaker logs
  kubectl logs -n metallb-system -l app=metallb,component=speaker | tail -30
```

### Error 2.2 — keepalived VIP Not Responding

```
Symptom: curl https://10.0.3.100:6443 times out
         kubectl commands fail with "connection refused"

Root Cause:
  A) keepalived not running on all masters
  B) HAProxy not forwarding to healthy master
  C) VRRP packets blocked by firewall

Fix:
  Step 1: Check keepalived status on all 3 masters
  ssh oracle@10.0.3.11 "sudo systemctl status keepalived"
  ssh oracle@10.0.3.12 "sudo systemctl status keepalived"
  ssh oracle@10.0.3.13 "sudo systemctl status keepalived"

  Step 2: Check who holds the VIP
  # Run on each master:
  ip addr show ens192 | grep 10.0.3.100
  # Exactly ONE master should show the VIP

  Step 3: Check HAProxy backends
  ssh oracle@10.0.3.11 "sudo systemctl status haproxy"
  echo "show stat" | sudo socat stdio /var/run/haproxy/admin.sock | cut -d, -f1,2,18

  Step 4: Test HAProxy forwards to kubelet
  curl -k https://10.0.3.11:6443/healthz
  curl -k https://10.0.3.12:6443/healthz
  curl -k https://10.0.3.13:6443/healthz
  # All 3 should return "ok"

  Step 5: Allow VRRP through firewalld
  sudo firewall-cmd --permanent --add-rich-rule='rule protocol value="vrrp" accept'
  sudo firewall-cmd --reload
```

### Error 2.3 — Pod-to-Pod Communication Failing (Calico CNI)

```
Symptom: kubectl exec pod-a -- ping <pod-b-ip> fails
         Services return connection refused from another pod

Root Cause:
  A) Calico not fully initialized
  B) firewalld blocking pod CIDR
  C) VXLAN packets blocked by DVS

Fix:
  Step 1: Check Calico pods
  kubectl get pods -n calico-system
  kubectl get pods -n kube-system | grep calico
  # All should be Running

  Step 2: Check Calico node status
  kubectl calico-node -bird-live
  # OR:
  kubectl exec -n calico-system <calico-node-pod> -- calico-node -bird-live

  Step 3: Add pod CIDR to firewalld trusted zone on all nodes
  sudo firewall-cmd --permanent --zone=trusted \
    --add-source=192.168.0.0/16    # pod CIDR
  sudo firewall-cmd --permanent --zone=trusted \
    --add-source=10.96.0.0/12     # service CIDR
  sudo firewall-cmd --reload

  Step 4: Allow VXLAN on DVS
  # vCenter → Networking → DVS → PG-K8s-Nodes → Edit
  # Forged transmits: Accept (required for VXLAN encapsulation)
```

---

## 3. Oracle Linux 9 VM Errors

### Error 3.1 — cloud-init Not Running on Cloned VM

```
Symptom: VM boots with old hostname/IP from template
         cloud-init log shows "no instance ID change detected"

Root Cause: Machine ID not cleared before cloning

Fix:
  # On the TEMPLATE before cloning:
  sudo cloud-init clean --logs
  sudo truncate -s 0 /etc/machine-id
  sudo rm -f /var/lib/dbus/machine-id
  sudo ln -s /etc/machine-id /var/lib/dbus/machine-id
  sudo shutdown -h now
  # Then mark as template: govc vm.markastemplate ol9-base-template

  # On an already-cloned stuck VM:
  sudo systemctl start cloud-init-local
  sudo systemctl start cloud-init
  sudo cloud-init status --wait
```

### Error 3.2 — SELinux Blocking containerd

```
Symptom: containerd won't start after install
         journalctl -u containerd shows: "AVC denied" messages

Root Cause: SELinux enforcing mode blocks containerd syscalls

Fix:
  Step 1: Check SELinux status
  getenforce    # "Enforcing" = SELinux active

  Step 2: For K8s nodes — set to permissive (during install)
  sudo setenforce 0
  sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

  Step 3: Restart containerd
  sudo systemctl restart containerd
  sudo systemctl status containerd   # Should be active

  Step 4: Generate and apply custom policy (if you want to keep Enforcing)
  # Watch for AVC denials:
  sudo ausearch -c 'containerd' --raw | audit2allow -M my-containerd
  sudo semodule -X 300 -i my-containerd.pp
```

### Error 3.3 — dnf install fails: GPG Key Error

```
Symptom: dnf install kubelet shows:
         "The GPG keys listed for the 'kubernetes' repository are already installed
          but they are not correct for this package"

Root Cause: GPG key file missing or corrupt

Fix:
  # Re-import the GPG key
  sudo rpm --import \
    https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key

  # Verify key imported
  rpm -q gpg-pubkey --qf '%{name}-%{version}-%{release}\n' | grep -i kube

  # If still failing, temporarily skip GPG check (once only):
  sudo dnf install -y --nogpgcheck kubelet-1.29.0 kubeadm-1.29.0 kubectl-1.29.0
```

### Error 3.4 — Static IP Lost After Reboot

```
Symptom: VM has correct IP after cloud-init but reverts to DHCP on reboot

Root Cause: NetworkManager on OL9 has a separate connection profile
            that overrides cloud-init network config

Fix:
  # Check existing NM connections
  nmcli con show

  # Find connection for ens192 and make it static
  nmcli con mod "ens192" ipv4.method manual
  nmcli con mod "ens192" ipv4.addresses "10.0.3.11/24"
  nmcli con mod "ens192" ipv4.gateway "10.0.3.1"
  nmcli con mod "ens192" ipv4.dns "10.0.1.5"
  nmcli con mod "ens192" connection.autoconnect yes

  nmcli con down ens192 && nmcli con up ens192
  # Verify
  ip addr show ens192
```

---

## 4. Kubernetes Errors

### Error 4.1 — kubeadm init Fails: "Port 6443 already in use"

```
Symptom: kubeadm init errors: "[preflight] Some fatal errors occurred:
         [ERROR Port-6443]: Port 6443 is in use"

Root Cause: Previous failed kubeadm init left partial state

Fix:
  # Reset and retry
  sudo kubeadm reset -f
  sudo rm -rf /etc/kubernetes/ /var/lib/etcd/ /var/lib/kubelet/

  # Verify port is free
  sudo ss -tlnp | grep 6443

  # Retry init
  sudo kubeadm init --config /etc/kubernetes/kubeadm-config.yaml
```

### Error 4.2 — Worker Node Fails to Join: "token has expired"

```
Symptom: kubeadm join fails: "error: couldn't validate the identity of the API Server:
         tls: failed to verify certificate"
         OR: "DEBU token is expired"

Root Cause: Bootstrap token expires after 24 hours

Fix:
  # On master-1: create a new join token
  sudo kubeadm token create --print-join-command
  # This prints a fresh kubeadm join command with a new 24h token

  # Run the printed command on the worker node
```

### Error 4.3 — Node Stuck in "NotReady"

```
Symptom: kubectl get nodes shows worker node as NotReady

Root Cause:
  A) kubelet not running
  B) CNI not initialized
  C) /etc/resolv.conf pointing to wrong DNS

Fix:
  Step 1: Check kubelet on the node
  ssh oracle@<node-ip> "sudo systemctl status kubelet"
  ssh oracle@<node-ip> "sudo journalctl -u kubelet -n 50"

  Step 2: Common kubelet failures
  # "failed to run Kubelet: no container runtime": containerd not running
  sudo systemctl start containerd
  sudo systemctl restart kubelet

  # "network plugin not initialized": CNI not deployed yet
  # On master: kubectl apply -f calico.yaml (run Calico install)

  Step 3: Check DNS config
  cat /etc/resolv.conf    # Should point to 10.0.1.5 (your DNS)
  # If pointing to 127.0.0.1 or wrong IP:
  sudo nmcli con mod ens192 ipv4.dns "10.0.1.5"
  sudo nmcli con up ens192
```

### Error 4.4 — PVC Stuck in "Pending": vSphere CSI

```
Symptom: kubectl get pvc shows STATUS: Pending
         kubectl describe pvc shows: "waiting for first consumer"
         OR: "failed to provision volume"

Root Cause:
  A) disk.EnableUUID not set on VM (CSI requirement)
  B) vSphere credentials secret missing in kube-system
  C) StorageClass references wrong vSAN policy

Fix:
  Step 1: Check disk.EnableUUID on ALL K8s VMs
  # From jump host:
  for VM in k8s-master-1 k8s-master-2 k8s-master-3 k8s-worker-1 k8s-worker-2; do
    echo -n "$VM: "
    govc vm.info "$VM" | grep -i "uuid"
  done
  # If not set:
  govc vm.change -vm="$VM" -e "disk.EnableUUID=TRUE"
  # Note: VM must be powered off to change this setting

  Step 2: Verify CSI driver running
  kubectl get pods -n vmware-system-csi
  kubectl describe pod <vsphere-csi-controller-pod> -n vmware-system-csi

  Step 3: Check vSphere CSI secret
  kubectl get secret vsphere-config-secret -n vmware-system-csi -o yaml

  Step 4: Check StorageClass policy name matches vSAN
  kubectl describe storageclass vsan-dev-qa
  # "storagePolicyName" must match an actual vSAN policy in vCenter
  # vCenter → Policies and Profiles → VM Storage Policies
```

### Error 4.5 — etcd Cluster Unhealthy

```
Symptom: kubectl get cs shows etcd as Unhealthy
         API server slow/unresponsive
         "etcdserver: request timed out"

Root Cause:
  A) etcd data disk is full
  B) etcd leader election taking too long (network latency between masters)
  C) One master node powered off

Fix:
  Step 1: Check etcd health
  sudo ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    endpoint health --cluster

  Step 2: Check disk on etcd nodes
  df -h /var/lib/etcd   # Must not be >80% full

  Step 3: Compact etcd if disk full
  REV=$(sudo ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    endpoint status -w json | jq '.[0].Status.header.revision')
  sudo ETCDCTL_API=3 etcdctl compact $REV [same certs]
  sudo ETCDCTL_API=3 etcdctl defrag [same certs]

  Step 4: If a master is down
  # Bring master back up → etcd auto-rejoin
  # If master is permanently lost: remove from cluster and re-add
  sudo kubeadm join phase control-plane-join etcd \
    --config=/etc/kubernetes/kubeadm-config.yaml
```

---

## 5. Harbor Registry Errors

### Error 5.1 — Docker Push Fails: "x509 certificate signed by unknown authority"

```
Symptom: docker push harbor.internal.company.com/library/myapp:v1
         Error: "x509: certificate signed by unknown authority"

Root Cause: Docker daemon doesn't trust your internal CA

Fix:
  # Install internal CA cert on each node that pushes/pulls images
  # Get the CA cert from your step-ca or Harbor UI

  # On each K8s node and jump host:
  sudo mkdir -p /etc/docker/certs.d/harbor.internal.company.com
  sudo cp /etc/step/certs/root_ca.crt \
    /etc/docker/certs.d/harbor.internal.company.com/ca.crt

  # For containerd on K8s nodes:
  sudo mkdir -p /etc/containerd/certs.d/harbor.internal.company.com
  cat > /etc/containerd/certs.d/harbor.internal.company.com/hosts.toml << 'EOF'
  server = "https://harbor.internal.company.com"
  [host."https://harbor.internal.company.com"]
    ca = "/etc/step/certs/root_ca.crt"
  EOF
  sudo systemctl restart containerd
```

### Error 5.2 — Harbor UI Not Accessible

```
Symptom: https://harbor.internal.company.com returns connection refused or 502

Fix:
  Step 1: Check Harbor pods
  kubectl get pods -n harbor
  # All pods should be Running

  Step 2: Check Harbor core logs
  kubectl logs -n harbor -l component=core | tail -30

  Step 3: Check MetalLB IP assigned
  kubectl get svc -n harbor harbor
  # EXTERNAL-IP should show an IP from MetalLB pool

  Step 4: Check DNS resolves Harbor
  dig harbor.internal.company.com @10.0.1.5
  # Should return MetalLB IP
```

---

## 6. PostgreSQL Migration Errors

### Error 6.1 — pg_dump Fails: "SSL connection required"

```
Symptom: pg_dump from Azure fails:
         "FATAL: SSL connection required"

Root Cause: Azure PostgreSQL enforces SSL by default

Fix:
  pg_dump \
    --host=your-dev-pg.postgres.database.azure.com \
    --port=5432 \
    --username=pgadmin@your-dev-pg \
    --dbname=dev_db \
    --format=custom \
    --compress=9 \
    --file=/tmp/dev_db.dump \
    "sslmode=require"    # <-- add this

  # OR set env variable:
  export PGSSLMODE=require
```

### Error 6.2 — pg_restore Fails: "role does not exist"

```
Symptom: pg_restore shows:
         "ERROR: role 'azure_pg_admin' does not exist"

Root Cause: Azure creates default roles that don't exist on-prem

Fix:
  # Use --no-owner and --role to reassign all objects:
  pg_restore \
    --host=10.0.5.11 \
    --port=5432 \
    --username=dev_user \
    --dbname=dev_db \
    --format=custom \
    --no-owner \            # <-- skip ownership assignments
    --no-privileges \       # <-- skip GRANT/REVOKE
    --role=dev_user \       # <-- assign all objects to this role
    /tmp/dev_db.dump

  # Then manually grant permissions
  sudo -u postgres /usr/pgsql-15/bin/psql dev_db << 'SQL'
  GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO dev_user;
  GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO dev_user;
  GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO dev_user;
  SQL
```

### Error 6.3 — pglogical Replication Lag Too High (Prod)

```
Symptom: pglogical subscriber lag growing during live replication
         SELECT lag FROM pg_stat_replication shows lag > 1GB

Root Cause:
  A) Network bandwidth between Azure and on-prem saturated
  B) On-prem PostgreSQL cannot keep up with write rate
  C) Large transaction (bulk INSERT) creating lag spike

Fix:
  Step 1: Monitor replication lag
  # On Azure (publisher):
  psql -h <azure-pg> -c "SELECT application_name, pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes FROM pg_stat_replication;"

  Step 2: Check VPN bandwidth utilization
  # On jump host:
  iftop -i <vpn-interface>    # Look for saturation

  Step 3: If network is bottleneck — schedule migration during low-traffic window
  # Lag should recover once traffic drops

  Step 4: If on-prem PG is slow — check vacuum / autovacuum blocking
  psql -h 10.0.5.15 -U postgres -c "SELECT pid, query_start, state, query FROM pg_stat_activity WHERE wait_event_type IS NOT NULL;"

  Step 5: If lag > 10GB — restart pglogical subscription and let it catch up
  psql -h 10.0.5.15 -U postgres -c "SELECT pglogical.alter_subscription_disable('azure_to_onprem');"
  psql -h 10.0.5.15 -U postgres -c "SELECT pglogical.alter_subscription_enable('azure_to_onprem');"
```

---

## 7. MongoDB Migration Errors

### Error 7.1 — mongorestore Fails: "authorization failure"

```
Symptom: mongorestore fails with:
         "Failed: error: (Unauthorized) not authorized on admin to execute command"

Root Cause: MongoDB user lacks restore permissions

Fix:
  # Connect as admin and add the role
  mongosh --host 10.0.5.21 -u admin -p 'MongoAdmin2026!' --authenticationDatabase admin << 'JS'
  use admin
  db.grantRolesToUser("dev_user", [
    { role: "restore", db: "admin" },
    { role: "readWriteAnyDatabase", db: "admin" }
  ])
  JS

  # Then retry mongorestore
  mongorestore \
    --host=10.0.5.21:27017 \
    --username=admin \
    --password='MongoAdmin2026!' \
    --authenticationDatabase=admin \
    --db=dev-cosmos \
    /tmp/cosmos-dev-dump/dev-cosmos/
```

### Error 7.2 — Replica Set Won't Initialize

```
Symptom: rs.initiate() returns:
         "MongoServerError: already initialized"
         OR: "MongoServerError: Quorum check failed"

Root Cause:
  A) Already initialized with different config
  B) Network connectivity between RS members blocked

Fix:
  Step 1: Check current RS config
  mongosh --quiet --eval "rs.status()"

  Step 2: If initialized with wrong members — force reconfig
  mongosh --quiet << 'JS'
  cfg = rs.conf()
  cfg.members = [
    {_id: 0, host: "10.0.5.25:27017"},
    {_id: 1, host: "10.0.5.26:27017"},
    {_id: 2, host: "10.0.5.27:27017"}
  ]
  rs.reconfig(cfg, {force: true})
  JS

  Step 3: Check port 27017 connectivity between all RS members
  # From mongo-prod-01:
  nc -zv 10.0.5.26 27017
  nc -zv 10.0.5.27 27017

  Step 4: Add firewall rules if blocked
  sudo firewall-cmd --permanent --add-port=27017/tcp
  sudo firewall-cmd --reload
```

---

## 8. Application Deployment Errors

### Error 8.1 — Pod in CrashLoopBackOff

```
Symptom: kubectl get pods shows STATUS: CrashLoopBackOff

Fix:
  Step 1: Get pod logs
  kubectl logs <pod-name> -n <namespace>
  kubectl logs <pod-name> -n <namespace> --previous   # previous run logs

  Step 2: Common causes and fixes
  
  A) "connection refused to database"
     → DB VM not running: check ssh oracle@10.0.5.11 "systemctl status postgresql-15"
     → Wrong DB hostname in ConfigMap: kubectl describe configmap app-config -n dev
     → pg_hba.conf doesn't allow pod CIDR: add "10.0.4.0/24" to pg_hba.conf

  B) "could not connect to Harbor / image pull error"
     → Fix: see Section 5 (Harbor errors)

  C) "OOMKilled" — pod killed for memory
     → Increase memory limits in Deployment:
     kubectl patch deploy myapp -n dev \
       -p '{"spec":{"template":{"spec":{"containers":[{"name":"myapp","resources":{"limits":{"memory":"1Gi"}}}]}}}}'

  D) Application error in logs
     → Fix application config; update ConfigMap; rolling restart pods:
     kubectl rollout restart deployment/myapp -n dev
```

### Error 8.2 — Image Pull Error: "ImagePullBackOff"

```
Symptom: kubectl get pods shows STATUS: ImagePullBackOff
         kubectl describe pod shows:
         "Failed to pull image: unauthorized: authentication required"

Root Cause: K8s nodes don't have Harbor credentials

Fix:
  Step 1: Create Harbor pull secret in namespace
  kubectl create secret docker-registry harbor-pull-secret \
    --docker-server=harbor.internal.company.com \
    --docker-username=robot_deploy \
    --docker-password='<robot-token>' \
    -n dev

  Step 2: Add to namespace service account (so all pods use it)
  kubectl patch serviceaccount default -n dev \
    -p '{"imagePullSecrets": [{"name": "harbor-pull-secret"}]}'

  Step 3: Or reference in Deployment spec:
  spec:
    imagePullSecrets:
    - name: harbor-pull-secret
```

---

## 9. DNS Cutover Errors

### Error 9.1 — DNS Not Propagating After Cutover

```
Symptom: Some clients still reaching Azure after DNS change
         dig app.company.com returns old Azure IP

Root Cause: DNS TTL was set too high before cutover

Fix:
  Step 1: Check current TTL (should have been lowered to 60s before cutover)
  dig app.company.com | grep -i ttl

  Step 2: If TTL is high — force flush DNS cache on affected clients
  # Linux:
  sudo systemctl restart systemd-resolved
  # macOS:
  sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
  # Windows:
  ipconfig /flushdns

  Step 3: Check your BIND9 zone file was updated correctly
  # On DNS VM (10.0.1.5):
  named-checkzone internal.company.com /etc/named/zones/db.internal.company.com
  sudo systemctl reload named
  # Verify:
  dig @10.0.1.5 app.company.com    # Should return on-prem IP
```

### Error 9.2 — Application Returns 502 After DNS Cutover

```
Symptom: DNS correctly points to on-prem MetalLB IP
         But app returns HTTP 502 Bad Gateway

Root Cause:
  A) Ingress controller pod not running
  B) Application pod not running or unhealthy
  C) TLS certificate mismatch

Fix:
  Step 1: Check Ingress controller
  kubectl get pods -n ingress-nginx
  kubectl get svc -n ingress-nginx ingress-nginx-controller

  Step 2: Check application pods
  kubectl get pods -n prod
  kubectl describe ingress myapp-ingress -n prod

  Step 3: Test without DNS (direct IP)
  curl -k -H "Host: app.company.com" https://<MetalLB-IP>/healthz

  Step 4: Check TLS cert
  echo | openssl s_client -servername app.company.com \
    -connect <MetalLB-IP>:443 2>/dev/null | openssl x509 -noout -dates
  # Verify cert is valid and CN matches
```

---

## 10. Veeam Backup Errors

### Error 10.1 — Veeam Job Fails: "Snapshot consolidation required"

```
Symptom: Veeam backup job fails with:
         "VM requires consolidation. Cannot create snapshot."

Root Cause: Previous backup left orphaned snapshot delta files

Fix:
  Step 1: Identify VMs needing consolidation
  # vCenter → VM → Monitor → Tasks and Events → look for "Needs Consolidation"
  # OR via PowerCLI (on vxrail-vbr-01):
  Get-VM | Where-Object {$_.Extensiondata.Runtime.ConsolidationNeeded}

  Step 2: Consolidate via vCenter
  # Right-click VM → Snapshots → Consolidate
  # OR via govc:
  govc vm.consolidate <vm-name>

  Step 3: Retry Veeam backup job after consolidation
```

### Error 10.2 — Veeam Agent Cannot Connect to VBR Server

```
Symptom: veeamconfig vbrserver list shows disconnected
         Veeam agent backup jobs fail

Root Cause: Firewall blocking port 10006 between OL9 VM and Veeam server

Fix:
  # On OL9 VM (Oracle Linux):
  sudo firewall-cmd --permanent --add-port=10006/tcp
  sudo firewall-cmd --permanent --add-port=10002/tcp
  sudo firewall-cmd --reload

  # On Windows (Veeam VBR server — via PowerShell):
  New-NetFirewallRule -DisplayName "Veeam Agent" -Direction Inbound -Protocol TCP -LocalPort 10006 -Action Allow

  # Test connectivity from OL9 VM:
  nc -zv 10.0.1.40 10006   # Should succeed
```

---

## 11. Azure VPN Errors

### Error 11.1 — VPN Tunnel Not Establishing

```
Symptom: strongSwan shows tunnel down
         pg_dump from Azure times out
         No connectivity to Azure private IPs

Root Cause:
  A) PSK mismatch between Azure VPN Gateway and strongSwan
  B) Firewall blocking UDP 500/4500 (IKE traffic)
  C) Azure VPN Gateway not yet provisioned

Fix:
  Step 1: Check strongSwan status
  sudo ipsec status         # Shows tunnel status
  sudo ipsec statusall      # Detailed with SA info

  Step 2: Check IKE negotiation logs
  sudo journalctl -u strongswan -f | grep -E "IKE|connecting|ERROR"

  Step 3: Verify PSK matches Azure
  # Azure Portal → VPN Gateway → Connections → Shared Key
  # Must exactly match /etc/ipsec.secrets on jump host

  Step 4: Allow IKE through firewalld
  sudo firewall-cmd --permanent --add-service=ipsec
  sudo firewall-cmd --permanent --add-port=500/udp
  sudo firewall-cmd --permanent --add-port=4500/udp
  sudo firewall-cmd --reload

  Step 5: Restart tunnel
  sudo ipsec restart
  sudo ipsec up azure-vpn
```

---

## 12. Patching Errors

### Error 12.1 — K8s Node Fails to Drain: "cannot evict pod"

```
Symptom: kubectl drain node fails:
         "error when evicting pods: Cannot evict pod as it would violate
          the pod's disruption budget"

Root Cause: PodDisruptionBudget prevents eviction (protects HA apps)

Fix:
  Option A: Wait for healthy pod to come up on another node, then retry drain
  kubectl get pdb -A    # Check disruption budgets

  Option B: Delete PDB temporarily (if you own the app)
  kubectl delete pdb myapp-pdb -n prod
  kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
  kubectl apply -f myapp-pdb.yaml   # Restore PDB after drain

  Option C: Force eviction (use with caution — may cause brief downtime)
  kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --force --disable-eviction
```

### Error 12.2 — kubeadm upgrade fails: "etcd cluster is not healthy"

```
Symptom: kubeadm upgrade apply v1.29.4 fails:
         "[upgrade/config] FATAL: etcd cluster is not healthy"

Root Cause: One etcd member is behind or unreachable

Fix:
  Step 1: Check etcd health before upgrade
  sudo ETCDCTL_API=3 etcdctl \
    --endpoints=https://10.0.3.11:2379,https://10.0.3.12:2379,https://10.0.3.13:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    endpoint health

  Step 2: If one member is unhealthy — check etcd on that master
  ssh oracle@10.0.3.12 "sudo systemctl status etcd"
  ssh oracle@10.0.3.12 "sudo journalctl -u etcd -n 30"

  Step 3: Fix etcd member, wait for it to sync, then retry upgrade
```

---

## Error Response Priority Matrix

```
SEVERITY LEVELS AND RESPONSE TIMES
────────────────────────────────────────────────────────────────────

P1 — CRITICAL (RTO: 30 minutes)
  Examples: Production completely down, data loss risk, vSAN critical
  Actions:
    1. Alert on-call engineer immediately
    2. Open war room (Teams/Slack bridge)
    3. Invoke Veeam Instant VM Recovery if VM is corrupted
    4. Rollback DNS if cutover-related

P2 — HIGH (RTO: 2 hours)
  Examples: One environment down (non-prod), replication lag >10GB,
            MetalLB not assigning IPs, Harbor unavailable
  Actions:
    1. Alert team via Teams channel
    2. Follow fix procedure from this guide
    3. Escalate to P1 if not resolved in 1 hour

P3 — MEDIUM (RTO: 4 hours / next business day)
  Examples: Single pod crashing (HA still serving), monitoring gap,
            Veeam job failure, DNS propagation slow
  Actions:
    1. Ticket in ITSM system
    2. Fix during business hours

P4 — LOW (Next sprint)
  Examples: Performance optimization, non-critical alert,
            documentation gap, minor config drift
  Actions:
    1. Log in backlog
    2. Fix in next maintenance window
```
