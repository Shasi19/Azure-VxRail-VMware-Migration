# Volume 7: Monitoring & Security
## Chapter 1: Observability Stack Setup

---

## Monitoring Architecture Overview

```mermaid
graph TB
    subgraph APPS["Applications (K8s)"]
        A1[WebApp Pods]
        A2[Batch Jobs]
        A3[PostgreSQL]
        A4[Redis]
        A5[NGINX Ingress]
    end

    subgraph COLLECT["Metrics Collection"]
        P[Prometheus\n10.0.7.10:9090]
        PE1[node-exporter\non each K8s node]
        PE2[kube-state-metrics]
        PE3[postgres-exporter]
        PE4[redis-exporter]
        PE5[nginx-exporter]
    end

    subgraph ALERT["Alerting"]
        AM[Alertmanager\n10.0.7.11:9093]
        PD[PagerDuty]
        SLACK[Slack Channel\n#ops-alerts]
        EMAIL[Email\nops@company.com]
    end

    subgraph VIZ["Visualization"]
        G[Grafana\n10.0.7.12:3000]
        D1[Infra Dashboard]
        D2[K8s Dashboard]
        D3[App Dashboard]
        D4[DB Dashboard]
    end

    subgraph LOGS["Log Aggregation ELK"]
        ES[Elasticsearch\n10.0.7.20:9200]
        LS[Logstash\n10.0.7.21:5044]
        KB[Kibana\n10.0.7.22:5601]
        FB[Filebeat\non each node]
    end

    subgraph TRACE["Distributed Tracing"]
        J[Jaeger\n10.0.7.30:16686]
    end

    A1 & A2 -->|/metrics endpoint| P
    A3 --> PE3 --> P
    A4 --> PE4 --> P
    A5 --> PE5 --> P
    PE1 & PE2 --> P
    P --> AM
    AM --> PD & SLACK & EMAIL
    P --> G
    G --> D1 & D2 & D3 & D4

    A1 & A2 -->|logs stdout| FB --> LS --> ES --> KB
    A1 & A2 -->|traces| J

    style APPS fill:#e3f2fd
    style COLLECT fill:#e8f5e9
    style ALERT fill:#fff3e0
    style VIZ fill:#f3e5f5
    style LOGS fill:#fce4ec
    style TRACE fill:#e0f2f1
```

---

## Prometheus Setup

```yaml
# prometheus-values.yaml (Helm kube-prometheus-stack)
prometheus:
  prometheusSpec:
    retention: 30d
    retentionSize: "50GB"
    replicas: 2
    replicaExternalLabelName: "prometheus_replica"
    scrapeInterval: 15s
    evaluationInterval: 15s
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: nfs-sc
          resources:
            requests:
              storage: 100Gi
    resources:
      requests:
        cpu: 500m
        memory: 2Gi
      limits:
        cpu: 2
        memory: 8Gi
    additionalScrapeConfigs:
      - job_name: 'postgresql'
        static_configs:
          - targets: ['10.0.5.1:9187', '10.0.5.2:9187']
      - job_name: 'redis'
        static_configs:
          - targets: ['10.0.6.50:9121']
      - job_name: 'haproxy'
        static_configs:
          - targets: ['10.0.5.100:8404']

alertmanager:
  config:
    global:
      resolve_timeout: 5m
    route:
      group_by: ['alertname', 'cluster', 'service']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 12h
      receiver: 'slack-critical'
      routes:
        - match:
            severity: critical
          receiver: 'pagerduty'
        - match:
            severity: warning
          receiver: 'slack-warning'
    receivers:
      - name: 'slack-critical'
        slack_configs:
          - api_url: '${SLACK_WEBHOOK_URL}'
            channel: '#ops-critical'
            title: '🔴 CRITICAL: {{ .GroupLabels.alertname }}'
            text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
      - name: 'pagerduty'
        pagerduty_configs:
          - routing_key: '${PD_ROUTING_KEY}'
      - name: 'slack-warning'
        slack_configs:
          - api_url: '${SLACK_WEBHOOK_URL}'
            channel: '#ops-alerts'

grafana:
  adminPassword: "${GRAFANA_PASSWORD}"
  persistence:
    enabled: true
    size: 10Gi
  sidecar:
    dashboards:
      enabled: true
      label: grafana_dashboard
  grafana.ini:
    auth.ldap:
      enabled: true
      config_file: /etc/grafana/ldap.toml
    server:
      root_url: "https://grafana.company.com"
```

---

## Alert Rules

