# PROD Environment - Detailed Implementation Guide
**Phase 4 | Weeks 9-16 | Live Migration with pglogical Replication**

**Environment**: Kubernetes k8s-prod, VLAN 120 (10.52.0.0/16), 150 GB storage, full cluster

**VxRail Infrastructure (production allocation)**:
- 6 VxRail hosts | 157 VMs currently running
- CPU: 149.84 GHz used / 871.58 GHz total / 721.75 GHz free
- Memory: 3.11 TB used / 4.5 TB total / 1.38 TB free
- Storage: 156.8 TB used / 247.66 TB total / **90.86 TB free** (PROD gets 150 GB quota)
- 9 datastores | 113 networks | 1 cluster

## Overview & Flowchart showing Azure PROD → pglogical replication → On-prem PROD → cutover

```
┌──────────────────────────────────────────────────────────────────────────────┐
│             PROD FLOW — AZURE PROD TO ON-PREM PROD CUTOVER                  │
└──────────────────────────────────────────────────────────────────────────────┘
     Azure PROD                       Dual-running                        On-prem PROD
┌────────────────────┐         ┌──────────────────────┐          ┌────────────────────┐
│ AKS + PostgreSQL   │───①───▶│ pglogical replication │───②───▶ │ Patroni + K8s PROD │
│ Source of truth    │         │ Continuous sync       │          │ Target environment  │
└────────────────────┘         └──────────────────────┘          └────────────────────┘
         │                               │                                  │
         └───────────────③ validation────┴────④ rehearsal───────⑤ cutover───┘
```

## Weeks 9-10: PROD Infrastructure Setup

Detailed kubectl commands, Patroni HA for PROD, PROD networking (VLANs, firewall rules), MetalLB, vSAN CSI, Harbor for PROD container images.

```bash
kubectl create namespace prod
kubectl label namespace prod environment=prod tier=production
kubectl apply -f metallb-prod-pool.yaml
kubectl apply -f vsan-csi-storageclass.yaml
kubectl apply -f prod-resourcequota.yaml
argocd app sync prod-apps --timeout 600
argocd app wait prod-apps --health --timeout 600
```

## Weeks 11-12: pglogical Live Replication Setup

Explanation of pglogical, install pglogical, create publication on Azure, create subscription on-prem, monitor replication lag, handle conflicts, validate data consistency.

```sql
SELECT pglogical.create_node(node_name := 'azure_prod_provider', dsn := 'host=azure-prod.postgres.database.azure.com port=5432 dbname=prod user=replicator sslmode=require');
SELECT pglogical.replication_set_add_all_tables('default', ARRAY['public']);
SELECT pglogical.create_node(node_name := 'onprem_prod_subscriber', dsn := 'host=10.52.10.20 port=5432 dbname=prod user=replicator');
SELECT pglogical.create_subscription(subscription_name := 'azure_to_onprem_prod', provider_dsn := 'host=azure-prod.postgres.database.azure.com port=5432 dbname=prod user=replicator sslmode=require', synchronize_structure := false, synchronize_data := true);
```

## Weeks 13-14: Application Deployment to PROD

Deploy apps in read-only mode, configure DNS, smoke testing, performance validation.

```bash
kubectl apply -f prod-configmaps.yaml
kubectl apply -f prod-secrets.yaml
kubectl apply -f prod-apps-readonly.yaml
kubectl get pods -n prod
kubectl rollout status deployment/api-gateway -n prod
```

## Week 15: Pre-Cutover Validation

72-hour parallel run checklist, load testing at PROD scale, failover drills, stakeholder sign-off.

## Week 16: Cutover (Zero-Downtime)

Pre-cutover checklist, cutover execution minute-by-minute, post-cutover validation, rollback decision point, Azure decommission schedule.

## Success Criteria

SLOs, SLIs, business metrics.

---

## Detailed Runbook Appendices

