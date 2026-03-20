<#
.SYNOPSIS
    Adds a GitHub item to the CM project board and/or updates its status.
.DESCRIPTION
    Wraps `gh project` commands for the Config Manager project board.
.PARAMETER Url
    GitHub URL (issue, PR, or repo) to add.
.PARAMETER Status
    Optional status to set: Backlog, InProgress, Review, Done.
.PARAMETER ItemId
    If updating status only (item already on board), provide the item ID.
.EXAMPLE
    .\project-board.ps1 -Url "https://github.com/msutara/config-manager-core/pull/65"
    .\project-board.ps1 -Url "https://github.com/msutara/config-manager-core/pull/65" -Status Review
#>
param(
    [string]$Url,
    [ValidateSet('Backlog', 'InProgress', 'Review', 'Done')]
    [string]$Status,
    [string]$ItemId
)

$projectId = 'PVT_kwHOAgHix84BPSxN'
$statusFieldId = 'PVTSSF_lAHOAgHix84BPSxNzg9vkrk'
$statusOptions = @{
    'Backlog'    = 'f75ad846'
    'InProgress' = '47fc9ee4'
    'Review'     = 'e70217cf'
    'Done'       = '98236657'
}

# Add item if URL provided
if ($Url) {
    Write-Output "Adding $Url to project board..."
    $addOutput = gh project item-add 1 --owner msutara --url $Url 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Output "  ✅ Added to project"
    }
    else {
        Write-Output "  ⚠️  $addOutput"
    }
}

# Update status if requested
if ($Status) {
    $optionId = $statusOptions[$Status]
    if (-not $ItemId -and $Url) {
        # Try to find the item ID from the URL
        $items = gh project item-list 1 --owner msutara --format json 2>$null | ConvertFrom-Json
        $item = $items.items | Where-Object { $_.content.url -eq $Url }
        if ($item) { $ItemId = $item.id }
    }

    if ($ItemId) {
        $mutation = "mutation { updateProjectV2ItemFieldValue(input: {projectId: \`"$projectId\`", itemId: \`"$ItemId\`", fieldId: \`"$statusFieldId\`", value: {singleSelectOptionId: \`"$optionId\`"}}) { projectV2Item { id } } }"
        gh api graphql -f query="$mutation" 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Output "  ✅ Status updated to $Status"
        }
        else {
            Write-Output "  ❌ Failed to update status"
        }
    }
    else {
        Write-Output "  ⚠️  Could not find item ID — add item first or provide -ItemId"
    }
}
