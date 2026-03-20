<#
.SYNOPSIS
    Shows git status, branch, and last tag for CM repos.
.DESCRIPTION
    Quick overview of all 5 CM repos: current branch, clean/dirty, last tag.
.PARAMETER Repo
    Optional — single repo name. If omitted, shows all 5.
.PARAMETER RepoBase
    Root directory containing the CM repos. Defaults to C:\Users\marius\repo.
    Override when repos are cloned to a different location.
.EXAMPLE
    .\repo-status.ps1
    .\repo-status.ps1 -Repo config-manager-core
    .\repo-status.ps1 -RepoBase D:\projects
#>
param(
    [string]$Repo,
    [string]$RepoBase = 'C:\Users\marius\repo'
)

$repos = @(
    'config-manager-core',
    'cm-plugin-network',
    'cm-plugin-update',
    'config-manager-tui',
    'config-manager-web'
)

if ($Repo) { $repos = @($Repo) }

foreach ($r in $repos) {
    $path = Join-Path $RepoBase $r
    if (-not (Test-Path $path)) {
        Write-Output "⚠️  $r — not found"
        continue
    }

    Push-Location $path
    try {
        $branch = git branch --show-current 2>$null
        $status = git status --porcelain 2>$null
        $lastTag = git describe --tags --abbrev=0 2>$null
        $dirty = if ($status) { $status.Count } else { 0 }
        $cleanIcon = if ($dirty -eq 0) { '✅' } else { "⚠️ ($dirty files)" }

        Write-Output "$r"
        Write-Output "  Branch:   $branch"
        Write-Output "  Clean:    $cleanIcon"
        Write-Output "  Last tag: $(if ($lastTag) { $lastTag } else { '(none)' })"
        Write-Output ""
    }
    finally {
        Pop-Location
    }
}
