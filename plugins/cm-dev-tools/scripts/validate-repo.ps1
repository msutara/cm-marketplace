<#
.SYNOPSIS
    Validates a single CM repo: build + test + lint.
.DESCRIPTION
    Runs go build, go test, and golangci-lint in the specified repo directory.
    Returns structured output for each step.
.PARAMETER RepoPath
    Full path to the repository directory.
.PARAMETER SkipLint
    Skip golangci-lint (useful if not installed).
.PARAMETER SkipMarkdown
    Skip markdownlint-cli2.
.EXAMPLE
    .\validate-repo.ps1 -RepoPath "C:\Users\marius\repo\config-manager-core"
#>
param(
    [Parameter(Mandatory)]
    [string]$RepoPath,

    [switch]$SkipLint,
    [switch]$SkipMarkdown
)

$ErrorActionPreference = 'Continue'
$results = @{
    repo    = Split-Path $RepoPath -Leaf
    path    = $RepoPath
    success = $true
    steps   = @()
}

function Run-Step {
    param([string]$Name, [string]$Command, [string[]]$Args)
    $step = @{ name = $Name; success = $false; output = ''; duration = '' }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $proc = Start-Process -FilePath $Command -ArgumentList $Args -WorkingDirectory $RepoPath `
            -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$env:TEMP\cm-$Name-out.txt" `
            -RedirectStandardError "$env:TEMP\cm-$Name-err.txt"
        $stdout = Get-Content "$env:TEMP\cm-$Name-out.txt" -Raw -ErrorAction SilentlyContinue
        $stderr = Get-Content "$env:TEMP\cm-$Name-err.txt" -Raw -ErrorAction SilentlyContinue
        $step.output = if ($stdout) { $stdout.Trim() } else { $stderr.Trim() }
        $step.success = $proc.ExitCode -eq 0
    }
    catch {
        $step.output = $_.Exception.Message
    }
    $sw.Stop()
    $step.duration = "$([math]::Round($sw.Elapsed.TotalSeconds, 1))s"
    return $step
}

Push-Location $RepoPath
try {
    # Build
    $buildStep = Run-Step -Name 'build' -Command 'go' -Args @('build', './...')
    $results.steps += $buildStep
    if (-not $buildStep.success) { $results.success = $false }

    # Test
    $testStep = Run-Step -Name 'test' -Command 'go' -Args @('test', './...')
    $results.steps += $testStep
    if (-not $testStep.success) { $results.success = $false }

    # Lint
    if (-not $SkipLint) {
        $lintStep = Run-Step -Name 'lint' -Command 'golangci-lint' -Args @('run')
        $results.steps += $lintStep
        if (-not $lintStep.success) { $results.success = $false }
    }

    # Markdownlint
    if (-not $SkipMarkdown) {
        $mdStep = Run-Step -Name 'markdownlint' -Command 'markdownlint-cli2' -Args @('"**/*.md"', '"#node_modules"')
        $results.steps += $mdStep
        if (-not $mdStep.success) { $results.success = $false }
    }
}
finally {
    Pop-Location
}

# Output
$icon = if ($results.success) { '✅' } else { '❌' }
Write-Output "$icon $($results.repo)"
foreach ($s in $results.steps) {
    $si = if ($s.success) { '  ✅' } else { '  ❌' }
    Write-Output "$si $($s.name) ($($s.duration))"
    if (-not $s.success -and $s.output) {
        $s.output -split "`n" | Select-Object -First 10 | ForEach-Object { Write-Output "     $_" }
    }
}

# Return structured result for piping
$results
