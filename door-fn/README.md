# Door Event Processing Functions (.NET 8)

This .NET 8 Azure Function App processes door sensor events and coordinates Alexa notifications through VoiceMonkey integration.

## 🔧 Function Overview

### `ReceiveRequest` (HTTP Trigger)
- **Method**: POST
- **Purpose**: Receive door sensor events via HTTP
- **Authorization**: Function-level authentication
- **Output**: Routes events to Service Bus queues

### `SendRequest` (Service Bus Trigger)
- **Trigger**: Service Bus queue messages
- **Purpose**: Process door events and send VoiceMonkey notifications
- **Queues**: Monitors multiple door-specific queues
- **Integration**: VoiceMonkey API for Alexa alerts

### `CancelRequest` (Service Bus Trigger)
- **Trigger**: Service Bus queue messages
- **Purpose**: Handle event cancellations and cleanup
- **Functionality**: Cancel pending notifications or alerts

## 📋 Prerequisites

### Required Azure Resources
- ✅ **Function App** (Linux, .NET 8 Isolated Worker)
- ✅ **App Service Plan** (Linux-based for .NET 8 support)
- ✅ **Service Bus Namespace** (Standard tier)
- ✅ **Service Bus Queues** (6 queues for different door types)
- ✅ **Application Insights** (monitoring and logging)
- ✅ **Storage Account** (function app requirements)

### Service Bus Queue Configuration
```
your-servicebus-namespace namespace:
├── triggerevents          # Main event processing queue
├── front_door_unlocked    # Front door specific events
├── garage_door_open       # Garage door events
├── garage_open            # General garage events
├── door_left_open         # Left side door events
└── sliding_door_right_open # Sliding door events
```

## ⚙️ Configuration

### Application Settings (Environment Variables)

#### Core Function App Settings
```bash
# Azure Functions Runtime (auto-configured by Bicep)
FUNCTIONS_WORKER_RUNTIME=dotnet-isolated
FUNCTIONS_EXTENSION_VERSION=~4
WEBSITE_USE_PLACEHOLDER_DOTNETISOLATED=1

# Storage Configuration (auto-configured)
AzureWebJobsStorage=DefaultEndpointsProtocol=https;AccountName=your-storage-account;AccountKey=***;EndpointSuffix=core.windows.net

# Application Insights (auto-configured)
APPLICATIONINSIGHTS_CONNECTION_STRING=InstrumentationKey=your-app-insights-key;IngestionEndpoint=https://eastus-8.in.applicationinsights.azure.com/;LiveEndpoint=https://eastus.livediagnostics.monitor.azure.com/
APPINSIGHTS_INSTRUMENTATIONKEY=your-app-insights-instrumentation-key
```

#### VoiceMonkey API Configuration (Required - Manual Setup)
```bash
# VoiceMonkey Integration Token - SET THIS MANUALLY
VoiceMonkey__Token=your_voice_monkey_access_token

# Example VoiceMonkey Configuration Format
VoiceMonkey__Token=vm_abc123def456ghi789_example_token
```

#### Door Sensor Authentication (Required - Manual Setup)
```bash
# Authentication key for door sensor HTTP requests - SET THIS MANUALLY
AuthKey=your_door_sensor_authentication_key

# Example Authentication Configuration Format
AuthKey=example_auth_key_placeholder
```

#### Service Bus Configuration (Auto-configured by Bicep)
```bash
# Service Bus Connection (deployed as 'sbcon')
sbcon=Endpoint=sb://your-servicebus-namespace.servicebus.windows.net/;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=***

# Service Bus Queue Names (referenced in code)
ServiceBusQueueTriggerEvents=triggerevents
ServiceBusQueueFrontDoor=front_door_unlocked  
ServiceBusQueueGarageDoor=garage_door_open
ServiceBusQueueGarageOpen=garage_open
ServiceBusQueueDoorLeft=door_left_open
ServiceBusQueueSlidingDoor=sliding_door_right_open
```

