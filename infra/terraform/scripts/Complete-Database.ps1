$ErrorActionPreference = 'Stop'
$infraDirectory = 'E:\download\AzureLab\AzureLab\infra\terraform'
$scriptPath = Join-Path $infraDirectory 'scripts\prepare-database.sh'
$azPython = 'C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\python.exe'

function Read-AzureJson {
    param([string[]]$Arguments)
    $result = & $azPython -IBm azure.cli @Arguments --output json
    if ($LASTEXITCODE -ne 0) { throw 'Azure CLI failed. See the error above.' }
    return (($result -join "`n") | ConvertFrom-Json)
}

$source = [IO.File]::ReadAllText($scriptPath).Replace("`r`n", "`n").TrimStart([char]0xFEFF)
if ($source.Length -lt 500 -or -not $source.Contains('DATABASE PREPARATION COMPLETE')) {
    throw 'Database script is incomplete. No request was sent.'
}

$account = Read-AzureJson -Arguments @('account', 'show')
$server = Read-AzureJson -Arguments @('postgres', 'flexible-server', 'show', '--resource-group', 'rg-azurelab-dev', '--name', 'psql-azurelab-b436d920')
$token = Read-AzureJson -Arguments @('account', 'get-access-token', '--resource', 'https://management.azure.com/')
$headers = @{ Authorization = "Bearer $($token.accessToken)" }
$commandUrl = "https://management.azure.com/subscriptions/$($account.id)/resourceGroups/rg-azurelab-dev/providers/Microsoft.Compute/virtualMachines/vm-admin-azurelab/runCommands/prepare-database?api-version=2024-11-01"

$passwordInput = Read-Host 'Enter the EXISTING PostgreSQL labadmin password' -AsSecureString
$passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($passwordInput)
try {
    $passwordText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
    if ([string]::IsNullOrEmpty($passwordText)) { throw 'Password must not be empty.' }

    $request = @{
        location = 'koreacentral'
        properties = @{
            source = @{ script = $source }
            parameters = @(
                @{ name = 'PGHOST'; value = $server.fullyQualifiedDomainName },
                @{ name = 'VAULT_NAME'; value = 'kv-azurelab-b436d920' }
            )
            protectedParameters = @(
                @{ name = 'ADMIN_PASSWORD'; value = $passwordText }
            )
            timeoutInSeconds = 600
        }
    }
    $requestJson = $request | ConvertTo-Json -Depth 10 -Compress
    $response = Invoke-RestMethod -Method Put -Uri $commandUrl -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($requestJson))
    if ($response.properties.source.script.Length -ne $source.Length) {
        throw 'Azure did not retain the full script. Check the command before retrying.'
    }
    Write-Host "Full script submitted ($($source.Length) characters). Waiting for execution..."
}
finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    Remove-Variable passwordText, passwordInput, request, requestJson -ErrorAction SilentlyContinue
}

$deadline = (Get-Date).AddMinutes(12)
do {
    Start-Sleep -Seconds 5
    $status = Invoke-RestMethod -Method Get -Uri ($commandUrl + '&$expand=instanceView') -Headers $headers
    $view = $status.properties.instanceView
    if ($view.executionState -in @('Succeeded', 'Failed', 'Canceled', 'TimedOut')) { break }
} while ((Get-Date) -lt $deadline)

if (-not $view -or $view.executionState -ne 'Succeeded' -or $view.exitCode -ne 0 -or -not $view.output.Contains('DATABASE PREPARATION COMPLETE')) {
    $view | Select-Object executionState, exitCode, executionMessage, output, error | Format-List
    throw 'Database preparation was not verified. Do not rerun blindly.'
}
Write-Host $view.output
Write-Host 'Verified: application login and database-url creation succeeded.'