```yaml
# alerting-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: onprem-alerts
  namespace: monitoring
spec:
  groups:
    - name: application.rules
      rules:
        - alert: HighResponseTime
          expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 0.2
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "P95 response time > 200ms"
            description: "App response time P95 is {{ $value }}s"

        - alert: HighErrorRate
          expr: rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) > 0.01
          for: 2m
          labels:
            severity: critical
          annotations:
            summary: "Error rate > 1%"

        - alert: PodCrashLooping
          expr: rate(kube_pod_container_status_restarts_total[15m]) > 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Pod {{ $labels.pod }} is crash looping"

    - name: database.rules
      rules:
        - alert: PostgreSQLDown
          expr: pg_up == 0
          for: 1m
          labels:
            severity: critical
          annotations:
            summary: "PostgreSQL is DOWN on {{ $labels.instance }}"

        - alert: PostgreSQLReplicationLag
          expr: pg_replication_lag > 30
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Replication lag {{ $value }}s on {{ $labels.instance }}"

        - alert: PostgreSQLConnectionsHigh
          expr: pg_stat_activity_count > 350
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "PostgreSQL connections {{ $value }}/400"

    - name: infrastructure.rules
      rules:
        - alert: NodeHighCPU
          expr: 100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Node CPU > 85% for 10 minutes"

        - alert: NodeHighMemory
          expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 90
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Node memory > 90%"

        - alert: DiskSpaceLow
          expr: (1 - (node_filesystem_avail_bytes / node_filesystem_size_bytes)) * 100 > 80
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Disk {{ $labels.mountpoint }} is {{ $value }}% full"
```

---

## ELK Stack Setup

```bash
# Deploy Elasticsearch (3-node cluster)
helm repo add elastic https://helm.elastic.co

# elasticsearch-values.yaml
cat > elasticsearch-values.yaml <<EOF
replicas: 3
minimumMasterNodes: 2
resources:
  requests:
    cpu: "1"
    memory: "4Gi"
  limits:
    cpu: "4"
    memory: "8Gi"
volumeClaimTemplate:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 500Gi
esConfig:
  elasticsearch.yml: |
    cluster.name: "onprem-logs"
    xpack.security.enabled: true
    xpack.security.transport.ssl.enabled: true
    indices.query.bool.max_clause_count: 4096
EOF

helm install elasticsearch elastic/elasticsearch \
  -f elasticsearch-values.yaml \
  --namespace logging --create-namespace

# Deploy Kibana
helm install kibana elastic/kibana \
  --set elasticsearchHosts="http://elasticsearch-master:9200" \
  --namespace logging

# Deploy Filebeat (DaemonSet on all K8s nodes)
helm install filebeat elastic/filebeat \
  --namespace logging
```

### Logstash Pipeline Configuration

```ruby
# logstash-pipeline.conf
input {
  beats {
    port => 5044
    ssl => false
  }
}

filter {
  if [kubernetes][namespace] == "production" {
    grok {
      match => {
        "message" => [
          "%{TIMESTAMP_ISO8601:timestamp} \[%{LOGLEVEL:log_level}\] %{GREEDYDATA:log_message}",
          "%{COMBINEDAPACHELOG}"
        ]
      }
    }
    date {
      match => ["timestamp", "ISO8601"]
      target => "@timestamp"
    }
    mutate {
      add_field => { "environment" => "production" }
      add_field => { "datacenter" => "onpremises" }
    }
  }
}

output {
  elasticsearch {
    hosts => ["http://elasticsearch-master:9200"]
    index => "app-logs-%{[kubernetes][namespace]}-%{+YYYY.MM.dd}"
    user => "elastic"
    password => "${ES_PASSWORD}"
  }
}
```

---

## Security: HashiCorp Vault Setup

```mermaid
flowchart LR
    subgraph VAULT["HashiCorp Vault Cluster"]
        V1[Vault-1\nActive]
        V2[Vault-2\nStandby]
        V3[Vault-3\nStandby]
        RAFT[(Raft\nStorage)]
    end

    subgraph K8S["Kubernetes"]
        SA[Service\nAccount]
        INJ[Vault Agent\nInjector Sidecar]
        POD[App Pod]
    end

    subgraph SECRETS["Secret Engines"]
        KV[KV Secrets Engine\nApp Secrets]
        PKI[PKI Engine\nTLS Certificates]
        DB[Database Engine\nDB Credentials Rotation]
    end

    V1 <-->|Raft Consensus| V2 & V3
    V1 & V2 & V3 --> RAFT
    SA --> V1
    V1 --> INJ
    INJ -->|Inject secrets\nas env vars| POD
    KV & PKI & DB --> V1

    style VAULT fill:#ffa500,color:#000
    style K8S fill:#1565c0,color:#fff
```

