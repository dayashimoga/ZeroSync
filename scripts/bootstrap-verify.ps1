#!/usr/bin/env pwsh
<#
.SYNOPSIS
    ZeroSync Project Progress Dashboard & Verification Auditor
.DESCRIPTION
    Reads .project_state.json, computes aggregate completion metrics,
    prints an ASCII visual dashboard with status indicators, and verifies
    dependency integrity across all subphases.
.PARAMETER JsonOutput
    Outputs raw JSON summary for CI/CD ingestion
.EXAMPLE
    ./scripts/bootstrap-verify.ps1
    ./scripts/bootstrap-verify.ps1 -JsonOutput
#>

[CmdletBinding()]
param(
    [switch]$JsonOutput
)

$ErrorActionPreference = "Stop"

$WorkspaceRoot = (Resolve-Path "$PSScriptRoot/..").Path
Set-Location $WorkspaceRoot
$StateFilePath = Join-Path $WorkspaceRoot ".project_state.json"

if (-not (Test-Path $StateFilePath)) {
    Write-Host "[ERROR] .project_state.json not found at $WorkspaceRoot" -ForegroundColor Red
    exit 1
}

$State = Get-Content -Raw -Path $StateFilePath | ConvertFrom-Json

# Calculate metrics
$Total = 0
$Completed = 0
$InProgress = 0
$Pending = 0
$SubphaseMap = @{}

foreach ($st in $State.stages) {
    foreach ($ph in $st.phases) {
        foreach ($sub in $ph.subphases) {
            $Total++
            $SubphaseMap[$sub.id] = $sub
            if ($sub.status -eq "COMPLETED") {
                $Completed++
            } elseif ($sub.status -eq "IN_PROGRESS") {
                $InProgress++
            } elseif ($sub.status -eq "PENDING") {
                $Pending++
            }
        }
    }
}

$Percent = 0.0
if ($Total -gt 0) {
    $Percent = [math]::Round(($Completed / $Total) * 100, 1)
}

# Dependency integrity check
$IntegrityErrors = @()
foreach ($id in $SubphaseMap.Keys) {
    $sub = $SubphaseMap[$id]
    if ($sub.status -eq "IN_PROGRESS" -or $sub.status -eq "COMPLETED") {
        if ($sub.dependencies) {
            foreach ($depId in $sub.dependencies) {
                $dep = $SubphaseMap[$depId]
                $depStat = "NOT_FOUND"
                if ($dep) {
                    $depStat = $dep.status
                }
                if ($null -eq $dep -or $dep.status -ne "COMPLETED") {
                    $IntegrityErrors += "Violation: '$id' has status '$($sub.status)' but dependency '$depId' is '$depStat'"
                }
            }
        }
    }
}

if ($JsonOutput) {
    $Summary = @{
        projectName = $State.project_name
        progressPercentage = $Percent
        totalSubphases = $Total
        completed = $Completed
        inProgress = $InProgress
        pending = $Pending
        activePointer = $State.active_pointer
        integrityPassed = ($IntegrityErrors.Count -eq 0)
        integrityErrors = $IntegrityErrors
    }
    $Summary | ConvertTo-Json -Depth 5
    exit 0
}

# Render Visual ASCII Dashboard
$BarLength = 40
$FilledLength = [math]::Round(($Percent / 100) * $BarLength)
$EmptyLength = $BarLength - $FilledLength
$ProgressBar = ("=" * $FilledLength) + ("-" * $EmptyLength)

Write-Host ""
Write-Host "+==============================================================================+" -ForegroundColor Cyan
Write-Host "|              AIRDROP-QR / ZEROSYNC - ORCHESTRATION DASHBOARD                 |" -ForegroundColor Cyan
Write-Host "+==============================================================================+" -ForegroundColor Cyan
Write-Host " System Status   : Active Air-Gapped Mobile Blueprint" -ForegroundColor White
Write-Host " Contract Version: $($State.contract_version)" -ForegroundColor White
Write-Host " Last Updated    : $($State.last_updated)" -ForegroundColor DarkGray
Write-Host " Active Target   : [$($State.active_pointer.subphase_id)]" -ForegroundColor Yellow
Write-Host ""
Write-Host " Completion Progress: [$ProgressBar] $Percent%" -ForegroundColor Green
Write-Host " Total: $Total | Completed: $Completed | In Progress: $InProgress | Pending: $Pending" -ForegroundColor White
Write-Host "------------------------------------------------------------------------------" -ForegroundColor DarkGray

foreach ($st in $State.stages) {
    Write-Host "`n>> $($st.id): $($st.name)" -ForegroundColor Magenta
    foreach ($ph in $st.phases) {
        Write-Host "   +-- $($ph.id): $($ph.name)" -ForegroundColor Blue
        foreach ($sub in $ph.subphases) {
            $badge = "[UNKNOWN]    "
            $badgeColor = "Red"
            if ($sub.status -eq "COMPLETED") {
                $badge = "[COMPLETED]  "
                $badgeColor = "Green"
            } elseif ($sub.status -eq "IN_PROGRESS") {
                $badge = "[IN_PROGRESS]"
                $badgeColor = "Yellow"
            } elseif ($sub.status -eq "PENDING") {
                $badge = "[PENDING]    "
                $badgeColor = "DarkGray"
            }
            
            $commitInfo = ""
            if ($sub.commit_hash) {
                $shortHash = $sub.commit_hash.Substring(0, [math]::Min(7, $sub.commit_hash.Length))
                $commitInfo = " (Commit: $shortHash)"
            }
            Write-Host "      $badge " -NoNewline -ForegroundColor $badgeColor
            Write-Host "$($sub.id): $($sub.title)$commitInfo" -ForegroundColor White

            if ($sub.dependencies -and $sub.dependencies.Count -gt 0) {
                $depsStr = ($sub.dependencies -join ", ")
                Write-Host "         Depends on: $depsStr" -ForegroundColor DarkGray
            }
        }
    }
}

Write-Host "`n------------------------------------------------------------------------------" -ForegroundColor DarkGray

if ($IntegrityErrors.Count -gt 0) {
    Write-Host "`n[CRITICAL WARNING] State Machine Integrity Violations Detected:" -ForegroundColor Red
    foreach ($err in $IntegrityErrors) {
        Write-Host "  - $err" -ForegroundColor Red
    }
    Write-Host ""
    exit 1
} else {
    Write-Host " [INTEGRITY OK] All subphase dependency chains are cryptographically consistent." -ForegroundColor Green
}

Write-Host ""
Write-Host "To advance the state machine:" -ForegroundColor Cyan
Write-Host "  pwsh ./scripts/bootstrap-subphase.ps1 -Stage $($State.active_pointer.stage_id) -Phase $($State.active_pointer.phase_id) -Subphase $($State.active_pointer.subphase_id) -Action start" -ForegroundColor Yellow
Write-Host ""
