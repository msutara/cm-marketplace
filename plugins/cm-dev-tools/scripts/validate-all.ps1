<#
.SYNOPSIS
    Validates ALL 5 CM repos in sequence.
.DESCRIPTION
    Runs validate-repo.ps1 for each repo and produces a summary.
.PARAMETER SkipLint
    Skip golangci-lint for all repos.
.PARAMETER SkipMarkdown
    Skip markdownlint-cli2 for all repos.
.PARAMETER RepoBase
    Root directory containing the CM repos. Defaults to C:\Users\marius\repo.
    Override when repos are cloned to a different location.
.EXAMPLE
    .\validate-all.ps1
    .\validate-all.ps1 -RepoBase D:\projects
#>
param(
    [switch]$SkipLint,
    [switch]$SkipMarkdown,
    [string]$RepoBase = 'C:\Users\marius\repo'
)

$scriptDir = $PSScriptRoot
$validateScript = Join-Path $scriptDir 'validate-repo.ps1'

$repos = @(
    'config-manager-core',
    'cm-plugin-network',
    'cm-plugin-update',
    'config-manager-tui',
    'config-manager-web'
)

$allPassed = $true
$summaries = @()

foreach ($repo in $repos) {
    $repoPath = Join-Path $RepoBase $repo
    if (-not (Test-Path $repoPath)) {
        Write-Output "⚠️  $repo — directory not found at $repoPath"
        continue
    }

    Write-Output "`n--- $repo ---"
    $params = @{ RepoPath = $repoPath }
    if ($SkipLint) { $params.SkipLint = $true }
    if ($SkipMarkdown) { $params.SkipMarkdown = $true }

    $result = & $validateScript @params
    if (-not $result.success) { $allPassed = $false }
    $summaries += $result
}

Write-Output "`n=== SUMMARY ==="
foreach ($s in $summaries) {
    $icon = if ($s.success) { '✅' } else { '❌' }
    $steps = ($s.steps | ForEach-Object {
        $si = if ($_.success) { '✓' } else { '✗' }
        "$si$($_.name)"
    }) -join ' '
    Write-Output "$icon $($s.repo): $steps"
}

$overallIcon = if ($allPassed) { '✅' } else { '❌' }
Write-Output "`n$overallIcon Overall: $(if ($allPassed) { 'ALL PASSED' } else { 'FAILURES DETECTED' })"
