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
if ($null -eq (Get-Command git.exe -ErrorAction SilentlyContinue)) {
  throw "Git for Windows is required for the native UI runner."
}
$gitCommand = Get-Command git.exe
$gitCommandDirectory = Split-Path -Path $gitCommand.Source -Parent
$gitInstallDirectory = Split-Path -Path $gitCommandDirectory -Parent
$gitBash = Join-Path $gitInstallDirectory 'bin\bash.exe'
if (-not (Test-Path -LiteralPath $gitBash)) {
  throw "Git Bash was not found beside $($gitCommand.Source). Install Git for Windows."
}
$cygpath = & $gitBash -c 'command -v cygpath' 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($cygpath)) {
  throw "Git Bash does not provide cygpath: $gitBash"
}
$script:GitBash = $gitBash
if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
  $EvidenceDirectory = Join-Path $yamiRoot "_build/native-ui/windows"
}
New-Item -ItemType Directory -Force -Path $EvidenceDirectory | Out-Null
$EvidenceDirectory = (Resolve-Path $EvidenceDirectory).Path

$env:MOONBIT_NEW_NATIVE = "0"
$env:CL = ("/EHsc $env:CL").Trim()
# Git Bash's MSYS runtime rewrites path-like environment values before it
# launches native Windows tools. Keep MSVC's slash-prefixed compiler option
# intact while retaining the inherited exclusions and normal path conversion.
$msysEnvConversionExclusions = @()
if (-not [string]::IsNullOrWhiteSpace($env:MSYS2_ENV_CONV_EXCL)) {
  $msysEnvConversionExclusions = @($env:MSYS2_ENV_CONV_EXCL -split ';' | Where-Object { $_ })
}
if (-not ($msysEnvConversionExclusions | Where-Object { $_ -ceq 'CL=' })) {
  $msysEnvConversionExclusions += 'CL='
}
$env:MSYS2_ENV_CONV_EXCL = $msysEnvConversionExclusions -join ';'

function Convert-ToBashPath([string]$Path) {
  $converted = & $script:GitBash -c 'cygpath -u "$1"' _ $Path
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($converted)) {
    throw "Could not convert path for Git Bash: $Path"
  }
  return $converted.Trim()
}

function Invoke-BashChecked([string[]]$Arguments) {
  & $script:GitBash @Arguments
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

$clCompiler = Get-Command cl.exe -ErrorAction SilentlyContinue
if ($null -eq $clCompiler) {
  throw "MSVC cl.exe is not on PATH. Run this script from a Visual Studio Developer PowerShell or initialize VsDevCmd.bat -arch=x64 -host_arch=x64 first."
}
Write-Output "Using MSVC compiler: $($clCompiler.Source)"
$pythonCandidates = @()
if (-not [string]::IsNullOrWhiteSpace($env:YAMI_PYTHON_PATH)) {
  if (-not (Test-Path -LiteralPath $env:YAMI_PYTHON_PATH)) {
    throw "YAMI_PYTHON_PATH does not exist: $env:YAMI_PYTHON_PATH"
  }
  $pythonCandidates = @($env:YAMI_PYTHON_PATH)
} else {
  foreach ($name in @('python3.exe', 'python.exe')) {
    foreach ($candidate in @(Get-Command $name -All -ErrorAction SilentlyContinue)) {
      if ($candidate.CommandType -eq 'Application' -and $pythonCandidates -notcontains $candidate.Source) {
        $pythonCandidates += $candidate.Source
      }
    }
  }
}
$pythonPath = $null
foreach ($candidatePath in $pythonCandidates) {
  $pythonVersion = & $candidatePath -c "import sys; print('%d.%d' % sys.version_info[:2])" 2>$null
  if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($pythonVersion)) {
    try {
      if ([version]$pythonVersion.Trim() -ge [version]'3.11') {
        $pythonPath = $candidatePath
        break
      }
    } catch {
      # Continue to another executable if this command did not report a version.
    }
  }
}
if ($null -eq $pythonPath) {
  throw "Python 3.11 or newer is required. Install Python or set YAMI_PYTHON_PATH to its executable; Microsoft Store aliases are ignored."
}
$env:YAMI_PYTHON_BIN = Convert-ToBashPath $pythonPath
$bashPython = $env:YAMI_PYTHON_BIN
Write-Output "Using Python: $pythonPath"
moon version --all

$env:YAMI_NATIVE_UI_EVIDENCE_DIR = $EvidenceDirectory
Invoke-BashChecked @($workspaceScript, "sh", $testsScript)
Invoke-BashChecked @(
  $workspaceScript,
  $bashPython,
  $driverScript,
  "--platform", "windows",
  "--evidence-dir", $bashEvidence,
  "--log", "$bashEvidence/native-ui.log",
  "--",
  "moon", "run", $examplePackage, "--target", "native"
)
