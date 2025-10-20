# Get Azure Function URLs and Configuration Values
# Unified configuration retrieval for all function apps in the system

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$ShowKeys
)

Write-Host "🔍 Getting Azure Function Configuration..." -ForegroundColor Green

# Get resource group from parameters if not provided
if (-not $ResourceGroupName) {
    if (Test-Path "main.parameters.local.json") {
        $params = Get-Content "main.parameters.local.json" | ConvertFrom-Json
        $functionAppName = $params.parameters.functionAppName.value
        $ResourceGroupName = "rg-$functionAppName"
        Write-Host "📋 Using resource group from parameters: $ResourceGroupName" -ForegroundColor Cyan
    } else {
        Write-Host "❌ No resource group specified and parameters file not found" -ForegroundColor Red
        Write-Host "Usage: .\get-function-config.ps1 -ResourceGroupName 'your-rg'" -ForegroundColor Yellow
        exit 1
    }
}

# Get function app names from parameters
$functionApps = @()
if (Test-Path "main.parameters.local.json") {
    $params = Get-Content "main.parameters.local.json" | ConvertFrom-Json
    
    $functionApps += @{
        Name = $params.parameters.functionAppName.value
        DisplayName = "Door Function App"
        Purpose = "Handles door sensor events and cancellation"
    }
    
    $functionApps += @{
        Name = $params.parameters.alexaFunctionAppName.value
        DisplayName = "Alexa Function App" 
        Purpose = "Alexa skill backend and announcement system"
    }
    
    $functionApps += @{
        Name = $params.parameters.flumeFunctionAppName.value
        DisplayName = "Flume Function App"
        Purpose = "Water monitoring and leak detection"
    }
} else {
    Write-Host "❌ Parameters file not found. Cannot determine function app names." -ForegroundColor Red
    exit 1
}

Write-Host "📋 Resource Group: $ResourceGroupName" -ForegroundColor Cyan
Write-Host ""

# Get configuration for each function app
foreach ($app in $functionApps) {
    Write-Host "🔍 $($app.DisplayName) ($($app.Name))" -ForegroundColor Blue
    Write-Host "   Purpose: $($app.Purpose)" -ForegroundColor Gray
    
    try {
        # Get the function app URL
        $functionAppUrl = az functionapp show --name $app.Name --resource-group $ResourceGroupName --query "defaultHostName" --output tsv
        if ($functionAppUrl) {
            $baseUrl = "https://$functionAppUrl"
            Write-Host "   ✅ Base URL: $baseUrl" -ForegroundColor Green
            
            # Get function keys if requested
            if ($ShowKeys) {
                try {
                    Write-Host "   🔑 Getting function keys..." -ForegroundColor Yellow
                    $masterKey = az functionapp keys list --name $app.Name --resource-group $ResourceGroupName --query "masterKey" --output tsv
                    if ($masterKey) {
                        Write-Host "   ✅ Master Key: $masterKey" -ForegroundColor Green
                    }
                    
                    $functionKeys = az functionapp keys list --name $app.Name --resource-group $ResourceGroupName --query "functionKeys" --output json | ConvertFrom-Json
                    if ($functionKeys -and $functionKeys.PSObject.Properties.Count -gt 0) {
                        Write-Host "   📋 Function Keys:" -ForegroundColor Cyan
                        $functionKeys.PSObject.Properties | ForEach-Object {
                            Write-Host "      $($_.Name): $($_.Value)" -ForegroundColor Gray
                        }
                    }
                } catch {
                    Write-Host "   ⚠️  Could not retrieve keys: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        } else {
            Write-Host "   ❌ Function app not found or not accessible" -ForegroundColor Red
        }
    } catch {
        Write-Host "   ❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Host ""
}

# Show environment variable configuration
Write-Host "📝 Environment Variable Configuration:" -ForegroundColor Cyan
Write-Host ""

# Get URLs for inter-service communication
$doorFnUrl = ""
$alexaFnUrl = ""
$flumeFnUrl = ""

foreach ($app in $functionApps) {
    $url = az functionapp show --name $app.Name --resource-group $ResourceGroupName --query "defaultHostName" --output tsv 2>$null
    if ($url) {
        switch ($app.Name) {
            { $_ -like "*door*" } { $doorFnUrl = "https://$url" }
            { $_ -like "*alexa*" } { $alexaFnUrl = "https://$url" }  
            { $_ -like "*flume*" } { $flumeFnUrl = "https://$url" }
        }
    }
}

if ($doorFnUrl -and $alexaFnUrl) {
    Write-Host "🔧 For alexa-fn (calling door-fn):" -ForegroundColor Green
    Write-Host "   DOOR_FN_BASE_URL=$doorFnUrl" -ForegroundColor White
    if ($ShowKeys) {
        $doorKey = az functionapp keys list --name ($functionApps | Where-Object { $_.Name -like "*door*" }).Name --resource-group $ResourceGroupName --query "masterKey" --output tsv 2>$null
        if ($doorKey) {
            Write-Host "   DOOR_FN_API_KEY=$doorKey" -ForegroundColor White
        }
    } else {
        Write-Host "   DOOR_FN_API_KEY=[Use -ShowKeys to display]" -ForegroundColor Gray
    }
    Write-Host ""
}

if ($alexaFnUrl) {
    Write-Host "🔧 For door-fn and flume-fn (calling alexa-fn):" -ForegroundColor Green
    Write-Host "   ALEXA_FN_BASE_URL=$alexaFnUrl" -ForegroundColor White
    if ($ShowKeys) {
        $alexaKey = az functionapp keys list --name ($functionApps | Where-Object { $_.Name -like "*alexa*" }).Name --resource-group $ResourceGroupName --query "masterKey" --output tsv 2>$null
        if ($alexaKey) {
            Write-Host "   ALEXA_FN_API_KEY=$alexaKey" -ForegroundColor White
        }
    } else {
        Write-Host "   ALEXA_FN_API_KEY=[Use -ShowKeys to display]" -ForegroundColor Gray
    }
    Write-Host ""
}

Write-Host "💡 Usage Tips:" -ForegroundColor Cyan
Write-Host "• Use .\configure-function-keys.ps1 to automatically update app settings with these keys"
Write-Host "• Use -ShowKeys parameter to display actual key values: .\get-function-config.ps1 -ShowKeys"
Write-Host "• These URLs and keys are used for inter-service communication"
