#!/usr/bin/env pwsh
<#!
.SYNOPSIS
  Install or check dependencies for BMSSP benchmark (Windows).
.DESCRIPTION
  Detects and installs: Rust (rustup), Python3 + pip packages, MSVC build tools (via winget), CMake/Make (via choco or winget), Crystal + shards, Nim, Kotlin (JDK), Elixir, Erlang.
  Use -CheckOnly to report without installing. Use -Yes for non-interactive.
#>
param(
  [switch]$CheckOnly,
  [switch]$Yes
)

function Have($cmd) {
  $null -ne (Get-Command $cmd -ErrorAction SilentlyContinue)
}

function Confirm-Action([string]$msg) {
  if ($Yes) { return $true }
  $r = Read-Host "$msg [y/N]"
  return ($r -match '^[Yy]$')
}

Write-Host "==> Checking package managers"
$haveWinget = Have 'winget'
$haveChoco = Have 'choco'
if (-not $haveWinget -and -not $haveChoco) {
  Write-Warning "Neither winget nor choco found. Install winget (Microsoft Store) or Chocolatey (https://chocolatey.org/install)."
}

function Install-WithWinget($id) {
  if ($CheckOnly) { return }
  if (-not $haveWinget) { return }
  winget install --id $id -e --source winget --silent --accept-source-agreements --accept-package-agreements
}
function Install-WithChoco($pkg) {
  if ($CheckOnly) { return }
  if (-not $haveChoco) { return }
  choco install $pkg -y
}

Write-Host "==> Rust (rustup)"
if (-not (Have 'cargo') -or -not (Have 'rustc')) {
  Write-Host "[miss] Rust"
  if (-not $CheckOnly -and (Confirm-Action "Install Rust via rustup?")) {
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://win.rustup.rs'))
  }
} else { Write-Host "[ok] Rust present" }

Write-Host "==> Python3 + pip"
if (-not (Have 'python') -and -not (Have 'python3')) {
  Write-Host "[miss] Python"
  if (-not $CheckOnly) {
    if ($haveWinget) { Install-WithWinget 'Python.Python.3' }
    elseif ($haveChoco) { Install-WithChoco 'python3' }
  }
} else { Write-Host "[ok] Python present" }
if (-not $CheckOnly) {
  try { python -m pip --version *>$null } catch { }
  try { python -m pip install --user pyyaml matplotlib *>$null } catch { }
}

Write-Host "==> Build tools (MSVC)"
if (-not (Have 'cl')) {
  Write-Host "[miss] MSVC build tools (cl.exe)"
  if (-not $CheckOnly) {
    if ($haveWinget) { Install-WithWinget 'Microsoft.VisualStudio.2022.BuildTools' }
    else { Write-Warning "Install MSVC Build Tools manually from https://visualstudio.microsoft.com/downloads/ (Tools for Visual Studio)." }
  }
} else { Write-Host "[ok] cl.exe present" }

Write-Host "==> CMake and Make (optional for some impls)"
if (-not (Have 'cmake')) { if ($haveWinget) { Install-WithWinget 'Kitware.CMake' } elseif ($haveChoco) { Install-WithChoco 'cmake' } }
if (-not (Have 'make')) { if ($haveChoco) { Install-WithChoco 'make' } else { Write-Warning "GNU Make not found; C/C++ impls may not build." } }

Write-Host "==> Crystal + shards"
if (-not (Have 'crystal')) {
  if ($haveWinget) { Install-WithWinget 'CrystalLang.Crystal' } elseif ($haveChoco) { Install-WithChoco 'crystal' }
}
if ((Have 'crystal') -and -not (Have 'shards')) {
  Write-Warning "shards not found; ensure it's on PATH (Crystal installer/version)."
}

Write-Host "==> Nim"
if (-not (Have 'nim')) {
  if ($haveWinget) { Install-WithWinget 'Nim.Nim' } elseif ($haveChoco) { Install-WithChoco 'nim' }
}

Write-Host "==> Kotlin (JDK)"
if (-not (Have 'java')) {
  if ($haveWinget) { Install-WithWinget 'EclipseAdoptium.Temurin.17.JDK' } elseif ($haveChoco) { Install-WithChoco 'temurin17' }
}
if (-not (Have 'kotlinc')) {
  if ($haveChoco) { Install-WithChoco 'kotlin-compiler' } else { Write-Warning "Install Kotlin compiler manually or via scoop/choco." }
}

Write-Host "==> Elixir + Erlang"
if (-not (Have 'elixir')) {
  if ($haveWinget) { Install-WithWinget 'Elixir.Elixir' } elseif ($haveChoco) { Install-WithChoco 'elixir' }
}
if (-not (Have 'erlc')) {
  if ($haveWinget) { Install-WithWinget 'Erlang.ErlangOTP' } elseif ($haveChoco) { Install-WithChoco 'erlang' }
}

Write-Host "\n==> Summary"
Write-Host ("Rust:   {0}" -f ((Have 'cargo' -and (Have 'rustc')) ? 'present' : 'missing'))
Write-Host ("Python: {0}" -f ((Have 'python' -or (Have 'python3')) ? 'present' : 'missing'))
Write-Host ("MSVC:   {0}" -f ((Have 'cl') ? 'present' : 'missing'))
Write-Host ("CMake:  {0}" -f ((Have 'cmake') ? 'present' : 'missing'))
Write-Host ("make:   {0}" -f ((Have 'make') ? 'present' : 'missing'))
Write-Host ("Crystal:{0}" -f ((Have 'crystal') ? 'present' : 'missing'))
Write-Host ("Nim:    {0}" -f ((Have 'nim') ? 'present' : 'missing'))
Write-Host ("Kotlin: {0}" -f (((Have 'java') -and (Have 'kotlinc')) ? 'present' : 'missing'))
Write-Host ("Elixir: {0}" -f ((Have 'elixir') ? 'present' : 'missing'))
Write-Host ("Erlang: {0}" -f ((Have 'erlc') ? 'present' : 'missing'))

Write-Host "\nNext: run"
Write-Host "  python bench/runner.py --release --out results"
