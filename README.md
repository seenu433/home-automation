# <<<<<<< HEAD

""

# 🏠 Home Automation System

Complete **Azure-native** home automation system with door monitoring and water leak detection capabilities. **100% Azure - No AWS Lambda dependencies!**

## 🎯 System Overview

This home automation solution provides:

- **🚪 Door Event Processing**: Real-time door status monitoring with enhanced Alexa integration
- **💧 Water Leak Detection**: Automated Flume sensor monitoring with alerts
- **🎮 Virtual Smart Devices**: Alexa-discoverable switches and sensors for routine triggering
- **📢 Queue Management**: Priority-based announcement queuing with device targeting
- **🔄 Press Event System**: Programmatic trigger system for Alexa routines
- **☁️ Azure-Native Architecture**: Fully deployed on Azure with comprehensive monitoring
- **📱 Enhanced Voice Integration**: Direct Alexa Smart Home integration with fallback support
- **💰 Cost-Optimized**: Single cloud provider (Azure) - no AWS Lambda costs

## 🏗️ Architecture

```ini
┌─────────────────────────────────────────────────────────────┐
│                 Azure-Native Home Automation                 │
├─────────────────────────────────────────────────────────────┤
│  🌐 External APIs        │  ☁️ Azure Services              │
│  ├── Alexa Skills        │  ├── Function Apps              │
│  ├── Flume API           │  │   ├── alexa-fn (Python 3.11) │
│  └── Door Sensors        │  │   ├── door-fn (.NET 8)       │
│                          │  │   └── flume-fn (Python 3.11) │
│                          │  ├── Service Bus (6 queues)     │
│                          │  ├── Application Insights       │
│                          │  └── Log Analytics Workspace    │
└─────────────────────────────────────────────────────────────┘

```

## 🚀 Quick Start

**Ready to deploy? Run one command:**

```powershell
.\deploy-azure.ps1
```

This master deployment script handles everything: Azure infrastructure, function apps, Alexa skill configuration, and system testing. See [deployment section](#complete-system-deployment) for details.

## 📁 Project Structure

```ini
home-automation/
├── 📂 alexa-fn/                   # Python Alexa Skill Backend
│   ├── function_app.py            # Alexa skill HTTP handlers
│   ├── requirements.txt           # Python dependencies
│   └── local.settings.json        # Local configuration
│
├── 📂 alexa-skill/                # Alexa Skill Configuration  
│   ├── skill-package/             # Alexa skill JSON configuration
│   └── README.md                  # Skill setup documentation
│
├── 📂 door-fn/                    # .NET 8 Door Event Functions
│   ├── ReceiveRequest.cs          # HTTP trigger for door events
│   ├── SendRequest.cs             # Service Bus message processor
│   ├── CancelRequest.cs           # Event cancellation handler
│   ├── host.json                  # Function app configuration
│   └── README.md                  # Door function documentation
│
├── 📂 flume-fn/                   # Python Water Monitoring
│   ├── function_app.py            # Timer-based leak detection
│   ├── requirements.txt           # Python dependencies
│   └── README.md                  # Flume function documentation
│
├── 📂 infra/                      # Infrastructure as Code
│   ├── main.bicep                 # Complete Azure resource template  
│   ├── main.parameters.json       # Production configuration
│   ├── deploy.ps1                 # Infrastructure deployment
│   ├── deploy-alexa-skill.ps1     # Alexa skill deployment
│   ├── get-function-config.ps1    # Configuration management
│   └── README.md                  # Infrastructure documentation
│
├── 📄 deploy-azure.ps1            # 🎯 Master deployment script
│
├── AZURE_MIGRATION.md             # AWS Lambda to Azure migration docs
└── README.md                      # This system overview

```

## 🚀 Quick Start Deployment

### 1. Prerequisites Setup

```bash
# Install required tools
winget install Microsoft.AzureCLI
winget install Microsoft.Azure.FunctionsCoreTools

# Login to Azure
az login

# Create resource group
az group create --name home-auto --location eastus

```

### 2. Configure Parameters

Edit `infra/main.parameters.json` with your credentials:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "functionAppName": {"value": "door-fn"},
    "flumeFunctionAppName": {"value": "flume-fn"},
    "alexaFunctionAppName": {"value": "alexa-fn"},
    "flumeUsername": {"value": "your_flume_email@example.com"},
    "flumePassword": {"value": "your_flume_password"},
    "flumeClientId": {"value": "your_flume_client_id"},
    "flumeClientSecret": {"value": "your_flume_client_secret"},
    "flumeTargetDeviceId": {"value": "your_flume_device_id"},
    "alexaNotificationClientId": {"value": "your_alexa_client_id"},
    "alexaNotificationClientSecret": {"value": "your_alexa_client_secret"}
  }
}

