#!/usr/bin/env powershell
<#
.SYNOPSIS
    Get Function App Keys and Update Test Configuration
    
.DESCRIPTION
    This script retrieves the current function app keys from Azure and updates
    the local test configuration files to ensure API calls work properly.
    
.PARAMETER ResourceGroupName
    The name of the resource group containing the function apps
    
.PARAMETER UpdateLocalSettings
    Switch to update local.settings.json files with production keys
    
.PARAMETER TestConnection
    Switch to test the API connection after updating keys
    
.EXAMPLE
    .\get-function-keys.ps1 -ResourceGroupName "rg-home-automation"
    
.EXAMPLE
    .\get-function-keys.ps1 -ResourceGroupName "rg-home-automation" -UpdateLocalSettings -TestConnection
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false)]
    [switch]$UpdateLocalSettings,
    
    [Parameter(Mandatory = $false)]
    [switch]$TestConnection
)

Write-Host "🔑 Getting Function App Keys for Test Configuration" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan

# Check if Azure CLI is available
try {
    $azVersion = az version 2>$null | ConvertFrom-Json
    Write-Host "✅ Azure CLI detected: $($azVersion.'azure-cli')" -ForegroundColor Green
} catch {
    Write-Error "❌ Azure CLI not found. Please install Azure CLI and login with 'az login'"
    exit 1
}

# Check if logged in
try {
    $account = az account show 2>$null | ConvertFrom-Json
    Write-Host "✅ Logged in as: $($account.user.name)" -ForegroundColor Green
    Write-Host "📋 Subscription: $($account.name) ($($account.id))" -ForegroundColor Gray
} catch {
    Write-Error "❌ Not logged in to Azure. Please run 'az login' first."
    exit 1
}

Write-Host "`n🔍 Finding Function Apps in Resource Group: $ResourceGroupName" -ForegroundColor Yellow

# Get function app names
$alexaFnName = az functionapp list --resource-group $ResourceGroupName --query "[?contains(name, 'alexa-fn')].name" -o tsv
$doorFnName = az functionapp list --resource-group $ResourceGroupName --query "[?contains(name, 'door-fn')].name" -o tsv
$flumeFnName = az functionapp list --resource-group $ResourceGroupName --query "[?contains(name, 'flume-fn')].name" -o tsv

if (-not $alexaFnName) {
    Write-Error "❌ Alexa Function App not found in resource group $ResourceGroupName"
    exit 1
}

Write-Host "✅ Found Function Apps:" -ForegroundColor Green
Write-Host "   📱 Alexa Function App: $alexaFnName" -ForegroundColor White
if ($doorFnName) {
    Write-Host "   🚪 Door Function App: $doorFnName" -ForegroundColor White
}
if ($flumeFnName) {
    Write-Host "   💧 Flume Function App: $flumeFnName" -ForegroundColor White
}

Write-Host "`n🔐 Retrieving Function Keys..." -ForegroundColor Yellow

# Get the Alexa function master key
$alexaFnKey = az functionapp keys list --name $alexaFnName --resource-group $ResourceGroupName --query "masterKey" -o tsv

if (-not $alexaFnKey) {
    Write-Error "❌ Could not retrieve Alexa function key"
    exit 1
}

Write-Host "✅ Successfully retrieved Alexa Function key: $($alexaFnKey.Substring(0,10))..." -ForegroundColor Green

# Update test_config.json
Write-Host "`n📝 Updating test_config.json..." -ForegroundColor Yellow

$testConfigPath = "test_config.json"
if (-not (Test-Path $testConfigPath)) {
    Write-Error "❌ test_config.json not found in current directory"
    exit 1
}

try {
    $testConfig = Get-Content $testConfigPath | ConvertFrom-Json
    
    # Add announce configuration with proper key
    if (-not $testConfig.announce) {
        $testConfig | Add-Member -NotePropertyName "announce" -NotePropertyValue @{}
    }
    
    # Update announce configuration
    $testConfig.announce.url = "https://$alexaFnName.azurewebsites.net/api/announce"
    $testConfig.announce.key = $alexaFnKey
    
    # Update Azure function configuration
    if (-not $testConfig.azureFunction) {
        $testConfig | Add-Member -NotePropertyName "azureFunction" -NotePropertyValue @{}
    }
    
    $testConfig.azureFunction.url = "https://$alexaFnName.azurewebsites.net/api/alexa_skill"
    $testConfig.azureFunction.key = $alexaFnKey
    $testConfig.azureFunction.functionAppName = $alexaFnName
    
    # Save updated configuration
    $testConfig | ConvertTo-Json -Depth 10 | Set-Content $testConfigPath -Encoding UTF8
    
    Write-Host "✅ Updated test_config.json with production function keys" -ForegroundColor Green
    
} catch {
    Write-Error "❌ Failed to update test_config.json: $($_.Exception.Message)"
    exit 1
}

