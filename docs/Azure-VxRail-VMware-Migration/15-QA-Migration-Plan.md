# QA Migration Plan

**Environment:** QA | Weeks 1–3 | Azure → On-Premises VxRail

> This document covers the **data and application migration** steps for QA specifically.
> For infrastructure build see [05-QA-Detailed-Implementation.md](./05-QA-Detailed-Implementation.md).
> For rollback see [09-Rollback-Procedures.md](./09-Rollback-Procedures.md).

## Required Controls Before QA Sign-Off

- [ ] QA AKS cost and node count reconciled to the workbook: 3 x Standard D2s v4, $284/month.
- [ ] QA Container Instance ($110/month) confirmed unused or retained by the application owner; remove only after approval.
- [ ] No passwords or tokens are stored in this runbook; use the approved secret manager and one-time credentials.
- [ ] Namespace restore from Kasten or the selected backup tool completed successfully before PREPROD starts.

---

## Migration Flowchart

```
QA MIGRATION FLOW — COMPLETE
═══════════════════════════════════════════════════════════════════════

  [AZURE QA — SOURCE]
  ┌──────────────────────────────────────────────────────────────────┐
  │  PostgreSQL Flexible Server  │  ACR images  │  AKS qa namespace  │
  │  Azure Blob Storage          │  Key Vault   │  ConfigMaps        │
  └─────────────────────────┬────────────────────────────────────────┘
                            │
  ① pg_dump (full export)   │  ② Image sync     ③ Secret export
                            ▼
  ┌──────────────────────────────────────────────────────────────────┐
  │  /backup/azure-qa-<date>.pgdump                                  │
  │  Harbor: harbor.internal.company.com/migration/*                 │
  │  K8s Secrets: kubectl create secret ... --namespace qa           │
  └─────────────────────────┬────────────────────────────────────────┘
                            │
  ④ pg_restore              │  ⑤ ArgoCD sync (qa branch)
                            ▼
  ┌──────────────────────────────────────────────────────────────────┐
  │  pg-qa-01 (10.30.0.100)  │  k8s-qa namespace                    │
  │  qa_db restored          │  All pods Running                     │
  └─────────────────────────┬────────────────────────────────────────┘
                            │
  ⑥ Validation              │
  ◆ Row counts match?  ◆ Smoke tests pass?  ◆ Load test 200 users?
         │                                         │
        YES ──────────────────────────────────▶ QA SIGN-OFF
         │                                     Proceed to PREPROD
        NO
         │
  ▼ Investigate → fix → retest (max 3 attempts)
  ▼ If unresolvable: rollback (Azure QA unaffected — no DNS cutover)
```

---

## Pre-Migration Checklist

```
[ ] k8s-qa cluster: 6 nodes Ready (kubectl get nodes)
[ ] pg-qa-01 VM running, PostgreSQL 15 installed (10.30.0.100)
[ ] Harbor registry accessible (harbor.internal.company.com)
[ ] ArgoCD connected to qa branch of k8s-manifests repo
[ ] VPN/Direct Connect Azure ↔ on-prem active and tested
[ ] /backup/ has at least 200 GB free space
[ ] Azure QA credentials + Key Vault access confirmed
[ ] DNS: qa.internal.company.com → MetalLB IP (internal test only)
[ ] QA team notified of migration schedule
[ ] Rollback plan reviewed by DBA and app team
```

---

## Step 1: Export Database from Azure

```bash
# WHY pg_dump with --format=custom:
#   - Consistent snapshot (no writes during export)
#   - Binary format: faster restore, parallel-capable
#   - --no-owner: avoids OS user conflicts on on-prem
#   - --compress=9: smaller file for transfer

AZURE_HOST="qa-server.postgres.database.azure.com"
AZURE_USER="adminuser"
BACKUP_DIR="/backup"
BACKUP_FILE="${BACKUP_DIR}/azure-qa-$(date +%Y%m%d-%H%M).pgdump"

# Test connectivity
psql "host=${AZURE_HOST} port=5432 dbname=qa_db user=${AZURE_USER} sslmode=require" \
  -c "SELECT version(), pg_size_pretty(pg_database_size('qa_db')) AS db_size;"

# Export
pg_dump \
  "host=${AZURE_HOST} port=5432 dbname=qa_db user=${AZURE_USER} sslmode=require" \
  --no-owner \
  --no-acl \
  --format=custom \
  --compress=9 \
  --verbose \
  -f "${BACKUP_FILE}"

# Verify dump is readable
pg_restore --list "${BACKUP_FILE}" | wc -l
ls -lh "${BACKUP_FILE}"
echo "Export complete: ${BACKUP_FILE}"
```

---

