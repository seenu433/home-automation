# Infrastructure as Code (Bicep)

This directory contains the complete Infrastructure as Code (IaC) templates for deploying the home automation system to Azure.

## 📁 Files Overview

### `main.bicep`

Complete Bicep template that provisions all required Azure resources:

- **Storage Account**: Configurable storage for function apps
- **Service Bus Namespace**: Standard tier with 6 specialized queues
- **App Service Plan**: Linux-based plan for both function apps
- **Function Apps**: Both .NET 8 and Python 3.11 function apps
- **Log Analytics Workspace**: Centralized logging and monitoring
- **Application Insights**: Application performance monitoring
- **Enhanced Logging**: Information-level logging with structured output

### Parameter Files

#### `main.parameters.json` (Template)

Template parameter file with placeholder values:

- 📝 **Placeholder Values**: Safe examples for all parameters
- 🔒 **Security**: Uses sanitized example values
- 📚 **Documentation**: Reference for required parameters

#### `main.parameters.local.json` (Working Copy)

Working parameter file with actual deployed values:

- ✅ **Real Credentials**: Actual Flume API credentials
- ✅ **Live Tokens**: Working VoiceMonkey tokens
- ✅ **Active Keys**: Current authentication keys
- ⚠️ **Private**: Contains sensitive data - **DO NOT COMMIT**

### Deployment Scripts

#### `deploy.ps1` (PowerShell)

Windows-friendly deployment script with:

- 🔍 **Preview Mode**: Shows what-if analysis before deployment
- ✅ **Validation**: Checks prerequisites and file existence
- 📊 **Progress**: Detailed deployment status and outputs
- 🎯 **User-Friendly**: Interactive prompts and colored output

#### `deploy.sh` (Bash)

Linux/Mac deployment script with same features as PowerShell version

## 🚀 Deployment Options

### Option 1: Automated Deployment Scripts (Recommended)

#### Windows (PowerShell)

```powershell
# Interactive deployment with preview
.\deploy.ps1

# Or specify custom parameters
.\deploy.ps1 -ResourceGroupName "my-home-auto" -Location "westus2"

```

#### Linux/Mac (Bash)

```bash
# Make executable (Linux/Mac only)
chmod +x deploy.sh

# Interactive deployment with preview
./deploy.sh

# Or specify custom parameters
./deploy.sh "my-home-auto" "westus2"

```

### Option 2: Manual Azure CLI Commands

#### Using Local Working Parameters

```bash
# Deploy with actual local values
az deployment group create \
  --resource-group home-auto \
  --template-file main.bicep \
  --parameters main.parameters.local.json

```

#### Using Template Parameters (for new deployments)

```bash
# Deploy with placeholder values (customize main.parameters.json first)
az deployment group create \
  --resource-group home-auto \
  --template-file main.bicep \
  --parameters main.parameters.json

```

### Option 3: Validation and Preview

#### Validate Template

```bash
# Validate without deploying
az deployment group validate \
  --resource-group home-auto \
  --template-file main.bicep \
  --parameters main.parameters.local.json

```

#### Preview Changes

```bash
# See what will change before deployment
az deployment group what-if \
  --resource-group home-auto \
  --template-file main.bicep \
  --parameters main.parameters.local.json

```

## 🎯 Quick Start (Windows)

```powershell
# 1. Navigate to infra directory
cd infra

# 2. Run the deployment script
.\deploy.ps1

# 3. Follow prompts to review and confirm deployment
# 4. Script will handle resource group creation and deployment

```

## 🏗️ Deployed Resources

### Service Bus Configuration

```ini
Namespace: srini-home-automation (Standard tier)
Queues:
├── triggerevents          # Main event processing queue
├── front_door_unlocked    # Front door events
├── garage_door_open       # Garage door events  
├── garage_open            # Garage open events
├── door_left_open         # Left door events
└── sliding_door_right_open # Sliding door events

```

### Function Apps Configuration

```ini
door-fn (Linux, .NET 8 Isolated Worker)
├── Runtime: dotnet-isolated
├── Version: .NET 8.0
├── Logging: Information level
└── Dependencies: Service Bus, Application Insights

flume-fn (Linux, Python 3.11)
├── Runtime: python  
├── Version: Python 3.11
├── Logging: Information level
└── Dependencies: Storage, Application Insights

```

### Monitoring Stack

```ini
Log Analytics Workspace: home-auto
├── Data retention: 30 days
├── Query capabilities: KQL
└── Integration: Application Insights

Application Insights: home-auto
├── Telemetry collection: Enabled
├── Performance monitoring: Enabled
└── Custom logging: Information level

```