#### Logging Configuration (Auto-configured)
```bash
# Enhanced Logging Level
FUNCTIONS_WORKER_RUNTIME_LOG_LEVEL=Information
AZURE_FUNCTIONS_ENVIRONMENT=Production

# Application Insights Sampling
APPINSIGHTS_SAMPLING_PERCENTAGE=100
```

### Manual Configuration Steps

#### 1. Set Required Application Settings
```bash
# Set VoiceMonkey token (REQUIRED)
az functionapp config appsettings set \
  --resource-group home-auto \
  --name door-fn \
  --settings "VoiceMonkey__Token=your_actual_voice_monkey_token"

# Set door sensor authentication key (REQUIRED)
az functionapp config appsettings set \
  --resource-group home-auto \
  --name door-fn \
  --settings "AuthKey=your_door_sensor_auth_key"

# Service Bus connection (auto-configured as 'sbcon')
# Only set this if not automatically configured
az functionapp config appsettings set \
  --resource-group home-auto \
  --name door-fn \
  --settings "sbcon=Endpoint=sb://your-servicebus-namespace.servicebus.windows.net/;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=your_service_bus_key"
```

#### 2. Verify Required Settings
```bash
# List all application settings
az functionapp config appsettings list \
  --resource-group home-auto \
  --name door-fn \
  --output table

# Check specific required settings
az functionapp config appsettings list \
  --resource-group home-auto \
  --name door-fn \
  --query "[?name=='VoiceMonkey__Token' || name=='AuthKey' || name=='sbcon']"
```

#### 3. Update Configuration (If Needed)
```bash
# Update VoiceMonkey token
az functionapp config appsettings set \
  --resource-group home-auto \
  --name door-fn \
  --settings "VoiceMonkey__Token=new_token_value"

# Update door sensor authentication key
az functionapp config appsettings set \
  --resource-group home-auto \
  --name door-fn \
  --settings "AuthKey=new_auth_key_value"

# Update Service Bus connection if needed
az functionapp config appsettings set \
  --resource-group home-auto \
  --name door-fn \
  --settings "sbcon=new_service_bus_connection_string"
```

### Function Configuration (`host.json`)
```json
{
  "version": "2.0",
  "functionTimeout": "00:05:00",
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true
      }
    },
    "logLevel": {
      "default": "Information"
    }
  },
  "extensions": {
    "serviceBus": {
      "prefetchCount": 100,
      "maxConcurrentCalls": 32,
      "autoCompleteMessages": true
    }
  }
}
```

## 🚀 Deployment Process

### 1. Build and Package
```bash
# From door-fn directory
dotnet build --configuration Release
dotnet publish --configuration Release
```

### 2. Deploy to Azure
```bash
# Deploy using Azure Functions Core Tools
func azure functionapp publish door-fn

# Alternative: Deploy using Azure CLI
az functionapp deployment source config-zip \
  --resource-group home-auto \
  --name door-fn \
  --src release.zip
```

### 3. Configure Application Settings
```bash
# Set VoiceMonkey configuration (use correct setting name)
az functionapp config appsettings set \
  --resource-group home-auto \
  --name door-fn \
  --settings "VoiceMonkey__Token=your_token"

# Set door sensor authentication key
az functionapp config appsettings set \
  --resource-group home-auto \
  --name door-fn \
  --settings "AuthKey=your_auth_key"

# Service Bus connection is configured via Bicep template as 'sbcon'
```

## 🧪 Testing & Validation

### HTTP Trigger Testing (`ReceiveRequest`)
```bash
# Test front door unlock event
curl -X POST "https://door-fn.azurewebsites.net/api/ReceiveRequest?code={function-key}" \
  -H "Content-Type: application/json" \
  -d '{
    "door": "front_door",
    "status": "unlocked",
    "timestamp": "2025-09-10T10:30:00Z",
    "deviceId": "front_door_sensor_001"
  }'

# Expected Response: HTTP 200 with confirmation message
# Expected Action: Message queued to Service Bus
```

