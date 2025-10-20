# Post-deployment script to configure inter-service function keys
# This script retrieves the function master keys and updates the app settings

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId
)

# Set the subscription if provided
if ($SubscriptionId) {
    Write-Host "Setting subscription to: $SubscriptionId"
    az account set --subscription $SubscriptionId
}

Write-Host "Configuring function keys for resource group: $ResourceGroupName"

# Get function app names from the deployment
Write-Host "Getting function app names..."
$alexaFnName = az functionapp list --resource-group $ResourceGroupName --query "[?contains(name, 'alexa-fn')].name" -o tsv
$doorFnName = az functionapp list --resource-group $ResourceGroupName --query "[?contains(name, 'door-fn')].name" -o tsv
$flumeFnName = az functionapp list --resource-group $ResourceGroupName --query "[?contains(name, 'flume-fn')].name" -o tsv

if (-not $alexaFnName -or -not $doorFnName -or -not $flumeFnName) {
    Write-Error "Could not find all function apps. Found: alexa=$alexaFnName, door=$doorFnName, flume=$flumeFnName"
    exit 1
}

Write-Host "Found function apps:"
Write-Host "  Alexa Function App: $alexaFnName"
Write-Host "  Door Function App: $doorFnName"
Write-Host "  Flume Function App: $flumeFnName"

# Get the function master keys
Write-Host "Retrieving function master keys..."
$alexaFnKey = az functionapp keys list --name $alexaFnName --resource-group $ResourceGroupName --query "masterKey" -o tsv
$doorFnKey = az functionapp keys list --name $doorFnName --resource-group $ResourceGroupName --query "masterKey" -o tsv

if (-not $alexaFnKey -or -not $doorFnKey) {
    Write-Error "Could not retrieve function keys. alexaKey=$alexaFnKey, doorKey=$doorFnKey"
    exit 1
}

Write-Host "Successfully retrieved function keys"

# Update alexa-fn with door-fn key
Write-Host "Updating alexa-fn with door-fn API key..."
az functionapp config appsettings set --name $alexaFnName --resource-group $ResourceGroupName --settings "DOOR_FN_API_KEY=$doorFnKey"

# Update door-fn with alexa-fn key
Write-Host "Updating door-fn with alexa-fn API key..."
az functionapp config appsettings set --name $doorFnName --resource-group $ResourceGroupName --settings "ALEXA_FN_API_KEY=$alexaFnKey"

# Update flume-fn with alexa-fn key
Write-Host "Updating flume-fn with alexa-fn API key..."
az functionapp config appsettings set --name $flumeFnName --resource-group $ResourceGroupName --settings "ALEXA_FN_API_KEY=$alexaFnKey"

Write-Host "Function key configuration completed successfully!"
Write-Host ""
Write-Host "Inter-service authentication is now properly configured:"
Write-Host "  - alexa-fn can call door-fn using the door-fn master key"
Write-Host "  - door-fn can call alexa-fn using the alexa-fn master key"
Write-Host "  - flume-fn can call alexa-fn using the alexa-fn master key"
Write-Host ""
Write-Host "All function apps are now configured with proper Azure Function-level security."
