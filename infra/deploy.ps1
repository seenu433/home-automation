# Home Automation Infrastructure Deployment Script
# This script deploys the home automation system with actual local settings

param(
    [string]$ResourceGroupName = "home-auto",
    [string]$Location = "eastus",
    [string]$TemplateFile = "main.bicep",
    [string]$ParametersFile = "main.parameters.local.json"
)

Write-Host "🏠 Home Automation Infrastructure Deployment" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host ""

# Check if Azure CLI is installed
if (!(Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error "Azure CLI is not installed. Please install it first: winget install Microsoft.AzureCLI"
    exit 1
}

# Check if logged in to Azure
$account = az account show 2>$null | ConvertFrom-Json
if (!$account) {
    Write-Host "⚠️ Not logged in to Azure. Logging in..." -ForegroundColor Yellow
    az login
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to login to Azure"
        exit 1
    }
}

Write-Host "✅ Logged in to Azure as: $($account.user.name)" -ForegroundColor Green
Write-Host "📋 Subscription: $($account.name) ($($account.id))" -ForegroundColor Cyan
Write-Host ""

# Check if resource group exists
$rg = az group show --name $ResourceGroupName 2>$null | ConvertFrom-Json
if (!$rg) {
    Write-Host "🆕 Creating resource group: $ResourceGroupName" -ForegroundColor Yellow
    az group create --name $ResourceGroupName --location $Location
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create resource group"
        exit 1
    }
    Write-Host "✅ Resource group created successfully" -ForegroundColor Green
} else {
    Write-Host "✅ Resource group exists: $ResourceGroupName" -ForegroundColor Green
}

# Check if template and parameters files exist
if (!(Test-Path $TemplateFile)) {
    Write-Error "Template file not found: $TemplateFile"
    exit 1
}

if (!(Test-Path $ParametersFile)) {
    Write-Error "Parameters file not found: $ParametersFile"
    exit 1
}

Write-Host "📄 Template file: $TemplateFile" -ForegroundColor Cyan
Write-Host "⚙️ Parameters file: $ParametersFile" -ForegroundColor Cyan
Write-Host ""

# Preview deployment changes
Write-Host "🔍 Previewing deployment changes..." -ForegroundColor Yellow
az deployment group what-if `
    --resource-group $ResourceGroupName `
    --template-file $TemplateFile `
    --parameters $ParametersFile

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to preview deployment"
    exit 1
}

Write-Host ""
$continue = Read-Host "Continue with deployment? (y/N)"
if ($continue -ne "y" -and $continue -ne "Y") {
    Write-Host "❌ Deployment cancelled" -ForegroundColor Red
    exit 0
}

# Deploy infrastructure
Write-Host ""
Write-Host "🚀 Deploying infrastructure..." -ForegroundColor Green
$deploymentName = "home-auto-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

az deployment group create `
    --resource-group $ResourceGroupName `
    --template-file $TemplateFile `
    --parameters $ParametersFile `
    --name $deploymentName `
    --verbose

if ($LASTEXITCODE -ne 0) {
    Write-Error "Deployment failed"
    exit 1
}

Write-Host ""
Write-Host "✅ Infrastructure deployment completed successfully!" -ForegroundColor Green
Write-Host ""

# Show deployment outputs
Write-Host "📊 Deployment outputs:" -ForegroundColor Cyan
az deployment group show `
    --resource-group $ResourceGroupName `
    --name $deploymentName `
    --query "properties.outputs" `
    --output table

Write-Host ""
Write-Host "🎉 Next steps:" -ForegroundColor Green
Write-Host "   1. Deploy door-fn: cd ../door-fn && func azure functionapp publish door-fn" -ForegroundColor White
Write-Host "   2. Deploy flume-fn: cd ../flume-fn && func azure functionapp publish flume-fn" -ForegroundColor White
Write-Host "   3. Test the system using the commands in the README.md" -ForegroundColor White
Write-Host ""
Write-Host "✅ Home automation infrastructure is ready!" -ForegroundColor Green
