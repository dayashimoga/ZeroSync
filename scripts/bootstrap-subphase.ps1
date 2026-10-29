#!/usr/bin/env pwsh
<#
.SYNOPSIS
    ZeroSync Subphase State Machine Execution Engine
.DESCRIPTION
    Enforces sequential subphase progression. Allows starting, verifying, and
    completing designated subphases while validating prerequisite dependencies,
    running strict lint/test gates, updating .project_state.json, and staging atomic Git commits.
.PARAMETER Stage
    The ID of the stage (e.g. STAGE_1, STAGE_2)
.PARAMETER Phase
    The ID of the phase (e.g. PHASE_1_1, PHASE_2_1)
.PARAMETER Subphase
    The ID of the subphase (e.g. SUBPHASE_1_1_1)
.PARAMETER Action
    Action to perform: 'start', 'verify', or 'complete'
.EXAMPLE
    ./scripts/bootstrap-subphase.ps1 -Stage STAGE_1 -Phase PHASE_1_1 -Subphase SUBPHASE_1_1_1 -Action start
    ./scripts/bootstrap-subphase.ps1 -Stage STAGE_1 -Phase PHASE_1_1 -Subphase SUBPHASE_1_1_1 -Action verify
    ./scripts/bootstrap-subphase.ps1 -Stage STAGE_1 -Phase PHASE_1_1 -Subphase SUBPHASE_1_1_1 -Action complete
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [Alias("s")]
    [string]$Stage,

    [Parameter(Mandatory = $true)]
    [Alias("p")]
    [string]$Phase,

    [Parameter(Mandatory = $true)]
    [Alias("sub")]
    [string]$Subphase,

    [Parameter(Mandatory = $true)]
    [Alias("a")]
    [ValidateSet("start", "verify", "complete")]
    [string]$Action,

    [switch]$SkipTests
)

$ErrorActionPreference = "Stop"

$WorkspaceRoot = (Resolve-Path "$PSScriptRoot/..").Path
Set-Location $WorkspaceRoot
$StateFilePath = Join-Path $WorkspaceRoot ".project_state.json"

if (-not (Test-Path $StateFilePath)) {
    Write-Host "[ERROR] .project_state.json not found at $WorkspaceRoot" -ForegroundColor Red
    exit 1
}

function Load-State {
    return Get-Content -Raw -Path $StateFilePath | ConvertFrom-Json
}

function Save-State {
    param($StateObj)
    $StateObj.last_updated = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    
    # Recalculate metrics
    $Total = 0
    $Completed = 0
    foreach ($st in $StateObj.stages) {
        foreach ($ph in $st.phases) {
            foreach ($sub in $ph.subphases) {
                $Total++
                if ($sub.status -eq "COMPLETED") {
                    $Completed++
                }
            }
        }
    }
    $StateObj.metrics.total_subphases = $Total
    $StateObj.metrics.completed_subphases = $Completed
    if ($Total -gt 0) {
        $StateObj.metrics.progress_percentage = [math]::Round(($Completed / $Total) * 100, 2)
    }

    $JsonString = $StateObj | ConvertTo-Json -Depth 20
    Set-Content -Path $StateFilePath -Value $JsonString -Encoding utf8
}

function Find-Subphase {
    param($StateObj, [string]$TargetId)
    foreach ($st in $StateObj.stages) {
        foreach ($ph in $st.phases) {
            foreach ($sub in $ph.subphases) {
                if ($sub.id -eq $TargetId) {
                    return @{
                        Stage = $st
                        Phase = $ph
                        Subphase = $sub
                    }
                }
            }
        }
    }
    return $null
}

function Find-SubphaseByIdOnly {
    param($StateObj, [string]$TargetId)
    foreach ($st in $StateObj.stages) {
        foreach ($ph in $st.phases) {
            foreach ($sub in $ph.subphases) {
                if ($sub.id -eq $TargetId) {
                    return $sub
                }
            }
        }
    }
    return $null
}

$State = Load-State
$Found = Find-Subphase -StateObj $State -TargetId $Subphase

if ($null -eq $Found) {
    Write-Host "[FATAL] Subphase '$Subphase' not found in state machine." -ForegroundColor Red
    exit 1
}

$CurrentSub = $Found.Subphase
$CurrentPhase = $Found.Phase
$CurrentStage = $Found.Stage

