# Monitoring & Logging Strategy

**Prometheus, Grafana, ELK Stack & SLO/SLI Definitions**

---

## Table of Contents
1. [Prometheus Configuration](#prometheus-configuration)
2. [Grafana Dashboards](#grafana-dashboards)
3. [ELK Stack Setup](#elk-stack-setup)
4. [Alerting Rules](#alerting-rules)
5. [SLO/SLI Definitions](#slosli-definitions)
6. [Dashboards & Reporting](#dashboards--reporting)
7. [Retention Policies](#retention-policies)

---

## Prometheus Configuration

### Prometheus Deployment

```bash
# Deploy Prometheus in Kubernetes

kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: monitoring
data:
  prometheus.yml: |
    global:
      scrape_interval: 30s
      evaluation_interval: 1m
      external_labels:
        cluster: k8s-prod
        environment: production
    
    scrape_configs:
    # Kubernetes API Server
    - job_name: 'kubernetes-apiservers'
      kubernetes_sd_configs:
      - role: endpoints
      scheme: https
      tls_config:
        ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
      bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
      relabel_configs:
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
        action: keep
        regex: default;kubernetes;https
    
    # Kubelet
    - job_name: 'kubernetes-nodes'
      kubernetes_sd_configs:
      - role: node
      scheme: https
      tls_config:
        ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
      bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
      relabel_configs:
      - action: labelmap
        regex: __meta_kubernetes_node_label_(.+)
    
    # PostgreSQL Exporter
    - job_name: 'postgresql'
      static_configs:
      - targets: ['10.30.0.10:9187']  # PostgreSQL exporter
      relabel_configs:
      - source_labels: [__address__]
        target_label: instance
    
    # Application Metrics (Prometheus client library)
    - job_name: 'applications'
      kubernetes_sd_configs:
      - role: pod
        namespaces:
          names:
          - prod
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app]
        action: keep
        regex: '(api-gateway|auth-service|order-service)'
      - source_labels: [__meta_kubernetes_pod_container_port_number]
        action: keep
        regex: '8080|9090'
    
    # Kubernetes Components
    - job_name: 'kube-state-metrics'
      static_configs:
      - targets: ['kube-state-metrics.kube-system:8080']
    
    alerting:
      alertmanagers:
      - static_configs:
        - targets: ['alertmanager:9093']
EOF

# Deploy Prometheus StatefulSet
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: prometheus
  namespace: monitoring
spec:
  serviceName: prometheus
  replicas: 1
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      containers:
      - name: prometheus
        image: prom/prometheus:latest
        args:
          - '--config.file=/etc/prometheus/prometheus.yml'
          - '--storage.tsdb.path=/prometheus'
          - '--storage.tsdb.retention.time=15d'
        ports:
        - containerPort: 9090
        volumeMounts:
        - name: config
          mountPath: /etc/prometheus
        - name: storage
          mountPath: /prometheus
        resources:
          requests:
            cpu: 500m
            memory: 2Gi
          limits:
            cpu: 1000m
            memory: 4Gi
      volumes:
      - name: config
        configMap:
          name: prometheus-config
  volumeClaimTemplates:
  - metadata:
      name: storage
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: vsan-platinum
      resources:
        requests:
          storage: 500Gi
EOF
```

### Key Metrics Collected

```
Kubernetes Metrics:
├── Node metrics
│   ├── kube_node_labels
│   ├── node_cpu_seconds_total
│   ├── node_memory_MemAvailable_bytes
│   ├── node_disk_io_time_seconds_total
│   └── node_network_receive_bytes_total
├── Pod metrics
│   ├── kube_pod_info
│   ├── container_cpu_usage_seconds_total
│   ├── container_memory_usage_bytes
│   ├── kube_pod_status_phase
│   └── kube_pod_container_status_restarts_total
└── Cluster metrics
    ├── kube_apiserver_request_total
    ├── scheduler_e2e_scheduling_duration_seconds
    └── apiserver_client_certificate_expiration_seconds

PostgreSQL Metrics (via postgres_exporter):
├── pg_up (server status)
├── pg_database_size_bytes (database size)
├── pg_stat_database_* (transaction stats)
├── pg_stat_user_tables_* (table stats)
├── pg_stat_activity (connections)
├── pg_replication_slots_* (replication status)
└── pg_wal_receiver_* (replication lag)

Application Metrics (custom instrumenting):
├── http_requests_total (API calls by endpoint)
├── http_request_duration_seconds (response times)
├── database_query_duration_seconds (query times)
├── errors_total (application errors)
├── business_transactions_total (revenue, signups)
└── cache_hits_total (cache effectiveness)
```

---

## Grafana Dashboards

### Dashboard 1: Cluster Health

```
Panel 1: Node Status
- Status of all 15 nodes (red/yellow/green)
- CPU usage per node
- Memory usage per node

Panel 2: Pod Status
- Running pods: 45/45
- Pending pods: 0
- Failed pods: 0
- Restart rate: < 1/hour

Panel 3: Storage
- vSAN usage: 63.3% of 247.66 TB (156.8 TB used, 90.86 TB free)
- Storage I/O: 500 IOPS
- vSAN rebuild status (if any)

Panel 4: Network
- Network throughput: 2 Gbps aggregate
- Network errors: 0
- Packet loss: 0%

Dashboard URL: http://grafana:3000/d/cluster-health
```

### Dashboard 2: Application Performance

```
Panel 1: API Response Times
- p50, p95, p99 latencies
- Target: p95 < 500ms
- Spike detection alert

Panel 2: Error Rates
- 5xx errors: < 0.1%
- 4xx errors: Expected rate
- Error breakdown by endpoint

Panel 3: Throughput
- Requests/sec by endpoint
- User concurrency (active sessions)
- Requests queued

Panel 4: Database Load
- Active connections: < 200
- Slow queries (> 1 sec): trending
- Query time percentiles

Dashboard URL: http://grafana:3000/d/app-performance
```

### Dashboard 3: Database Health

```
Panel 1: Replication Status
- Replication lag (milliseconds)
- Committed transactions
- Aborted transactions

Panel 2: Database Size
- Current size: ~650 GB
- Growth trend (GB/week)
- Forecast when out of space

Panel 3: Backup Status
- Last backup time
- Backup duration
- Backup success rate

Panel 4: Slow Queries
- Queries > 1 second
- Top 10 slowest queries
- Query plans (via pg_stat_statements)

Dashboard URL: http://grafana:3000/d/database-health
```

### Dashboard 4: Business Metrics

```
Panel 1: Transactions
- Transactions/min
- Transaction value (revenue)
- Conversion rate

Panel 2: Users
- Active users
- New signups/day
- User retention rate

Panel 3: Errors
- Customer-impacting errors
- Revenue lost to errors (estimate)
- Error trend analysis

Panel 4: SLOs
- Availability SLO: 99.9% (current: 99.95%)
- Response time SLO: p95 < 500ms (current: 245ms)
- Error rate SLO: < 0.1% (current: 0.02%)

Dashboard URL: http://grafana:3000/d/business-metrics
```

---

## ELK Stack Setup

### Elasticsearch Cluster

```bash
# Deploy Elasticsearch (3-node cluster)
kubectl apply -f - <<EOF
apiVersion: v1
kind: StatefulSet
metadata:
  name: elasticsearch
  namespace: monitoring
spec:
  serviceName: elasticsearch
  replicas: 3
  selector:
    matchLabels:
      app: elasticsearch
  template:
    metadata:
      labels:
        app: elasticsearch
    spec:
      containers:
      - name: elasticsearch
        image: docker.elastic.co/elasticsearch/elasticsearch:8.0.0
        env:
        - name: cluster.name
          value: prod-elasticsearch
        - name: node.name
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: discovery.seed_hosts
          value: "elasticsearch-0,elasticsearch-1,elasticsearch-2"
        - name: cluster.initial_master_nodes
          value: "elasticsearch-0,elasticsearch-1,elasticsearch-2"
        ports:
        - containerPort: 9200
        - containerPort: 9300
        volumeMounts:
        - name: data
          mountPath: /usr/share/elasticsearch/data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: vsan-platinum
      resources:
        requests:
          storage: 500Gi
EOF
```

### Logstash Pipeline

```bash
# Configure Logstash to collect logs from all sources

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: logstash-config
  namespace: monitoring
data:
  logstash.yml: |
    pipeline:
      batch:
        size: 125
        delay: 5
    
    http.host: "0.0.0.0"
    http.port: 9600
  
  pipeline.conf: |
    input {
      # Kubernetes pod logs (via Fluentd)
      tcp {
        port => 5000
        codec => json
      }
      
      # Syslog from infrastructure
      syslog {
        port => 5514
        codec => plain
      }
    }
    
    filter {
      # Parse Kubernetes metadata
      mutate {
        add_field => { "[@metadata][index_name]" => "logs-%{+YYYY.MM.dd}" }
      }
      
      # Parse JSON if needed
      if [message] =~ /^\{/ {
        json {
          source => "message"
        }
      }
      
      # Extract timestamp
      date {
        match => [ "timestamp", "ISO8601" ]
        target => "@timestamp"
      }
      
      # Add environment tags
      mutate {
        add_tag => [ "prod", "k8s", "%{kubernetes_cluster}" ]
      }
    }
    
    output {
      # Send to Elasticsearch
      elasticsearch {
        hosts => ["elasticsearch:9200"]
        index => "%{[@metadata][index_name]}"
        document_type => "_doc"
      }
      
      # Debug output
      stdout { codec => rubydebug }
    }
EOF
```

### Kibana Dashboards

```
Kibana Dashboard 1: Log Analysis
├── Error logs by service
├── Exception traces
├── Log level distribution
└── High-volume log detection

Kibana Dashboard 2: Application Events
├── Login attempts (successful/failed)
├── User actions (pageviews, clicks)
├── API endpoint popularity
└── Performance events

Kibana Dashboard 3: Infrastructure
├── Container logs (restarts, crashes)
├── Kernel logs (OOM, IO errors)
├── Network events
└── Storage capacity warnings

Access: http://kibana:5601
```

---

## Alerting Rules

### Critical Alerts (P1 - Page on-call immediately)

```yaml
groups:
- name: production
  interval: 30s
  rules:
  # Cluster health
  - alert: KubernetesNodeNotReady
    expr: kube_node_status_condition{condition="Ready",status="true"} == 0
    for: 5m
    annotations:
      summary: "Kubernetes Node not ready"
      
  # Database
  - alert: PostgreSQLDown
    expr: pg_up == 0
    for: 1m
    annotations:
      summary: "PostgreSQL is down"
      
  - alert: PostgreSQLReplicationLag
    expr: pg_replication_slots_restart_lsn_bytes - pg_replication_slots_confirmed_flush_lsn_bytes > 1073741824
    for: 5m
    annotations:
      summary: "PostgreSQL replication lag > 1 GB"
      
  # Application
  - alert: HighErrorRate
    expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.05
    for: 5m
    annotations:
      summary: "Error rate > 5%"
      
  - alert: APILatencyHigh
    expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 1
    for: 10m
    annotations:
      summary: "API p95 latency > 1 second"
```

### High Alerts (P2 - Email + Slack)

```yaml
  - alert: HighMemoryUsage
    expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) > 0.85
    for: 10m
    
  - alert: HighCPUUsage
    expr: rate(node_cpu_seconds_total[5m]) > 0.80
    for: 10m
    
  - alert: DiskSpaceLow
    expr: (1 - (node_filesystem_avail_bytes / node_filesystem_size_bytes)) > 0.90
    for: 10m
    
  - alert: PodCrashLooping
    expr: rate(kube_pod_container_status_restarts_total[15m]) > 0.1
    for: 5m
```

---

## SLO/SLI Definitions

### Service Level Objectives (SLOs)

```
PROD Environment SLOs (Target: 99.9% uptime)

1. Availability SLO
   - Target: 99.9%
   - Calculation: (Seconds with error rate < 0.1%) / Total seconds
   - Measurement: Monthly (30 days = 43,200 minutes)
   - Error budget: 43.2 minutes downtime per month
   - Current: 99.95% (exceeding target ✓)

2. Response Time SLO
   - Target: p95 latency < 500ms
   - Calculation: Percentage of requests with latency < 500ms
   - Measurement: Hourly
   - Error budget: 5% of requests can be slower
   - Current: 98% of requests < 500ms (p95=245ms) ✓

3. Error Rate SLO
   - Target: < 0.1% of requests return 5xx
   - Calculation: 5xx errors / total requests
   - Measurement: Real-time
   - Error budget: 0.1% = 43.2 requests/minute in error (on 50k req/min traffic)
   - Current: 0.02% (well within budget ✓)

4. Data Durability SLO
   - Target: 99.999% (zero data loss)
   - Calculation: Successful backups / scheduled backups
   - Measurement: Daily
   - Error budget: 1 failed backup per 100,000 backups
   - Current: 100% (all backups succeeding ✓)
```

### Service Level Indicators (SLIs)

```
SLI 1: Request Success Rate
- Definition: (200-399 responses) / total requests
- Measurement: Prometheus http_requests_total counter
- Target: 99.9%
- Alert if: < 99.5% for 5 minutes

SLI 2: API Latency (p95)
- Definition: 95th percentile of request duration
- Measurement: Prometheus http_request_duration_seconds histogram
- Target: < 500ms
- Alert if: > 1000ms for 10 minutes

SLI 3: Database Availability
- Definition: PostgreSQL accepting connections
- Measurement: pg_up metric = 1
- Target: 99.99%
- Alert if: pg_up = 0 for > 1 minute

SLI 4: Replication Lag
- Definition: Bytes behind on replication
- Measurement: pg_replication_slots_restart_lsn_bytes - pg_replication_slots_confirmed_flush_lsn_bytes
- Target: < 50 MB
- Alert if: > 1 GB for > 5 minutes

SLI 5: Pod Restart Rate
- Definition: Container restarts per hour
- Measurement: kube_pod_container_status_restarts_total
- Target: < 1 restart/hour per pod
- Alert if: > 5 restarts in 1 hour
```

---

## Dashboards & Reporting

### Executive Dashboard (Weekly)

```
Metrics presented to stakeholders:
1. Uptime: 99.95% (target: 99.9%) ✓
2. Performance: p95 latency 245ms (target: 500ms) ✓
3. Errors: 0.02% error rate (target: 0.1%) ✓
4. Users: 45,000 active users this week
5. Revenue: $2.4M (0.1% higher than last week)
6. Incidents: 2 (both resolved < 1 hour)
```

### Technical Dashboard (Daily)

```
For DevOps/SRE team:
1. Resource Utilization
   - CPU: 32% (headroom: 68%)
   - Memory: 48% (headroom: 52%)
   - Storage: 45% (headroom: 55%)

2. Performance Trends
   - API latency trending down (good)
   - Error rate stable (good)
   - Throughput increasing with load

3. Top Issues
   - Memory leak in cache-service (monitoring)
   - Slow query in user search (optimize index)
   - Pod evictions on 2 nodes (OOMKilled)

4. Alerts
   - 3 active alerts
   - 12 resolved in last 24 hours
```

---

## Retention Policies

```
Prometheus Metrics:
├── High-resolution (30s): 15 days
├── 1-minute aggregation: 30 days
├── 1-hour aggregation: 1 year
└── Daily aggregation: 5 years (cold storage)

Elasticsearch Logs:
├── Real-time index: 7 days
├── Daily indices: 30 days (hot)
├── Archive indices: 90 days (warm)
└── Long-term retention: 1 year (cold storage / S3)

PostgreSQL WAL Files:
├── Active WAL: 7 days
├── Archived WAL: 30 days
├── Cold storage: 1 year (for PITR)

Application Logs:
├── Container logs: 30 days (in Kubernetes)
├── Fluentd forwarding: Real-time → ELK
└── ELK retention: 30 days (hot), 90 days (archive)
```

---

**Reference**: [00-VxRail-Complete-Index.md](./00-VxRail-Complete-Index.md), [12-Cutover-Runbook.md](./12-Cutover-Runbook.md)