```

> __💡 Note__: All application settings are automatically configured by the Bicep deployment using these parameters. Authentication is handled by Azure Function keys.

### 3. Deploy Infrastructure

```bash
# Deploy all Azure resources with complete configuration
cd infra
az deployment group create \
  --resource-group home-auto \
  --template-file main.bicep \
  --parameters main.parameters.json

```

### 4. Complete System Deployment

#### Option A: One-Command Deployment (Recommended)

```powershell
# 🚀 Deploy everything: infrastructure + functions + Alexa skill + testing
.\deploy-azure.ps1

# The script will:
# ✅ Deploy all Azure resources (Bicep)
# ✅ Deploy all function apps (door-fn, flume-fn, alexa-fn) 
# ✅ Configure Alexa skill backend
# ✅ Test all components
# ✅ Provide voice command examples

```

#### Option B: Manual Step-by-Step Deployment

```bash
# Deploy .NET door functions
cd door-fn
func azure functionapp publish door-fn

# Deploy Python flume functions  
cd flume-fn
func azure functionapp publish flume-fn

# Deploy Alexa skill backend to Azure (NOT AWS Lambda!)
cd infra
.\deploy-alexa-skill.ps1

```

### 5. Verify Deployment

```bash
# Check function app status
az functionapp list --resource-group home-auto --output table

# Verify door-fn configuration (all settings configured via Bicep)
az functionapp config appsettings list \
  --resource-group home-auto \
  --name door-fn \
  --query "[?name=='sbcon' || name=='ALEXA_FN_BASE_URL']"

# Test door function
curl -X POST "https://door-fn.azurewebsites.net/api/ReceiveRequest?code={function-key}" \
  -H "Content-Type: application/json" \
  -d '{"door": "front_door", "status": "unlocked"}'

# Monitor logs
az webapp log tail --resource-group home-auto --name flume-fn

```

## 🔧 System Components

### Alexa Skill Backend (alexa-fn)
- **Technology**: Python 3.11 on Azure Functions (NOT AWS Lambda!)
- **Triggers**: HTTP requests from Alexa service
- **Purpose**: Handle Alexa voice commands and skill interactions  
- **Integration**: Service Bus for announcements, door-fn API calls
- **Features**: Smart Home device discovery, voice announcements, door event reporting
- **Deployment**: Native Azure deployment eliminates AWS costs

### Door Event Processing (door-fn)

- **Technology**: .NET 8 Isolated Worker Model
- **Triggers**: HTTP requests, Service Bus messages
- **Purpose**: Process door sensor events and coordinate notifications
- **Queues**: 6 specialized queues for different door types
- **Integration**: alexa-fn API for Alexa notifications
- **Configuration**: All settings automatically deployed via Bicep parameters

### Water Leak Detection (flume-fn)

- **Technology**: Python 3.11 on Linux
- **Triggers**: Timer (every 5 minutes)
- **Purpose**: Monitor Flume water sensors for leak detection
- **API**: Flume cloud service integration
- **Alerts**: Alexa notifications for water anomalies
- **Configuration**: All Flume API credentials deployed via Bicep parameters

### Infrastructure (infra/)

- **Technology**: Bicep Infrastructure as Code
- **Resources**: Function Apps, Service Bus, Monitoring Stack
- **Security**: Fully parameterized templates with secure values
- **Monitoring**: Application Insights + Log Analytics
- **Configuration**: Complete application settings management

## 📊 Monitoring & Observability

### Application Insights Integration

```kql
// Function execution overview
requests
| where cloud_RoleName in ("door-fn", "flume-fn")
| summarize 
    ExecutionCount = count(),
    AvgDuration = avg(duration),
    SuccessRate = countif(success == true) * 100.0 / count()