### Service Bus Message Testing
```bash
# Send test message directly to Service Bus queue
az servicebus queue message send \
  --resource-group home-auto \
  --namespace-name your-servicebus-namespace \
  --queue-name triggerevents \
  --body '{
    "door": "garage_door",
    "status": "open",
    "timestamp": "2025-09-10T11:00:00Z"
  }'
```

### End-to-End Validation
1. **Send HTTP Request**: Use curl or Postman to trigger ReceiveRequest
2. **Monitor Service Bus**: Check queue message count
3. **Verify Processing**: Confirm SendRequest processes the message
4. **Validate Notification**: Check Alexa device receives notification
5. **Review Logs**: Examine Application Insights for execution traces

## 📊 Function Logic Flow

### Event Processing Pipeline
```
1. 🌐 HTTP Request → ReceiveRequest function
2. 📝 Validate and log incoming event
3. 📤 Route to appropriate Service Bus queue
4. 🚌 Service Bus triggers SendRequest function
5. 🔍 Process door event details
6. 📢 Send VoiceMonkey notification
7. ✅ Complete message processing
8. 📊 Log execution results to Application Insights
```

### Door Event Types
```csharp
// Supported door events
public enum DoorStatus
{
    Unlocked,     // "Front door has been unlocked"
    Locked,       // "Front door has been locked"
    Open,         // "Garage door is open"
    Closed,       // "Garage door is closed"
    LeftOpen      // "Door has been left open"
}
```

## 🔍 Monitoring & Troubleshooting

### Application Insights Queries
```kql
// Function execution overview
requests
| where cloud_RoleName == "door-fn"
| summarize 
    Count = count(),
    AvgDuration = avg(duration),
    SuccessRate = countif(success == true) * 100.0 / count()
by operation_Name, bin(timestamp, 1h)

// Error analysis
exceptions
| where cloud_RoleName == "door-fn"
| project timestamp, operation_Name, problemId, outerMessage
| order by timestamp desc

// Service Bus processing metrics
dependencies
| where cloud_RoleName == "door-fn"
| where type == "Azure Service Bus"
| summarize count() by resultCode, bin(timestamp, 5m)
```

### Real-time Log Monitoring
```bash
# Stream function logs
az webapp log tail --resource-group home-auto --name door-fn

# Download recent logs
az webapp log download --resource-group home-auto --name door-fn

# Function-specific logs
func azure functionapp logstream door-fn
```

### Common Issues & Solutions

#### Function Not Triggering
```bash
# Check function app status
az functionapp show \
  --resource-group home-auto \
  --name door-fn \
  --query "state"

# Restart function app if needed
az functionapp restart --resource-group home-auto --name door-fn
```

#### Service Bus Connection Issues
```bash
# Verify Service Bus connection string (check 'sbcon' setting)
az functionapp config appsettings list \
  --resource-group home-auto \
  --name door-fn \
  --query "[?name=='sbcon']"

# Test Service Bus connectivity
az servicebus namespace authorization-rule keys list \
  --resource-group home-auto \
  --namespace-name your-servicebus-namespace \
  --name RootManageSharedAccessKey
```

#### VoiceMonkey Integration Problems
```bash
# Check VoiceMonkey settings (check 'VoiceMonkey__Token' setting)
az functionapp config appsettings list \
  --resource-group home-auto \
  --name door-fn \
  --query "[?name=='VoiceMonkey__Token']"

# Test VoiceMonkey API manually
curl -X POST "https://api.voicemonkey.io/trigger" \
  -H "Content-Type: application/json" \
  -d '{
    "access_token": "your_token",
    "monkey": "your_device_name",
    "announcement": "Test notification from door function"
  }'
```

#### Door Sensor Authentication Issues
```bash
# Check door sensor authentication key
az functionapp config appsettings list \
  --resource-group home-auto \
  --name door-fn \
  --query "[?name=='AuthKey']"

# Test door sensor endpoint with authentication
curl -X POST "https://door-fn.azurewebsites.net/api/ReceiveRequest?code={function-key}" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your_auth_key" \
  -d '{
    "door": "front_door",
    "status": "unlocked",
    "timestamp": "2025-09-10T10:30:00Z"
  }'
```

