# Alexa Skill Package

This folder contains the Alexa skill package for the Home Automation system, including an AWS Lambda proxy for Smart Home functionality.

## Overview

The Home Automation system runs on Azure Functions, but Alexa Smart Home skills require AWS Lambda endpoints. This proxy provides the bridge between AWS Lambda and Azure Functions.

## Architecture

```
Alexa Smart Home ──► AWS Lambda Proxy ──► Azure Function (srp-alexa-fn)
                     (Minimal Forwarding)    (Full Business Logic)
```

## Files

- `lambda_function.py` - Minimal AWS Lambda proxy that forwards requests to Azure
- `requirements.txt` - Python dependencies for Lambda  
- `deploy-to-aws.ps1` - PowerShell deployment script for Windows
- `deploy-to-aws.sh` - Bash deployment script for Linux/Mac
- `skill-package/` - Alexa skill configuration files

## 🚀 **AWS Lambda Proxy Deployment**

### Prerequisites

1. **AWS CLI installed and configured**
2. **Python 3.11 installed** 
3. **Azure Function Key** (get from Azure portal)

### Deploy to AWS Lambda

```powershell
# Navigate to alexa-skill folder
cd alexa-skill

# Get Azure Function Key
az functionapp keys list --name srp-alexa-fn --resource-group srp-home-automation --query "functionKeys.default" --output tsv

# Deploy Lambda proxy
.\deploy-to-aws.ps1 -AzureFunctionKey "YOUR_AZURE_FUNCTION_KEY"
```

### Configure Alexa Developer Console

1. Set Smart Home endpoint to Lambda ARN
2. Add Lambda permissions for Alexa
3. Test device discovery

## 🏗️ **Azure Infrastructure Deployment**

👉 **[Go to Infrastructure Deployment Guide](../infra/README.md)**

---

# Home Automation Alexa Skill with Announcements

This Alexa skill provides comprehensive home automation control through voice commands **and making announcements**. Now runs entirely on Azure!

## 🎤 Announcement Features

### Voice-Triggered Announcements

- **"Alexa, tell Home Automation to announce dinner is ready"**
- **"Alexa, ask Home Automation to say the laundry is done"**
- **"Alexa, tell Home Automation to broadcast it's time for bed"**

### Automatic System Announcements

- **Door Alerts**: Automatically announces when doors are left unlocked
- **Water Leak Alerts**: Announces water leaks detected by Flume sensor
- **Comprehensive Solution**: All your existing automation flows now use Alexa

### 🏠 Virtual Announcement Devices

The skill creates virtual announcement zones that allow targeted announcements:

- **All Devices** - Announces to every Echo in your home
- **Bedroom** - Target bedroom Echo devices only  
- **Downstairs** - Announce to main floor (living room, kitchen, dining room)
- **Upstairs** - Target second floor devices (bedroom, office, hallway)

#### Targeted Voice Commands
- **"Alexa, tell Home Automation to tell the bedroom it's bedtime"**
- **"Alexa, ask Home Automation to announce to downstairs dinner is ready"** 
- **"Alexa, tell Home Automation to broadcast to upstairs the movie is starting"**

#### Smart Home Integration
Virtual devices appear in your Alexa app as "Announcement Zone" devices that can be controlled and configured like any other smart home device.

## 🚀 Quick Start

### ⚠️ Deployment Moved to `infra/` Folder

**All deployment scripts have been consolidated in the `../infra/` folder for better organization.**

# Deploy complete system (infrastructure + Alexa skill + function keys)
cd ../infra
.\deploy.ps1 -IncludeAlexaSkill -ConfigureFunctionKeys

# Or deploy Alexa skill only (assumes infrastructure exists)
cd ../infra
.\deploy-alexa-skill.ps1

The complete deployment automatically:

- ✅ Deploys all Azure infrastructure (Function Apps, Service Bus, Storage, etc.)
- ✅ Configures inter-service authentication keys
- ✅ Deploys Alexa Function App code to Azure
- ✅ Updates skill manifest with Azure Function endpoint
- ✅ Tests the deployed function
- ✅ Provides next steps for Alexa Developer Console configuration

