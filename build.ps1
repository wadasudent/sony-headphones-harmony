param([string]$ToolHome = $env:DEVECO_STUDIO_HOME, [switch]$CheckOnly)
$ErrorActionPreference = 'Stop'

function Find-File([string[]]$Candidates) {
  foreach ($candidate in $Candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }
  return ''
}

if (-not $ToolHome) {
  $roots = @()
  if ($env:DEVECO_SDK_HOME) { $roots += Split-Path -Parent $env:DEVECO_SDK_HOME }
  $localToolPath = Join-Path $PSScriptRoot '.local\deveco-home.txt'
  if (Test-Path -LiteralPath $localToolPath -PathType Leaf) {
    $roots += (Get-Content -LiteralPath $localToolPath -TotalCount 1 -Encoding UTF8)
  }
  $roots += @("$env:ProgramFiles\Huawei\DevEco Studio", "$env:ProgramFiles\Huawei\DevEcoStudio")
  foreach ($root in $roots) {
    if ($root -and (Test-Path -LiteralPath ([IO.Path]::Combine($root, 'sdk')) -PathType Container)) { $ToolHome = $root; break }
  }
}
if (-not $ToolHome -or -not (Test-Path -LiteralPath $ToolHome -PathType Container)) {
  throw 'HarmonyOS SDK not found. Install official DevEco Studio/API 26 or pass -ToolHome with the extracted official command-line tools folder.'
}
$resolvedToolRoot = (Resolve-Path -LiteralPath $ToolHome).Path
$hvigorScript = Find-File @(
  (Join-Path $resolvedToolRoot 'bin\hvigorw.bat'),
  (Join-Path $resolvedToolRoot 'bin\hvigorw.cmd'),
  (Join-Path $resolvedToolRoot 'tools\hvigor\bin\hvigorw.bat')
)
$hvigorJs = Find-File @(
  (Join-Path $resolvedToolRoot 'bin\hvigorw.js'),
  (Join-Path $resolvedToolRoot 'tools\hvigor\bin\hvigorw.js')
)
$nodeBinary = Find-File @(
  (Join-Path $resolvedToolRoot 'tool\node\node.exe'),
  (Join-Path $resolvedToolRoot 'tool\node\bin\node.exe'),
  (Join-Path $resolvedToolRoot 'tools\node\node.exe'),
  (Join-Path $resolvedToolRoot 'tools\node\bin\node.exe')
)
$ohpmScript = Find-File @(
  (Join-Path $resolvedToolRoot 'bin\ohpm.bat'),
  (Join-Path $resolvedToolRoot 'tools\ohpm\bin\ohpm.bat')
)
if (-not $hvigorScript -and (-not $hvigorJs -or -not $nodeBinary)) {
  throw 'Official Hvigor launcher not found in ToolHome. Open the project in DevEco Studio instead.'
}
$sdkDirectory = Join-Path $resolvedToolRoot 'sdk'
if (-not (Test-Path -LiteralPath $sdkDirectory -PathType Container)) {
  throw 'SDK directory is missing. Complete the official HarmonyOS SDK installation first.'
}
$env:DEVECO_SDK_HOME = $sdkDirectory
$env:OHOS_SDK_HOME = Join-Path $sdkDirectory 'default\openharmony'
if ($nodeBinary) { $env:PATH = (Split-Path -Parent $nodeBinary) + ';' + $env:PATH }
Push-Location -LiteralPath $PSScriptRoot
try {
  if ($CheckOnly) {
    if (-not $nodeBinary) { throw 'DevEco Node.js runtime not found. Check -ToolHome.' }
    foreach ($check in @('equalizer', 'widgets', 'reconnect')) {
      & $nodeBinary "checks/$check.cjs"
      if ($LASTEXITCODE -ne 0) { throw "Check failed: $check ($LASTEXITCODE)" }
    }
    return
  }
  # The template contains no signing credentials. Preserve any existing developer profile.
  $localBuildProfile = Join-Path $PSScriptRoot 'build-profile.json5'
  if (-not (Test-Path -LiteralPath $localBuildProfile -PathType Leaf)) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'build-profile.example.json5') -Destination $localBuildProfile
  }
  if ($ohpmScript) {
    & $ohpmScript install
    if ($LASTEXITCODE -ne 0) { throw "ohpm failed: $LASTEXITCODE" }
  }
  $arguments = @('--mode', 'module', '-p', 'product=default', '-p', 'module=entry@default', '-p', 'buildMode=debug', 'assembleHap', '--no-daemon')
  if ($hvigorScript) { & $hvigorScript @arguments }
  else { & $nodeBinary $hvigorJs @arguments }
  if ($LASTEXITCODE -ne 0) { throw "HarmonyOS build failed: $LASTEXITCODE" }
  Write-Output 'Build completed. HAP output: entry\build\default\outputs\default'
  Write-Output 'Device installation requires a valid device-specific development signature.'
} finally {
  Pop-Location
}
