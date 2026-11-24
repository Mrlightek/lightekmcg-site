# Run as SYSTEM from the fixed LightekEndpointPatch scheduled task.
$ErrorActionPreference = 'Stop'
$Root = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'Lightek\EndpointPatch'

function Find-ExactUpdate($Searcher, [string]$Id, [int]$Revision, [int]$Installed) {
    $found = $Searcher.Search("UpdateID='$Id' and RevisionNumber=$Revision and IsInstalled=$Installed")
    if ([int]$found.ResultCode -ne 2) { throw 'Windows Update search failed' }
    if ($found.Updates.Count -eq 1) {
        $update = $found.Updates.Item(0)
        if ($update.Identity.UpdateID -eq $Id -and $update.Identity.RevisionNumber -eq $Revision) { return $update }
    }
}

function Install-ExactUpdate([string]$Target) {
    if ($Target -cnotmatch '^([0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})=([1-9][0-9]{0,8})\z') {
        return @{ status = 'unavailable' }
    }
    $id = $Matches[1]
    $revision = [int]$Matches[2]
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $existing = Find-ExactUpdate $searcher $id $revision 1
    if ($null -ne $existing) {
        if ($existing.RebootRequired) { return @{ status = 'pending_restart' } }
        return @{ status = 'installed'; target = $Target }
    }
    $update = Find-ExactUpdate $searcher $id $revision 0
    if ($null -eq $update -or [int]$update.Type -ne 1 -or $update.IsHidden -or
        $update.InstallationBehavior.CanRequestUserInput) { return @{ status = 'unavailable' } }

    $installer = $session.CreateUpdateInstaller()
    if ($installer.IsBusy -or $installer.RebootRequiredBeforeInstallation) {
        return @{ status = 'unavailable' }
    }
    if (!$update.EulaAccepted) { $update.AcceptEula() }
    $collection = New-Object -ComObject Microsoft.Update.UpdateColl
    [void]$collection.Add($update)
    if (!$update.IsDownloaded) {
        $downloader = $session.CreateUpdateDownloader()
        $downloader.Updates = $collection
        $download = $downloader.Download()
        if ([int]$download.ResultCode -ne 2 -or [int]$download.GetUpdateResult(0).ResultCode -ne 2) {
            return @{ status = 'failed' }
        }
    }
    $installer.Updates = $collection
    $installer.ForceQuiet = $true
    $installer.AllowSourcePrompts = $false
    $installation = $installer.Install()
    if ([int]$installation.ResultCode -ne 2 -or [int]$installation.GetUpdateResult(0).ResultCode -ne 2) {
        return @{ status = 'failed' }
    }
    if ($installation.RebootRequired) { return @{ status = 'pending_restart' } }
    $installed = Find-ExactUpdate $searcher $id $revision 1
    if ($null -eq $installed) { return @{ status = 'failed' } }
    if ($installed.RebootRequired) { return @{ status = 'pending_restart' } }
    return @{ status = 'installed'; target = $Target }
}

# The task permits one instance. Move the request into the SYSTEM-only work directory.
$inbox = Join-Path $Root 'inbox\request.json'
$work = Join-Path $Root 'work\request.json'
$resultFile = Join-Path $Root 'outbox\result.json'
if (!(Test-Path -LiteralPath $inbox -PathType Leaf)) { exit 0 }
try {
    Move-Item -LiteralPath $inbox -Destination $work
    $item = Get-Item -LiteralPath $work
    if ($item.Length -gt 1024 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { exit 1 }
    $request = Get-Content -LiteralPath $work -Raw | ConvertFrom-Json
    if ($request.id -isnot [string] -or $request.id -cnotmatch '^[0-9a-f]{32}\z') { exit 1 }
    $deadline = [DateTimeOffset]::Parse($request.deadline)
    $policy = (Get-Content -LiteralPath (Join-Path $Root 'policy.txt') -Raw).Trim()
    $result = @{ status = 'unavailable' }
    if ($deadline -gt [DateTimeOffset]::UtcNow -and $deadline -le [DateTimeOffset]::UtcNow.AddMinutes(11) -and
        $request.target -is [string] -and $request.target -ceq $policy) {
        try { $result = Install-ExactUpdate $request.target }
        catch { $result = @{ status = 'failed' } }
    }
    $encoded = @{ id = $request.id; result = $result } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText("$resultFile.tmp", $encoded)
    if ([IO.File]::Exists($resultFile)) { [IO.File]::Replace("$resultFile.tmp", $resultFile, $null) }
    else { [IO.File]::Move("$resultFile.tmp", $resultFile) }
} finally {
    Remove-Item -LiteralPath $work -Force -ErrorAction SilentlyContinue
}