**See `../infra/README.md` for detailed deployment documentation.**

- ✅ Creates virtual announcement devices (All, Bedroom, Downstairs, Upstairs)
- ✅ Enables Smart Home device discovery

### Configure Alexa Skill

1. Go to Alexa Developer Console
2. Set endpoint to: https://alexa-fn.azurewebsites.net/api/alexa_skill
3. Enable testing: "Alexa, ask Home Automation for help"

## 📱 Detailed Alexa Skill Setup

### Step 1: Create Alexa Developer Account
1. Go to [Alexa Developer Console](https://developer.amazon.com/alexa/console/ask)
2. Sign in with your Amazon account (same account as your Alexa devices)
3. Click "Create Skill"

### Step 2: Basic Skill Information
1. **Skill name**: `Home Automation`
2. **Primary locale**: `English (US)`
3. **Model**: Choose `Custom`
4. **Hosting method**: Choose `Provision your own` 
5. Click "Create skill"

### Step 3: Build Interaction Model
1. In the left sidebar, click **"JSON Editor"**
2. Delete all existing content
3. Copy and paste the content from `skill-package/interactionModels/custom/en-US.json`
4. Click **"Save Model"**
5. Click **"Build Model"** (wait for completion)

### Step 4: Configure Endpoint
1. In the left sidebar, click **"Endpoint"**
2. Select **"HTTPS"**
3. In **"Default Region"** field, enter:
   ```
   https://alexa-fn.azurewebsites.net/api/alexa_skill
   ```
4. In **"SSL certificate type"**, select:
   ```
   My development endpoint is a sub-domain of a domain that has a wildcard certificate from a certificate authority
   ```
5. Click **"Save Endpoints"**

### Step 5: Enable Testing
1. In the top navigation, click **"Test"**
2. In the dropdown, select **"Development"**
3. Test by typing or saying: `"ask home automation for help"`

### Step 6: Permissions (Optional)
1. In the left sidebar, click **"Permissions"**
2. Enable **"Send Alexa Events"** if you want proactive notifications
3. Click **"Save Permissions"**

### Step 7: Test Voice Commands
Try these commands in the test console:
- `"ask home automation for help"`
- `"tell home automation the front door is open"`
- `"ask home automation to cancel door alert"`
- `"tell home automation to announce dinner is ready"`

### Step 8: Enable on Your Devices
1. In the **Test** tab, if testing works, your skill is automatically available on your Alexa devices
2. Try saying to your physical Alexa device: `"Alexa, ask Home Automation for help"`
3. The skill will be available on all devices linked to your Amazon account

## 💰 Cost Savings

- **Before**: Third-party subscription services ~/month = /year
- **After**: Azure Functions free tier = /month
- **Total savings**: + per year

## 🎯 Voice Commands

### Door Management

- "Alexa, tell Home Automation the front door is open"
- "Alexa, ask Home Automation to cancel door alert"

### Custom Announcements

- "Alexa, tell Home Automation to announce dinner is ready"
- "Alexa, ask Home Automation to say the kids need to come inside"

### System Monitoring

- "Alexa, ask Home Automation for system status"
- "Alexa, ask Home Automation to check door status"

## ⚙️ Virtual Device Configuration

### Customizing Announcement Zones

Edit `alexa-fn/virtual-devices-config.json` to customize your announcement zones:

```json
{
  "virtualDevices": {
    "all": {
      "name": "All Devices",
      "description": "Announce to all Echo devices in the home",
      "deviceIds": ["*"],
      "friendlyNames": ["all", "everywhere", "all devices", "whole house"]
    },
    "bedroom": {
      "name": "Bedroom", 
      "deviceIds": ["bedroom-echo", "master-bedroom-echo"],
      "friendlyNames": ["bedroom", "master bedroom", "bed room"]
    },
    "kitchen": {
      "name": "Kitchen",
      "deviceIds": ["kitchen-echo"],
      "friendlyNames": ["kitchen", "cooking area"]
    }
  }
}
```

### Adding New Zones

1. Add new device to `virtual-devices-config.json`
2. Update interaction model with new device names
3. Redeploy the function

### Device Mapping

- **deviceIds**: Physical Echo device IDs (use "*" for all devices)
- **friendlyNames**: Voice recognition aliases for the zone  
- **name**: Display name in Alexa app

## 🔄 How It Works

Architecture Flow:
`Door/Leak Event → door-fn/flume-fn → Alexa Function → Your Alexa Devices`

Integration Points:

1. **door-fn SendRequest**: Calls Alexa announcement endpoint
2. **flume-fn leak detection**: Calls Alexa announcement endpoint
3. **Voice commands**: Direct Alexa skill interaction
4. **Reliability**: Built-in error handling and retry logic

## 🧪 Testing

### Test Announcement API

Target specific devices:
```powershell
$body = @{
    message = "Test announcement to bedroom"
    device = "bedroom"
} | ConvertTo-Json

Invoke-RestMethod -Uri "https://alexa-fn.azurewebsites.net/api/announce" -Method POST -Body $body -ContentType "application/json"
```

### Test Device Discovery

```powershell
Invoke-RestMethod -Uri "https://alexa-fn.azurewebsites.net/api/devices" -Method GET
```

### Run Full Test Suite

```powershell
cd ../infra && .\deploy-alexa-skill.ps1 -SkipCodeDeployment
```

Invoke-RestMethod -Uri "https://alexa-fn.azurewebsites.net/api/announce" -Method POST -Body  -ContentType "application/json"
`

## 🚨 Alexa Skill Troubleshooting

### Common Setup Issues

#### "There was a problem with the requested skill's response"
1. **Check Endpoint URL**: Ensure it's `https://alexa-fn.azurewebsites.net/api/alexa_skill`
2. **Verify Function is Running**: 
   ```powershell
   Invoke-RestMethod -Uri "https://alexa-fn.azurewebsites.net/api/alexa_skill" -Method POST -Body '{"version":"1.0","request":{"type":"LaunchRequest"}}' -ContentType "application/json"
   ```
3. **Check Azure Function Logs**: Go to Azure Portal → alexa-fn → Monitor → Logs

#### "Sorry, I don't know that"
1. **Verify Invocation Name**: Should be "home automation"
2. **Check Interaction Model**: Ensure it's built successfully
3. **Try Different Phrases**: 
   - `"ask home automation for help"` ✅
   - `"open home automation"` ✅
   - `"start home automation"` ✅

#### Skill Not Available on Physical Devices
1. **Check Account**: Ensure you're logged into Alexa Developer Console with the same Amazon account as your devices
2. **Enable Testing**: Must be set to "Development" in Test tab
3. **Wait**: Sometimes takes 5-10 minutes to propagate to devices

#### Authentication/Permission Errors
1. **Check Function Auth Level**: Should be set to "Function" in Azure
2. **Add Function Key**: If needed, get function key from Azure Portal and add `?code=YOUR_KEY` to endpoint URL
3. **SSL Certificate**: Ensure you selected the wildcard certificate option

#### Response Timeout Issues
1. **Function Timeout**: Check if Azure Function is taking too long to respond
2. **Increase Timeout**: In Azure Portal → alexa-fn → Configuration → General Settings → Platform Settings → Timeout
3. **Check Dependencies**: Ensure door-fn and flume-fn are responding quickly

### Debug Commands

#### Test Azure Function Directly
```powershell
# Test Launch Request
$launchPayload = @{
    version = "1.0"
    session = @{
        new = $true
        sessionId = "test-session"
        user = @{ userId = "test-user" }
    }
    request = @{
        type = "LaunchRequest"
        requestId = "test-request"
    }
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri "https://alexa-fn.azurewebsites.net/api/alexa_skill" -Method POST -Body $launchPayload -ContentType "application/json"
```

#### Test Intent Request
```powershell
# Test System Status Intent
$intentPayload = @{
    version = "1.0"
    session = @{
        new = $false
        sessionId = "test-session"
        user = @{ userId = "test-user" }
    }
    request = @{
        type = "IntentRequest"
        requestId = "test-request"
        intent = @{
            name = "SystemStatusIntent"
            slots = @{}
        }
    }
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri "https://alexa-fn.azurewebsites.net/api/alexa_skill" -Method POST -Body $intentPayload -ContentType "application/json"
```

### Performance Optimization

#### Reduce Response Time
1. **Enable Always On**: Azure Portal → alexa-fn → Configuration → General Settings → Always On = On
2. **Increase Plan**: Consider upgrading to Premium plan for faster cold starts
3. **Optimize Code**: Remove unnecessary logging in production

#### Monitor Usage
1. **Application Insights**: Check performance metrics in Azure Portal
2. **Usage Analytics**: Monitor skill usage in Alexa Developer Console
3. **Error Tracking**: Set up alerts for function failures

## 🎉 Ready to Deploy!

You now have a complete Alexa-powered home automation system that:

- ✅ Eliminates costly third-party subscription services
- ✅ Runs entirely on your Azure infrastructure
- ✅ Supports voice commands AND automatic announcements
- ✅ Has built-in fallback for reliability
- ✅ Saves you + per year

**Next step**: Deploy from `../infra/` folder - see `../infra/README.md` for instructions!

## 📦 Optional: Publishing Your Skill

### For Personal Use Only (Recommended)
- Keep your skill in **Development** mode
- Only available on devices linked to your Amazon account
- No certification required
- Perfect for home automation

### For Public Distribution (Advanced)
If you want to share your skill publicly:

#### Step 1: Complete Skill Information
1. **Distribution** tab → Fill out all required fields:
   - Public Name: "Home Automation"
   - One Sentence Description: "Control your smart home with voice commands"
   - Detailed Description: Add comprehensive description
   - Keywords: "smart home", "automation", "IoT"
   - Category: "Smart Home"

#### Step 2: Privacy & Compliance
1. **Privacy Policy**: Create and host a privacy policy
2. **Terms of Use**: Create and host terms of use
3. **Testing Instructions**: Provide detailed testing instructions
4. **Availability**: Select countries/regions

#### Step 3: Certification
1. **Validation** tab → Run all validation tests
2. **Submission** tab → Submit for review
3. **Wait**: Amazon review process takes 7-10 business days
4. **Address Feedback**: Fix any issues Amazon identifies

#### Important Considerations for Public Skills
- **Security**: Remove hardcoded URLs and credentials
- **Multi-tenant**: Support multiple users/homes
- **Error Handling**: Robust error messages for all scenarios
- **Privacy**: Don't store personal data
- **Scalability**: Handle increased traffic

### Recommended Approach
For personal home automation:
1. ✅ Keep in Development mode
2. ✅ Use on your devices only
3. ✅ Avoid certification complexity
4. ✅ Maintain full control and privacy

## 🔧 Advanced Configuration

### Custom Function Keys
If you need enhanced security:

1. **Generate Function Key**:
   ```bash
   az functionapp keys set --name alexa-fn --resource-group rg-door-fn --key-name alexa-skill --key-value YOUR_CUSTOM_KEY
   ```

2. **Update Endpoint URL**:
   ```
   https://alexa-fn.azurewebsites.net/api/alexa_skill?code=YOUR_CUSTOM_KEY
   ```

### Environment-Specific Deployments
For multiple environments (dev/staging/prod):

1. **Create Additional Function Apps**:
   ```bash
   # Staging
   az functionapp create --name alexa-fn-staging --resource-group rg-door-fn-staging
   
   # Production  
   az functionapp create --name alexa-fn-prod --resource-group rg-door-fn-prod
   ```

2. **Create Separate Skills**:
   - Development: `alexa-fn-dev.azurewebsites.net`
   - Staging: `alexa-fn-staging.azurewebsites.net`
   - Production: `alexa-fn-prod.azurewebsites.net`

### Backup and Recovery
1. **Export Skill**: Download skill package from Developer Console
2. **Backup Code**: Ensure all code is in source control
3. **Document Config**: Keep environment variables documented
4. **Test Restore**: Periodically test deployment from scratch