## Step 2: Transfer Backup to On-Prem

```bash
# Option A: scp from Azure jump host to on-prem backup storage
scp "${BACKUP_FILE}" postgres@10.30.0.100:/backup/

# Option B: rsync (resumes if interrupted, better for large files)
rsync -avz --progress "${BACKUP_FILE}" postgres@10.30.0.100:/backup/

# Verify integrity (checksum comparison)
sha256sum "${BACKUP_FILE}"
# Run same command on 10.30.0.100 and compare hashes
ssh postgres@10.30.0.100 "sha256sum /backup/$(basename ${BACKUP_FILE})"
```

---

## Step 3: Restore Database on On-Prem

```bash
# On pg-qa-01 (10.30.0.100)
BACKUP_FILE="/backup/azure-qa-<date>.pgdump"   # update with actual filename

# Create target database
psql -h 10.30.0.100 -U postgres << 'SQL'
CREATE DATABASE qa_db OWNER postgres;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE ROLE app_user LOGIN PASSWORD 'AppQA_2026!';
GRANT ALL PRIVILEGES ON DATABASE qa_db TO app_user;
SQL

# Restore (--jobs=4 uses 4 parallel workers for faster restore)
pg_restore \
  -h 10.30.0.100 \
  -U postgres \
  -d qa_db \
  --no-owner \
  --no-acl \
  --jobs=4 \
  --verbose \
  "${BACKUP_FILE}"

echo "Restore complete — running validation..."
```

---

## Step 4: Validate Database Row Counts

```bash
# Compare Azure vs On-prem row counts for every table
AZURE_HOST="qa-server.postgres.database.azure.com"
AZURE_USER="adminuser"

echo "=== DATABASE VALIDATION $(date) ==="
PASS=0
FAIL=0

TABLES=$(psql -h 10.30.0.100 -U postgres -d qa_db -t -c \
  "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename;")

for TABLE in ${TABLES}; do
  AZ_COUNT=$(psql \
    "host=${AZURE_HOST} port=5432 dbname=qa_db user=${AZURE_USER} sslmode=require" \
    -t -c "SELECT COUNT(*) FROM public.${TABLE};" 2>/dev/null | tr -d ' ')

  OP_COUNT=$(psql -h 10.30.0.100 -U postgres -d qa_db \
    -t -c "SELECT COUNT(*) FROM public.${TABLE};" 2>/dev/null | tr -d ' ')

  if [ "${AZ_COUNT}" = "${OP_COUNT}" ]; then
    echo "  ✅ ${TABLE}: ${OP_COUNT} rows"
    PASS=$((PASS+1))
  else
    echo "  ❌ ${TABLE}: Azure=${AZ_COUNT} vs On-prem=${OP_COUNT}"
    FAIL=$((FAIL+1))
  fi
done

echo ""
echo "Result: ${PASS} tables match, ${FAIL} mismatches"
[ "${FAIL}" -eq 0 ] && echo "PASSED" || echo "FAILED — investigate before proceeding"
```

---

## Step 5: Migrate Container Images (ACR → Harbor)

```bash
# Why: On-prem K8s cannot reach Azure ACR at runtime; images must be in Harbor
ACR_NAME="yourcompanyacr.azurecr.io"
HARBOR_HOST="harbor.internal.company.com"
HARBOR_PROJECT="migration"

# Login
az acr login --name yourcompanyacr
docker login ${HARBOR_HOST} -u admin -p "HarborAdmin2026!"

# Pull, retag, push each image
IMAGES="api-gateway auth-service user-service notification-service"

for IMAGE in ${IMAGES}; do
  SRC="${ACR_NAME}/${IMAGE}:latest"
  DST="${HARBOR_HOST}/${HARBOR_PROJECT}/${IMAGE}:latest"
  docker pull "${SRC}"
  docker tag  "${SRC}" "${DST}"
  docker push "${DST}"
  echo "Migrated: ${IMAGE}"
done

# Verify
curl -s -u admin:HarborAdmin2026! \
  "https://${HARBOR_HOST}/api/v2.0/projects/${HARBOR_PROJECT}/repositories" \
  | python3 -c "import sys,json; [print(r['name']) for r in json.load(sys.stdin)]"
```

---

## Step 6: Migrate Secrets and ConfigMaps