by cloud_RoleName, bin(timestamp, 1h)

```

### Service Bus Queue Monitoring

```bash
# Check queue message counts
az servicebus queue show \
  --resource-group home-auto \
  --namespace-name srini-home-automation \
  --name triggerevents \
  --query "messageCount"

```

### Function App Health Checks

```bash
# Get function app metrics
az monitor metrics list \
  --resource "/subscriptions/{subscription-id}/resourceGroups/home-auto/providers/Microsoft.Web/sites/door-fn" \
  --metric "Requests" \
  --interval PT1H

```

## 🛡️ Security Features

### Authentication & Authorization

- **Function Level**: HTTP trigger authentication keys
- **API Integration**: Secure credential management via Bicep parameters
- **Network Security**: HTTPS-only communication
- **Secrets Management**: All sensitive values handled via @secure() parameters

## 🎮 Virtual Smart Devices

The system now includes enhanced Alexa integration through virtual smart devices that appear as switches and sensors in your Alexa app. This enables sophisticated automation through Alexa routines.

### Key Features
- **Smart Home Integration**: Devices appear natively in Alexa app
- **Press Event System**: Programmatically trigger virtual device presses 
- **Queue Management**: Priority-based announcement queuing with device targeting
- **Routine Integration**: Seamless integration with Alexa routines for complex automations
- **Fallback Support**: Graceful degradation to direct announcements if needed

### Device Types
- **Virtual Switches**: `PowerController` interface for press/toggle events
- **Contact Sensors**: `ContactSensor` interface for open/close states  
- **Area Targeting**: Bedroom, Upstairs, Downstairs, All devices

### Configuration Files
- `alexa-fn/virtual-devices-config.json` - Device definitions and queue settings
- `CONFIG_VIRTUAL_DEVICES.md` - Complete setup and usage guide
- `alexa-fn/VIRTUAL_DEVICES_GUIDE.md` - Detailed technical documentation

### API Endpoints
- `POST /api/queue` - Add message to device queue
- `POST /api/press` - Trigger device press event  
- `GET /api/devices` - List configured devices
- `GET /api/queue/{device}` - Get queue for specific device

### Secure Configuration

- **Parameter Files**: All sensitive data externalized and automatically deployed
- **@secure() Decorator**: Bicep template security for all credentials
- **Environment Variables**: Runtime configuration isolation
- **API Key Rotation**: Support for credential updates via parameter file

## 🧪 Testing & Validation

### Door Function Testing

```bash
# Test door unlock event
curl -X POST "https://door-fn.azurewebsites.net/api/ReceiveRequest?code={function-key}" \
  -H "Content-Type: application/json" \
  -d '{
    "door": "front_door",
    "status": "unlocked",
    "timestamp": "2025-09-10T10:30:00Z"
  }'

# Expected: Alexa notification "Front door has been unlocked"

```

### Flume Function Testing

```bash
# Manual function execution
az functionapp function invoke \
  --resource-group home-auto \
  --name flume-fn \
  --function-name flume_timer_function

# Check logs for water status
az webapp log tail --resource-group home-auto --name flume-fn

```

### End-to-End Validation

1. **Door Events**: Trigger door sensor → Service Bus → Alexa notification
2. **Water Monitoring**: Timer execution → Flume API check → Alert if needed
3. **Monitoring**: All events captured in Application Insights
4. **Logging**: Structured logs with emoji indicators for easy tracking

## 🔧 Troubleshooting Guide

### Common Issues & Solutions

#### Function App Deployment Fails

```bash
# Check deployment logs
az webapp deployment list --resource-group home-auto --name door-fn

# Restart function app
az functionapp restart --resource-group home-auto --name door-fn

```

#### Service Bus Connection Issues

```bash
# Verify connection string (automatically configured by Bicep)
az functionapp config appsettings list \
  --resource-group home-auto \
  --name door-fn \
  --query "[?name=='sbcon']"

