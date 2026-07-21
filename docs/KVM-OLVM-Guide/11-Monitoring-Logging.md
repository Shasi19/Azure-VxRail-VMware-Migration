# 11 — Monitoring and Logging

> Full observability stack for KVM hosts, OLVM engine, VMs, and Kubernetes: Prometheus, Grafana, ELK, QEMU guest agent metrics, libvirt-exporter, and OLVM Data Warehouse.

---

## What to Monitor

| Layer | Key Metrics | Tool |
|-------|-------------|------|
| KVM Host | CPU steal, memory, disk I/O, NIC throughput | node_exporter |
| KVM/libvirt | VM CPU%, VM memory, VM disk IOPS, VM network | libvirt_exporter |
| OLVM Engine | Host health, VM states, storage domain usage | OLVM DWH + Grafana |
| Kubernetes | Pod status, node resource, API latency | kube-prometheus-stack |
| Databases | PG replication lag, MongoDB RS health, connections | postgres_exporter, mongodb_exporter |
| Applications | HTTP error rate, latency, request rate | Prometheus scrape / Jaeger |

---

## 1. Prometheus node_exporter (KVM Hosts and VMs)

Install on **every KVM host** and **every VM**:

```bash
# Download node_exporter
ARCH=linux-amd64
VERSION=1.8.0
wget https://github.com/prometheus/node_exporter/releases/download/v${VERSION}/node_exporter-${VERSION}.${ARCH}.tar.gz
tar xvf node_exporter-*.tar.gz
mv node_exporter-*/node_exporter /usr/local/bin/
chmod +x /usr/local/bin/node_exporter

# Create systemd service
cat > /etc/systemd/system/node-exporter.service << 'EOF'
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
User=nobody
ExecStart=/usr/local/bin/node_exporter \
  --collector.systemd \
  --collector.processes \
  --collector.tcpstat \
  --collector.meminfo_numa \
  --web.listen-address=0.0.0.0:9100 \
  --web.telemetry-path=/metrics

Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now node-exporter

# Verify
curl -s http://localhost:9100/metrics | head -20
```

### Key KVM Host Metrics to Alert On

```yaml
# Prometheus alert rules for KVM hosts
# /etc/prometheus/rules/kvm-alerts.yaml

groups:
- name: kvm-host
  rules:
  - alert: HighCPUSteal
    expr: rate(node_cpu_seconds_total{mode="steal"}[5m]) > 0.05
    for: 10m
    labels:
      severity: warning
    annotations:
      summary: "High CPU steal time on {{ $labels.instance }}"
      description: "CPU steal is {{ $value | humanizePercentage }} — host may be overloaded"

  - alert: LowMemoryFree
    expr: (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) < 0.1
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "Low memory on {{ $labels.instance }}"
      description: "Only {{ $value | humanizePercentage }} memory available"

  - alert: DiskSpaceWarning
    expr: (node_filesystem_avail_bytes{fstype!="tmpfs"} / node_filesystem_size_bytes) < 0.2
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Disk space low on {{ $labels.instance }}:{{ $labels.mountpoint }}"

  - alert: NfsUnreachable
    expr: node_filesystem_avail_bytes{fstype="nfs4"} == 0
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "NFS not mounted on {{ $labels.instance }}"
```

---

## 2. libvirt-exporter (KVM VM Metrics)

Exposes per-VM CPU, memory, disk I/O, and network metrics to Prometheus.

```bash
# Install libvirt exporter
pip3 install prometheus-libvirt-exporter
# OR install binary:
wget https://github.com/zhangjianweibj/prometheus-libvirt-exporter/releases/latest/download/prometheus-libvirt-exporter
chmod +x prometheus-libvirt-exporter
mv prometheus-libvirt-exporter /usr/local/bin/

# Create service
cat > /etc/systemd/system/libvirt-exporter.service << 'EOF'
[Unit]
Description=Prometheus libvirt Exporter
After=network.target libvirtd.service

[Service]
User=root
ExecStart=/usr/local/bin/prometheus-libvirt-exporter \
  --libvirt.uri=qemu:///system \
  --web.listen-address=0.0.0.0:9177 \
  --web.telemetry-path=/metrics
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl enable --now libvirt-exporter
curl -s http://localhost:9177/metrics | grep libvirt_ | head -20
```

### Useful libvirt Prometheus Queries

