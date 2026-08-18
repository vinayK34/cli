$ErrorActionPreference = 'Stop'

# HTTPie is installed into an existing Python installation via pip, so we need
# a Python interpreter — but NOT necessarily a Chocolatey-managed one. Declaring
# a hard `python3` dependency in the .nuspec makes Chocolatey install its own
# Python even when a perfectly good one is already present (e.g. installed from
# python.org), and that second install can fail outright, taking the whole
# `choco install httpie` down with it. See:
# https://github.com/httpie/cli/issues/1621
# Instead, we detect whatever Python is already available and only ask the user
# to install one when there is genuinely none.

$MinimumPythonVersion = [version]'3.7'
$VersionProbe = 'import sys; sys.stdout.write(".".join(str(part) for part in sys.version_info[:3]))'

function Get-UsablePython {
    # In order of preference. `py` is the Windows Python launcher: it finds
    # interpreters registered by any installer, not just Chocolatey's.
    $candidates = @(
        @{ Command = 'py'      ; Prefix = @('-3') },
        @{ Command = 'python'  ; Prefix = @() },
        @{ Command = 'python3' ; Prefix = @() }
    )

    foreach ($candidate in $candidates) {
        $resolved = Get-Command $candidate.Command -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $resolved) { continue }

        $reported = & $resolved.Path @($candidate.Prefix + @('-c', $VersionProbe)) 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($reported)) { continue }

        try { $version = [version]$reported.Trim() } catch { continue }
        if ($version -lt $MinimumPythonVersion) { continue }

        return [pscustomobject]@{
            Path    = $resolved.Path
            Prefix  = $candidate.Prefix
            Version = $version
        }
    }

    return $null
}

$python = Get-UsablePython
if (-not $python) {
    throw @"
HTTPie needs Python $MinimumPythonVersion or newer, but no usable Python interpreter was found on PATH.
Install Python, then run ``choco install httpie`` again:
    choco install python3
Or download an installer from https://www.python.org/downloads/windows/
(make sure "Add Python to PATH" is enabled).
"@
}

Write-Host "Installing HTTPie with Python $($python.Version) from '$($python.Path)'."

& $python.Path @($python.Prefix + @(
    '-m', 'pip', 'install',
    "$env:ChocolateyPackageName==$env:ChocolateyPackageVersion",
    '--disable-pip-version-check'
))
if ($LASTEXITCODE -ne 0) {
    throw "pip failed to install $env:ChocolateyPackageName==$env:ChocolateyPackageVersion (exit code $LASTEXITCODE)."
}
