<#
.SYNOPSIS
    Shows git status, branch, and last tag for CM repos.
.DESCRIPTION
    Quick overview of all 5 CM repos: current branch, clean/dirty, last tag.
.PARAMETER Repo
    Optional — single repo name. If omitted, shows all 5.
.EXAMPLE
    .\repo-status.ps1
    .\repo-status.ps1 -Repo config-manager-core
#>
param(
    [string]$Repo
)

$repos = @(
    'config-manager-core',
    'cm-plugin-network',
    'cm-plugin-update',
    'config-manager-tui',
    'config-manager-web'
)

$repoBase = 'C:\Users\marius\repo'

if ($Repo) { $repos = @($Repo) }

foreach ($r in $repos) {
    $path = Join-Path $repoBase $r
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