# Update local settings if requested
if ($UpdateLocalSettings) {
    Write-Host "`n📝 Updating Local Settings Files..." -ForegroundColor Yellow
    
    # Update flume-fn local.settings.json
    $flumeFnLocalSettings = "..\flume-fn\local.settings.json"
    if (Test-Path $flumeFnLocalSettings) {
        try {
            $flumeConfig = Get-Content $flumeFnLocalSettings | ConvertFrom-Json
            $flumeConfig.Values.ALEXA_FN_API_KEY = $alexaFnKey
            $flumeConfig.Values.ALEXA_FN_BASE_URL = "https://$alexaFnName.azurewebsites.net"
            
            $flumeConfig | ConvertTo-Json -Depth 10 | Set-Content $flumeFnLocalSettings -Encoding UTF8
            Write-Host "✅ Updated flume-fn local.settings.json" -ForegroundColor Green
        } catch {
            Write-Warning "⚠️  Failed to update flume-fn local.settings.json: $($_.Exception.Message)"
        }
    }
    
    # Update alexa-fn local.settings.json if door function exists
    if ($doorFnName) {
        $alexaFnLocalSettings = "..\alexa-fn\local.settings.json"
        if (Test-Path $alexaFnLocalSettings) {
            try {
                $doorFnKey = az functionapp keys list --name $doorFnName --resource-group $ResourceGroupName --query "masterKey" -o tsv
                if ($doorFnKey) {
                    $alexaConfig = Get-Content $alexaFnLocalSettings | ConvertFrom-Json
                    $alexaConfig.Values.DOOR_FN_API_KEY = $doorFnKey
                    $alexaConfig.Values.DOOR_FN_BASE_URL = "https://$doorFnName.azurewebsites.net"
                    
                    $alexaConfig | ConvertTo-Json -Depth 10 | Set-Content $alexaFnLocalSettings -Encoding UTF8
                    Write-Host "✅ Updated alexa-fn local.settings.json" -ForegroundColor Green
                }
            } catch {
                Write-Warning "⚠️  Failed to update alexa-fn local.settings.json: $($_.Exception.Message)"
            }
        }
    }
}

# Test connection if requested
if ($TestConnection) {
    Write-Host "`n🧪 Testing API Connection..." -ForegroundColor Yellow
    
    try {
        $testUrl = "https://$alexaFnName.azurewebsites.net/api/announce"
        $headers = @{
            "Content-Type" = "application/json"
            "x-functions-key" = $alexaFnKey
        }
        $body = @{
            message = "Test connection from get-function-keys script"
            device = "all"
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri $testUrl -Method POST -Body $body -Headers $headers -TimeoutSec 30
        
        Write-Host "✅ API connection successful!" -ForegroundColor Green
        Write-Host "📤 Test response: $($response | ConvertTo-Json -Compress)" -ForegroundColor Gray
        
    } catch {
        Write-Warning "⚠️  API connection test failed: $($_.Exception.Message)"
        Write-Host "💡 This might be normal if the function app is not running or needs time to warm up" -ForegroundColor Gray
    }
}

Write-Host "`n✅ Function Key Configuration Completed!" -ForegroundColor Green
Write-Host "📋 Summary:" -ForegroundColor Cyan
Write-Host "   • Retrieved function keys from Azure" -ForegroundColor White
Write-Host "   • Updated test_config.json with production endpoints and keys" -ForegroundColor White
if ($UpdateLocalSettings) {
    Write-Host "   • Updated local.settings.json files with production keys" -ForegroundColor White
}
if ($TestConnection) {
    Write-Host "   • Tested API connection" -ForegroundColor White
}

Write-Host "`n💡 Next Steps:" -ForegroundColor Yellow
Write-Host "   • Run: .\test_flume_announce.ps1 -Production" -ForegroundColor White
Write-Host "   • Or:  python test_flume_announce.py --production" -ForegroundColor White
Write-Host "   • For full testing: .\test_azure_function.ps1" -ForegroundColor White