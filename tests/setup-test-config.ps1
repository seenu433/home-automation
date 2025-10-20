#!/usr/bin/env powershell
<#
.SYNOPSIS
    Setup Test Configuration from Template
    
.DESCRIPTION
    This script helps setup the test configuration files from templates,
    prompting for required values and optionally retrieving them from Azure.
    
.PARAMETER AutoDetect
    Switch to automatically detect values from Azure resources
    
.PARAMETER ResourceGroupName
    The name of the resource group containing the function apps
    
.PARAMETER Interactive
    Switch to prompt for values interactively
    
.EXAMPLE
    .\setup-test-config.ps1 -AutoDetect -ResourceGroupName "rg-home-automation"
    
.EXAMPLE
    .\setup-test-config.ps1 -Interactive
#>

param(
    [Parameter(Mandatory = $false)]
    [switch]$AutoDetect,
    
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false)]
    [switch]$Interactive
)

Write-Host "🔧 Test Configuration Setup" -ForegroundColor Cyan
Write-Host "============================" -ForegroundColor Cyan

$templatePath = "test_config.json.template"
$configPath = "test_config.json"

# Check if template exists
if (-not (Test-Path $templatePath)) {
    Write-Error "❌ Template file not found: $templatePath"
    exit 1
}

# Check if config already exists
if (Test-Path $configPath) {
    $response = Read-Host "⚠️  Configuration file already exists. Overwrite? (y/N)"
    if ($response -ne "y" -and $response -ne "Y") {
        Write-Host "❌ Setup cancelled" -ForegroundColor Yellow
        exit 0
    }
}

Write-Host "📄 Loading template..." -ForegroundColor Yellow

try {
    $config = Get-Content $templatePath | ConvertFrom-Json
} catch {
    Write-Error "❌ Failed to parse template file: $($_.Exception.Message)"
    exit 1
}

$values = @{}

if ($AutoDetect -and $ResourceGroupName) {
    Write-Host "🔍 Auto-detecting values from Azure..." -ForegroundColor Yellow
    
    # Check Azure CLI
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
    } catch {
        Write-Error "❌ Not logged in to Azure. Please run 'az login' first."
        exit 1
    }
    
    # Get function app name
    $functionAppName = az functionapp list --resource-group $ResourceGroupName --query "[?contains(name, 'alexa-fn')].name" -o tsv
    if ($functionAppName) {
        $values["functionAppName"] = $functionAppName
        $values["functionAppUrl"] = "https://$functionAppName.azurewebsites.net"
        Write-Host "✅ Found Function App: $functionAppName" -ForegroundColor Green
        
        # Get function key
        $functionKey = az functionapp keys list --name $functionAppName --resource-group $ResourceGroupName --query "masterKey" -o tsv
        if ($functionKey) {
            $values["functionKey"] = $functionKey
            Write-Host "✅ Retrieved Function Key: $($functionKey.Substring(0,10))..." -ForegroundColor Green
        }
    }
    
    $values["resourceGroup"] = $ResourceGroupName
}

if ($Interactive) {
    Write-Host "`n📝 Interactive Configuration Setup" -ForegroundColor Yellow
    
    # Function App Configuration
    if (-not $values["functionAppName"]) {
        $values["functionAppName"] = Read-Host "Enter Function App Name (e.g., srp-alexa-fn)"
    }
    
    if (-not $values["functionAppUrl"]) {
        $defaultUrl = "https://$($values["functionAppName"]).azurewebsites.net"
        $urlInput = Read-Host "Enter Function App URL [$defaultUrl]"
        $values["functionAppUrl"] = if ($urlInput) { $urlInput } else { $defaultUrl }
    }
    
    if (-not $values["functionKey"]) {
        $values["functionKey"] = Read-Host "Enter Function Key"
    }
    
    if (-not $values["resourceGroup"]) {
        $values["resourceGroup"] = Read-Host "Enter Resource Group Name (e.g., rg-home-automation)"
    }
    
    # Alexa Configuration
    $alexaUserId = Read-Host "Enter Alexa User ID (amzn1.account.xxx) [press Enter to keep template value]"
    if ($alexaUserId) {
        $values["alexaUserId"] = $alexaUserId
    }
    
    $skillId = Read-Host "Enter Alexa Skill ID (amzn1.ask.skill.xxx) [press Enter to keep template value]"
    if ($skillId) {
        $values["skillId"] = $skillId
    }
    
    # OAuth Configuration
    $clientId = Read-Host "Enter OAuth Client ID (amzn1.application-oa2-client.xxx) [press Enter to keep template value]"
    if ($clientId) {
        $values["oauthClientId"] = $clientId
    }
    
    $clientSecret = Read-Host "Enter OAuth Client Secret [press Enter to keep template value]"
    if ($clientSecret) {
        $values["oauthClientSecret"] = $clientSecret
    }
    
    $redirectUri = Read-Host "Enter OAuth Redirect URI [press Enter to keep template value]"
    if ($redirectUri) {
        $values["oauthRedirectUri"] = $redirectUri
    }
}