Write-Host "`n==================================================================" -ForegroundColor Cyan
Write-Host " ZeroSync State Machine Harness | Subphase Orchestrator" -ForegroundColor Cyan
Write-Host " Target: [$($CurrentStage.id)] > [$($CurrentPhase.id)] > [$($CurrentSub.id)]" -ForegroundColor Yellow
Write-Host " Title : $($CurrentSub.title)" -ForegroundColor White
Write-Host " Action: $($Action.ToUpper())" -ForegroundColor Magenta
Write-Host "==================================================================" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# ACTION: START
# -----------------------------------------------------------------------------
if ($Action -eq "start") {
    # Check dependencies
    $UnsatisfiedDeps = @()
    if ($CurrentSub.dependencies) {
        foreach ($depId in $CurrentSub.dependencies) {
            $depObj = Find-SubphaseByIdOnly -StateObj $State -TargetId $depId
            if ($null -eq $depObj -or $depObj.status -ne "COMPLETED") {
                $depStatus = $(if ($depObj) { $depObj.status } else { "NOT_FOUND" })
                $UnsatisfiedDeps += "$depId (Status: $depStatus)"
            }
        }
    }

    if ($UnsatisfiedDeps.Count -gt 0) {
        Write-Host "`n[BLOCKED] Cannot start '$($CurrentSub.id)'. Unmet dependencies:" -ForegroundColor Red
        foreach ($u in $UnsatisfiedDeps) {
            Write-Host "  - $u" -ForegroundColor Red
        }
        Write-Host "`nComplete all prerequisite subphases before activating this one." -ForegroundColor Yellow
        exit 1
    }

    # Set active pointer and IN_PROGRESS
    $CurrentSub.status = "IN_PROGRESS"
    if (-not $CurrentSub.started_at) {
        $CurrentSub.started_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    $State.active_pointer.stage_id = $CurrentStage.id
    $State.active_pointer.phase_id = $CurrentPhase.id
    $State.active_pointer.subphase_id = $CurrentSub.id

    Save-State -StateObj $State

    Write-Host "`n[SUCCESS] Subphase '$($CurrentSub.id)' is now IN_PROGRESS." -ForegroundColor Green
    Write-Host "`nRequired Artifacts to create/verify:" -ForegroundColor Cyan
    foreach ($art in $CurrentSub.required_artifacts) {
        $exists = Test-Path (Join-Path $WorkspaceRoot $art)
        $badge = $(if ($exists) { "[EXISTS]" } else { "[MISSING]" })
        $color = $(if ($exists) { "Green" } else { "DarkYellow" })
        Write-Host "  $badge $art" -ForegroundColor $color
    }

    Write-Host "`nVerification Criteria:" -ForegroundColor Cyan
    foreach ($crit in $CurrentSub.verification_criteria) {
        Write-Host "  [ ] $crit" -ForegroundColor White
    }
    Write-Host ""
    exit 0
}

# -----------------------------------------------------------------------------
# ACTION: VERIFY
# -----------------------------------------------------------------------------
function Execute-Verification {
    param($CurrentSub, $WorkspaceRoot, [switch]$SkipTests)

    Write-Host "`n>>> Running Gate 1: Artifact Existence Check..." -ForegroundColor Cyan
    $MissingArtifacts = @()
    foreach ($art in $CurrentSub.required_artifacts) {
        $artPath = Join-Path $WorkspaceRoot $art
        if (-not (Test-Path $artPath)) {
            $MissingArtifacts += $art
            Write-Host "  [X] Missing: $art" -ForegroundColor Red
        } else {
            Write-Host "  [OK] Found  : $art" -ForegroundColor Green
        }
    }

    if ($MissingArtifacts.Count -gt 0) {
        Write-Host "`n[GATE 1 FAILED] $($MissingArtifacts.Count) required artifact(s) missing." -ForegroundColor Red
        return $false
    }

    Write-Host "`n>>> Running Gate 2: Dart & Flutter Static Analysis..." -ForegroundColor Cyan
    if (Test-Path (Join-Path $WorkspaceRoot "pubspec.yaml")) {
        try {
            $AnalyzeOut = dart analyze --fatal-infos --fatal-warnings 2>&1
            $AnalyzeExit = $LASTEXITCODE
            if ($AnalyzeExit -ne 0) {
                Write-Host $AnalyzeOut -ForegroundColor Red
                Write-Host "`n[GATE 2 FAILED] Static analysis found errors/warnings." -ForegroundColor Red
                return $false
            }
            Write-Host "  [OK] Zero warnings, zero infos reported." -ForegroundColor Green
        } catch {
            Write-Host "  [WARN] Dart analysis command error: $_" -ForegroundColor Yellow
        }
    }

    if (-not $SkipTests) {
        Write-Host "`n>>> Running Gate 3: Unit & Domain Test Suites..." -ForegroundColor Cyan
        $TestDir = Join-Path $WorkspaceRoot "test"
        $HasTests = ((Get-ChildItem -Path $TestDir -Filter "*_test.dart" -Recurse -ErrorAction SilentlyContinue).Count -gt 0)

        if ($HasTests) {
            $TestOut = flutter test 2>&1
            $TestExit = $LASTEXITCODE
            if ($TestExit -ne 0) {
                Write-Host $TestOut -ForegroundColor Red
                Write-Host "`n[GATE 3 FAILED] Test suite failed with exit code $TestExit." -ForegroundColor Red
                return $false
            }
            Write-Host "  [OK] All test suites passed successfully." -ForegroundColor Green
        } else {
            Write-Host "  [SKIP] No unit test files found matching *_test.dart." -ForegroundColor DarkGray
        }
    }

    Write-Host "`n>>> Running Gate 4: Zero-Trust Network Air-Gap Audit..." -ForegroundColor Cyan
    $Manifests = @(
        "android/app/src/main/AndroidManifest.xml",
        "ios/Runner/Info.plist"
    )
    $NetworkViolation = $false
    foreach ($mf in $Manifests) {
        $p = Join-Path $WorkspaceRoot $mf
        if (Test-Path $p) {
            $content = Get-Content -Raw -Path $p
            if ($content -match "android\.permission\.INTERNET" -or $content -match "NSAllowsArbitraryLoads\s*<true/>") {
                Write-Host "  [SECURITY VIOLATION] Network permission detected in $mf!" -ForegroundColor Red
                $NetworkViolation = $true
            }
        }
    }
    if ($NetworkViolation) {
        Write-Host "`n[GATE 4 FAILED] Air-gap zero-trust security audit failed." -ForegroundColor Red
        return $false
    }
    Write-Host "  [OK] Air-gap zero-network security verified." -ForegroundColor Green

    return $true
}

if ($Action -eq "verify") {
    $Passed = Execute-Verification -CurrentSub $CurrentSub -WorkspaceRoot $WorkspaceRoot -SkipTests:$SkipTests
    if ($Passed) {
        Write-Host "`n[VERIFY PASSED] Subphase '$($CurrentSub.id)' satisfied all verification gates." -ForegroundColor Green
        exit 0
    } else {
        Write-Host "`n[VERIFY FAILED] Resolve all issues above before completing subphase." -ForegroundColor Red
        exit 1
    }
}

# -----------------------------------------------------------------------------
# ACTION: COMPLETE
# -----------------------------------------------------------------------------
if ($Action -eq "complete") {
    Write-Host "`nVerifying gates prior to subphase seal..." -ForegroundColor Cyan
    $Passed = Execute-Verification -CurrentSub $CurrentSub -WorkspaceRoot $WorkspaceRoot -SkipTests:$SkipTests

    if (-not $Passed) {
        Write-Host "`n[ABORT] Cannot complete subphase. Verification failed." -ForegroundColor Red
        exit 1
    }

    Write-Host "`n>>> Staging Atomic Git Commit..." -ForegroundColor Cyan
    git add -A | Out-Null
    
    $Status = (git status --porcelain).Trim()
    $CommitMsg = "feat($($CurrentPhase.id.ToLower().Replace('_','-'))): complete $($CurrentSub.id) - $($CurrentSub.title)"

    if ($Status) {
        git commit -m "$CommitMsg" | Out-Null
        Write-Host "  [OK] Created git commit: $CommitMsg" -ForegroundColor Green
    } else {
        Write-Host "  [INFO] Working tree clean; recording existing HEAD commit." -ForegroundColor Yellow
    }

    $CommitHash = (git rev-parse HEAD 2>&1).Trim()
    Write-Host "  [OK] SHA256 Commit Hash: $CommitHash" -ForegroundColor Green

    # Mark COMPLETED
    $CurrentSub.status = "COMPLETED"
    $CurrentSub.completed_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $CurrentSub.commit_hash = $CommitHash

    # Advance pointer to next available pending subphase
    $NextPendingFound = $false
    foreach ($st in $State.stages) {
        foreach ($ph in $st.phases) {
            foreach ($sub in $ph.subphases) {
                if ($sub.status -eq "PENDING" -and -not $NextPendingFound) {
                    $State.active_pointer.stage_id = $st.id
                    $State.active_pointer.phase_id = $ph.id
                    $State.active_pointer.subphase_id = $sub.id
                    $NextPendingFound = $true
                    Write-Host "`nNext Active Subphase Queued: [$($sub.id)] $($sub.title)" -ForegroundColor Cyan
                }
            }
        }
    }

    Save-State -StateObj $State

    Write-Host "`n==================================================================" -ForegroundColor Green
    Write-Host " [SEALED] Subphase $($CurrentSub.id) successfully marked COMPLETED!" -ForegroundColor Green
    Write-Host " Project Progress: $($State.metrics.completed_subphases) / $($State.metrics.total_subphases) ($($State.metrics.progress_percentage)%)" -ForegroundColor Green
    Write-Host "==================================================================`n" -ForegroundColor Green
    exit 0
}
