# 08 — Observability and Security (KVM)

> **Goal**: Deploy Prometheus + Grafana (metrics), ELK Stack (logs), Jaeger (tracing), cert-manager (TLS), and NetworkPolicies (isolation).  
> This replaces Azure Monitor + Application Insights.

---

## 1. Prometheus + Grafana (Metrics Stack)

### 1a. Install kube-prometheus-stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

kubectl create namespace monitoring

cat > /tmp/prometheus-values.yaml << 'EOF'
grafana:
  enabled: true
  adminPassword: Grafana-OnPrem-2026!
  service:
    type: LoadBalancer
    loadBalancerIP: 10.0.2.13
  persistence:
    enabled: true
    storageClassName: netapp-nfs
    size: 10Gi
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: default
          folder: OnPrem
          type: file
          options:
            path: /var/lib/grafana/dashboards/default

prometheus:
  prometheusSpec:
    retention: 30d
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: netapp-nfs
          accessModes: [ReadWriteOnce]
          resources:
            requests:
              storage: 100Gi
    additionalScrapeConfigs:
      - job_name: postgresql
        static_configs:
          - targets: ['10.0.1.30:9187', '10.0.1.31:9187', '10.0.1.32:9187']
      - job_name: mongodb
        static_configs:
          - targets: ['10.0.1.30:9216', '10.0.1.31:9216', '10.0.1.32:9216']
      - job_name: minio
        static_configs:
          - targets: ['10.0.1.30:9000']

alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: netapp-nfs
          resources:
            requests:
              storage: 5Gi
    externalUrl: http://10.0.2.13:9093

nodeExporter:
  enabled: true

kubeStateMetrics:
  enabled: true
EOF

helm install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values /tmp/prometheus-values.yaml \
  --version 58.0.0

kubectl get pods -n monitoring
```

### 1b. Configure Alertmanager (Slack/Email Alerts)

```bash
kubectl create secret generic alertmanager-config \
  --namespace monitoring \
  --from-literal=alertmanager.yaml='
global:
  resolve_timeout: 5m
  slack_api_url: "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"

route:
  group_by: [alertname, namespace]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 12h
  receiver: default
  routes:
    - match:
        severity: critical
      receiver: pagerduty
    - match:
        namespace: prod
      receiver: prod-team

receivers:
  - name: default
    slack_configs:
      - channel: "#alerts"
        title: "{{ .GroupLabels.alertname }}"
        text: "{{ range .Alerts }}{{ .Annotations.description }}{{ end }}"

  - name: prod-team
    slack_configs:
      - channel: "#prod-alerts"
    email_configs:
      - to: oncall@company.com
        from: alerts@company.com
        smarthost: smtp.company.com:587
'
```

### 1c. Add Postgres and MongoDB Exporters

```bash
# Install postgres_exporter on DB VMs
wget https://github.com/prometheus-community/postgres_exporter/releases/latest/download/postgres_exporter-0.15.0.linux-amd64.tar.gz
tar xvf postgres_exporter-*.tar.gz
mv postgres_exporter-*/postgres_exporter /usr/local/bin/

cat > /etc/systemd/system/postgres-exporter.service << 'EOF'
[Unit]
Description=PostgreSQL Exporter

[Service]
Environment="DATA_SOURCE_NAME=postgresql://postgres:PgSuper-OnPrem-2026!@localhost:5432/postgres?sslmode=disable"
ExecStart=/usr/local/bin/postgres_exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable --now postgres-exporter

# Install mongodb_exporter
wget https://github.com/percona/mongodb_exporter/releases/latest/download/mongodb_exporter_linux_amd64.tar.gz
tar xvf mongodb_exporter_*.tar.gz
mv mongodb_exporter /usr/local/bin/

cat > /etc/systemd/system/mongodb-exporter.service << 'EOF'
[Unit]
Description=MongoDB Exporter

[Service]
Environment="MONGODB_URI=mongodb://admin:MongoAdmin-OnPrem-2026!@localhost:27017/admin"
ExecStart=/usr/local/bin/mongodb_exporter --discovering-mode --mongodb.uri=$MONGODB_URI
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable --now mongodb-exporter
```

---

## 2. ELK Stack (Logs — Replaces Azure Log Analytics)

```bash
helm repo add elastic https://helm.elastic.co
helm repo update

kubectl create namespace logging

# Elasticsearch
cat > /tmp/es-values.yaml << 'EOF'
replicas: 3
minimumMasterNodes: 2
persistence:
  enabled: true
  storageClass: netapp-nfs
  size: 200Gi
