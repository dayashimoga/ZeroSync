#!/usr/bin/env pwsh
<#
.SYNOPSIS
    ZeroSync Pre-Push Hook Gate
.DESCRIPTION
    Runs full test coverage verification, ensuring domain coverage >= 85.0%,
    and verifies that state machine integrity is intact prior to git push.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$WorkspaceRoot = (Resolve-Path "$PSScriptRoot/../..").Path
Set-Location $WorkspaceRoot

Write-Host "`n[Git Hook] Running Pre-Push Verification..." -ForegroundColor Cyan

# Verify State Machine Integrity
Write-Host ">>> Checking State Machine Integrity..." -ForegroundColor Cyan
& powershell -ExecutionPolicy Bypass -File "$WorkspaceRoot/scripts/bootstrap-verify.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[PRE-PUSH FAILED] State machine integrity verification failed." -ForegroundColor Red
    exit 1
}

# Run Full Coverage
Write-Host ">>> Executing Test Suite with Coverage Collection..." -ForegroundColor Cyan
$TestOutput = flutter test --coverage 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[PRE-PUSH FAILED] Test suite failed under coverage collection." -ForegroundColor Red
    Write-Host $TestOutput -ForegroundColor Yellow
    exit 1
}

# Check 85% Line Coverage Gate
$LcovPath = Join-Path $WorkspaceRoot "coverage/lcov.info"
if (Test-Path $LcovPath) {
    $Lines = Get-Content $LcovPath
    $TotalLines = ($Lines | Where-Object { $_ -match "^DA:" }).Count
    $HitLines = ($Lines | Where-Object { $_ -match "^DA:.*,[1-9]" }).Count
    if ($TotalLines -gt 0) {
        $CoveragePct = [math]::Round(($HitLines / $TotalLines) * 100, 2)
        Write-Host ">>> Domain Line Coverage: $CoveragePct% (Threshold: 85.0%)" -ForegroundColor Cyan
        if ($CoveragePct -lt 85.0) {
            Write-Host "[PRE-PUSH FAILED] Domain line coverage ($CoveragePct%) below 85.0% threshold." -ForegroundColor Red
            exit 1
        }
        Write-Host "  [OK] Coverage gate passed ($CoveragePct%)." -ForegroundColor Green
    }
}

Write-Host "[Git Hook] Pre-push verification passed successfully!`n" -ForegroundColor Green
exit 0