## 🛡️ Security Considerations

### Authentication & Authorization
- **HTTP Triggers**: Function-level authentication keys required
- **Service Bus**: Managed identity or connection string authentication
- **VoiceMonkey**: API token-based authentication
- **Application Insights**: Automatic Azure authentication

### Secure Configuration Management
```bash
# Rotate function keys
az functionapp keys renew \
  --resource-group home-auto \
  --name door-fn \
  --key-type functionKeys \
  --key-name default

# Update VoiceMonkey token securely
az functionapp config appsettings set \
  --resource-group home-auto \
  --name door-fn \
  --settings "VoiceMonkey__Token=new_secure_token"
```

## 📈 Performance & Scaling

### Current Configuration
- **Hosting Plan**: Linux App Service Plan (supports .NET 8)
- **Runtime**: .NET 8 Isolated Worker Model
- **Concurrency**: Up to 32 concurrent Service Bus messages
- **Timeout**: 5 minutes maximum execution time

### Optimization Recommendations
- 🚀 **Prefetch Count**: Configured for optimal Service Bus throughput
- 📊 **Concurrent Processing**: Multiple messages processed simultaneously
- 🔄 **Retry Policies**: Built-in Service Bus retry mechanisms
- 💾 **Memory Efficiency**: .NET 8 performance improvements

### Scaling Considerations
```bash
# Monitor function execution metrics
az monitor metrics list \
  --resource "/subscriptions/{sub-id}/resourceGroups/home-auto/providers/Microsoft.Web/sites/door-fn" \
  --metric "FunctionExecutionCount" \
  --interval PT1H

# Check Service Bus queue length
az servicebus queue show \
  --resource-group home-auto \
  --namespace-name your-servicebus-namespace \
  --name triggerevents \
  --query "messageCount"
```

## 🔧 Development & Debugging

### Local Development Setup
```bash
# Install .NET 8 SDK
winget install Microsoft.DotNet.SDK.8

# Install Azure Functions Core Tools
npm install -g azure-functions-core-tools@4 --unsafe-perm true

# Run functions locally
func start --verbose
```

### Debug Configuration (`local.settings.json`)
```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "dotnet-isolated",
    "sbcon": "Endpoint=sb://localhost...",
    "VoiceMonkey__Token": "your_development_token",
    "AuthKey": "your_test_auth_key"
  }
}
```

### Unit Testing Examples
```csharp
[Test]
public async Task ReceiveRequest_ValidDoorEvent_ReturnsSuccess()
{
    // Arrange
    var request = new DoorEvent 
    { 
        Door = "front_door", 
        Status = "unlocked" 
    };
    
    // Act
    var response = await _function.Run(request, _logger);
    
    // Assert
    Assert.That(response.StatusCode, Is.EqualTo(200));
}
```

## 📞 Maintenance & Support

### Regular Maintenance Tasks
- **Weekly**: Review function execution metrics and error rates
- **Monthly**: Update API tokens and validate external integrations
- **Quarterly**: Review and optimize Service Bus queue configuration

### Deployment Updates
```bash
# Update function code
dotnet build --configuration Release
func azure functionapp publish door-fn

# Update configuration
az functionapp config appsettings set \
  --resource-group home-auto \
  --name door-fn \
  --settings "NEW_SETTING=value"
```

### Backup & Recovery
- **Configuration**: Export application settings regularly
- **Code**: Maintain source control with Git
- **Infrastructure**: Bicep templates provide infrastructure as code
- **Monitoring**: Application Insights retains 90 days of telemetry

---

## 🎯 Integration Points

### External APIs
- **VoiceMonkey**: Alexa notification delivery
- **Door Sensors**: HTTP webhook integration
- **Service Bus**: Azure message queuing service

### Internal Dependencies
- **Application Insights**: Telemetry and monitoring
- **Storage Account**: Function app runtime requirements
- **Log Analytics**: Centralized logging workspace

This .NET 8 door function provides reliable, scalable door event processing with comprehensive monitoring and robust error handling!