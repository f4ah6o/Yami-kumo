param(
  [string]$GpuiSource = $env:GPUI_SOURCE,
  [string]$EvidenceDirectory = $env:YAMI_NATIVE_UI_EVIDENCE_DIR,
  [string]$GitBashPath = $env:YAMI_GIT_BASH,
  [switch]$TestsOnly
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
if ([string]::IsNullOrWhiteSpace($GitBashPath)) {
  $gitBash = $null
  foreach ($gitCommand in @(Get-Command git.exe -All -ErrorAction SilentlyContinue)) {
    $directory = Get-Item -LiteralPath (Split-Path -Path $gitCommand.Source -Parent)
    while ($null -ne $directory) {
      foreach ($relativePath in @('bin\bash.exe', 'usr\bin\bash.exe')) {
        $candidate = Join-Path $directory.FullName $relativePath
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
          $gitBash = $candidate
          break
        }
      }
      if ($null -ne $gitBash) { break }
      $directory = $directory.Parent
    }
    if ($null -ne $gitBash) { break }
  }
  if ($null -eq $gitBash) {
    throw "Git Bash was not found beside any Git for Windows executable on PATH. Set YAMI_GIT_BASH to its bash.exe path."
  }
} else {
  if (-not (Test-Path -LiteralPath $GitBashPath -PathType Leaf)) {
    throw "YAMI_GIT_BASH does not exist: $GitBashPath"
  }
  $gitBash = (Resolve-Path -LiteralPath $GitBashPath).Path
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
if (-not ($msysEnvConversionExclusions | Where-Object { $_ -ceq 'YAMI_SELECTED_PYTHON_PATH=' })) {
  $msysEnvConversionExclusions += 'YAMI_SELECTED_PYTHON_PATH='
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
  try {
    $pythonVersion = & $candidatePath -c "import sys; print('%d.%d' % sys.version_info[:2])" 2>$null
    $pythonExitCode = $LASTEXITCODE
  } catch {
    # Windows Store execution aliases can write stderr and terminate a native
    # command under Windows PowerShell 5.1 even when it is redirected.
    continue
  }
  if ($pythonExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($pythonVersion)) {
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
$pythonPath = (Resolve-Path -LiteralPath $pythonPath).Path
$bashPython = Convert-ToBashPath $pythonPath
Write-Output "Using Python: $pythonPath"
$pythonDirectory = Split-Path -Path $pythonPath -Parent
$pythonShimDirectory = Join-Path ([IO.Path]::GetTempPath()) ("yami-native-ui-python-$PID-" + [guid]::NewGuid().ToString('N'))
$forwarderSource = Join-Path $PSScriptRoot 'native_ui_python_forwarder.c'
$forwarderPath = Join-Path $pythonShimDirectory 'python3.exe'
$forwarderObject = Join-Path $pythonShimDirectory 'python3_forwarder.obj'
$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$originalPath = $env:PATH
New-Item -ItemType Directory -Path $pythonShimDirectory | Out-Null
try {
  # Moon runs GPUI's Python prebuild by the name `python3`. A native forwarder
  # keeps the selected interpreter at its original path, which preserves venv
  # discovery, and inherits the runner's stdio while forwarding argv and exit.
  if (-not (Test-Path -LiteralPath $forwarderSource -PathType Leaf)) {
    throw "Python forwarder source was not found: $forwarderSource"
  }
  & cl.exe /nologo /O2 /W4 /DUNICODE /D_UNICODE "/Fo:$forwarderObject" "/Fe:$forwarderPath" $forwarderSource /link Shell32.lib
  if ($LASTEXITCODE -ne 0) {
    throw "Could not build the Python forwarder (cl.exe exit code $LASTEXITCODE)"
  }
  $env:PATH = "$pythonShimDirectory;$pythonDirectory;$originalPath"
  $env:YAMI_SELECTED_PYTHON_PATH = $pythonPath
  $env:YAMI_PYTHON_BIN = $bashPython
  $env:YAMI_PYTHON_FORWARDER_PATH = $forwarderPath
  $forwarderTest = Join-Path $yamiRoot 'tests\native-ui\test_windows_python_forwarder.py'
  & $pythonPath $forwarderTest
  if ($LASTEXITCODE -ne 0) {
    throw "Python forwarder contract test failed with exit code $LASTEXITCODE"
  }
  Write-Output "Using Python 3 alias for Moon prebuild: $(Join-Path $pythonShimDirectory 'python3.exe')"
  moon version --all

  $env:YAMI_NATIVE_UI_EVIDENCE_DIR = $EvidenceDirectory
  Invoke-BashChecked @($workspaceScript, "sh", $testsScript)
  if ($TestsOnly) {
    Write-Output 'Tests-only mode passed; skipping the visible Windows sample E2E.'
    return
  }
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
} finally {
  $env:PATH = $originalPath
  $resolvedShimDirectory = [IO.Path]::GetFullPath($pythonShimDirectory)
  if ($resolvedShimDirectory.StartsWith("$temporaryRoot\", [StringComparison]::OrdinalIgnoreCase) -and
      (Split-Path -Path $resolvedShimDirectory -Leaf).StartsWith("yami-native-ui-python-$PID-", [StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $resolvedShimDirectory -Recurse -Force
  }
}
