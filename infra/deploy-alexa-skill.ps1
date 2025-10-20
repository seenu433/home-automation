# Deploy Alexa Skill Code and Configuration
# This script assumes infrastructure is already deployed via deploy.ps1

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipCodeDeployment,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipSkillConfiguration
)

Write-Host "🎤 Deploying Alexa Skill Code and Configuration..." -ForegroundColor Green

# Get resource group from parameters if not provided
if (-not $ResourceGroupName) {
    if (Test-Path "main.parameters.local.json") {
        $params = Get-Content "main.parameters.local.json" | ConvertFrom-Json
        $functionAppName = $params.parameters.functionAppName.value
        $ResourceGroupName = "rg-$functionAppName"
        Write-Host "📋 Using resource group from parameters: $ResourceGroupName" -ForegroundColor Cyan
    } else {
        Write-Host "❌ No resource group specified and parameters file not found" -ForegroundColor Red
        Write-Host "Usage: .\deploy-alexa-skill.ps1 -ResourceGroupName 'your-rg'" -ForegroundColor Yellow
        exit 1
    }
}

# Get alexa function app name from parameters
$alexaFunctionAppName = "alexa-fn"
if (Test-Path "main.parameters.local.json") {
    $params = Get-Content "main.parameters.local.json" | ConvertFrom-Json
    if ($params.parameters.alexaFunctionAppName) {
        $alexaFunctionAppName = $params.parameters.alexaFunctionAppName.value
    }
}

Write-Host "📋 Alexa Function App: $alexaFunctionAppName" -ForegroundColor Cyan

# Step 1: Deploy the Alexa Function App code (if not skipped)
if (-not $SkipCodeDeployment) {
    Write-Host "📦 Step 1: Deploying Alexa Function App code..." -ForegroundColor Blue
    
    Push-Location ..\alexa-fn
    try {
        # Check if required files exist
        $requiredFiles = @("function_app.py", "requirements.txt", "host.json")
        foreach ($file in $requiredFiles) {
            if (-not (Test-Path $file)) {
                Write-Host "❌ Required file missing: $file" -ForegroundColor Red
                exit 1
            }
        }
        
        # Create deployment package
        if (Test-Path "deployment.zip") { Remove-Item "deployment.zip" }
        
        # Include all necessary files for the deployment
        $filesToInclude = @(
            "function_app.py",
            "requirements.txt", 
            "host.json"
        )
        
        # Add virtual devices config if it exists
        if (Test-Path "virtual-devices-config.json") {
            $filesToInclude += "virtual-devices-config.json"
        }
        
        Compress-Archive -Path $filesToInclude -DestinationPath "deployment.zip"
        
        # Deploy to Azure Functions
        Write-Host "   Deploying to $alexaFunctionAppName..." -ForegroundColor Gray
        az functionapp deployment source config-zip --resource-group $ResourceGroupName --name $alexaFunctionAppName --src deployment.zip
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Function app deployment failed" -ForegroundColor Red
            exit 1
        }
        Write-Host "✅ Alexa Function App code deployed successfully" -ForegroundColor Green
        
        # Clean up
        Remove-Item "deployment.zip"
    } finally {
        Pop-Location
    }
} else {
    Write-Host "⏭️  Skipping code deployment" -ForegroundColor Yellow
}

# Step 2: Get the Azure Function URL and configure skill (if not skipped)
if (-not $SkipSkillConfiguration) {
    Write-Host "🔍 Step 2: Getting Azure Function URL and configuring skill..." -ForegroundColor Blue
    
    $functionUrl = az functionapp show --name $alexaFunctionAppName --resource-group $ResourceGroupName --query "defaultHostName" --output tsv
    if ($functionUrl) {
        $fullUrl = "https://$functionUrl/api/alexa_skill"
        Write-Host "✅ Function URL: $fullUrl" -ForegroundColor Green
        
        # Update the skill manifest with the correct URL
        $skillManifestPath = "..\alexa-skill\skill-package\skill.json"
        if (Test-Path $skillManifestPath) {
            try {
                $skillManifest = Get-Content $skillManifestPath | ConvertFrom-Json
                $skillManifest.manifest.apis.custom.endpoint.uri = $fullUrl
                $skillManifest | ConvertTo-Json -Depth 10 | Set-Content $skillManifestPath
                Write-Host "✅ Updated skill manifest with Azure Function URL" -ForegroundColor Green
            } catch {
                Write-Host "⚠️  Could not update skill manifest: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "⚠️  Skill manifest not found at: $skillManifestPath" -ForegroundColor Yellow
        }
        
        # Step 3: Test the Azure Function endpoint
        Write-Host "🧪 Step 3: Testing Azure Function endpoint..." -ForegroundColor Blue
        
        try {
            # Create a simple test payload
            $testPayload = @{
                version = "1.0"
                session = @{
                    new = $true
                    sessionId = "test-session-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                    user = @{ userId = "test-user" }
                }
                request = @{
                    type = "LaunchRequest"
                    requestId = "test-request-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                }
            } | ConvertTo-Json -Depth 5
        
            $response = Invoke-RestMethod -Uri $fullUrl -Method POST -Body $testPayload -ContentType "application/json" -TimeoutSec 30
            if ($response -and $response.response) {
                Write-Host "✅ Azure Function is responding correctly" -ForegroundColor Green
                if ($response.response.outputSpeech -and $response.response.outputSpeech.text) {
                    Write-Host "   Response: $($response.response.outputSpeech.text)" -ForegroundColor Gray
                }
            } else {
                Write-Host "⚠️  Function responded but format may be unexpected" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "❌ Function test failed: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "   This might be due to authentication requirements or function startup time." -ForegroundColor Yellow
        }
    } else {
        Write-Host "❌ Could not get function URL" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "⏭️  Skipping skill configuration" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "🎯 Deployment Summary:" -ForegroundColor Cyan
Write-Host "✅ Alexa skill backend is deployed to Azure Functions" -ForegroundColor Green
Write-Host "✅ All components running on Azure (no AWS services)" -ForegroundColor Green

if (-not $SkipSkillConfiguration -and $functionUrl) {
    Write-Host ""
    Write-Host "🔧 Next Steps:" -ForegroundColor Cyan
    Write-Host "1. Update your Alexa Developer Console:"
    Write-Host "   - Skill Endpoint URL: https://$functionUrl/api/alexa_skill"
    Write-Host "2. For authentication, configure the function auth level in Azure portal"
    Write-Host "3. Test the skill in Alexa Developer Console or on your device"
}

Write-Host ""
Write-Host "💡 The skill runs entirely on Azure - no AWS Lambda or other AWS services!" -ForegroundColor Green