resources:
  requests:
    cpu: 2
    memory: 4Gi
  limits:
    cpu: 4
    memory: 8Gi
esJavaOpts: "-Xmx4g -Xms4g"
EOF

helm install elasticsearch elastic/elasticsearch \
  --namespace logging \
  --values /tmp/es-values.yaml

# Kibana
helm install kibana elastic/kibana \
  --namespace logging \
  --set service.type=LoadBalancer \
  --set service.loadBalancerIP=10.0.2.14 \
  --set persistence.storageClassName=netapp-nfs

# Filebeat (DaemonSet on all nodes — ships pod logs to ES)
cat > /tmp/filebeat-values.yaml << 'EOF'
daemonset:
  enabled: true
filebeatConfig:
  filebeat.yml: |
    filebeat.inputs:
      - type: container
        paths:
          - /var/log/containers/*.log
        processors:
          - add_kubernetes_metadata:
              host: ${NODE_NAME}
              matchers:
                - logs_path:
                    logs_path: /var/log/containers/
    output.elasticsearch:
      hosts: [elasticsearch-master:9200]
      index: "k8s-logs-%{[kubernetes.namespace]}-%{+yyyy.MM.dd}"
EOF

helm install filebeat elastic/filebeat \
  --namespace logging \
  --values /tmp/filebeat-values.yaml
```

---

## 3. Jaeger — Distributed Tracing

```bash
helm repo add jaegertracing https://jaegertracing.github.io/helm-charts
helm repo update

kubectl create namespace tracing

helm install jaeger jaegertracing/jaeger \
  --namespace tracing \
  --set provisionDataStore.cassandra=false \
  --set provisionDataStore.elasticsearch=true \
  --set storage.type=elasticsearch \
  --set storage.elasticsearch.host=elasticsearch-master.logging.svc.cluster.local \
  --set query.service.type=LoadBalancer

# Applications report traces to jaeger-agent:6831 (UDP)
# In app deployment:
# env:
#   - name: JAEGER_AGENT_HOST
#     value: jaeger-agent.tracing.svc.cluster.local
#   - name: JAEGER_AGENT_PORT
#     value: "6831"
```

---

## 4. Network Policies — Environment Isolation

```bash
# Default deny all ingress per namespace
for NS in dev qa preprod prod; do
cat > /tmp/netpol-${NS}.yaml << EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: ${NS}
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-intranamespace
  namespace: ${NS}
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              environment: ${NS}
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              environment: ${NS}
    - to: []         # Allow DNS
      ports:
        - port: 53
          protocol: UDP
    - to:
        - ipBlock:
            cidr: 10.0.1.0/24    # Allow infra VMs (DB, MinIO)
EOF
kubectl apply -f /tmp/netpol-${NS}.yaml
done
```

---

## 5. cert-manager TLS Certificates

```bash
# Create internal CA (already installed in 04-Kubernetes-Setup.md)
# Generate internal CA key and cert
openssl genrsa -out /tmp/ca.key 4096
openssl req -new -x509 -days 3650 -key /tmp/ca.key -out /tmp/ca.crt \
  -subj "/CN=OnPrem Internal CA/O=Company"

# Store as Kubernetes secret
kubectl create secret tls internal-ca-secret \
  --namespace cert-manager \
  --cert=/tmp/ca.crt \
  --key=/tmp/ca.key

# Create Certificate for Harbor
cat > /tmp/harbor-cert.yaml << 'EOF'
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: harbor-tls
  namespace: harbor
spec:
  secretName: harbor-tls
  issuerRef:
    name: internal-ca
    kind: ClusterIssuer
  dnsNames:
    - harbor.internal
  ipAddresses:
    - 10.0.2.10
EOF

kubectl apply -f /tmp/harbor-cert.yaml

# Trust the CA on all K8s nodes
cp /tmp/ca.crt /usr/local/share/ca-certificates/internal-ca.crt
update-ca-certificates
```

---

## Verify Observability Stack

```bash
echo "=== Prometheus ==="
kubectl get pods -n monitoring
curl -s http://10.0.2.13:9090/-/healthy && echo "Prometheus OK"

echo "=== Grafana ==="
curl -s http://10.0.2.13:3000/api/health | jq '.database'

echo "=== Elasticsearch ==="
kubectl exec -n logging elasticsearch-master-0 -- \
  curl -s localhost:9200/_cluster/health | jq '.status'

echo "=== Kibana ==="
curl -s http://10.0.2.14:5601/api/status | jq '.status.overall.level'

echo "=== Network Policies ==="
kubectl get networkpolicies --all-namespaces
```

---

*Next: [09-Backup-DR.md](09-Backup-DR.md)*
