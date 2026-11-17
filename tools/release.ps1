<#
.SYNOPSIS
    Builds the Release .esriAddinX for both supported ArcGIS Pro versions and publishes them as
    assets on a new GitHub Release.

.DESCRIPTION
    Requires ArcGIS Pro + the ArcGIS Pro SDK for .NET installed locally (the project's build
    targets and assembly references live under "C:\Program Files\ArcGIS\Pro\bin", so this cannot
    run on a hosted CI runner -- see docs-src/installation.md). Also requires the GitHub CLI
    ("gh"), authenticated ("gh auth login"), with push/release permission on the repo.

    Builds both versions from ONE branch (default "master"), in a temporary git worktree, so your
    current checkout and any uncommitted work are left untouched. The single StacProAddin.csproj
    targets net8.0-windows (Pro 3.6.x); the 3.7.x build overrides the target framework to
    net10.0-windows on the command line. No branch is modified or committed to.

.PARAMETER Version
    Release version, without a leading "v" (e.g. "1.2.0"). The GitHub tag and release title are
    "v<Version>".

.PARAMETER Branch
    The branch to build both versions from. Defaults to "master".

.PARAMETER Notes
    Release notes. If omitted, gh auto-generates notes from commits since the previous tag.

.PARAMETER DryRun
    Build and stage both .esriAddinX files but skip creating the GitHub release. The staged files
    are left in release-staging\ for inspection.

.EXAMPLE
    tools\release.ps1 -Version 1.2.0

.EXAMPLE
    tools\release.ps1 -Version 1.2.0 -Notes "Adds the Help button and per-section docs links."
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version,

    [string]$Branch = "master",

    [string]$Notes,

    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$tag = "v$Version"

function Find-MSBuild {
    $vswhere = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) {
        throw "vswhere.exe not found at '$vswhere' -- install Visual Studio, or edit this script to point at MSBuild.exe directly."
    }
    $msbuildPath = & $vswhere -latest -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe | Select-Object -First 1
    if (-not $msbuildPath) {
        throw "vswhere couldn't find an MSBuild.exe. Is Visual Studio (with the ArcGIS Pro SDK workload) installed?"
    }
    return $msbuildPath
}

function Assert-GhReady {
    $null = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $?) {
        throw "GitHub CLI ('gh') not found on PATH. Install it (winget install --id GitHub.cli) and run 'gh auth login'."
    }
    # Redirect stdout only -- redirecting stderr here would turn gh's non-zero exit into a
    # terminating error (via $ErrorActionPreference) before the friendlier throw below runs.
    gh auth status 1> $null
    if ($LASTEXITCODE -ne 0) {
        throw "gh is not authenticated. Run 'gh auth login' first."
    }
}

if (-not $DryRun) { Assert-GhReady }
$msbuild = Find-MSBuild
Write-Host "Using MSBuild: $msbuild"

