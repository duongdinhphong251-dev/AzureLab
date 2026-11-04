$ErrorActionPreference = 'Stop'
# Bypass az.cmd: cmd.exe misinterprets & in ARM query URLs.
$azCommand = Get-Command az -ErrorAction Stop
$azPython = [IO.Path]::GetFullPath((Join-Path (Split-Path $azCommand.Source -Parent) '..\python.exe'))
if (-not (Test-Path -LiteralPath $azPython)) { throw 'Azure CLI Python executable not found.' }
$scriptPath = Join-Path $PSScriptRoot 'build-image.sh'
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw "Missing script: $scriptPath"
}
$scriptContent = [IO.File]::ReadAllText($scriptPath).Replace("`r`n", "`n").TrimStart([char]0xFEFF)
if (-not $scriptContent.Contains('BUILD AND PUSH COMPLETE')) { throw 'Incomplete build script.' }

$subscriptionId = & $azPython -X utf8 -IBm azure.cli account show --query id --output tsv
if ($LASTEXITCODE -ne 0) { throw 'Could not read Azure subscription.' }
$commandUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/rg-azurelab-dev/providers/Microsoft.Compute/virtualMachines/vm-admin-azurelab/runCommands/build-images?api-version=2024-11-01"
$request = @{
    location = 'koreacentral'
    properties = @{
        source = @{ script = $scriptContent }
        timeoutInSeconds = 1800
        asyncExecution = $true
    }
}
$requestFile = Join-Path ([IO.Path]::GetTempPath()) ('azurelab-build-' + [guid]::NewGuid().ToString('N') + '.json')
try {
    [IO.File]::WriteAllText($requestFile, ($request | ConvertTo-Json -Depth 10 -Compress), [Text.UTF8Encoding]::new($false))
    & $azPython -X utf8 -IBm azure.cli rest --method put --url $commandUrl --body "@$requestFile" --output none
    if ($LASTEXITCODE -ne 0) { throw 'Could not submit build script.' }
}
finally {
    if (Test-Path -LiteralPath $requestFile) { Remove-Item -LiteralPath $requestFile }
}

Write-Host 'Build submitted. Waiting for the VM; do not run this script again while it is running.'
$deadline = (Get-Date).AddMinutes(32)
do {
    Start-Sleep -Seconds 15
    $statusJson = & $azPython -X utf8 -IBm azure.cli rest --method get --url ($commandUrl + '&$expand=instanceView') --query properties.instanceView --output json
    if ($LASTEXITCODE -ne 0) { throw 'Could not retrieve build status.' }
    $status = ($statusJson -join "`n") | ConvertFrom-Json
    Write-Host ("Build state: " + $status.executionState)
    if ($status.executionState -in @('Succeeded', 'Failed', 'Canceled', 'TimedOut')) { break }
} while ((Get-Date) -lt $deadline)

Write-Host $status.output
if ($status.error) { Write-Host $status.error }
if ($status.executionState -ne 'Succeeded' -or $status.exitCode -ne 0 -or -not ([string]$status.output).Contains('BUILD AND PUSH COMPLETE')) {
    throw ('Build was not verified. State=' + $status.executionState + ', ExitCode=' + $status.exitCode)
}
