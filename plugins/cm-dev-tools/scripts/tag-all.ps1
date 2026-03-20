<#
.SYNOPSIS
    Tags all 5 CM repos in dependency order.
.DESCRIPTION
    Creates git tags and pushes them in the correct dependency order:
    core → plugins → tui → web.
.PARAMETER Version
    Semver tag (e.g., "v0.5.0"). Required.
.PARAMETER DryRun
    Show what would be tagged without actually tagging.
.EXAMPLE
    .\tag-all.ps1 -Version v0.5.0
    .\tag-all.ps1 -Version v0.5.0 -DryRun
#>
param(
    [Parameter(Mandatory)]
    [string]$Version,

    [switch]$DryRun
)

if ($Version -notmatch '^v\d+\.\d+\.\d+$') {
    Write-Error "Version must be semver format: v{MAJOR}.{MINOR}.{PATCH}"
    return
}

$repoBase = 'C:\Users\marius\repo'
$depOrder = @(
    'config-manager-core',
    'cm-plugin-network',
    'cm-plugin-update',
    'config-manager-tui',
    'config-manager-web'
)

foreach ($repo in $depOrder) {
    $path = Join-Path $repoBase $repo
    if (-not (Test-Path $path)) {
        Write-Error "$repo not found at $path"
        return
    }

    Push-Location $path
    try {
        # Verify clean working tree
        $status = git status --porcelain 2>$null
        if ($status) {
            Write-Error "$repo has uncommitted changes — aborting"
            Pop-Location
            return
        }

        # Verify on main branch
        $branch = git branch --show-current 2>$null
        if ($branch -ne 'main') {
            Write-Error "$repo is on branch '$branch', not 'main' — aborting"
            Pop-Location
            return
        }

        if ($DryRun) {
            Write-Output "[DRY RUN] Would tag $repo at $Version"
        }
        else {
            Write-Output "Tagging $repo at $Version..."
            git tag $Version 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to create tag $Version in $repo"
                Pop-Location
                return
            }
            git push origin $Version 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to push tag $Version in $repo"
                Pop-Location
                return
            }
            Write-Output "  ✅ $repo tagged and pushed $Version"
        }
    }
    finally {
        Pop-Location
    }
}

Write-Output "`n✅ All repos tagged at $Version"