$repoRoot = (git rev-parse --show-toplevel).Trim()
if (-not $repoRoot) { throw "Not inside a git repository." }
Push-Location $repoRoot
try {
    $status = git status --porcelain
    # Worktrees build in isolated checkouts, so a dirty current tree is not itself unsafe -- but
    # warn anyway, since it's easy to forget you meant to commit something first.
    if ($status) {
        Write-Warning "Your current checkout has uncommitted changes. They are NOT included in the release build (each branch is built from its own committed tip in a separate worktree)."
    }

    $targets = @(
        @{ Tfm = "net8.0-windows";  AssetName = "StacProAddin-3.6.x.esriAddinX" },
        @{ Tfm = "net10.0-windows"; AssetName = "StacProAddin-3.7.x.esriAddinX" }
    )

    $stagingDir = Join-Path $repoRoot "release-staging"
    if (Test-Path $stagingDir) { Remove-Item $stagingDir -Recurse -Force }
    New-Item -ItemType Directory -Path $stagingDir | Out-Null

    $worktreeName = "stac-release-$($Branch -replace '[^\w.]', '-')"
    $worktreePath = Join-Path (Split-Path $repoRoot -Parent) $worktreeName
    if (Test-Path $worktreePath) {
        Write-Host "Removing stale worktree at $worktreePath"
        git worktree remove $worktreePath --force 2>$null
        if (Test-Path $worktreePath) { Remove-Item $worktreePath -Recurse -Force }
    }

    # --detach: $Branch may already be checked out in this repo's main worktree, which
    # "git worktree add <path> <branch>" refuses. Detached HEAD at the branch's tip avoids that.
    git worktree add --detach $worktreePath $Branch
    if ($LASTEXITCODE -ne 0) { throw "git worktree add failed for $Branch" }

    try {
        # Stamp Config.daml's AddInInfo version too, so ArcGIS Pro's own Add-In Manager shows the real
        # version -- cosmetic only, UpdateCheckService compares the assembly version set by /p:Version
        # below, not this. desktopVersion stays "3.6.0" for both builds, so one manifest loads on 3.6 and 3.7.
        $damlPath = Join-Path $worktreePath "Config.daml"
        $daml = Get-Content $damlPath -Raw
        $stamped = $daml -replace '(<AddInInfo\b[^>]*\bversion=")[^"]*(")', "`${1}$Version.0`$2"
        if ($stamped -eq $daml) { throw "Could not find AddInInfo version=`"...`" to stamp in $damlPath" }
        Set-Content $damlPath $stamped -NoNewline

        Push-Location $worktreePath
        try {
            foreach ($t in $targets) {
                Write-Host "`n=== Building $Branch ($($t.Tfm)) ==="
                # /p:Version stamps the compiled assembly's version with this release's version, so the in-app
                # "Check version" button (UpdateCheckService) compares against the right thing. Restore runs per
                # target framework, because project.assets.json is rewritten for whichever one is restored.
                & $msbuild "StacProAddin.csproj" /t:Restore /p:Configuration=Release /p:Version=$Version /p:TargetFramework=$($t.Tfm) /v:minimal
                if ($LASTEXITCODE -ne 0) { throw "Restore failed for $($t.Tfm)" }

                & $msbuild "StacProAddin.csproj" /p:Configuration=Release /p:Version=$Version /p:TargetFramework=$($t.Tfm) /v:minimal
                if ($LASTEXITCODE -ne 0) { throw "Build failed for $($t.Tfm)" }

                $builtFile = Join-Path $worktreePath "bin\Release\$($t.Tfm)\StacProAddin.esriAddinX"
                if (-not (Test-Path $builtFile)) {
                    throw "Expected build output not found: $builtFile"
                }

                $stagedFile = Join-Path $stagingDir $t.AssetName
                Copy-Item $builtFile $stagedFile -Force
                $sizeMb = [math]::Round((Get-Item $stagedFile).Length / 1MB, 1)
                Write-Host "Staged $($t.AssetName) ($sizeMb MB)"
            }
        }
        finally {
            Pop-Location
        }
    }
    finally {
        git worktree remove $worktreePath --force
    }

    if ($DryRun) {
        Write-Host "`n-DryRun set: skipping GitHub release. Staged files are in $stagingDir"
        return
    }

    Write-Host "`n=== Creating GitHub release $tag ==="
    $assetPaths = $targets | ForEach-Object { Join-Path $stagingDir $_.AssetName }
    $ghArgs = @($tag) + $assetPaths + @("--title", $tag, "--target", $Branch)
    if ($Notes) { $ghArgs += @("--notes", $Notes) } else { $ghArgs += "--generate-notes" }

    gh release create @ghArgs
    if ($LASTEXITCODE -ne 0) { throw "gh release create failed" }

    Remove-Item $stagingDir -Recurse -Force
    Write-Host "`nReleased $tag with assets: $($targets.AssetName -join ', ')"
    Write-Host "Stable download links (update once in docs-src/installation.md, never again):"
    foreach ($t in $targets) {
        Write-Host "  https://github.com/ianhorn/stac-arcgispro-addin/releases/latest/download/$($t.AssetName)"
    }
}
finally {
    Pop-Location
}
