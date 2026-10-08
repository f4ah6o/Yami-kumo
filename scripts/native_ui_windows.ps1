param(
  [string]$GpuiSource = $env:GPUI_SOURCE,
  [string]$EvidenceDirectory = $env:YAMI_NATIVE_UI_EVIDENCE_DIR
)

$ErrorActionPreference = "Stop"
$yamiRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ([string]::IsNullOrWhiteSpace($GpuiSource)) {
  $GpuiSource = Join-Path (Split-Path $yamiRoot -Parent) "gpui.mbt"
}
$GpuiSource = (Resolve-Path $GpuiSource).Path
if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
  $EvidenceDirectory = Join-Path $yamiRoot "_build/native-ui/windows"
}
New-Item -ItemType Directory -Force -Path $EvidenceDirectory | Out-Null
$EvidenceDirectory = (Resolve-Path $EvidenceDirectory).Path

$env:MOONBIT_NEW_NATIVE = "0"
$env:CL = ("/EHsc $env:CL").Trim()

function Convert-ToBashPath([string]$Path) {
  $converted = & bash -c 'cygpath -u "$1"' _ $Path
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($converted)) {
    throw "Could not convert path for Git Bash: $Path"
  }
  return $converted.Trim()
}

function Invoke-BashChecked([string[]]$Arguments) {
  & bash @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "bash $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
  }
}

$bashYamiRoot = Convert-ToBashPath $yamiRoot
$bashGpuiRoot = Convert-ToBashPath $GpuiSource
$bashEvidence = Convert-ToBashPath $EvidenceDirectory
$env:GPUI_SOURCE = $bashGpuiRoot
$workspaceScript = "$bashYamiRoot/scripts/native_ui_workspace.sh"
$driverScript = "$bashYamiRoot/tests/native-ui/drive_native_ui.py"
$testsScript = "$bashYamiRoot/scripts/native_ui_tests.sh"
$examplePackage = "$bashYamiRoot/native/examples/windows"

where.exe cl
moon version --all

$env:YAMI_NATIVE_UI_EVIDENCE_DIR = $EvidenceDirectory
Invoke-BashChecked @($workspaceScript, "sh", $testsScript)
Invoke-BashChecked @(
  $workspaceScript,
  "python",
  $driverScript,
  "--platform", "windows",
  "--evidence-dir", $bashEvidence,
  "--log", "$bashEvidence/native-ui.log",
  "--",
  "moon", "run", $examplePackage, "--target", "native"
)
