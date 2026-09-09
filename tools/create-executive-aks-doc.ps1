$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$out = Join-Path $root 'deliverables\Executive-AKS-Migration-Pack-2026-V2.docx'
$assets = Join-Path $root 'docs\Azure-VxRail-VMware-Migration\assets'
$word = New-Object -ComObject Word.Application
$word.Visible = $false
$doc = $word.Documents.Add()
$sel = $word.Selection

function Text([string]$value) { $sel.TypeText($value); $sel.TypeParagraph() }
function Heading([string]$value, [int]$level) { $sel.Style = "Heading $level"; Text $value; $sel.Style = 'Normal' }
function Table([string[]]$headers, [object[][]]$rows) {
    $table = $doc.Tables.Add($sel.Range, $rows.Count + 1, $headers.Count)
    $table.Style = 'Table Grid'
    for ($c = 0; $c -lt $headers.Count; $c++) { $table.Cell(1, $c + 1).Range.Text = $headers[$c] }
    for ($r = 0; $r -lt $rows.Count; $r++) {
        for ($c = 0; $c -lt $headers.Count; $c++) { $table.Cell($r + 2, $c + 1).Range.Text = [string]$rows[$r][$c] }
    }
    $sel.SetRange($table.Range.End, $table.Range.End); $sel.TypeParagraph()
}
function Picture([string]$name) {
    $path = Join-Path $assets $name
    $shape = $sel.InlineShapes.AddPicture($path, $false, $true)
    $shape.LockAspectRatio = -1
    $shape.Width = 500
    $sel.TypeParagraph()
}

try {
    $sel.Style = 'Title'; Text 'Executive AKS Cost and Migration Pack'; $sel.Style = 'Normal'
    Text 'Azure to on-premises VxRail | QA, PREPROD, PROD | Prepared 2026-09-09'
    Text 'Decision audience: Directors, CTO, architecture board, finance, and migration steering committee'

    Heading 'Executive Decision Summary' 1
    Text 'The workbook shows 16 AKS nodes and $2,370/month of AKS cost: QA $284, PREPROD $189, and PROD $1,897. Directly related visible rows add to partial platform subtotals of QA $526, PREPROD $1,040, and PROD $2,029 per month.'
    Text 'These are partial workbook-detail costs, not complete environment bills. Shared networking, storage, backup, monitoring, ingress, and unallocated subscription costs must be reconciled from Azure Cost Management before financial approval.'
    Text 'The key decision risk is PROD sizing: the workbook shows 11 PROD AKS nodes, while the repository target design plans 12 PROD workers plus 3 shared control-plane VMs. Confirm the intended target before capacity or platform licensing approval.'
    Picture 'aks-cost-by-environment.svg'

    Heading 'Workbook-Based Environment Cost' 1
    Table @('Environment','AKS cost/month','Related visible rows','Partial platform total','Annualized') @(
        @('QA','$284','Cosmos $132; Container Instance $110','$526','$6,312'),
        @('PREPROD','$189','PostgreSQL $719; Cosmos $132','$1,040','$12,480'),
        @('PROD','$1,897','Cosmos $132','$2,029','$24,348'),
        @('Visible total','$2,370','$1,225','$3,595','$43,140'))
    Text 'The QA Container Instance is marked for removal in the workbook. The PREPROD PostgreSQL row is the only directly visible PostgreSQL row and should not be treated as the complete database estate.'

    Heading 'Environment Readout' 1
    Heading 'QA: low-cost validation lane' 2
    Text 'Visible cost: $526/month. Run the six-node on-prem QA target, restore the database and namespace, verify Harbor images and secrets, and complete the 200-user test. Configure autoscaling at 1-3 nodes. Remove the $110 Container Instance only after application-owner confirmation.'
    Heading 'PREPROD: resilience and performance rehearsal' 2
    Text 'Visible cost: $1,040/month. Prove the selected platform, three-member Patroni database, persistent storage, ingress, observability, backup restore, failover, and agreed load target. Confirm that the workbook PostgreSQL resize recommendation does not invalidate the on-prem target.'
    Heading 'PROD: controlled live migration' 2
    Text 'Visible cost: $2,029/month. Reconcile 11 workbook AKS nodes with the 12-worker target, then require stable replication, a full restore rehearsal, 72-hour canary traffic, DNS rollback, and executive change approval before cutover.'

    Heading 'Gated Migration Flow' 1
    Picture 'aks-migration-flow.svg'

    Heading 'Executive Timeline' 1
    Picture 'aks-executive-timeline.svg'
    Text 'Indicative sequence: September cost reconciliation and proof of concept; October QA; November PREPROD; December onward PROD parallel build, canary, cutover, and hypercare. Final dates depend on capacity and platform-selection gates.'

    Heading 'Operating Model' 1
    Table @('Capability','QA','PREPROD','PROD') @(
        @('Availability','Best effort','HA rehearsal','HA with anti-affinity and failure testing'),
        @('Backup','Weekly namespace; DB as needed','Daily namespace and DB','Daily namespace, frequent WAL, immutable offsite copy'),
        @('Restore test','Before sign-off','Monthly during migration','Quarterly full restore; annual DR exercise'),
        @('Change control','QA owner','Planned test window','CAB/change record and executive approval'),
        @('On-call','Platform + QA','Platform + DBA + performance','24x7 platform, DBA, security, network, service owner'))

    Heading 'Migration and Backup Corrections' 1
    Text '1. Resolve the PROD 11-node workbook versus 12-worker target mismatch before capacity approval.'
    Text '2. Remove plaintext credentials from runbooks and use Key Vault, an approved secret manager, or one-time injected credentials.'
    Text '3. Validate Azure PostgreSQL logical replication / pglogical support for the exact tier and version before promising zero-downtime migration.'
    Text '4. Replace guaranteed RPO 0 language with RPO equal to the last confirmed replication point; block cutover when lag exceeds the approved threshold.'
    Text '5. Require immutable offsite PROD backups. Same-site NAS is not sufficient for site-loss recovery.'
    Text '6. Test namespace/PVC restore, PostgreSQL PITR, VM restore, and full cluster rebuild before PROD sign-off.'
    Text '7. Record the Kasten K10 entitlement and supported version for the selected Kubernetes platform.'

    Heading 'Executive Risks and Decisions' 1
    Table @('Risk / decision','Impact','Required gate') @(
        @('PROD node-count mismatch','Under-sizing or unnecessary capital allocation','Infrastructure architecture sign-off'),
        @('Incomplete workbook detail','Platform cost is understated','Finance/Azure Cost Management reconciliation'),
        @('VxRail memory below target design','All environments may not run concurrently','Infrastructure capacity gate'),
        @('Logical replication capability','Zero-downtime plan may be invalid','DBA and Azure platform test'),
        @('Same-site backup only','Site loss may exceed RTO/RPO','DR and security approval'),
        @('Platform license/support choice','Multi-year cost and staffing commitment','CTO/steering committee decision'))

    Heading 'Recommendation' 1
    Text 'Use QA as the first controlled validation lane, PREPROD as the platform and restore proof, and PROD only after the replication and recovery gates pass. Select the Kubernetes platform through a short proof of concept using the same node, CPU, storage, monitoring, backup, and support requirements for every vendor.'
    Text 'The companion Markdown report contains the detailed cost assumptions and platform comparison. This document is designed as the management presentation pack.'
    $doc.SaveAs2($out, 16)
} finally {
    if ($doc) { $doc.Close() }
    if ($word) { $word.Quit() }
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}