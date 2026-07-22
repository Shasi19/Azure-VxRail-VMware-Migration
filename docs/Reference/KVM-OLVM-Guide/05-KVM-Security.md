# 05 — KVM Security

> Covers sVirt, SELinux, AppArmor, VM isolation, TLS for libvirt, firewall, audit logging, and secrets management.

---

## KVM Security Model

```
┌────────────────────────────────────────────────────────────────────┐
│ HARDWARE                                                            │
│  CPU rings: Ring 0 (kernel), Ring 3 (userspace), Ring -1 (hypervisor) │
│  Intel VT-x / AMD-V → VMs cannot access host memory               │
└─────────────────────────┬──────────────────────────────────────────┘
                          │
┌─────────────────────────▼──────────────────────────────────────────┐
│ LINUX KERNEL + KVM MODULE                                           │
│  KVM isolates each VM's memory (EPT/NPT page tables)               │
│  /dev/kvm — only libvirt/QEMU process has access                   │
└─────────────────────────┬──────────────────────────────────────────┘
                          │
┌─────────────────────────▼──────────────────────────────────────────┐
│ QEMU PROCESS (one per VM)                                           │
│  sVirt: each QEMU process labelled with unique SELinux MCS label   │
│  seccomp: system call filter reduces QEMU attack surface           │
│  AppArmor: confines QEMU to only required files/capabilities       │
└─────────────────────────┬──────────────────────────────────────────┘
                          │
┌─────────────────────────▼──────────────────────────────────────────┐
│ GUEST VM                                                            │
│  Isolated memory, isolated I/O, virtual NIC, virtual disk          │
│  Cannot access host kernel or other VMs' memory                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## 1. sVirt — SELinux + Virtualisation Security

sVirt automatically assigns each VM its own **unique SELinux Multi-Category Security (MCS)** label. Even if a QEMU process is compromised, it cannot access another VM's disk files.

```bash
# Check sVirt labels on running QEMU processes
ps -eZ | grep qemu
# Example output:
# system_u:system_r:svirt_t:s0:c123,c456  qemu-system-x86_64

# Each VM gets a unique c-pair (e.g., c123,c456 vs c789,c012)
# This prevents VM-A's QEMU from reading VM-B's disk

# Verify disk image has the matching label
ls -Z /data/kvm/images/
# system_u:object_r:svirt_image_t:s0:c123,c456  k8s-cp-01.qcow2
# system_u:object_r:svirt_image_t:s0:c789,c012  k8s-wk-01.qcow2

# If label is wrong (e.g., after manual copy):
restorecon -v /data/kvm/images/k8s-cp-01.qcow2

# Check active SELinux booleans for virtualisation
getsebool -a | grep virt
# Most important:
# virt_use_nfs --> on      (VMs can access NFS storage)
# virt_use_execmem --> on  (needed by some QEMU JIT)

# Enable required booleans
setsebool -P virt_use_nfs 1
setsebool -P virt_use_samba 0          # Disable if not needed
setsebool -P virt_use_rawip 0

# Check SELinux denials related to libvirt
ausearch -m AVC -ts recent | grep qemu | tail -20

# Generate policy for a denial (if you need to allow something)
ausearch -m AVC -ts recent | grep qemu | audit2allow -M my-qemu-policy
semodule -i my-qemu-policy.pp
```

---

## 2. AppArmor (Ubuntu / Debian)

```bash
# Check AppArmor status for libvirt
aa-status | grep -E '(qemu|libvirt)'

# Profiles involved:
# /usr/sbin/libvirtd          — main libvirt daemon
# /etc/apparmor.d/usr.sbin.libvirtd
# /etc/apparmor.d/abstractions/libvirt-qemu  — per-VM profile