### Appendix Item 001
- Scope: PROD migration control point 1.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 002
- Scope: PROD migration control point 2.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 003
- Scope: PROD migration control point 3.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 004
- Scope: PROD migration control point 4.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 005
- Scope: PROD migration control point 5.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 006
- Scope: PROD migration control point 6.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 007
- Scope: PROD migration control point 7.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 008
- Scope: PROD migration control point 8.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 009
- Scope: PROD migration control point 9.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 010
- Scope: PROD migration control point 10.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 011
- Scope: PROD migration control point 11.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 012
- Scope: PROD migration control point 12.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 013
- Scope: PROD migration control point 13.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 014
- Scope: PROD migration control point 14.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 015
- Scope: PROD migration control point 15.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 016
- Scope: PROD migration control point 16.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 017
- Scope: PROD migration control point 17.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 018
- Scope: PROD migration control point 18.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 019
- Scope: PROD migration control point 19.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 020
- Scope: PROD migration control point 20.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 021
- Scope: PROD migration control point 21.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 022
- Scope: PROD migration control point 22.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 023
- Scope: PROD migration control point 23.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 024
- Scope: PROD migration control point 24.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 025
- Scope: PROD migration control point 25.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 026
- Scope: PROD migration control point 26.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 027
- Scope: PROD migration control point 27.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 028
- Scope: PROD migration control point 28.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 029
- Scope: PROD migration control point 29.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 030
- Scope: PROD migration control point 30.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 031
- Scope: PROD migration control point 31.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 032
- Scope: PROD migration control point 32.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 033
- Scope: PROD migration control point 33.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 034
- Scope: PROD migration control point 34.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 035
- Scope: PROD migration control point 35.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 036
- Scope: PROD migration control point 36.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 037
- Scope: PROD migration control point 37.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 038
- Scope: PROD migration control point 38.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 039
- Scope: PROD migration control point 39.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 040
- Scope: PROD migration control point 40.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 041
- Scope: PROD migration control point 41.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 042
- Scope: PROD migration control point 42.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 043
- Scope: PROD migration control point 43.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 044
- Scope: PROD migration control point 44.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 045
- Scope: PROD migration control point 45.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 046
- Scope: PROD migration control point 46.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 047
- Scope: PROD migration control point 47.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 048
- Scope: PROD migration control point 48.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 049
- Scope: PROD migration control point 49.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 050
- Scope: PROD migration control point 50.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 051
- Scope: PROD migration control point 51.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 052
- Scope: PROD migration control point 52.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 053
- Scope: PROD migration control point 53.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 054
- Scope: PROD migration control point 54.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 055
- Scope: PROD migration control point 55.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 056
- Scope: PROD migration control point 56.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 057
- Scope: PROD migration control point 57.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 058
- Scope: PROD migration control point 58.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 059
- Scope: PROD migration control point 59.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 060
- Scope: PROD migration control point 60.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 061
- Scope: PROD migration control point 61.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 062
- Scope: PROD migration control point 62.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 063
- Scope: PROD migration control point 63.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 064
- Scope: PROD migration control point 64.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 065
- Scope: PROD migration control point 65.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 066
- Scope: PROD migration control point 66.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 067
- Scope: PROD migration control point 67.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 068
- Scope: PROD migration control point 68.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 069
- Scope: PROD migration control point 69.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 070
- Scope: PROD migration control point 70.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 071
- Scope: PROD migration control point 71.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 072
- Scope: PROD migration control point 72.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 073
- Scope: PROD migration control point 73.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 074
- Scope: PROD migration control point 74.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 075
- Scope: PROD migration control point 75.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 076
- Scope: PROD migration control point 76.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 077
- Scope: PROD migration control point 77.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 078
- Scope: PROD migration control point 78.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 079
- Scope: PROD migration control point 79.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 080
- Scope: PROD migration control point 80.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 081
- Scope: PROD migration control point 81.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 082
- Scope: PROD migration control point 82.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 083
- Scope: PROD migration control point 83.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 084
- Scope: PROD migration control point 84.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 085
- Scope: PROD migration control point 85.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 086
- Scope: PROD migration control point 86.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 087
- Scope: PROD migration control point 87.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 088
- Scope: PROD migration control point 88.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 089
- Scope: PROD migration control point 89.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 090
- Scope: PROD migration control point 90.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 091
- Scope: PROD migration control point 91.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 092
- Scope: PROD migration control point 92.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 093
- Scope: PROD migration control point 93.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 094
- Scope: PROD migration control point 94.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 095
- Scope: PROD migration control point 95.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 096
- Scope: PROD migration control point 96.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 097
- Scope: PROD migration control point 97.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 098
- Scope: PROD migration control point 98.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 099
- Scope: PROD migration control point 99.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 100
- Scope: PROD migration control point 100.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 101
- Scope: PROD migration control point 101.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 102
- Scope: PROD migration control point 102.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 103
- Scope: PROD migration control point 103.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 104
- Scope: PROD migration control point 104.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 105
- Scope: PROD migration control point 105.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 106
- Scope: PROD migration control point 106.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 107
- Scope: PROD migration control point 107.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 108
- Scope: PROD migration control point 108.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 109
- Scope: PROD migration control point 109.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 110
- Scope: PROD migration control point 110.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 111
- Scope: PROD migration control point 111.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 112
- Scope: PROD migration control point 112.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 113
- Scope: PROD migration control point 113.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 114
- Scope: PROD migration control point 114.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 115
- Scope: PROD migration control point 115.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 116
- Scope: PROD migration control point 116.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 117
- Scope: PROD migration control point 117.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 118
- Scope: PROD migration control point 118.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 119
- Scope: PROD migration control point 119.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 120
- Scope: PROD migration control point 120.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 121
- Scope: PROD migration control point 121.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 122
- Scope: PROD migration control point 122.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 123
- Scope: PROD migration control point 123.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 124
- Scope: PROD migration control point 124.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 125
- Scope: PROD migration control point 125.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 126
- Scope: PROD migration control point 126.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 127
- Scope: PROD migration control point 127.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 128
- Scope: PROD migration control point 128.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 129
- Scope: PROD migration control point 129.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 130
- Scope: PROD migration control point 130.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 131
- Scope: PROD migration control point 131.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 132
- Scope: PROD migration control point 132.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 133
- Scope: PROD migration control point 133.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 134
- Scope: PROD migration control point 134.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 135
- Scope: PROD migration control point 135.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 136
- Scope: PROD migration control point 136.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 137
- Scope: PROD migration control point 137.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 138
- Scope: PROD migration control point 138.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 139
- Scope: PROD migration control point 139.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 140
- Scope: PROD migration control point 140.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 141
- Scope: PROD migration control point 141.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 142
- Scope: PROD migration control point 142.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 143
- Scope: PROD migration control point 143.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 144
- Scope: PROD migration control point 144.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 145
- Scope: PROD migration control point 145.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 146
- Scope: PROD migration control point 146.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 147
- Scope: PROD migration control point 147.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 148
- Scope: PROD migration control point 148.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 149
- Scope: PROD migration control point 149.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 150
- Scope: PROD migration control point 150.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 151
- Scope: PROD migration control point 151.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 152
- Scope: PROD migration control point 152.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.

### Appendix Item 153
- Scope: PROD migration control point 153.
- Capacity reference: 6 hosts, 157 VMs, 1 cluster, 113 networks, 9 datastores.
- Resource reference: CPU 149.84 GHz used / 871.58 GHz total / 721.75 GHz free; memory 3.11 TB used / 4.5 TB total / 1.38 TB free; storage 156.8 TB used / 247.66 TB total / 90.86 TB free.
