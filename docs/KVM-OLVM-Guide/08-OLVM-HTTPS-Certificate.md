# 08 — OLVM HTTPS Certificate

> Replace the default self-signed certificate in OLVM with a CA-signed certificate. Covers: internal CA, Let's Encrypt (if engine is internet-accessible), certificate renewal, and troubleshooting.

---

## Why Replace the Default Certificate?

OLVM ships with a self-signed certificate. Browsers show "Not Secure" warnings. Most enterprise security policies require:
- Certificates signed by a trusted internal CA (recommended for internal-only engines)
- Or publicly trusted certificate (Let's Encrypt, DigiCert, etc.)

```
Default state: Self-signed cert at /etc/pki/ovirt-engine/
Goal state:    CA-signed cert (internal CA or public CA)
```

---

## Part A: Using an Internal CA (Recommended for Internal Deployments)

### Step A1: Generate Internal CA

```bash
# On a dedicated CA server or on the OLVM engine itself
# Install certificate tools
dnf install -y gnutls-utils openssl

mkdir -p /etc/pki/internal-ca/{certs,private,crl}
chmod 700 /etc/pki/internal-ca/private

# Generate CA private key (4096-bit RSA)
openssl genrsa -aes256 \
  -passout pass:CAPassphrase2026! \
  -out /etc/pki/internal-ca/private/ca.key 4096

chmod 400 /etc/pki/internal-ca/private/ca.key

# Generate CA self-signed certificate (10-year validity)
openssl req -new -x509 \
  -days 3650 \
  -key /etc/pki/internal-ca/private/ca.key \
  -passin pass:CAPassphrase2026! \
  -out /etc/pki/internal-ca/certs/ca.crt \
  -subj "/C=US/ST=State/L=City/O=Company/OU=IT/CN=Internal CA 2026"

# Verify CA certificate
openssl x509 -noout -text -in /etc/pki/internal-ca/certs/ca.crt | \
  grep -E '(Subject:|Validity|Not Before|Not After)'
```

### Step A2: Generate OLVM Engine Certificate

```bash
# Generate private key for OLVM
openssl genrsa -out /tmp/olvm-engine.key 4096

# Generate CSR (Certificate Signing Request)
openssl req -new \
  -key /tmp/olvm-engine.key \
  -out /tmp/olvm-engine.csr \
  -subj "/C=US/ST=State/L=City/O=Company/OU=IT/CN=olvm-engine.internal"

# Create v3 extension file (SAN — Subject Alternative Names)
cat > /tmp/olvm-engine-ext.cnf << 'EOF'
[req]
req_extensions = v3_req
[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = olvm-engine.internal
DNS.2 = olvm-engine
IP.1 = 10.0.1.10
EOF

# Sign the CSR with the internal CA
openssl x509 -req \
  -days 730 \
  -in /tmp/olvm-engine.csr \
  -CA /etc/pki/internal-ca/certs/ca.crt \
  -CAkey /etc/pki/internal-ca/private/ca.key \
  -passin pass:CAPassphrase2026! \
  -CAcreateserial \
  -out /tmp/olvm-engine.crt \
  -extensions v3_req \
  -extfile /tmp/olvm-engine-ext.cnf

# Verify the signed certificate
openssl x509 -noout -text -in /tmp/olvm-engine.crt | \
  grep -E '(Subject:|Issuer:|DNS:|IP:|Not Before|Not After)'

# Verify chain
openssl verify -CAfile /etc/pki/internal-ca/certs/ca.crt /tmp/olvm-engine.crt
# Expected: /tmp/olvm-engine.crt: OK
```

### Step A3: Install the Certificate in OLVM

```bash
# OLVM engine must be stopped before replacing certs
systemctl stop ovirt-engine

# Backup existing certificates
cp -r /etc/pki/ovirt-engine /etc/pki/ovirt-engine.backup.$(date +%Y%m%d)

# Copy new certificate and key to OLVM PKI directory
cp /tmp/olvm-engine.crt /etc/pki/ovirt-engine/certs/engine.cer
cp /tmp/olvm-engine.key /etc/pki/ovirt-engine/keys/engine.key.nopass
chmod 640 /etc/pki/ovirt-engine/keys/engine.key.nopass
chown ovirt:ovirt /etc/pki/ovirt-engine/keys/engine.key.nopass

# Also replace the Apache HTTPS cert (OLVM uses Apache as frontend)
cp /tmp/olvm-engine.crt /etc/pki/ovirt-engine/apache.cer
cp /tmp/olvm-engine.key /etc/pki/ovirt-engine/keys/apache.key.nopass
chmod 640 /etc/pki/ovirt-engine/keys/apache.key.nopass

# Copy CA cert to OLVM trust store
cp /etc/pki/internal-ca/certs/ca.crt \
  /etc/pki/ovirt-engine/ca.pem

# Update the Apache virtual host config to use new cert
cat > /etc/httpd/conf.d/ovirt-engine-https.conf << 'EOF'
<VirtualHost _default_:443>
    SSLEngine on
    SSLCertificateFile      /etc/pki/ovirt-engine/apache.cer
    SSLCertificateKeyFile   /etc/pki/ovirt-engine/keys/apache.key.nopass
    SSLCACertificateFile    /etc/pki/ovirt-engine/ca.pem
    SSLVerifyClient         none
    SSLProtocol             TLSv1.2 TLSv1.3
    SSLCipherSuite          HIGH:!aNULL:!MD5:!3DES
    SSLHonorCipherOrder     on
</VirtualHost>
EOF

# Restart services
systemctl start ovirt-engine
systemctl restart httpd

# Verify new cert is served
openssl s_client -connect olvm-engine.internal:443 -showcerts 2>/dev/null | \
  openssl x509 -noout -subject -issuer -dates
```

### Step A4: Trust the CA on All Clients

```bash
# On all KVM hosts and admin workstations:
# Copy internal CA certificate
scp /etc/pki/internal-ca/certs/ca.crt root@kvm-host-01:/tmp/internal-ca.crt

# On each host:
cp /tmp/internal-ca.crt /etc/pki/ca-trust/source/anchors/internal-ca.crt
update-ca-trust   # RHEL/OL

# Ubuntu:
cp /tmp/internal-ca.crt /usr/local/share/ca-certificates/internal-ca.crt
update-ca-certificates

# Verify OLVM connection now trusted
curl https://olvm-engine.internal/ovirt-engine/ -I
# Should NOT show SSL certificate error

# Add to Firefox: Settings > Privacy > Certificates > Import
# Add to Chrome: Settings > Privacy > Security > Manage Certificates > Import
```

---

## Part B: Let's Encrypt (Public Trusted Certificate)

Only applicable if the OLVM engine is reachable from the internet or if you can use DNS challenge.

### Step B1: Install certbot

```bash
dnf install -y certbot python3-certbot-apache  # RHEL/OL
# apt install -y certbot python3-certbot-apache  # Ubuntu
```

### Step B2: Obtain Certificate (HTTP Challenge)

```bash
# OLVM engine must be reachable on port 80 from the internet
# or use DNS challenge for internal servers

# Stop Apache temporarily for standalone challenge
systemctl stop httpd

certbot certonly \
  --standalone \
  --preferred-challenges http \
  -d olvm-engine.example.com \
  --email admin@example.com \
  --agree-tos \
  --non-interactive

# Certs are stored at:
# /etc/letsencrypt/live/olvm-engine.example.com/fullchain.pem
# /etc/letsencrypt/live/olvm-engine.example.com/privkey.pem
```

### Step B3: DNS Challenge (Internal Servers — Recommended)

```bash
# Use DNS challenge — no need for internet access on port 80
# Requires ability to create DNS TXT records

# Using Cloudflare DNS:
pip3 install certbot-dns-cloudflare
cat > /etc/letsencrypt/cloudflare.ini << 'EOF'
dns_cloudflare_api_token = your-cloudflare-api-token
EOF
chmod 600 /etc/letsencrypt/cloudflare.ini

certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
  -d olvm-engine.internal \
  --email admin@example.com \
  --agree-tos \
  --non-interactive

# For other DNS providers: certbot-dns-route53, certbot-dns-azure, etc.
```

### Step B4: Install Let's Encrypt Cert in OLVM

```bash
LE_DIR="/etc/letsencrypt/live/olvm-engine.example.com"

systemctl stop ovirt-engine

cp ${LE_DIR}/cert.pem /etc/pki/ovirt-engine/certs/engine.cer
cp ${LE_DIR}/privkey.pem /etc/pki/ovirt-engine/keys/engine.key.nopass
cp ${LE_DIR}/fullchain.pem /etc/pki/ovirt-engine/apache.cer
cp ${LE_DIR}/privkey.pem /etc/pki/ovirt-engine/keys/apache.key.nopass

chmod 640 /etc/pki/ovirt-engine/keys/*.nopass

systemctl start ovirt-engine
systemctl restart httpd
```

### Step B5: Auto-Renewal

```bash
# Let's Encrypt certs expire every 90 days — automate renewal
cat > /etc/cron.d/certbot-renewal << 'EOF'
0 3 * * * root certbot renew --quiet --deploy-hook "/usr/local/bin/olvm-cert-deploy.sh"
EOF

cat > /usr/local/bin/olvm-cert-deploy.sh << 'SCRIPT'
#!/bin/bash
LE_DIR="/etc/letsencrypt/live/olvm-engine.example.com"

systemctl stop ovirt-engine

cp ${LE_DIR}/cert.pem /etc/pki/ovirt-engine/certs/engine.cer
cp ${LE_DIR}/privkey.pem /etc/pki/ovirt-engine/keys/engine.key.nopass
cp ${LE_DIR}/fullchain.pem /etc/pki/ovirt-engine/apache.cer
cp ${LE_DIR}/privkey.pem /etc/pki/ovirt-engine/keys/apache.key.nopass

chmod 640 /etc/pki/ovirt-engine/keys/*.nopass

systemctl start ovirt-engine
systemctl restart httpd
echo "OLVM cert renewed and deployed: $(date)" >> /var/log/olvm-cert-renewal.log
SCRIPT

chmod +x /usr/local/bin/olvm-cert-deploy.sh
```

---

## Part C: Certificate Monitoring and Renewal Alerts

```bash
# Check certificate expiry
openssl s_client -connect olvm-engine.internal:443 2>/dev/null | \
  openssl x509 -noout -enddate
# Returns: notAfter=Jul 21 12:00:00 2027 GMT

# Script to alert when cert is within 30 days of expiry
cat > /usr/local/bin/check-cert-expiry.sh << 'SCRIPT'
#!/bin/bash
HOST="olvm-engine.internal"
PORT=443
WARN_DAYS=30

EXPIRY=$(echo | openssl s_client -connect ${HOST}:${PORT} 2>/dev/null | \
  openssl x509 -noout -enddate | cut -d= -f2)

EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s)
NOW_EPOCH=$(date +%s)
DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))

if [ $DAYS_LEFT -lt $WARN_DAYS ]; then
  echo "WARNING: OLVM certificate expires in $DAYS_LEFT days ($EXPIRY)"
  # Send alert
  curl -s -X POST https://hooks.slack.com/services/YOUR/WEBHOOK \
    -d "{\"text\":\"ALERT: OLVM cert expires in $DAYS_LEFT days\"}"
else
  echo "OK: OLVM certificate valid for $DAYS_LEFT days ($EXPIRY)"
fi
SCRIPT

chmod +x /usr/local/bin/check-cert-expiry.sh

# Run weekly
echo "0 9 * * 1 root /usr/local/bin/check-cert-expiry.sh" >> /etc/cron.d/cert-check
```

---

## Verify HTTPS is Working

```bash
# Check certificate chain
openssl s_client -connect olvm-engine.internal:443 -showcerts 2>/dev/null | \
  grep -E '(subject|issuer|Not After)'

# Test with curl (should not show SSL errors)
curl -v https://olvm-engine.internal/ovirt-engine/api 2>&1 | \
  grep -E '(SSL|TLS|expire|OK)'

# Check TLS version and cipher
openssl s_client -connect olvm-engine.internal:443 -tls1_3 2>/dev/null | \
  grep "Protocol"

# Test OLVM REST API over HTTPS
curl -k -u admin@internal:password \
  https://olvm-engine.internal/ovirt-engine/api \
  -H "Accept: application/json" | python3 -m json.tool | head -5
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| "SSL certificate verify failed" | CA not trusted | Import CA cert to system trust store + `update-ca-trust` |
| "Certificate expired" | Cert past notAfter date | Renew with certbot or generate new cert from CA |
| OLVM won't start after cert replace | Wrong file permissions | `chmod 640 /etc/pki/ovirt-engine/keys/*.nopass; chown ovirt:ovirt ...` |
| Apache still serving old cert | Apache cache / wrong config | `systemctl restart httpd`; check SSLCertificateFile in config |
| Browser shows "ERR_CERT_AUTHORITY_INVALID" | Self-signed or wrong CA | Import CA cert into browser: Firefox/Chrome certificate import |
| OLVM hosts disconnected after cert change | Hosts verify engine cert | Re-add hosts in OLVM UI or re-enroll: `engine-config -s CertificateFingerprint=<new-fingerprint>` |
| certbot renewal fails | DNS challenge timeout | Check DNS provider API credentials; test: `certbot renew --dry-run` |
| "CN mismatch" error | SAN not set | Regenerate cert with correct SAN entries |

---

*Next: [09-Kubernetes-on-KVM.md](09-Kubernetes-on-KVM.md)*