## 🔧 Configuration Management

### Parameter Categories

- **🔒 Secure Parameters**: API keys, passwords, tokens
- **📍 Location Parameters**: Azure regions, resource naming
- **⚙️ Configuration Parameters**: Settings, device IDs, URLs

### Security Features

- All sensitive values use `@secure()` decorator
- No secrets stored in template files
- Function-level authorization for HTTP endpoints
- Managed identities where applicable

## 🔄 Update Process

### Modify Infrastructure

1. Edit `main.bicep` template
2. Update `main.parameters.json` if needed
3. Validate changes with what-if
4. Deploy updated template

### Add New Resources

1. Add resource definition to `main.bicep`
2. Add any required parameters
3. Update dependencies if needed
4. Deploy and verify

## 📊 Monitoring & Troubleshooting

### Deployment Monitoring

```bash
# Check deployment status
az deployment group list --resource-group home-auto

# Get deployment details
az deployment group show --resource-group home-auto --name main

```

### Resource Verification

```bash
# List all resources
az resource list --resource-group home-auto --output table

# Check specific resource
az resource show --resource-group home-auto --name <resource-name>

```

## 🛡️ Best Practices Implemented

- ✅ **Parameterization**: All configurable values externalized
- ✅ **Security**: Sensitive data properly secured
- ✅ **Naming**: Consistent resource naming conventions
- ✅ **Dependencies**: Proper resource dependency management
- ✅ **Monitoring**: Comprehensive logging and telemetry
- ✅ **Scalability**: Consumption-based hosting for cost efficiency

## 📝 Template Structure

```ini
main.bicep
├── Parameters (external configuration)
├── Storage Account (function app storage)
├── Log Analytics Workspace (centralized logging)
├── Application Insights (telemetry)  
├── Service Bus Namespace & Queues (messaging)
├── App Service Plan (hosting)
├── Function Apps (compute)
└── Outputs (deployment results)

```

## 🔍 Resource Details

### Storage Account (`homeautomation`)

```bicep
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

```

### Service Bus Namespace

```bicep
resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: serviceBusNamespaceName
  location: location
  sku: { name: 'Standard', tier: 'Standard' }
  properties: {
    disableLocalAuth: false
  }
}

```

### Function Apps (Linux App Service Plan)

```bicep
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  sku: { name: 'Y1', tier: 'Dynamic' }
  kind: 'linux'
  properties: { reserved: true }
}

```

## 📈 Cost Optimization

### Resource Tiers

- __Storage Account__: Standard_LRS (lowest cost for function storage)
- **Service Bus**: Standard tier (message deduplication capabilities)
- **Function Apps**: Consumption plan (pay-per-execution)
- **Log Analytics**: Pay-as-you-go with 30-day retention

### Cost Monitoring

```bash
# Check current costs
az consumption usage list \
  --resource-group home-auto \
  --start-date 2025-09-01 \
  --end-date 2025-09-30

# Set up cost alerts
az monitor action-group create \
  --resource-group home-auto \
  --name cost-alerts \
  --short-name cost-alert

```

## 🔐 Security Configuration

### Parameter Security

```json
{
  "flumePassword": {
    "type": "securestring",
    "metadata": { "description": "Flume API password (secured)" }
  },
  "voiceMonkeyToken": {
    "type": "securestring", 
    "metadata": { "description": "VoiceMonkey access token (secured)" }
  }
}

```

### Network Security

- **HTTPS Only**: All resources configured for HTTPS traffic
- **TLS 1.2**: Minimum TLS version enforced
- **Function Keys**: HTTP triggers protected with function-level auth
- **Service Bus**: Secure connection strings with managed access

## 🛠️ Development & Testing

### Local Development

```bash
# Run Bicep validation locally
az bicep build --file main.bicep

# Test parameter file syntax
az deployment group validate \
  --resource-group home-auto \
  --template-file main.bicep \
  --parameters main.parameters.json

```

### CI/CD Integration

```yaml
# Azure DevOps pipeline example
- task: AzureResourceManagerTemplateDeployment@3
  inputs:
    deploymentScope: 'Resource Group'
    resourceGroupName: 'home-auto'
    location: 'East US'
    templateLocation: 'Linked artifact'
    csmFile: 'infra/main.bicep'
    csmParametersFile: 'infra/main.parameters.json'

```

## 📋 Parameter Reference