# Apply values to configuration
Write-Host "`n🔄 Applying configuration values..." -ForegroundColor Yellow

if ($values["functionKey"]) {
    $config.announce.key = $values["functionKey"]
    $config.azureFunction.key = $values["functionKey"]
}

if ($values["functionAppName"]) {
    $config.azureFunction.functionAppName = $values["functionAppName"]
}

if ($values["functionAppUrl"]) {
    $config.announce.url = "$($values["functionAppUrl"])/api/announce"
    $config.azureFunction.url = "$($values["functionAppUrl"])/api/alexa_skill"
}

if ($values["resourceGroup"]) {
    $config.azureFunction.resourceGroup = $values["resourceGroup"]
}

if ($values["alexaUserId"]) {
    $config.alexa.userId = $values["alexaUserId"]
}

if ($values["skillId"]) {
    $config.alexa.applicationId = $values["skillId"]
}

if ($values["oauthClientId"]) {
    $config.oauth.clientId = $values["oauthClientId"]
}

if ($values["oauthClientSecret"]) {
    $config.oauth.clientSecret = $values["oauthClientSecret"]
}

if ($values["oauthRedirectUri"]) {
    $config.oauth.redirectUri = $values["oauthRedirectUri"]
}

# Save configuration
try {
    $config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
    Write-Host "✅ Configuration saved to: $configPath" -ForegroundColor Green
} catch {
    Write-Error "❌ Failed to save configuration: $($_.Exception.Message)"
    exit 1
}

# Validate configuration
Write-Host "`n🧪 Validating configuration..." -ForegroundColor Yellow

$errors = @()

if ($config.announce.key -eq "YOUR_FUNCTION_KEY_HERE") {
    $errors += "Function key not set"
}

if ($config.announce.url -contains "YOUR-FUNCTION-APP") {
    $errors += "Function app URL not set"
}

if ($config.azureFunction.functionAppName -eq "YOUR-FUNCTION-APP-NAME") {
    $errors += "Function app name not set"
}

if ($errors.Count -gt 0) {
    Write-Host "⚠️  Configuration warnings:" -ForegroundColor Yellow
    foreach ($warning in $errors) {
        Write-Host "   • $warning" -ForegroundColor Yellow
    }
    Write-Host "💡 Run with -Interactive to set missing values" -ForegroundColor Gray
} else {
    Write-Host "✅ Configuration validation passed" -ForegroundColor Green
}

Write-Host "`n✅ Test Configuration Setup Complete!" -ForegroundColor Green
Write-Host "📋 Summary:" -ForegroundColor Cyan
Write-Host "   • Configuration file created: $configPath" -ForegroundColor White
Write-Host "   • Template preserved: $templatePath" -ForegroundColor White
Write-Host "   • Configuration excluded from git (see .gitignore)" -ForegroundColor White

Write-Host "`n💡 Next Steps:" -ForegroundColor Yellow
Write-Host "   • Test configuration: .\test_flume_announce.ps1 -Production" -ForegroundColor White
Write-Host "   • Run full test suite: .\test_azure_function.ps1" -ForegroundColor White
Write-Host "   • Update configuration: .\setup-test-config.ps1 -Interactive" -ForegroundColor White