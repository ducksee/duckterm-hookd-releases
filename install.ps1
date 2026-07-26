[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if ([Net.ServicePointManager]::SecurityProtocol -band [Net.SecurityProtocolType]::Tls12) {
  # TLS 1.2 is already enabled.
} else {
  [Net.ServicePointManager]::SecurityProtocol = `
    [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

$releaseRepository = 'ducksee/duckterm-hookd-releases'
$latestUrl = "https://raw.githubusercontent.com/$releaseRepository/main/LATEST"
$releaseBaseUrl = "https://github.com/$releaseRepository/releases/download"

function Write-HookdStep {
  param([Parameter(Mandatory = $true)][string]$Message)
  Write-Host "[hookd] $Message"
}

function Resolve-HookdArchitecture {
  $nativeArchitecture = if ($env:PROCESSOR_ARCHITEW6432) {
    $env:PROCESSOR_ARCHITEW6432
  } else {
    $env:PROCESSOR_ARCHITECTURE
  }

  switch ($nativeArchitecture.ToUpperInvariant()) {
    'AMD64' { return 'amd64' }
    'ARM64' { return 'arm64' }
    default { throw "Unsupported Windows architecture: $nativeArchitecture" }
  }
}

function Copy-HookdExecutable {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination
  )

  $copied = $false
  for ($attempt = 0; $attempt -lt 20; $attempt++) {
    try {
      Copy-Item -LiteralPath $Source -Destination $Destination -Force
      $copied = $true
      break
    } catch {
      Start-Sleep -Milliseconds 250
    }
  }
  if (-not $copied) {
    throw "Could not replace $Destination. Stop the running Hookd process and retry."
  }
}

$architecture = Resolve-HookdArchitecture
$version = ([string](Invoke-RestMethod -UseBasicParsing -Uri $latestUrl)).Trim()
if ($version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') {
  throw "Release server returned an invalid Hookd version: $version"
}

$asset = "duckterm-hookd_windows-$architecture.zip"
$releaseRoot = "$releaseBaseUrl/v$version"
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("duckterm-hookd-install-" + [Guid]::NewGuid().ToString('N'))
$archivePath = Join-Path $temporaryRoot $asset
$stagePath = Join-Path $temporaryRoot 'package'
$localAppData = if ($env:LOCALAPPDATA) {
  $env:LOCALAPPDATA
} else {
  Join-Path $env:USERPROFILE 'AppData\Local'
}
$installDirectory = Join-Path $localAppData 'Programs\duckterm-hookd'
$executablePath = Join-Path $installDirectory 'duckterm-hookd.exe'
$bundlePath = Join-Path $installDirectory 'duckterm-hookd-web.tar.gz'

New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null

try {
  Write-HookdStep "downloading DuckTerm Hookd v$version for Windows $architecture"
  $checksums = [string](Invoke-RestMethod -UseBasicParsing -Uri "$releaseRoot/SHA256SUMS")
  $checksumPattern = '(?m)^([0-9a-fA-F]{64})\s+\*?' + [Regex]::Escape($asset) + '\s*$'
  $checksumMatch = [Regex]::Match($checksums, $checksumPattern)
  if (-not $checksumMatch.Success) {
    throw "Release checksum is missing for $asset"
  }

  Invoke-WebRequest -UseBasicParsing -Uri "$releaseRoot/$asset" -OutFile $archivePath
  $actualChecksum = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
  $expectedChecksum = $checksumMatch.Groups[1].Value.ToLowerInvariant()
  if ($actualChecksum -ne $expectedChecksum) {
    throw "SHA256 verification failed for $asset"
  }
  Write-HookdStep 'sha256 verified'

  Expand-Archive -LiteralPath $archivePath -DestinationPath $stagePath -Force
  $stagedExecutable = Join-Path $stagePath 'duckterm-hookd.exe'
  if (-not (Test-Path -LiteralPath $stagedExecutable -PathType Leaf)) {
    throw 'Windows release does not contain duckterm-hookd.exe'
  }

  New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
  & schtasks.exe /End /TN 'DuckTerm Hookd' 2>$null | Out-Null
  Copy-HookdExecutable -Source $stagedExecutable -Destination $executablePath

  $stagedBundle = Join-Path $stagePath 'duckterm-hookd-web.tar.gz'
  if (Test-Path -LiteralPath $stagedBundle -PathType Leaf) {
    Copy-Item -LiteralPath $stagedBundle -Destination $bundlePath -Force
    try {
      & $executablePath ui bootstrap $bundlePath
    } catch {
      Write-Warning 'Bundled Hookd UI could not be installed. Run: duckterm-hookd ui upgrade'
    }
  }

  $installedVersion = (& $executablePath version 2>&1 | Out-String).Trim()
  if ($LASTEXITCODE -ne 0 -or $installedVersion -notmatch [Regex]::Escape($version)) {
    throw "Installed Hookd binary did not report v$version"
  }
  Write-HookdStep "installed $executablePath ($installedVersion)"
  Write-HookdStep 'starting QR setup'
  & $executablePath setup --qr
  if ($LASTEXITCODE -ne 0) {
    throw "Hookd setup failed with exit code $LASTEXITCODE"
  }
} finally {
  Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
}