### Required Parameters

```json
{
  "functionAppName": "door-fn",
  "functionAppPlanName": "homeautomation-plan",
  "location": "eastus",
  "storageAccountName": "homeautomation",
  "flumeFunctionAppName": "flume-fn",
  "logAnalyticsWorkspaceName": "home-auto",
  "applicationInsightsName": "home-auto",
  "serviceBusNamespaceName": "srini-home-automation",
  "authKey": "your_secure_auth_key_here",
  "voiceMonkeyToken": "your_voice_monkey_token_here",
  "flumeUsername": "your_flume_email@example.com",
  "flumePassword": "your_secure_flume_password",
  "flumeClientId": "your_flume_client_id_here",
  "flumeClientSecret": "your_flume_client_secret_here",
  "flumeTargetDeviceId": "your_flume_device_id_here",
  "voiceMonkeyDevice": "your_alexa_device_name"
}

```

### Parameter Descriptions

#### Function App Configuration

- **functionAppName**: Name for the door automation Function App (.NET 8)
- **functionAppPlanName**: Name for the App Service Plan (Linux)
- **flumeFunctionAppName**: Name for the Flume water monitoring Function App (Python)

#### Infrastructure Configuration

- **location**: Azure region for resource deployment
- **storageAccountName**: Storage account for Function Apps
- **logAnalyticsWorkspaceName**: Name for Log Analytics workspace (monitoring)
- **applicationInsightsName**: Name for Application Insights instance (telemetry)
- **serviceBusNamespaceName**: Name for Service Bus namespace (messaging)

#### Application Secrets

- **authKey**: Secure authentication key for door functions
- **voiceMonkeyToken**: API token for VoiceMonkey Alexa integration
- **flumeUsername**: Your Flume account email address
- **flumePassword**: Your Flume account password
- **flumeClientId**: Flume API client identifier
- **flumeClientSecret**: Flume API client secret key
- **flumeTargetDeviceId**: Specific Flume device ID to monitor
- **voiceMonkeyDevice**: Target Alexa device name for notifications

## 🔄 Upgrade Procedures

### Template Updates

1. **Review Changes**: Use `az deployment group what-if` to preview
2. **Test Deployment**: Deploy to development environment first
3. **Backup Configuration**: Export current settings before changes
4. **Deploy Updates**: Use incremental deployment mode
5. **Validate Results**: Verify all resources and configurations

### Version Management

```bash
# Tag template versions
git tag -a v1.0.0 -m "Initial production deployment"
git tag -a v1.1.0 -m "Added enhanced logging configuration"

# Deploy specific version
git checkout v1.1.0
az deployment group create \
  --resource-group home-auto \
  --template-file main.bicep \
  --parameters main.parameters.json

```

## 🚨 Disaster Recovery

### Backup Strategy

- **Infrastructure**: Bicep templates in source control
- **Configuration**: Parameter files with secure storage
- **Application Code**: Function apps deployed from CI/CD
- **Data**: Service Bus message queues (transient data)

### Recovery Procedures

1. **Resource Group**: Recreate from Bicep template
2. **Configuration**: Deploy parameter file
3. **Applications**: Redeploy function apps
4. **Monitoring**: Validate telemetry collection
5. **Testing**: Execute end-to-end validation

## 📞 Support Information

### Template Dependencies

- **Azure CLI**: Version 2.50+ with Bicep extension
- **Bicep**: Version 0.20+ for latest features
- **Azure Subscription**: With necessary resource quotas
- **Service Principals**: For automated deployments

### Troubleshooting Resources

- **Bicep Documentation**: https://docs.microsoft.com/azure/azure-resource-manager/bicep/
- **Template Validation**: Use `az deployment group validate`
- **Resource Monitoring**: Application Insights and Log Analytics
- **Community Support**: Azure Bicep GitHub repository

---

## 🎯 Deployment Checklist

### Pre-Deployment

- ✅ **Azure CLI**: Installed and authenticated
- ✅ **Resource Group**: Created with appropriate permissions
- ✅ **Parameters**: Configured with secure values
- ✅ **Validation**: Template passes validation checks

### Post-Deployment

- ✅ **Resource Verification**: All resources deployed successfully
- ✅ **Configuration**: Application settings properly configured
- ✅ **Monitoring**: Application Insights collecting telemetry
- ✅ **Function Apps**: Ready for code deployment

This Bicep infrastructure provides a robust, secure, and scalable foundation for your home automation system with comprehensive monitoring and cost optimization!