```

#### Alexa Function Integration Problems

```bash
# Check Alexa Function settings (configured by Bicep parameters)
az functionapp config appsettings list \
  --resource-group home-auto \
  --name door-fn \
  --query "[?name=='ALEXA_FN_BASE_URL' || name=='ALEXA_FN_API_KEY']"

# Test Alexa Function API manually
curl -X POST "https://alexa-fn.azurewebsites.net/api/announce" \
  -H "Content-Type: application/json" \
  -H "x-functions-key: your_alexa_function_key" \
  -d '{
    "message": "Test notification from door function",
    "device": "all"
  }'

```

#### Configuration Issues

> **💡 Important**: All application settings are managed through Bicep parameters. If settings are missing, verify your `main.parameters.json` file and redeploy the infrastructure rather than manually configuring settings.

```bash
# Redeploy with updated parameters
cd infra
az deployment group create \
  --resource-group home-auto \
  --template-file main.bicep \
  --parameters main.parameters.json

```

#### Timer Function Not Executing

```bash
# Check function status
az functionapp function show \
  --resource-group home-auto \
  --name flume-fn \
  --function-name flume_timer_function

# Verify timer configuration in function.json

```

### Log Analysis Queries

```kql
// Error analysis
traces
| where severityLevel >= 3
| where cloud_RoleName in ("door-fn", "flume-fn")
| project timestamp, message, severityLevel, cloud_RoleName
| order by timestamp desc

// Performance monitoring
requests
| where cloud_RoleName in ("door-fn", "flume-fn")
| summarize avg(duration), max(duration), count() by cloud_RoleName

```

## 📈 Performance & Scaling

### Current Configuration

- **Door Functions**: Consumption plan (auto-scaling)
- **Flume Function**: Single instance (appropriate for monitoring)
- **Service Bus**: Standard tier (6 queues, message deduplication)
- **Monitoring**: 30-day retention, Information-level logging

### Optimization Recommendations

- 🚀 **Caching**: Implement response caching for frequent API calls
- 📊 **Batching**: Process multiple events in single execution
- 🔄 **Retry Policies**: Exponential backoff for external API failures
- 💾 **State Management**: Optimize function cold start times

## 🔄 Maintenance & Updates

### Regular Maintenance Tasks

- **Weekly**: Review function execution metrics and error rates
- **Monthly**: Update API credentials in parameters file and redeploy infrastructure
- **Quarterly**: Review and optimize detection thresholds and alerting rules

### Update Procedures

1. **Code Updates**: Deploy functions using `func azure functionapp publish`
2. **Infrastructure Changes**: Update Bicep templates and redeploy
3. **Configuration Updates**: Modify `main.parameters.json` and redeploy infrastructure
4. **Monitoring Updates**: Adjust Application Insights queries and alerts

## 📞 Support & Documentation

### Component Documentation

- **[Door Functions](door-fn/README.md)**: .NET function deployment and testing
- **[Flume Functions](flume-fn/README.md)**: Python function configuration and API integration
- **[Infrastructure](infra/README.md)**: Bicep templates and deployment procedures

### External Dependencies

- **Flume API**: Water sensor data and device management
- **alexa-fn API**: Alexa notification delivery service
- **Azure Services**: Function Apps, Service Bus, Application Insights

### System Requirements

- **Azure Subscription**: With Function Apps and Service Bus capabilities
- **API Accounts**: Active Flume subscription
- **Development Tools**: Azure CLI, Azure Functions Core Tools
- **Network Access**: HTTPS connectivity to external APIs

---

## 🎉 System Status

✅ **Production Ready**: Complete deployment with monitoring  
✅ **Secure Configuration**: Fully parameterized templates with secret management  
✅ **Comprehensive Logging**: Information-level logging with emoji indicators  
✅ **Clean Architecture**: Modular design with clear separation of concerns  
✅ **Full Documentation**: Complete deployment and maintenance guides  
✅ **Automated Configuration**: All application settings deployed via Infrastructure as Code

Your home automation system is ready for reliable 24/7 operation!

> > > > > > > master
