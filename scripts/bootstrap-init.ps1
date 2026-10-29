#!/usr/bin/env pwsh
<#
.SYNOPSIS
    ZeroSync Environment Bootstrap & Directory Tree Initializer
.DESCRIPTION
    Verifies development prerequisites (Flutter, Dart, Git, OpenSSL),
    initializes the Git version control repository, creates the strict Clean
    Architecture directory tree, and ensures .project_state.json is ready.
.EXAMPLE
    ./scripts/bootstrap-init.ps1
#>

[CmdletBinding()]
param(
    [switch]$SkipGitInit,
    [switch]$VerboseOutput
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "`n[ZeroSync Bootstrap] >> $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  [WARN] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "  [FAIL] $Message" -ForegroundColor Red
}

$WorkspaceRoot = (Resolve-Path "$PSScriptRoot/..").Path
Set-Location $WorkspaceRoot

Write-Step "Auditing Host System Prerequisites..."

$PrereqsPassed = $true

# Check Git
if (Get-Command git -ErrorAction SilentlyContinue) {
    $GitVersion = (git --version).Trim()
    Write-Success "Git detected: $GitVersion"
} else {
    Write-Fail "Git is not installed or not available on PATH."
    $PrereqsPassed = $false
}

# Check Flutter
if (Get-Command flutter -ErrorAction SilentlyContinue) {
    $FlutterRaw = (flutter --version 2>&1 | Select-Object -First 1).ToString().Trim()
    Write-Success "Flutter SDK detected: $FlutterRaw"
} else {
    Write-Fail "Flutter SDK is not found on PATH. Please install Flutter 3.10+."
    $PrereqsPassed = $false
}

# Check Dart
if (Get-Command dart -ErrorAction SilentlyContinue) {
    $DartRaw = (dart --version 2>&1).ToString().Trim()
    Write-Success "Dart SDK detected: $DartRaw"
} else {
    Write-Fail "Dart SDK is not found on PATH."
    $PrereqsPassed = $false
}

# Check Android SDK (Optional for pure domain, required for native build)
if ($env:ANDROID_HOME -or $env:ANDROID_SDK_ROOT) {
    $AndroidPath = $(if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $env:ANDROID_SDK_ROOT })
    Write-Success "Android SDK found at: $AndroidPath"
} else {
    Write-Warn "ANDROID_HOME / ANDROID_SDK_ROOT not set. Required later for Android compilation."
}

# Check OpenSSL
if (Get-Command openssl -ErrorAction SilentlyContinue) {
    Write-Success "OpenSSL cryptographic CLI detected."
} else {
    Write-Warn "OpenSSL CLI not found. Built-in Dart cryptographic fallbacks will be used."
}

if (-not $PrereqsPassed) {
    Write-Fail "Critical prerequisites missing. Resolve errors and re-run bootstrap-init.ps1."
    exit 1
}

Write-Step "Constructing Clean Architecture Directory Tree..."

$Directories = @(
    "contracts",
    "scripts",
    ".github/workflows",
    "lib/core/constants",
    "lib/core/errors",
    "lib/core/network_policy",
    "lib/core/utils",
    "lib/domain/entities",
    "lib/domain/value_objects",
    "lib/domain/services",
    "lib/domain/repositories",
    "lib/domain/usecases",
    "lib/data/datasources",
    "lib/data/models",
    "lib/data/repositories",
    "lib/presentation/blocs/optical_transmitter",
    "lib/presentation/blocs/optical_receiver",
    "lib/presentation/pages",
    "lib/presentation/widgets",
    "lib/presentation/theme",
    "test/unit/domain",
    "test/unit/data",
    "test/unit/core",
    "test/widget/presentation",
    "test/integration",
    "test/golden",
    "benchmark",
    "assets/icons"
)

foreach ($Dir in $Directories) {
    $TargetDir = Join-Path $WorkspaceRoot $Dir
    if (-not (Test-Path $TargetDir)) {
        New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
        if ($VerboseOutput) {
            Write-Host "    + Created directory: $Dir" -ForegroundColor DarkGray
        }
    }
}
$DirCount = $Directories.Count
Write-Success "Complete directory tree constructed ($DirCount packages)."

Write-Step "Validating State Machine Configuration..."

$StateFile = Join-Path $WorkspaceRoot ".project_state.json"
if (-not (Test-Path $StateFile)) {
    Write-Fail ".project_state.json is missing! Expected at workspace root."
    exit 1
}

try {
    $StateJson = Get-Content -Raw -Path $StateFile | ConvertFrom-Json
    $TotalSubphases = $StateJson.metrics.total_subphases
    Write-Success "State machine schema valid. Tracked subphases: $TotalSubphases."
} catch {
    Write-Fail "Corrupted JSON in .project_state.json: $_"
    exit 1
}

if (-not $SkipGitInit) {
    Write-Step "Verifying Git Version Control..."
    $GitDir = Join-Path $WorkspaceRoot ".git"
    if (-not (Test-Path $GitDir)) {
        git init -b main | Out-Null
        Write-Success "Git repository initialized with default branch 'main'."
    } else {
        Write-Success "Git repository already initialized."
    }
}

Write-Host "`n==================================================================" -ForegroundColor Green
Write-Host " [ZeroSync Bootstrap] Workspace successfully initialized!" -ForegroundColor Green
Write-Host " Run 'pwsh ./scripts/bootstrap-verify.ps1' to view the state engine." -ForegroundColor Green
Write-Host "==================================================================`n" -ForegroundColor Green
