$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$out = Join-Path $root 'deliverables\OnPrem-VxRail-TCO-2026-V3.docx'
$assetRoot = Join-Path $root 'docs\Azure-VxRail-VMware-Migration\assets'
$word = New-Object -ComObject Word.Application
$word.Visible = $false
$doc = $word.Documents.Add()
$selection = $word.Selection
function AddText([string]$value) { $selection.TypeText($value); $selection.TypeParagraph() }
function AddHeading([string]$value, [int]$level) { $selection.Style = "Heading $level"; AddText $value; $selection.Style = 'Normal' }
function AddPicture([string]$fileName) { $shape = $selection.InlineShapes.AddPicture((Join-Path $assetRoot $fileName), $false, $true); $shape.Width = 500; $selection.TypeParagraph() }
try {
    $selection.Style = 'Title'; AddText 'On-Premises Dell VxRail TCO and Operations'; $selection.Style = 'Normal'
    AddText 'V3 | Prepared 2026-09-09 | Full new-cluster purchase model'
    AddHeading 'Executive Decision' 1
    AddText 'If a new six-node Dell VxRail cluster must be purchased, on-premises is not automatically cheaper than the current Azure bill. Budget $1.04M-$2.39M initially, $390k-$980k annually, and $2.39M-$5.75M over three years including migration.'
    AddText 'With a new purchase, Azure is the best immediate financial and operational choice. On-premises is justified when sovereignty, latency, regulatory control, or an already-funded datacenter strategy has value beyond the cost comparison.'
    AddPicture 'onprem-tco-bars.svg'
    AddHeading 'Target Architecture' 1
    AddText 'Six Dell VxRail nodes with N+1 capacity; VMware vSphere/vCenter; three Kubernetes control-plane VMs and 15 workers; PostgreSQL Patroni HA; Mongo-compatible replica set; Harbor; ArgoCD; Prometheus/Grafana; logging; Veeam; 40-60 TB backup repository; redundant TOR switching; immutable offsite backup.'
    AddHeading 'Full Acquisition Budget' 1
    AddText 'VxRail nodes: $600k-$1.2M. VMware/vSphere licensing: $150k-$400k. TOR switching and optics: $50k-$120k. Backup repository: $25k-$80k. Firewall/VPN/load balancing: $30k-$100k. Rack, UPS, PDUs, and power: $50k-$150k. Commissioning and spares: $40k-$120k. Initial subtotal: $945k-$2.17M. Recommended approval envelope with contingency: $1.04M-$2.39M.'
    AddHeading 'Annual Operating Cost' 1
    AddText 'Hardware support: $60k-$150k. VMware support: $50k-$150k. Power and cooling: $35k-$90k. Backup and offsite DR: $25k-$75k. OS/security/platform support: $25k-$75k. Operations staffing: $180k-$400k. Refresh reserve: $15k-$40k. Fully loaded annual total: $390k-$980k.'
    AddPicture 'onprem-operating-model.svg'
    AddHeading 'Operational Effort' 1
    AddText 'Monthly OS patching requires approximately 3-6 engineer-days. Kubernetes upgrades require 5-10 engineer-days per quarter. VxRail and vSphere lifecycle work requires 3-8 engineer-days per maintenance window. Database patching, failover, backup checks, restore tests, certificate rotation, vulnerability remediation, capacity reviews, incidents, and on-call coverage must be planned continuously.'
    AddText 'Two FTE is a minimum shared-service model. Three to four FTE is more realistic for 24x7 production ownership across VMware, Linux/Kubernetes, DBA, backup, security, and on-call responsibilities.'
    AddHeading 'Migration Effort' 1
    AddText 'Discovery and design: $25k-$50k. Platform and network build: $45k-$100k. QA: $20k-$45k. PREPROD: $30k-$65k. PROD replication, canary, cutover, and hypercare: $50k-$120k. Project governance and security: $10k-$40k. Total: $180k-$420k over approximately 20-28 weeks.'
    AddHeading 'Three-Year Comparison' 1
    AddText 'Azure current bill: $855,144 over three years. New VxRail low case: $2.39M. New VxRail high case: $5.75M. Azure is the lower-cost immediate option; on-premises requires a strategic justification or already-funded assets.'
    AddHeading 'Final Recommendation' 1
    AddText 'Remain on Azure and optimize first. Approve an on-premises purchase only after Dell/Broadcom quotes, facilities capacity, 2-4 FTE ownership, VxRail memory headroom, database compatibility, immutable offsite DR, and a complete three-year TCO are approved.'
    $doc.SaveAs2($out, 16)
} finally {
    if ($doc) { $doc.Close() }
    if ($word) { $word.Quit() }
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}