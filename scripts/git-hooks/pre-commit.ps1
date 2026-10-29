#!/usr/bin/env pwsh
<#
.SYNOPSIS
    ZeroSync Pre-Commit Hook Gate
.DESCRIPTION
    Executes automated static analysis (dart analyze) and unit tests before git commit.
    Blocks commit if any warnings, errors, or test failures occur.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$WorkspaceRoot = (Resolve-Path "$PSScriptRoot/../..").Path
Set-Location $WorkspaceRoot

Write-Host "`n[Git Hook] Running Pre-Commit Gates..." -ForegroundColor Cyan

# 1. Format Check
Write-Host ">>> Checking Dart Formatting..." -ForegroundColor Cyan
$FormatOutput = dart format --output=none --set-exit-if-changed . 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[PRE-COMMIT FAILED] Dart files require formatting. Run: dart format ." -ForegroundColor Red
    Write-Host $FormatOutput -ForegroundColor Yellow
    exit 1
}
Write-Host "  [OK] Formatting verified." -ForegroundColor Green

# 2. Static Analysis
Write-Host ">>> Running Static Analysis (--fatal-infos --fatal-warnings)..." -ForegroundColor Cyan
$AnalyzeOutput = dart analyze --fatal-infos --fatal-warnings 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[PRE-COMMIT FAILED] Static analysis found errors/warnings:" -ForegroundColor Red
    Write-Host $AnalyzeOutput -ForegroundColor Yellow
    exit 1
}
Write-Host "  [OK] Zero static analysis issues." -ForegroundColor Green

# 3. Unit Tests
Write-Host ">>> Running Unit Tests..." -ForegroundColor Cyan
$TestFiles = (Get-ChildItem -Path "$WorkspaceRoot/test" -Filter "*_test.dart" -Recurse -ErrorAction SilentlyContinue).Count
if ($TestFiles -gt 0) {
    $TestOutput = flutter test 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[PRE-COMMIT FAILED] Test suite failed:" -ForegroundColor Red
        Write-Host $TestOutput -ForegroundColor Yellow
        exit 1
    }
    Write-Host "  [OK] Unit test suite passed." -ForegroundColor Green
}

# 4. Air-Gap Manifest Audit
Write-Host ">>> Auditing Manifests for Air-Gap Violations..." -ForegroundColor Cyan
$Manifests = @(
    "android/app/src/main/AndroidManifest.xml",
    "ios/Runner/Info.plist"
)
foreach ($mf in $Manifests) {
    $p = Join-Path $WorkspaceRoot $mf
    if (Test-Path $p) {
        $content = Get-Content -Raw -Path $p
        if ($content -match "android\.permission\.INTERNET" -or $content -match "NSAllowsArbitraryLoads\s*<true/>") {
            Write-Host "[PRE-COMMIT FAILED] Security violation: network permission detected in $mf!" -ForegroundColor Red
            exit 1
        }
    }
}
Write-Host "  [OK] Air-gap zero-network security verified." -ForegroundColor Green

Write-Host "[Git Hook] Pre-commit gates passed successfully!`n" -ForegroundColor Green
exit 0