```bash
kubectl create namespace qa 2>/dev/null || true

# Database credentials
kubectl create secret generic postgres-qa-creds \
  --namespace qa \
  --from-literal=POSTGRES_HOST="10.30.0.100" \
  --from-literal=POSTGRES_PORT="5432" \
  --from-literal=POSTGRES_DB="qa_db" \
  --from-literal=POSTGRES_USER="app_user" \
  --from-literal=POSTGRES_PASSWORD="AppQA_2026!"

# Application secrets (from Azure Key Vault)
# Export each secret value and create as K8s secret
AKV="your-qa-keyvault"
for SECRET_NAME in jwt-secret api-key smtp-password; do
  SECRET_VALUE=$(az keyvault secret show \
    --vault-name ${AKV} --name ${SECRET_NAME} --query value -o tsv)
  kubectl create secret generic "${SECRET_NAME}" \
    --namespace qa \
    --from-literal=value="${SECRET_VALUE}"
  echo "Migrated secret: ${SECRET_NAME}"
done
```

---

## Step 7: Deploy Applications via ArgoCD

```bash
# Update image references in manifests/qa/ to use Harbor
# (Edit your k8s-manifests qa branch before applying)
# Example change:
#   image: yourcompanyacr.azurecr.io/api-gateway:latest
#   → image: harbor.internal.company.com/migration/api-gateway:latest

cat <<YAML | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: qa-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/k8s-manifests
    targetRevision: qa
    path: environments/qa
  destination:
    server: https://kubernetes.default.svc
    namespace: qa
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
YAML

kubectl rollout status deployment -n qa --timeout=300s
echo "All QA deployments rolled out"
```

---

## Step 8: Smoke Tests

```bash
QA_IP=$(kubectl get svc api-gateway -n qa \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "QA IP: ${QA_IP}"

# Health
STATUS=$(curl -sf "http://${QA_IP}/health" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])" 2>/dev/null)
echo "Health: ${STATUS}"

# DB connection
DB_STATUS=$(curl -sf "http://${QA_IP}/health" | python3 -c "import sys,json; print(json.load(sys.stdin)['database'])" 2>/dev/null)
echo "Database: ${DB_STATUS}"

# User count (validates DB content)
USER_COUNT=$(curl -sf "http://${QA_IP}/api/users/count" | python3 -c "import sys,json; print(json.load(sys.stdin)['count'])" 2>/dev/null)
echo "User count: ${USER_COUNT}"

# All pods running
kubectl get pods -n qa --no-headers | grep -v "Running\|Completed"
echo "Above should be empty (all pods Running)"
```

---

## Rollback Plan

```
QA ROLLBACK — WHEN AND HOW
═══════════════════════════════════════════════════════

  Trigger: Any of the following after deploying to QA:
  - DB row count mismatch after restore
  - Critical smoke test failures not fixed within 2 hours
  - Data corruption detected in on-prem database

  QA ROLLBACK IS LOW-RISK:
  ✅ No Azure QA DNS cutover has happened
  ✅ Azure QA is completely untouched
  ✅ On-prem QA is isolated (VLAN 100, no external traffic)

  ROLLBACK STEPS:
  1. Notify team: "QA migration paused, investigating"
  2. Scale down QA apps: kubectl scale deploy --all --replicas=0 -n qa
  3. Drop and re-create database: DROP DATABASE qa_db; CREATE DATABASE qa_db;
  4. Fix the root cause (data export issue, config issue, etc.)
  5. Re-run migration from Step 1
  6. Max 3 retry attempts before escalating to architect

  WHAT IS NOT AFFECTED:
  - Azure QA (still running, users unaffected)
  - PREPROD and PROD environments (separate VLANs)
  - On-prem VxRail cluster health
```

---

## QA Migration Sign-Off

```
QA MIGRATION SIGN-OFF
═════════════════════════════════════════════════════

Migration date:     _______________
DB backup file:     _______________
Restore duration:   _______________

Checklist:
[ ] DB row counts match Azure (all tables — validation script PASSED)
[ ] All container images in Harbor (verified via API)
[ ] All secrets migrated from Azure Key Vault
[ ] Health endpoint: 200 OK
[ ] DB connected from application
[ ] All pods Running (no CrashLoops)
[ ] Load test 200 users: p95 < 500ms, error < 0.1%
[ ] No pod restarts in 24 hours post-deploy

Signatures:
DBA:            ________________  Date: ________
App Team Lead:  ________________  Date: ________
QA Lead:        ________________  Date: ________

RECOMMENDATION: [ ] PROCEED TO PREPROD    [ ] EXTEND QA (reason: _______)
```

---

**Next:** [16-PREPROD-Migration-Plan.md](./16-PREPROD-Migration-Plan.md)
**Infrastructure:** [05-QA-Detailed-Implementation.md](./05-QA-Detailed-Implementation.md)
**Rollback detail:** [09-Rollback-Procedures.md](./09-Rollback-Procedures.md)
**Index:** [00-VxRail-Complete-Index.md](./00-VxRail-Complete-Index.md)
