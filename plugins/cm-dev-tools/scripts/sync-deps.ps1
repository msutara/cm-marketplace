<#
.SYNOPSIS
    Bumps a go.mod dependency across downstream CM repos.
.DESCRIPTION
    After updating config-manager-core (or a plugin), this script runs
    `go get` + `go mod tidy` in all downstream repos that import it.
.PARAMETER SourceModule
    Go module path (e.g., "github.com/msutara/config-manager-core").
.PARAMETER Version
    Tag or commit hash to update to (e.g., "v0.5.0").
.PARAMETER RepoBase
    Root directory containing the CM repos. Defaults to C:\Users\marius\repo.
    Override when repos are cloned to a different location.
.EXAMPLE
    .\sync-deps.ps1 -SourceModule "github.com/msutara/config-manager-core" -Version "v0.5.0"
    .\sync-deps.ps1 -SourceModule "github.com/msutara/config-manager-core" -Version "v0.5.0" -RepoBase D:\projects
#>
param(
    [Parameter(Mandatory)]
    [string]$SourceModule,

    [Parameter(Mandatory)]
    [string]$Version,

    [string]$RepoBase = 'C:\Users\marius\repo'
)

$allRepos = @(
    'config-manager-core',
    'cm-plugin-network',
    'cm-plugin-update',
    'config-manager-tui',
    'config-manager-web'
)

$updated = @()
$errors = @()

foreach ($repo in $allRepos) {
    $path = Join-Path $RepoBase $repo
    $gomod = Join-Path $path 'go.mod'

    if (-not (Test-Path $gomod)) { continue }

    $content = Get-Content $gomod -Raw
    if ($content -notmatch [regex]::Escape($SourceModule)) {
        continue  # This repo doesn't import the source module
    }

    # Skip self — extract module path and compare exactly
    $moduleLine = ($content -split "`n" | Where-Object { $_ -match '^module ' })[0]
    $thisModule = ($moduleLine -replace '^module\s+', '').Trim()
    if ($thisModule -eq $SourceModule) { continue }

    Write-Output "Updating $repo..."
    Push-Location $path
    try {
        $goGetOutput = go get "$SourceModule@$Version" 2>&1
        if ($LASTEXITCODE -ne 0) {
            $errors += "$repo : go get failed: $goGetOutput"
            continue
        }

        $tidyOutput = go mod tidy 2>&1
        if ($LASTEXITCODE -ne 0) {
            $errors += "$repo : go mod tidy failed: $tidyOutput"
            continue
        }

        Write-Output "  ✅ $repo updated to $SourceModule@$Version"
        $updated += $repo
    }
    finally {
        Pop-Location
    }
}

Write-Output "`n=== Summary ==="
Write-Output "Updated: $($updated -join ', ')"
if ($errors) {
    Write-Output "Errors:"
    $errors | ForEach-Object { Write-Output "  ❌ $_" }
}
