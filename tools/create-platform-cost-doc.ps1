$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$out = Join-Path $root 'deliverables\Platform-Costing-Comparison-2026.docx'
$word = New-Object -ComObject Word.Application
$word.Visible = $false
$doc = $word.Documents.Add()
$selection = $word.Selection
function Text([string]$value) { $selection.TypeText($value); $selection.TypeParagraph() }
function Heading([string]$value, [int]$level) { $selection.Style = "Heading $level"; Text $value; $selection.Style = 'Normal' }
try {
    $selection.Style = 'Title'; Text 'Kubernetes Platform and On-Premises Costing Comparison'; $selection.Style = 'Normal'
    Text 'Prepared 2026-09-09 | 35-VM target | Presentation report'
    Heading 'Executive Answer' 1
    Text 'Existing VxRail expansion: $155,000-$510,000 one time, plus $39,500-$106,700/month shared operations. OpenShift: $47,000-$121,700/month or $564,000-$1,460,000/year. SUSE Rancher Prime: $42,400-$114,200/month or $509,000-$1,370,000/year. Canonical Kubernetes: $41,000-$111,300/month or $492,000-$1,335,000/year. Migration effort is separate at $180,000-$420,000.'
    Heading '35-VM Target' 1
    Text '18 Kubernetes VMs, 7 PostgreSQL VMs, and 10 platform/operations VMs. Approximate requirement: 556 vCPU, 2.22 TB RAM, and 14.2 TB logical storage. Current reported free memory is 1.38 TB, so the estimated RAM gap is 844 GB before reserve and vSAN overhead.'
    Heading 'Common Monthly and Annual Cost' 1
    Text 'VxRail support: $5,000-$12,500/month ($60,000-$150,000/year). VMware/vSAN: $4,200-$12,500/month ($50,000-$150,000/year). PostgreSQL HA and DBA: $3,000-$10,000/month ($36,000-$120,000/year). Mongo-compatible database: $1,000-$4,000/month ($12,000-$48,000/year). Storage/PVC: $500-$2,000/month ($6,000-$24,000/year). Backup/offsite DR: $2,100-$6,250/month ($25,000-$75,000/year). Network/security: $1,000-$4,000/month ($12,000-$48,000/year). Monitoring/logging: $1,500-$5,000/month ($18,000-$60,000/year). OS/security: $2,100-$6,250/month ($25,000-$75,000/year). Staffing: $15,000-$33,333/month ($180,000-$400,000/year). Refresh reserve: $1,250-$3,333/month ($15,000-$40,000/year). Common subtotal: $39,500-$106,700/month or $474,000-$1,280,000/year.'
    Heading 'Platform Comparison' 1
    Text 'OpenShift: platform support $7,500-$15,000/month, $90,000-$180,000/year; total with common operations $47,000-$121,700/month, $564,000-$1,460,000/year. Choose for Red Hat support, certified operators, compliance, or an existing agreement.'
    Text 'SUSE Rancher Prime: platform support $2,917-$7,500/month, $35,000-$90,000/year; total with common operations $42,400-$114,200/month, $509,000-$1,370,000/year. Choose for centralized multi-cluster management and distribution flexibility.'
    Text 'Canonical Kubernetes: Ubuntu Pro and Canonical support $1,500-$4,583/month, $18,000-$55,000/year; total with common operations $41,000-$111,300/month, $492,000-$1,335,000/year. Choose for the lowest commercial platform cost, accepting more internal operational responsibility.'
    Heading 'One-Time and Migration Cost' 1
    Text 'Existing-cluster expansion: $155,000-$510,000. Migration program: $180,000-$420,000 over 20-28 weeks. Combined expansion plus migration cash requirement: $335,000-$930,000. A new six-node VxRail purchase is separate at $1.04M-$2.39M initial.'
    Heading 'Recommendation' 1
    Text 'Azure is the best immediate choice because it is operating and has a measured bill. If on-premises is mandatory, expand the existing VxRail after Dell validates memory and N+1 capacity. Use Canonical for the lowest commercial platform cost, Rancher Prime for centralized multi-cluster governance, and OpenShift only where Red Hat enterprise value justifies the premium.'
    Text 'The browser-viewable Markdown report contains the full cost tables and Mermaid diagram: deliverables/Platform-Costing-Comparison-2026.md.'
    $doc.SaveAs2($out, 16)
} finally {
    if ($doc) { $doc.Close() }
    if ($word) { $word.Quit() }
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}
