# Flume Water Leak Detection Function (Python)

This Python Azure Function monitors Flume water sensors for potential leaks and sends Alexa notifications through VoiceMonkey when issues are detected.

## 🔧 Function Overview

### `flume_timer_function`
- **Trigger**: Timer (every 5 minutes)
- **Runtime**: Python 3.11 on Linux
- **Purpose**: Monitor Flume devices for water leak detection
- **Notifications**: Alexa alerts via VoiceMonkey API

## 📋 Prerequisites

### Required Azure Resources
- ✅ **Function App** (Linux, Python 3.11)
- ✅ **Storage Account** (for function app state)
- ✅ **Application Insights** (for monitoring and logging)
- ✅ **Log Analytics Workspace** (centralized logging)

### Required API Access
- ✅ **Flume API Account** with active subscription
- ✅ **VoiceMonkey Account** with device configuration
- ✅ **API Credentials** properly configured

## ⚙️ Configuration

### Environment Variables (Application Settings)
```bash
# Flume API Configuration
FLUME_USERNAME=your_flume_email@example.com
FLUME_PASSWORD=your_flume_password
FLUME_CLIENT_ID=your_flume_client_id
FLUME_CLIENT_SECRET=your_flume_client_secret

# VoiceMonkey Configuration  
VOICE_MONKEY_TOKEN=your_voice_monkey_token
VOICE_MONKEY_DEVICE=your_alexa_device_name

# Azure Configuration (auto-configured)
AzureWebJobsStorage=DefaultEndpointsProtocol=https;AccountName=...
APPLICATIONINSIGHTS_CONNECTION_STRING=InstrumentationKey=...
FUNCTIONS_WORKER_RUNTIME=python
```

### Required Dependencies (`requirements.txt`)
```
azure-functions
requests
azure-functions-worker
```

## 🚀 Deployment Process

### 1. Deploy Infrastructure
```bash
# Deploy from infra directory
az deployment group create \
  --resource-group home-auto \
  --template-file main.bicep \
  --parameters main.parameters.json
```

### 2. Deploy Function Code
```bash
# From flume-fn directory
func azure functionapp publish flume-fn --python
```

### 3. Configure Application Settings
```bash
# Set Flume API credentials
az functionapp config appsettings set \
  --resource-group home-auto \
  --name flume-fn \
  --settings "FLUME_USERNAME=your_email@example.com"

az functionapp config appsettings set \
  --resource-group home-auto \
  --name flume-fn \
  --settings "FLUME_PASSWORD=your_password"

# Set VoiceMonkey configuration
az functionapp config appsettings set \
  --resource-group home-auto \
  --name flume-fn \
  --settings "VOICE_MONKEY_TOKEN=your_token"
```

## 🧪 Testing & Validation

### Manual Function Execution
```bash
# Test the timer function manually
az functionapp function invoke \
  --resource-group home-auto \
  --name flume-fn \
  --function-name flume_timer_function
```

### Log Monitoring
```bash
# Stream function logs in real-time
az webapp log tail --resource-group home-auto --name flume-fn

# View recent logs
az webapp log download --resource-group home-auto --name flume-fn
```

### Application Insights Queries
```kql
// Function execution traces
traces
| where cloud_RoleName == "flume-fn"
| where timestamp > ago(1h)
| project timestamp, message, severityLevel
| order by timestamp desc

// Function performance
requests
| where cloud_RoleName == "flume-fn"
| summarize avg(duration), count() by bin(timestamp, 5m)
```

## 📊 Function Logic Flow

### Timer Execution (Every 5 Minutes)
```
1. 🚀 Function triggered by timer
2. 🔑 Authenticate with Flume API
3. 📱 Retrieve device list and status
4. 💧 Check for water usage anomalies
5. 🚨 Detect potential leaks
6. 📢 Send Alexa notifications if needed
7. 📝 Log execution results
```

### Leak Detection Logic
```python
# Enhanced logging with emoji indicators
if high_usage_detected:
    logging.info("🚨 High water usage detected - potential leak!")
    send_voice_monkey_alert("Water leak detected")
else:
    logging.info("✅ Water usage normal")
```

## 🔍 Monitoring & Troubleshooting

### Common Issues & Solutions

#### Authentication Errors
```bash
# Symptoms: 401/403 errors in logs
# Solution: Verify API credentials
az functionapp config appsettings list \
  --resource-group home-auto \
  --name flume-fn \
  --query "[?name=='FLUME_USERNAME']"
```

#### Timer Not Triggering
```bash
# Symptoms: No recent executions
# Solution: Check function app status
az functionapp show \
  --resource-group home-auto \
  --name flume-fn \
  --query "state"

# Restart if needed
az functionapp restart \
  --resource-group home-auto \
  --name flume-fn
```

#### VoiceMonkey Notifications Not Working
```bash
# Check VoiceMonkey configuration
az functionapp config appsettings list \
  --resource-group home-auto \
  --name flume-fn \
  --query "[?name=='VOICE_MONKEY_TOKEN']"
```

### Performance Monitoring
- ✅ **Execution Duration**: Typically < 30 seconds
- ✅ **Success Rate**: Should be > 95%
- ✅ **API Response Times**: Monitor Flume API latency
- ✅ **Memory Usage**: Python runtime memory consumption

## 🛡️ Security Considerations

### API Key Management
- 🔒 **Secure Storage**: All credentials in Application Settings
- 🔄 **Rotation**: Regular API key rotation recommended
- 🚫 **Source Control**: Never commit credentials to code

### Network Security
- 🌐 **HTTPS Only**: All API calls use secure connections
- 🔐 **Authentication**: Proper OAuth/API key usage
- 📝 **Audit Logs**: Comprehensive logging for security review

## 📈 Scaling & Performance

### Current Configuration
- **Timer Interval**: 5 minutes (optimal for leak detection)
- **Timeout**: 5 minutes maximum execution time
- **Concurrency**: Single instance (appropriate for monitoring)

### Optimization Tips
- 🚀 **API Caching**: Consider caching device lists between runs
- 📊 **Batch Processing**: Process multiple devices efficiently  
- 🔄 **Retry Logic**: Implement exponential backoff for API failures
- 💾 **State Management**: Use Azure Storage for persistent state

## 📞 Support & Maintenance

### Regular Maintenance Tasks
1. **Weekly**: Review execution logs for patterns
2. **Monthly**: Validate API credentials and quotas
3. **Quarterly**: Review and optimize detection thresholds

### Escalation Contacts
- **Flume API Issues**: Contact Flume support
- **VoiceMonkey Issues**: Check VoiceMonkey dashboard
- **Azure Function Issues**: Review Application Insights metrics