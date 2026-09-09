$ErrorActionPreference = 'Stop'
$out = Join-Path $PSScriptRoot '..\deliverables\Azure-OnPrem-Cost-Comparison-2026.docx'
$word = New-Object -ComObject Word.Application
$word.Visible = $false
$doc = $word.Documents.Add()
$sel = $word.Selection

function Add-Text([string]$text) { $sel.TypeText($text); $sel.TypeParagraph() }
function Add-Heading([string]$text, [int]$level) { $sel.Style = "Heading $level"; Add-Text $text; $sel.Style = 'Normal' }
function Add-Table([string[]]$headers, [object[][]]$rows) {
    $table = $doc.Tables.Add($sel.Range, $rows.Count + 1, $headers.Count)
    $table.Style = 'Table Grid'
    for ($column = 0; $column -lt $headers.Count; $column++) { $table.Cell(1, $column + 1).Range.Text = $headers[$column] }
    for ($row = 0; $row -lt $rows.Count; $row++) {
        for ($column = 0; $column -lt $headers.Count; $column++) { $table.Cell($row + 2, $column + 1).Range.Text = [string]$rows[$row][$column] }
    }
    $sel.SetRange($table.Range.End, $table.Range.End)
    $sel.TypeParagraph()
}

try {
    $sel.Style = 'Title'; Add-Text 'Azure vs On-Premises Cost Comparison - 2026'; $sel.Style = 'Normal'
    Add-Text 'Prepared: 2026-09-09'
    Add-Text 'Source workbook: DI_Cost_Optimization_2026.xlsx'
    Add-Text 'Scope: Azure resources represented in the workbook and the existing six-node Dell VxRail target'

    Add-Heading 'Executive Summary' 1
    Add-Text 'The workbook Cost Summary sheet reports $23,754 for the last month, or $285,048 annualized. The resource-detail rows visible in the workbook total $9,011 and are an optimization worklist, not a complete bill reconciliation. This document uses $23,754/month as the Azure baseline.'
    Add-Text 'The repository treats the six-node VxRail cluster, vSphere/vCenter, existing Veeam deployment, and TOR switching as existing assets. Incremental on-premises procurement is estimated at $20,000-$45,000 one time, plus $3,600-$19,300/year for optional licensing and support. Migration labor, taxes, facilities, staffing, and hardware support are excluded.'

    Add-Heading 'Current Azure Cost' 1
    Add-Table @('Subscription','Last month','Annualized') @(
        @('Sub-APP-ServerLess-WE','$49','$588'), @('Sub-ACRPS-AE-WE','$5,593','$67,116'), @('Sub-ACRPS-DRU-WE','$5,817','$69,804'),
        @('Sub-DI-Backup-WE','$3,121','$37,452'), @('Sub-DI-DR-WE','$4,302','$51,624'), @('Sub-DI-HUB-WE','$4,475','$53,700'),
        @('Sub-DI-VLAB-WE','$397','$4,764'), @('TOTAL','$23,754','$285,048'))
    Add-Text 'The visible resource-detail subtotal is $9,011/month. The difference from the subscription total means the detail sheet is incomplete; it must not replace the Cost Summary total.'
    Add-Text 'Key workbook actions: reconcile against Azure Cost Management, configure Kubernetes autoscaling, validate and remove the unused QA container instance, apply lifecycle policies to the 8 TB, 4 TB, and 65 TB storage accounts, and review the 2 TB disk.'

    Add-Heading 'On-Premises Resource Requirements' 1
    Add-Table @('Azure capability','On-premises equivalent','Sizing / notes') @(
        @('AKS','Kubernetes on VMware VMs with kubeadm, Calico, and shared control plane','Repository target: 3 control-plane VMs plus 15 worker VMs; workbook shows 16 worker nodes, so validate final count.'),
        @('Azure PostgreSQL','PostgreSQL 15 with Patroni and HAProxy/Keepalived','QA 1 VM; PREPROD 3 VMs; PROD 3 VMs.'),
        @('Cosmos DB','MongoDB-compatible service on VMs','Three-member production replica set; non-prod after compatibility testing.'),
        @('ACR','Harbor registry','Two or three registry VMs or HA deployment on Kubernetes.'),
        @('Storage Accounts','vSAN plus MinIO and NFS/SMB where required','Size using data footprint and retention policy.'),
        @('Azure Backup / Veeam','Existing Veeam with dedicated NAS repository','40-60 TB usable repository planning range.'),
        @('Azure Monitor','Prometheus, Grafana, Loki or ELK, Alertmanager','Persistent monitoring and log retention storage.'),
        @('Load Balancer','MetalLB plus existing firewall or load balancer','Redundant ingress for all environments.'),
        @('VNet / VPN / NSGs','Distributed switches, VLANs, firewall zones, site-to-site VPN','Confirm management, vMotion, vSAN, Kubernetes, database, backup, and ingress networks.'),
        @('Bastion','Hardened jump host or existing privileged access platform','MFA and session logging required.'))

    Add-Heading 'On-Premises One-Time Procurement' 1
    Add-Table @('Item','Low','High') @(
        @('NAS / backup repository and disks','$5,000','$12,000'),
        @('Additional TOR switching if required','$15,000','$25,000'),
        @('Hardware VPN appliance, optional','$0','$8,000'),
        @('TOTAL','$20,000','$45,000'))
    Add-Text 'A practical approval envelope is approximately $47,000-$50,000 after 5-10% contingency for optics, cabling, rails, and installation.'

    Add-Heading 'On-Premises Annual Incremental Cost' 1
    Add-Table @('Item','Low','High') @(
        @('Oracle Linux Premier subscriptions','$0','$13,000'), @('Veeam workload add-on','$3,600','$6,000'), @('Public TLS certificates','$0','$300'), @('TOTAL','$3,600','$19,300'))
    Add-Text 'This is $300-$1,608/month excluding shared VxRail platform, power/cooling, hardware support, staffing, and migration labor. If existing Veeam and Oracle Linux entitlements cover the migrated workloads, incremental annual software cost can be close to $0.'

    Add-Heading 'Three-Year View' 1
    Add-Table @('Scenario','Three-year cost','Notes') @(
        @('Low incremental','$30,800','$20,000 one-time + 3 x $3,600 recurring'),
        @('High incremental','$102,900','$45,000 one-time + 3 x $19,300 recurring'),
        @('High with 10% procurement contingency','$107,400','$49,500 one-time + 3 x $19,300 recurring'),
        @('Azure baseline','$855,144','$23,754/month x 36 months'))

    Add-Heading 'Kubernetes Platform Options' 1
    Add-Text 'The comparison uses the repository target of 18 Kubernetes VMs: 3 control-plane VMs plus 15 worker VMs across QA, PREPROD, and PROD. The workbook shows 16 AKS worker nodes across its entries, so confirm the final node count and CPU entitlement before requesting quotes. Prices below are 2026 budgetary planning ranges in USD, not vendor quotations.'
    Add-Table @('Option','Annual platform support','Implementation','Three-year incremental TCO') @(
        @('Red Hat OpenShift','$90,000-$180,000','$60,000-$120,000','$300,800-$643,900'),
        @('SUSE Rancher Prime','$35,000-$90,000','$35,000-$75,000','$170,800-$449,900'),
        @('Canonical Kubernetes','$18,000-$55,000','$25,000-$60,000','$155,800-$342,900'))
    Add-Text 'OpenShift is the highest-cost option and should be selected when Red Hat support, certified operators, compliance, or an existing enterprise agreement justify the premium. Rancher Prime is the middle option for centralized multi-cluster management. Canonical Kubernetes has the lowest commercial platform cost, but shifts more lifecycle and Linux/Kubernetes expertise to the internal team.'
    Add-Text 'The three-year platform TCO includes $20,000-$45,000 common infrastructure procurement, platform implementation, three years of common recurring items, and platform subscription/support. It excludes personnel, VxRail depreciation, facilities, and application remediation. Add a local loaded staffing allowance; a planning range of $75,000-$180,000 per platform FTE/year is reasonable for budgeting, subject to local compensation and coverage requirements.'

    Add-Heading 'Capacity Risks and Next Actions' 1
    Add-Text 'The repository reports 90.86 TB free vSAN capacity and 1.38 TB free memory. Its full target design calculates approximately 2.1 TB RAM, so memory is the controlling capacity risk. Validate VxRail headroom, worker count, Veeam entitlements, Oracle Linux subscriptions, and network port capacity before approval.'
    Add-Text 'Next: reconcile the workbook to an Azure Cost Management export, obtain quotes for NAS and switching, validate database compatibility, and add facilities, support, staffing, depreciation, and migration labor to the final TCO.'
    $doc.SaveAs2((Resolve-Path $out), 16)
} finally {
    if ($doc) { $doc.Close() }
    if ($word) { $word.Quit() }
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}