# If QEMU can't access a custom image directory:
# Add the path to the abstraction file
cat >> /etc/apparmor.d/abstractions/libvirt-qemu << 'EOF'
  /data/kvm/images/** rwk,
  /mnt/nfs-kvm/** rwk,
EOF

systemctl reload apparmor
# Or for a specific profile:
apparmor_parser -r /etc/apparmor.d/usr.sbin.libvirtd

# Check if AppArmor is blocking libvirt
journalctl -u apparmor | grep -i denied
dmesg | grep -i apparmor | tail -20
```

---

## 3. QEMU Security Hardening

```bash
# Verify QEMU runs as qemu user (not root)
cat /etc/libvirt/qemu.conf | grep -E '(user|group)'
# Should show:
# user = "qemu"
# group = "qemu"

# Enable seccomp sandbox (restricts system calls QEMU can make)
cat /etc/libvirt/qemu.conf | grep seccomp
# seccomp_sandbox = 1  (default on modern libvirt)

# Disable QEMU as root (edit /etc/libvirt/qemu.conf)
sed -i 's/#user = "root"/user = "qemu"/' /etc/libvirt/qemu.conf
sed -i 's/#group = "root"/group = "qemu"/' /etc/libvirt/qemu.conf

# Restart libvirt to apply
systemctl restart libvirtd

# Verify processes are not running as root
ps aux | grep qemu | grep -v grep | awk '{print $1}'
# Should show: qemu (not root)

# Disable KVM fallback (prevent unaccelerated VMs — security + performance)
cat >> /etc/libvirt/qemu.conf << 'EOF'
# Do not allow VMs to run without hardware acceleration
kvm_device = "/dev/kvm"
EOF
```

---

## 4. TLS for libvirt Remote Access

For remote management (virsh -c qemu+tls://host/system), use TLS certificates.

```bash
# --- Generate CA ---
mkdir -p /etc/pki/libvirt-ca
cd /etc/pki/libvirt-ca

# Generate CA key and cert
certtool --generate-privkey --bits=4096 --outfile ca-key.pem
cat > ca.info << 'EOF'
cn = "KVM CA"
ca
cert_signing_key
expiration_days = 3650
EOF
certtool --generate-self-signed --load-privkey ca-key.pem \
  --template ca.info --outfile ca-cert.pem

# --- Generate Server Cert (for each KVM host) ---
certtool --generate-privkey --bits=4096 --outfile server-key.pem
cat > server.info << 'EOF'
cn = "kvm-host-01.internal"
tls_www_server
encryption_key
signing_key
expiration_days = 365
EOF
certtool --generate-certificate \
  --load-privkey server-key.pem \
  --load-ca-certificate ca-cert.pem \
  --load-ca-privkey ca-key.pem \
  --template server.info \
  --outfile server-cert.pem

# --- Install certs on KVM host ---
mkdir -p /etc/pki/libvirt/private

cp ca-cert.pem /etc/pki/CA/cacert.pem
cp server-cert.pem /etc/pki/libvirt/servercert.pem
cp server-key.pem /etc/pki/libvirt/private/serverkey.pem

chmod 600 /etc/pki/libvirt/private/serverkey.pem
chown root:root /etc/pki/CA/cacert.pem

# Enable TLS in libvirtd.conf
sed -i 's/#listen_tls = 0/listen_tls = 1/' /etc/libvirt/libvirtd.conf
sed -i 's/#listen_tcp = 1/listen_tcp = 0/' /etc/libvirt/libvirtd.conf
systemctl restart libvirtd

# --- Generate Client Cert (for admin workstation) ---
certtool --generate-privkey --bits=4096 --outfile client-key.pem
cat > client.info << 'EOF'
cn = "admin-workstation"
tls_www_client
encryption_key
signing_key
expiration_days = 365
EOF
certtool --generate-certificate \
  --load-privkey client-key.pem \
  --load-ca-certificate ca-cert.pem \
  --load-ca-privkey ca-key.pem \
  --template client.info \
  --outfile client-cert.pem

# Install client certs
mkdir -p ~/.pki/libvirt/private
cp ca-cert.pem ~/.pki/libvirt/cacert.pem
cp client-cert.pem ~/.pki/libvirt/clientcert.pem
cp client-key.pem ~/.pki/libvirt/private/clientkey.pem

# Test TLS connection
virsh -c qemu+tls://kvm-host-01.internal/system list --all
```

---

## 5. VM Network Isolation

```bash
# Block direct VM-to-VM traffic on same host
# (VMs should communicate through the application layer, not directly)

# Using nftables — block traffic between VM tap interfaces
nft add rule inet filter forward \
  iifname "vnet*" oifname "vnet*" drop

# Allow only specific inter-VM traffic (e.g., only K8s pod CIDR)
nft add rule inet filter forward \
  iifname "vnet*" oifname "vnet*" \
  ip daddr 10.244.0.0/16 accept

# Create VLAN-isolated networks in libvirt for environment separation
# Dev VMs on VLAN 100, QA on VLAN 200, Prod on VLAN 300
# (See 03-KVM-Networking.md for VLAN setup)
```

---

## 6. Audit Logging

```bash
# Enable audit logging in libvirt
cat >> /etc/libvirt/libvirtd.conf << 'EOF'
audit_level = 2
# 0 = disabled, 1 = enabled (default), 2 = required (fail if auditd unavailable)
EOF

systemctl restart libvirtd

# Check libvirt audit events
ausearch -m VIRT_CONTROL | tail -20
# Records: who started/stopped a VM, who defined/undefined a domain

ausearch -m VIRT_MACHINE_ID | tail -10
# Records: unique sVirt label assignment

ausearch -m VIRT_RESOURCE | tail -10
# Records: disk/network resource access

# Forward audit logs to ELK (via auditd + Filebeat)
cat >> /etc/audit/auditd.conf << 'EOF'
log_format = ENRICHED
EOF

# Useful audit rules for KVM hosts
cat >> /etc/audit/rules.d/kvm-audit.rules << 'EOF'
# Monitor libvirt config changes
-w /etc/libvirt/ -p wa -k libvirt-config
# Monitor VM image directory
-w /data/kvm/images/ -p rwxa -k vm-images
# Monitor virsh binary usage
-w /usr/bin/virsh -p x -k virsh-exec
EOF

augenrules --load
```

---

## 7. Secrets Management for VMs

```bash
# libvirt secret objects (for Ceph auth keys, iSCSI CHAP passwords)
# Define a secret
cat > /tmp/ceph-secret.xml << 'EOF'
<secret ephemeral='no' private='yes'>
  <usage type='ceph'>
    <name>client.libvirt secret</name>
  </usage>
</secret>
EOF

virsh secret-define /tmp/ceph-secret.xml
# Returns: Secret <uuid> created

# Set the secret value
virsh secret-set-value <uuid> base64-encoded-ceph-key

# Reference in VM XML:
# <auth username='libvirt'>
#   <secret type='ceph' uuid='<uuid>'/>
# </auth>

# For application secrets: use HashiCorp Vault
# VMs can retrieve secrets at boot via cloud-init or init scripts:
# MONGO_PWD=$(vault kv get -field=password secret/prod/mongodb)
```

---

## 8. Security Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| VM disk access denied | SELinux wrong fcontext | `restorecon -Rv /data/kvm/images` |
| QEMU process killed by seccomp | QEMU feature needs blocked syscall | Disable seccomp (temporary debug): `qemu.conf: seccomp_sandbox = 0` |
| AppArmor blocking image access | Profile doesn't include path | Add path to `/etc/apparmor.d/abstractions/libvirt-qemu` |
| `virsh` TLS connection refused | TLS cert mismatch | Verify CN in cert matches hostname; check `/etc/pki/CA/cacert.pem` |
| AVC denial for virt_use_nfs | Boolean not set | `setsebool -P virt_use_nfs 1` |
| QEMU running as root | qemu.conf not updated | Set `user = "qemu"` in `/etc/libvirt/qemu.conf` |
| Audit log not recording VM events | auditd not running | `systemctl enable --now auditd` |
| VM can access host filesystem | Missing seccomp/SELinux | Check sVirt labels; ensure SELinux is Enforcing |
| libvirt secret not found | Wrong UUID referenced | `virsh secret-list`; verify UUID in VM XML |

---

*Next: [06-KVM-Best-Practices.md](06-KVM-Best-Practices.md)*
