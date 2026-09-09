$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$out = Join-Path $root 'deliverables\GCP-Azure-OnPrem-Comparison-2026.docx'
$word = New-Object -ComObject Word.Application
$word.Visible = $false
$doc = $word.Documents.Add()
$selection = $word.Selection
function AddText([string]$value) { $selection.TypeText($value); $selection.TypeParagraph() }
function AddHeading([string]$value, [int]$level) { $selection.Style = "Heading $level"; AddText $value; $selection.Style = 'Normal' }
try {
    $selection.Style = 'Title'; AddText 'GCP Migration Architecture and Cost - Standalone'; $selection.Style = 'Normal'
    AddText 'GCP V1 | Prepared 2026-09-09 | Separate from Azure/on-premises V1/V2 packs'
    AddHeading 'Executive Recommendation' 1
    AddText 'Keep Azure as the immediate platform while optimizing the measured $23,754/month bill. Do not authorize a GCP production migration for cost savings alone. Authorize a limited GCP discovery and proof of concept only if GKE, Google analytics, networking, or an existing commercial commitment is strategically important.'
    AddText 'GCP steady-state planning range: $14,000-$36,000/month including contingency. One-time migration planning range: $80,000-$195,000. The largest uncertainty is replacing Cosmos DB and validating application compatibility.'
    AddHeading 'Source Inventory' 1
    AddText 'QA: 3 AKS nodes, $284/month AKS, partial visible platform cost $526/month. PREPROD: 2 AKS nodes, $189/month AKS, partial visible platform cost $1,040/month. PROD: 11 AKS nodes across two rows, $1,897/month AKS, partial visible platform cost $2,029/month. Full Azure subscription baseline: $23,754/month.'
    AddHeading 'Proposed GCP Architecture' 1
    AddText 'GKE Standard with separate QA, PREPROD, and regional PROD clusters; Cloud SQL for PostgreSQL; Firestore or MongoDB Atlas for the Cosmos-compatible workload; Artifact Registry; Cloud Storage; Backup for GKE; Cloud Monitoring and Logging; Cloud Load Balancing; VPC with Cloud VPN or Interconnect.'
    AddHeading 'GCP Monthly Cost Model' 1
    AddText 'GKE and compute: $3,200-$7,200. GKE management: $75-$300. Cloud SQL: $3,050-$6,950. Cosmos replacement: $1,150-$4,400. Cloud Storage and backup: $1,450-$5,000. Artifact Registry: $175-$650. Load balancing, VPC, VPN, DNS: $1,500-$4,200. Monitoring, logging, security: $2,150-$5,900. Calculated total: $12,750-$32,675/month. Practical approval envelope: $14,000-$36,000/month.'
    AddHeading 'One-Time Migration Cost' 1
    AddText 'Discovery and landing zone: $15,000-$35,000. GKE and CI/CD conversion: $20,000-$45,000. PostgreSQL and Cosmos-compatible migration: $20,000-$55,000. Image, secret, storage, DNS, and integration migration: $15,000-$35,000. Testing, cutover, rollback, and hypercare: $10,000-$25,000. Total: $80,000-$195,000.'
    AddHeading 'Azure vs GCP vs On-Premises' 1
    AddText 'Azure has the lowest immediate risk because it is the current operating platform and has a measured actual bill. On-premises has the strongest cost potential if VxRail capacity, staffing, and facilities are already available, but memory headroom is a constraint. GCP is the best cloud alternative when GKE, analytics, global services, or negotiated pricing creates strategic value. GCP is not recommended solely as a cost-saving move.'
    AddHeading 'Approval Gates' 1
    AddText 'Reconcile Azure Cost Management. Complete the GCP pricing calculator model. Test Cosmos compatibility. Prove GKE latency, security, availability, and restore. Approve a three-year TCO and migration business case before production migration.'
    AddHeading 'Official Pricing References' 1
    AddText 'GKE: https://cloud.google.com/kubernetes-engine/pricing'
    AddText 'Cloud SQL: https://cloud.google.com/sql/pricing'
    AddText 'Cloud Storage: https://cloud.google.com/storage/pricing'
    AddText 'Pricing calculator: https://cloud.google.com/products/calculator'
    $doc.SaveAs2($out, 16)
} finally {
    if ($doc) { $doc.Close() }
    if ($word) { $word.Quit() }
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}