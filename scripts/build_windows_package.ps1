# Copyright (c) 2026 gugutu
# SPDX-License-Identifier: MIT

param(
  [Parameter(Mandatory = $true)]
  [ValidateSet(
    "compiler-windows-x64",
    "compiler-windows-arm64",
    "runtime-windows-x64",
    "runtime-windows-arm64"
  )]
  [string]$Target
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Get-Content (Join-Path $Root "config/hermes.env") | ForEach-Object {
  if ($_ -match '^([A-Z0-9_]+)=(.*)$') {
    Set-Item -Path "Env:$($Matches[1])" -Value $Matches[2]
  }
}

$SourceDir = if ($Env:HERMES_SOURCE_DIR) {
  $Env:HERMES_SOURCE_DIR
} else {
  Join-Path $Root "work/hermes-source"
}
$BuildRoot = Join-Path $Root "work/build/$Target"
$PackageDir = Join-Path $Root "work/package/$Target"
$PackageTag = if ($Env:HERMES_PACKAGE_TAG) { $Env:HERMES_PACKAGE_TAG } else { "local" }
$Architecture = if ($Target.EndsWith("arm64")) { "ARM64" } else { "x64" }
$RustTarget = if ($Architecture -eq "ARM64") {
  "aarch64-pc-windows-msvc"
} else {
  "x86_64-pc-windows-msvc"
}
$PackageKind = if ($Target.StartsWith("compiler-")) { "compiler" } else { "runtime" }

if (Test-Path $PackageDir) {
  Remove-Item -Recurse -Force $PackageDir
}
New-Item -ItemType Directory -Force (Join-Path $PackageDir "LICENSES") | Out-Null

$Configure = @(
  "-S", $SourceDir,
  "-B", $BuildRoot,
  "-G", "Visual Studio 17 2022",
  "-A", $Architecture,
  "-DHERMES_ENABLE_NAPI=OFF",
  "-DHERMES_ENABLE_INTL=OFF",
  "-DHERMES_ENABLE_CORE_EXTENSIONS=ON",
  "-DHERMES_ENABLE_CONTRIB_EXTENSIONS=ON",
  "-DHERMES_ENABLE_DEBUGGER=OFF",
  "-DHERMES_BUILD_SHARED_JSI=OFF",
  "-DHERMES_UNICODE_LITE=ON"
)
& cmake @Configure
if ($LASTEXITCODE -ne 0) { throw "Hermes configure failed" }

function Find-Artifact([string[]]$Names) {
  $Artifact = Get-ChildItem -Path $BuildRoot -Recurse -File |
    Where-Object { $Names -contains $_.Name } |
    Select-Object -First 1
  if (-not $Artifact) {
    throw "Missing Hermes artifact: $($Names -join ', ')"
  }
  return $Artifact.FullName
}

if ($PackageKind -eq "compiler") {
  & cmake --build $BuildRoot --target hermesc --config MinSizeRel --parallel
  if ($LASTEXITCODE -ne 0) { throw "hermesc build failed" }
  New-Item -ItemType Directory -Force (Join-Path $PackageDir "bin") | Out-Null
  Copy-Item (Find-Artifact @("hermesc.exe")) (Join-Path $PackageDir "bin/hermesc.exe")
  foreach ($RuntimeDll in @("msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll")) {
    $SystemDll = Join-Path $Env:WINDIR "System32/$RuntimeDll"
    if (Test-Path $SystemDll) {
      Copy-Item $SystemDll (Join-Path $PackageDir "bin/$RuntimeDll")
    }
  }
} else {
  & cmake --build $BuildRoot --target hermesvm_a jsi --config MinSizeRel --parallel
  if ($LASTEXITCODE -ne 0) { throw "Hermes runtime build failed" }
  New-Item -ItemType Directory -Force (Join-Path $PackageDir "include/hermes") | Out-Null
  New-Item -ItemType Directory -Force (Join-Path $PackageDir "include/jsi") | Out-Null
  New-Item -ItemType Directory -Force (Join-Path $PackageDir "lib") | Out-Null
  Copy-Item (Join-Path $SourceDir "API/hermes/hermes.h") (Join-Path $PackageDir "include/hermes/hermes.h")
  Copy-Item -Recurse (Join-Path $SourceDir "public/hermes/Public") (Join-Path $PackageDir "include/hermes/Public")
  Copy-Item -Recurse (Join-Path $SourceDir "API/jsi/jsi/*") (Join-Path $PackageDir "include/jsi")
  Copy-Item (Find-Artifact @("hermesvm_a.lib", "libhermesvm_a.lib")) (Join-Path $PackageDir "lib/hermesvm.lib")
  Copy-Item (Find-Artifact @("jsi.lib", "libjsi.lib")) (Join-Path $PackageDir "lib/jsi.lib")
  Copy-Item (Find-Artifact @("boost_context.lib", "libboost_context.lib")) (Join-Path $PackageDir "lib/boost_context.lib")
}

Copy-Item (Join-Path $SourceDir "LICENSE") (Join-Path $PackageDir "LICENSES/Hermes-LICENSE")
Copy-Item (Join-Path $SourceDir "external/boost/boost_1_86_0/LICENSE_1_0.txt") `
  (Join-Path $PackageDir "LICENSES/Boost-LICENSE_1_0.txt")

$Manifest = @"
format_version = 2
package_kind = "$PackageKind"
package_tag = "$PackageTag"
source_revision = "$Env:HERMES_REVISION"
source_branch = "$Env:HERMES_BRANCH"
bytecode_version = $Env:HERMES_BYTECODE_VERSION
target = "$RustTarget"
intl = false
core_extensions = true
contrib_extensions = true
napi = false
platform_support = "windows-unicode-lite"
"@
Set-Content -Encoding utf8NoBOM (Join-Path $PackageDir "manifest.toml") $Manifest

$Metadata = [ordered]@{
  schema_version = 1
  package_target = $Target
  package_kind = $PackageKind
  rust_target = $RustTarget
  platform_support = "windows-unicode-lite"
  package_tag = $PackageTag
  hermes_revision = $Env:HERMES_REVISION
  hermes_branch = $Env:HERMES_BRANCH
  bytecode_version = [int]$Env:HERMES_BYTECODE_VERSION
  features = [ordered]@{
    intl = $false
    core_extensions = $true
    contrib_extensions = $true
    napi = $false
  }
}
$Metadata | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8NoBOM `
  (Join-Path $PackageDir "metadata.json")

Write-Host "Packaged $Target at $PackageDir"