```promql
# CPU usage per VM (seconds/second across all vCPUs)
rate(libvirt_domain_info_cpu_time_seconds_total[5m])

# Memory allocated vs maximum
libvirt_domain_info_maximum_memory_bytes - libvirt_domain_info_memory_usage_bytes

# Disk read IOPS per VM
rate(libvirt_domain_block_stats_read_requests_total[5m])

# Network bytes received per VM
rate(libvirt_domain_interface_stats_receive_bytes_total[5m])

# Which VMs are not running
libvirt_domain_info_vstate != 1   # 1=running, 3=paused, 5=shutoff
```

---

## 3. OLVM Data Warehouse (DWH) + Grafana

OLVM includes a Data Warehouse (DWH) component that stores historical metrics in PostgreSQL. It ships with a built-in Grafana integration.

```bash
# Verify DWH is installed and running
systemctl status ovirt-engine-dwhd

# Check DWH database
su - postgres -c "psql -d ovirt_engine_history -c '\dt' | head -20"

# Enable Grafana integration (if not done during engine-setup)
engine-setup --reconfigure-optional-components
# Answer: Configure Grafana on this host: Yes

# Grafana will be available at:
# https://olvm-engine.internal/ovirt-engine-grafana/
# Login: admin / admin (change immediately)

echo "OLVM Grafana: https://olvm-engine.internal/ovirt-engine-grafana/"
```

### OLVM Built-in Grafana Dashboards

```
Screenshot: Navigate to https://olvm-engine.internal/ovirt-engine-grafana/

Available pre-built dashboards:
  - Executive Summary      — high-level cluster health
  - Cluster Capacity       — CPU/RAM utilisation across hosts
  - VM Performance         — per-VM CPU, memory, disk trend
  - Storage Domain Usage   — storage utilisation over time
  - Host Performance       — per-host metrics
  - Top Utilized VMs       — identify VMs consuming most resources
```

---

## 4. kube-prometheus-stack (K8s Monitoring)

```bash
# Add Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

kubectl create namespace monitoring

cat > /tmp/prom-values.yaml << 'EOF'
grafana:
  enabled: true
  adminPassword: Grafana-KVM-2026!
  service:
    type: LoadBalancer
    loadBalancerIP: 10.0.2.13
  persistence:
    enabled: true
    storageClassName: netapp-nfs
    size: 10Gi
  # Import KVM-specific dashboards
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: 'default'
          folder: 'KVM-OnPrem'
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
    # Scrape KVM hosts and VMs (external to K8s)
    additionalScrapeConfigs:
      - job_name: kvm-hosts
        static_configs:
          - targets:
              - 10.0.1.11:9100    # kvm-host-01 node_exporter
              - 10.0.1.12:9100    # kvm-host-02
              - 10.0.1.13:9100    # kvm-host-03
        labels:
          role: kvm-host
      - job_name: libvirt
        static_configs:
          - targets:
              - 10.0.1.11:9177    # kvm-host-01 libvirt-exporter
              - 10.0.1.12:9177
              - 10.0.1.13:9177
      - job_name: postgresql
        static_configs:
          - targets:
              - 10.0.1.30:9187
              - 10.0.1.31:9187
              - 10.0.1.32:9187
      - job_name: mongodb
        static_configs:
          - targets:
              - 10.0.1.30:9216
              - 10.0.1.31:9216
              - 10.0.1.32:9216
EOF

helm install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values /tmp/prom-values.yaml

kubectl get pods -n monitoring
```

### Import Grafana Dashboards

```
Screenshot: In Grafana UI > + > Import

Import these dashboard IDs:
  1860  — Node Exporter Full (host metrics)
  315   — Kubernetes cluster monitoring
  7249  — Kubernetes Deployment metrics
  14694 — PostgreSQL Prometheus Exporter
  7362  — MongoDB Exporter
  12175 — libvirt exporter dashboard

Click Import for each
```

---

## 5. ELK Stack for Logs

```bash
# Install ELK in K8s (see OnPrem-KVM/08-Observability-Security.md for full setup)
# Here: configure Filebeat to capture KVM host logs

# Install Filebeat on KVM hosts
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add -
echo "deb https://artifacts.elastic.co/packages/8.x/apt stable main" \
  > /etc/apt/sources.list.d/elastic-8.x.list
apt update && apt install -y filebeat

cat > /etc/filebeat/filebeat.yml << 'EOF'
filebeat.inputs:
  # libvirt main log
  - type: log
    enabled: true
    paths:
      - /var/log/libvirt/libvirtd.log
    fields:
      log_type: libvirt
      host_role: kvm-host

  # QEMU per-VM logs
  - type: log
    enabled: true
    paths:
      - /var/log/libvirt/qemu/*.log
    fields:
      log_type: qemu
      host_role: kvm-host
    multiline.pattern: '^\d{4}-\d{2}-\d{2}'
    multiline.negate: true
    multiline.match: after

  # System logs
  - type: log
    enabled: true
    paths:
      - /var/log/messages
      - /var/log/syslog
    fields:
      log_type: system

output.elasticsearch:
  hosts: ["elasticsearch-master.logging.svc.cluster.local:9200"]
  index: "kvm-logs-%{[fields.host_role]}-%{+yyyy.MM.dd}"

processors:
  - add_host_metadata: ~
  - add_fields:
      target: host
      fields:
        kvm_host: "{{ inventory_hostname }}"
EOF

systemctl enable --now filebeat
```

