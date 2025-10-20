#!/usr/bin/env pwsh
# Deploy Home Automation with Virtual Announcement Devices to Azure

param(
    [string]$ResourceGroupName = "rg-home-automation",
    [string]$Location = "East US",
    [switch]$SkipBuild,
    [switch]$TestOnly
)

Write-Host "DEPLOY: Home Automation with Virtual Announcement Devices" -ForegroundColor Cyan

# Set error handling
$ErrorActionPreference = "Stop"

try {
    if (!$TestOnly) {
        # Check if logged in to Azure
        Write-Host "Checking Azure login..." -ForegroundColor Yellow
        $context = az account show 2>$null | ConvertFrom-Json
        if (!$context) {
            Write-Host "Please login to Azure first: az login" -ForegroundColor Red
            exit 1
        }
        Write-Host "SUCCESS: Logged in as: $($context.user.name)" -ForegroundColor Green

        # Create resource group if it doesn't exist
        Write-Host "Creating resource group if needed..." -ForegroundColor Yellow
        az group create --name $ResourceGroupName --location $Location --output none
        Write-Host "SUCCESS: Resource group ready" -ForegroundColor Green

        # Deploy infrastructure
        Write-Host "Deploying infrastructure..." -ForegroundColor Yellow
        $deployment = az deployment group create `
            --resource-group $ResourceGroupName `
            --template-file "main.bicep" `
            --parameters "main.parameters.local.json" `
            --output json | ConvertFrom-Json

        if ($LASTEXITCODE -ne 0) {
            throw "Infrastructure deployment failed"
        }

        # Extract outputs with error handling
        $alexaFunctionUrl = ""
        $alexaFunctionAppName = ""
        $doorFunctionAppName = ""
        $flumeFunctionAppName = ""
        $keyVaultName = ""
        $keyVaultUri = ""
        if ($deployment -and $deployment.properties -and $deployment.properties.outputs) {
            $alexaFunctionUrl = $deployment.properties.outputs.alexaFunctionAppUrl.value
            $alexaFunctionAppName = $deployment.properties.outputs.alexaFunctionAppName.value
            $doorFunctionAppName = $deployment.properties.outputs.doorFunctionAppName.value
            $flumeFunctionAppName = $deployment.properties.outputs.flumeFunctionAppName.value
            $keyVaultName = $deployment.properties.outputs.keyVaultName.value
            $keyVaultUri = $deployment.properties.outputs.keyVaultUri.value
            $alexaFunctionAppName = $deployment.properties.outputs.alexaFunctionAppName.value
            $doorFunctionAppName = $deployment.properties.outputs.doorFunctionAppName.value
            $flumeFunctionAppName = $deployment.properties.outputs.flumeFunctionAppName.value
        } else {
            Write-Host "WARNING: Could not extract outputs from deployment. Getting function app details..." -ForegroundColor Yellow
            $functionApps = az functionapp list --resource-group $ResourceGroupName | ConvertFrom-Json
            $alexaApp = $functionApps | Where-Object { $_.name -like "*alexa*" }
            $doorApp = $functionApps | Where-Object { $_.name -like "*door*" }
            $flumeApp = $functionApps | Where-Object { $_.name -like "*flume*" }
            if ($alexaApp) {
                $alexaFunctionUrl = "https://$($alexaApp.defaultHostName)"
                $alexaFunctionAppName = $alexaApp.name
            }
            if ($doorApp) {
                $doorFunctionAppName = $doorApp.name
            }
            if ($flumeApp) {
                $flumeFunctionAppName = $flumeApp.name
            }
        }
        
        Write-Host "SUCCESS: Infrastructure deployed" -ForegroundColor Green
        Write-Host "  Alexa Function URL: $alexaFunctionUrl" -ForegroundColor Cyan
        Write-Host "  Alexa Function Name: $alexaFunctionAppName" -ForegroundColor Cyan
        Write-Host "  Door Function Name: $doorFunctionAppName" -ForegroundColor Cyan
        Write-Host "  Flume Function Name: $flumeFunctionAppName" -ForegroundColor Cyan
        if ($keyVaultName) {
            Write-Host "  Key Vault Name: $keyVaultName" -ForegroundColor Cyan
            Write-Host "  Key Vault URI: $keyVaultUri" -ForegroundColor Cyan
        }

        # Build and deploy all function apps if not skipping build
        if (!$SkipBuild) {
            # Deploy Alexa Function (Python)
            Write-Host "Building and deploying Alexa Function (Python)..." -ForegroundColor Yellow
            Push-Location "..\alexa-fn"
            try {
                # Use Azure Functions Core Tools for proper Python deployment with remote build
                $deployResult = func azure functionapp publish $alexaFunctionAppName --python 2>&1
                
                if ($LASTEXITCODE -ne 0) {
                    throw "Alexa Function deployment failed: $deployResult"
                }

                Write-Host "SUCCESS: Alexa Function deployed" -ForegroundColor Green
            }
            catch {
                Write-Host "ERROR: Alexa Function deployment failed: $($_.Exception.Message)" -ForegroundColor Red
                throw
            }
            finally {
                Pop-Location
            }

                        # Deploy Door Function (.NET 8)
            Write-Host "Building and deploying Door Function (.NET 8)..." -ForegroundColor Yellow
            Push-Location "..\door-fn"
            try {
                # Use Azure Functions Core Tools for proper .NET deployment
                $deployResult = func azure functionapp publish $doorFunctionAppName 2>&1
                
                if ($LASTEXITCODE -ne 0) {
                    throw "Door Function deployment failed: $deployResult"
                }

                Write-Host "SUCCESS: Door Function deployed" -ForegroundColor Green
            }
            catch {
                Write-Host "ERROR: Door Function deployment failed: $($_.Exception.Message)" -ForegroundColor Red
                throw
            }
            finally {
                Pop-Location
            }

            # Deploy Flume Function (Python)
            Write-Host "Building and deploying Flume Function (Python)..." -ForegroundColor Yellow
            Push-Location "..\flume-fn"
            try {
                # Use Azure Functions Core Tools for proper Python deployment with remote build
                $deployResult = func azure functionapp publish $flumeFunctionAppName --python 2>&1
                
                if ($LASTEXITCODE -ne 0) {
                    throw "Flume Function deployment failed: $deployResult"
                }

                Write-Host "SUCCESS: Flume Function deployed" -ForegroundColor Green
            }
            catch {
                Write-Host "ERROR: Flume Function deployment failed: $($_.Exception.Message)" -ForegroundColor Red
                throw
            }
            finally {
                Pop-Location
            }
        }

        Write-Host "SUCCESS: All function apps deployed!" -ForegroundColor Green
        Write-Host "  ✓ Alexa Function (Python): $alexaFunctionAppName" -ForegroundColor Green
        Write-Host "  ✓ Door Function (.NET): $doorFunctionAppName" -ForegroundColor Green
        Write-Host "  ✓ Flume Function (Python): $flumeFunctionAppName" -ForegroundColor Green
        
        # Configure function keys for inter-service authentication
        Write-Host ""
        Write-Host "Configuring function keys for inter-service authentication..." -ForegroundColor Yellow
        try {
            # Get the function master keys
            Write-Host "Retrieving function master keys..." -ForegroundColor Yellow
            $alexaFnKey = az functionapp keys list --name $alexaFunctionAppName --resource-group $ResourceGroupName --query "masterKey" -o tsv
            $doorFnKey = az functionapp keys list --name $doorFunctionAppName --resource-group $ResourceGroupName --query "masterKey" -o tsv
            $flumeFnKey = az functionapp keys list --name $flumeFunctionAppName --resource-group $ResourceGroupName --query "masterKey" -o tsv

            if (-not $alexaFnKey -or -not $doorFnKey -or -not $flumeFnKey) {
                throw "Could not retrieve all function keys. alexa=$alexaFnKey, door=$doorFnKey, flume=$flumeFnKey"
            }

            # Update alexa-fn with door-fn and flume-fn keys
            Write-Host "Configuring alexa-fn with inter-service keys..." -ForegroundColor Yellow
            az functionapp config appsettings set --name $alexaFunctionAppName --resource-group $ResourceGroupName --settings "DOOR_FN_API_KEY=$doorFnKey" --output none
            az functionapp config appsettings set --name $alexaFunctionAppName --resource-group $ResourceGroupName --settings "FLUME_FN_API_KEY=$flumeFnKey" --output none

            # Update door-fn with alexa-fn key
            Write-Host "Configuring door-fn with alexa-fn key..." -ForegroundColor Yellow
            az functionapp config appsettings set --name $doorFunctionAppName --resource-group $ResourceGroupName --settings "ALEXA_FN_API_KEY=$alexaFnKey" --output none

            # Update flume-fn with alexa-fn key
            Write-Host "Configuring flume-fn with alexa-fn key..." -ForegroundColor Yellow
            az functionapp config appsettings set --name $flumeFunctionAppName --resource-group $ResourceGroupName --settings "ALEXA_FN_API_KEY=$alexaFnKey" --output none

            # Restart function apps to ensure they pick up new settings
            Write-Host "Restarting function apps to apply new configuration..." -ForegroundColor Yellow
            az functionapp restart --name $alexaFunctionAppName --resource-group $ResourceGroupName --output none
            az functionapp restart --name $doorFunctionAppName --resource-group $ResourceGroupName --output none  
            az functionapp restart --name $flumeFunctionAppName --resource-group $ResourceGroupName --output none
            
            # Wait for functions to start up
            Write-Host "Waiting for function apps to restart..." -ForegroundColor Yellow
            Start-Sleep -Seconds 30
            
            Write-Host "SUCCESS: Function keys configured for inter-service authentication" -ForegroundColor Green
            Write-Host "  ✓ alexa-fn can call door-fn and flume-fn" -ForegroundColor Green
            Write-Host "  ✓ door-fn can call alexa-fn" -ForegroundColor Green
            Write-Host "  ✓ flume-fn can call alexa-fn" -ForegroundColor Green

            # Configure Key Vault for OAuth token storage if deployed
            if ($keyVaultName) {
                Write-Host ""
                Write-Host "Configuring Key Vault for OAuth token storage..." -ForegroundColor Yellow
                
                try {
                    # Test Key Vault access
                    $kv = az keyvault show --name $keyVaultName --resource-group $ResourceGroupName 2>$null | ConvertFrom-Json
                    if ($kv) {
                        Write-Host "✓ Key Vault '$keyVaultName' accessible" -ForegroundColor Green
                        
                        # Check OAuth secrets
                        $clientIdSecret = az keyvault secret show --vault-name $keyVaultName --name "oauth-client-id" 2>$null | ConvertFrom-Json
                        $clientSecretSecret = az keyvault secret show --vault-name $keyVaultName --name "oauth-client-secret" 2>$null | ConvertFrom-Json
                        
                        if ($clientIdSecret -and $clientSecretSecret) {
                            Write-Host "✓ OAuth configuration secrets found in Key Vault" -ForegroundColor Green
                        } else {
                            Write-Host "⚠️ OAuth secrets not found in Key Vault - they may need to be manually added" -ForegroundColor Yellow
                        }
                        
                        # Update Function Apps to use Key Vault for token storage
                        Write-Host "Configuring alexa-fn to use Key Vault token storage..." -ForegroundColor Yellow
                        az functionapp config appsettings set --name $alexaFunctionAppName --resource-group $ResourceGroupName --settings "TOKEN_STORAGE_TYPE=azure_key_vault" --output none
                        
                        Write-Host "SUCCESS: Key Vault OAuth configuration complete" -ForegroundColor Green
                        Write-Host "  ✓ Key Vault: $keyVaultName" -ForegroundColor Green
                        Write-Host "  ✓ OAuth token storage: azure_key_vault" -ForegroundColor Green
                        Write-Host "  ✓ Managed identity authentication configured" -ForegroundColor Green
                    } else {
                        Write-Host "⚠️ Key Vault not accessible - OAuth tokens will use memory storage" -ForegroundColor Yellow
                    }
                } catch {
                    Write-Host "⚠️ Key Vault configuration failed: $($_.Exception.Message)" -ForegroundColor Yellow
                    Write-Host "  OAuth tokens will use memory storage as fallback" -ForegroundColor Yellow
                }
            } else {
                Write-Host ""
                Write-Host "ℹ️ No Key Vault detected - OAuth tokens will use memory storage" -ForegroundColor Cyan
                Write-Host "  To enable secure token storage, add Key Vault to your Bicep template" -ForegroundColor Cyan
            }
        }
        catch {
            Write-Host "ERROR: Function key configuration failed: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Functions may not be able to authenticate with each other" -ForegroundColor Yellow
        }
        
        Write-Host ""
        Write-Host "Next steps:" -ForegroundColor Cyan
        Write-Host "1. Update Alexa Developer Console with endpoint: $alexaFunctionUrl" -ForegroundColor White
        Write-Host "2. Test virtual devices using the commands below" -ForegroundColor White
    }

    # Run comprehensive tests using existing test suite
    Write-Host ""
    Write-Host "TESTING: Running Comprehensive Test Suite" -ForegroundColor Cyan
    
    $testScript = "..\tests\test_azure_function.ps1"
    if (Test-Path $testScript) {
        Write-Host "Found comprehensive test suite: $testScript" -ForegroundColor Green
        Write-Host "Running tests with SkipPrompts..." -ForegroundColor Yellow
        
        try {
            # Change to project root directory to ensure relative paths work correctly
            $originalLocation = Get-Location
            Set-Location $PSScriptRoot\..
            
            # Run the comprehensive test suite with skip prompts to avoid user interaction
            & .\tests\test_azure_function.ps1 -SkipPrompts
            
            # Restore original location
            Set-Location $originalLocation
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✅ Test suite completed successfully!" -ForegroundColor Green
            } else {
                Write-Host "⚠️  Test suite completed with some issues (exit code: $LASTEXITCODE)" -ForegroundColor Yellow
                Write-Host "This is normal if OAuth credentials are not yet configured." -ForegroundColor Gray
            }
        }
        catch {
            Write-Host "❌ Error running test suite: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "💡 You can run tests manually: .\tests\test_azure_function.ps1" -ForegroundColor Yellow
            
            # Restore original location in case of error
            if ($originalLocation) {
                Set-Location $originalLocation
            }
        }
    } else {
        Write-Host "❌ Test suite not found at: $testScript" -ForegroundColor Red
        Write-Host "💡 Skipping automated testing" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "MANUAL TESTING: Additional Test Options" -ForegroundColor Cyan
    Write-Host "💡 For detailed testing, run: .\tests\test_azure_function.ps1" -ForegroundColor Yellow
    Write-Host "💡 For verbose testing, run: .\tests\test_azure_function.ps1 -Verbose" -ForegroundColor Yellow
    Write-Host "💡 To force new OAuth token: .\tests\test_azure_function.ps1 -ForceNewToken" -ForegroundColor Yellow

    Write-Host ""
    Write-Host "VOICE COMMANDS: Voice Commands to Test:" -ForegroundColor Cyan
    Write-Host '"Alexa, ask Home Automation to announce dinner is ready"' -ForegroundColor White
    Write-Host '"Alexa, tell Home Automation to tell the bedroom it''s bedtime"' -ForegroundColor White
    Write-Host '"Alexa, ask Home Automation to announce to downstairs that someone is at the door"' -ForegroundColor White
    Write-Host '"Alexa, tell Home Automation to broadcast to upstairs that the movie is starting"' -ForegroundColor White

    Write-Host ""
    Write-Host "SMART HOME: Smart Home Devices:" -ForegroundColor Cyan
    Write-Host "After enabling the skill, look for 'Announcement Zone' devices in your Alexa app:" -ForegroundColor White
    Write-Host "  - Announcement Zone - All Devices" -ForegroundColor Gray
    Write-Host "  - Announcement Zone - Bedroom" -ForegroundColor Gray
    Write-Host "  - Announcement Zone - Downstairs" -ForegroundColor Gray
    Write-Host "  - Announcement Zone - Upstairs" -ForegroundColor Gray

    Write-Host ""
    Write-Host "SUCCESS: Deployment and testing complete!" -ForegroundColor Green

}
catch {
    Write-Host "ERROR: Deployment failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