```bash
# Initialize Vault
vault operator init -key-shares=5 -key-threshold=3

# Unseal (requires 3 of 5 keys)
vault operator unseal <key1>
vault operator unseal <key2>
vault operator unseal <key3>

# Enable Kubernetes auth method
vault auth enable kubernetes
vault write auth/kubernetes/config \
    token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
    kubernetes_host="https://k8s-api.internal:6443" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

# Create policy for webapp
vault policy write webapp-policy - <<EOF
path "secret/webapp/*" {
  capabilities = ["read", "list"]
}
path "database/creds/webapp-role" {
  capabilities = ["read"]
}
EOF

# Create K8s role for webapp service account
vault write auth/kubernetes/role/webapp-role \
    bound_service_account_names=webapp-sa \
    bound_service_account_namespaces=production \
    policies=webapp-policy \
    ttl=1h

# Store secrets (migrated from Azure Key Vault)
vault kv put secret/webapp/db \
    DB_CONNECTION_STRING="Server=10.0.5.100;Database=production_db;..."
vault kv put secret/webapp/api-keys \
    EXTERNAL_API_KEY="<migrated-from-azure>"

# Enable database secrets engine (auto-rotation)
vault secrets enable database
vault write database/config/postgresql \
    plugin_name=postgresql-database-plugin \
    connection_url="postgresql://{{username}}:{{password}}@10.0.5.100:5432/production_db" \
    allowed_roles="webapp-role" \
    username="vault_admin" password="<vaultpw>"

vault write database/roles/webapp-role \
    db_name=postgresql \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    default_ttl="1h" max_ttl="24h"
```

---

## Grafana Dashboard Import

```bash
# Import pre-built dashboards via API
GRAFANA_URL="http://grafana.company.com"
GRAFANA_USER="admin"
GRAFANA_PASS="${GRAFANA_PASSWORD}"

# Download and import K8s cluster dashboard (ID: 7249)
curl -X POST ${GRAFANA_URL}/api/dashboards/import \
  -H "Content-Type: application/json" \
  -u ${GRAFANA_USER}:${GRAFANA_PASS} \
  -d '{"dashboard":{"id":7249},"overwrite":true,"folderId":0}'

# PostgreSQL dashboard (ID: 9628)
curl -X POST ${GRAFANA_URL}/api/dashboards/import \
  -H "Content-Type: application/json" \
  -u ${GRAFANA_USER}:${GRAFANA_PASS} \
  -d '{"dashboard":{"id":9628},"overwrite":true}'

# Redis dashboard (ID: 11835)
curl -X POST ${GRAFANA_URL}/api/dashboards/import \
  -H "Content-Type: application/json" \
  -u ${GRAFANA_USER}:${GRAFANA_PASS} \
  -d '{"dashboard":{"id":11835},"overwrite":true}'

# NGINX Ingress dashboard (ID: 9614)
curl -X POST ${GRAFANA_URL}/api/dashboards/import \
  -H "Content-Type: application/json" \
  -u ${GRAFANA_USER}:${GRAFANA_PASS} \
  -d '{"dashboard":{"id":9614},"overwrite":true}'
```

---

## Azure Monitor → Prometheus Equivalents

```
┌─────────────────────────────────────────────────────────────────────┐
│          AZURE MONITOR → PROMETHEUS/GRAFANA MAPPING                 │
├──────────────────────────────┬──────────────────────────────────────┤
│  Azure Monitor Alert         │  Prometheus Alert Rule               │
├──────────────────────────────┼──────────────────────────────────────┤
│  CPU > 80%                   │  HighCPU (node_cpu > 0.8)           │
│  Memory > 85%                │  HighMemory (mem_avail < 15%)       │
│  DB Connections > 350        │  PostgreSQLConnectionsHigh          │
│  Response Time > 500ms P95   │  HighResponseTime (> 0.2s)         │
│  Error Rate > 1%             │  HighErrorRate (5xx > 1%)          │
│  Storage Quota > 80%         │  DiskSpaceLow (> 80%)              │
│  Health Check Failure        │  PodNotReady + AppHealthDown        │
├──────────────────────────────┼──────────────────────────────────────┤
│  App Insights (APM)          │  Jaeger + Prometheus + OTEL SDK     │
│  Log Analytics               │  Elasticsearch + Kibana             │
│  Azure Sentinel (SIEM)       │  Wazuh SIEM + OSSEC                │
└──────────────────────────────┴──────────────────────────────────────┘
```

---

**Document Version**: 2.0
**Date**: July 2026
**Classification**: Internal Use Only