---

## 6. QEMU Guest Agent Metrics

```bash
# Get VM stats via guest agent (from KVM host)
# Requires qemu-guest-agent installed inside VM

# Get memory stats inside VM
virsh qemu-agent-command k8s-cp-01 '{"execute":"guest-get-memory-block-info"}'

# Get network interfaces from VM (useful when DHCP is not used)
virsh domifaddr k8s-cp-01 --source agent
# Shows actual IP addresses visible inside the VM

# Get disk usage inside VM
virsh qemu-agent-command k8s-cp-01 \
  '{"execute":"guest-get-fsinfo"}' | python3 -m json.tool

# Get OS info
virsh guestinfo k8s-cp-01
# Shows: os.name, os.kernel, hostname, timezone, uptime

# Freeze filesystems before snapshot (application-consistent)
virsh domfsfreeze k8s-cp-01
# Snapshot here
virsh snapshot-create-as k8s-cp-01 consistent-snap --disk-only --atomic
# Thaw
virsh domfsthaw k8s-cp-01
```

---

## 7. Alertmanager Configuration

```bash
kubectl create secret generic alertmanager-kvm-config \
  --namespace monitoring \
  --from-literal=alertmanager.yaml='
global:
  resolve_timeout: 5m
  slack_api_url: "https://hooks.slack.com/services/YOUR/WEBHOOK"

route:
  group_by: [alertname, job, instance]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: default
  routes:
    - match: {severity: critical}
      receiver: pagerduty
    - match: {role: kvm-host}
      receiver: infra-team
    - match: {namespace: prod}
      receiver: prod-team

receivers:
  - name: default
    slack_configs:
      - channel: "#alerts"
        title: "{{ .GroupLabels.alertname }}"
        text: |
          {{ range .Alerts }}
          *Host*: {{ .Labels.instance }}
          *Description*: {{ .Annotations.description }}
          {{ end }}

  - name: prod-team
    slack_configs:
      - channel: "#prod-oncall"
    email_configs:
      - to: oncall@company.com
        from: alerts@company.com
        smarthost: smtp.company.com:587
'
```

---

## 8. Log Retention and Rotation

```bash
# Libvirt log rotation
cat > /etc/logrotate.d/libvirt << 'EOF'
/var/log/libvirt/*.log {
  weekly
  rotate 8
  compress
  delaycompress
  missingok
  notifempty
  sharedscripts
  postrotate
    systemctl reload libvirtd 2>/dev/null || true
  endscript
}

/var/log/libvirt/qemu/*.log {
  weekly
  rotate 4
  compress
  delaycompress
  missingok
  notifempty
}
EOF

# ELK index lifecycle (auto-delete old indices)
# In Kibana > Stack Management > Index Lifecycle Policies:
# Create policy "kvm-logs-policy":
#   Hot phase: max age 7d
#   Warm phase: 7d-30d (force merge, shrink)
#   Delete phase: after 90d
```

---

## Troubleshooting Monitoring

| Symptom | Cause | Fix |
|---------|-------|-----|
| node_exporter port 9100 not accessible | Firewall blocking | `firewall-cmd --add-port=9100/tcp --permanent; firewall-cmd --reload` |
| libvirt_exporter no metrics | libvirtd not running | `systemctl restart libvirtd` then restart exporter |
| OLVM DWH data missing | DWH service stopped | `systemctl start ovirt-engine-dwhd` |
| Grafana shows no data | Prometheus scrape fails | Check `http://prometheus:9090/targets` for errors |
| Filebeat not sending logs | ES unreachable | `curl http://elasticsearch:9200/_cluster/health` |
| ELK index not created | Wrong index name | Check Filebeat output in `/var/log/filebeat/filebeat.log` |
| Alert not firing | Alertmanager config error | `kubectl logs -n monitoring alertmanager-0 -c alertmanager` |

---

*Next: [12-Backup-Recovery.md](12-Backup-Recovery.md)*
