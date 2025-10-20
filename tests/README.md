# Comprehensive Testing Suite

This directory contains comprehensive testing scripts for the home automation system's Azure Function implementation, including Custom Skill, Smart Home, OAuth authorization, and announce API testing.

## Test Files Overview

| File | Purpose | Description |
|------|---------|-------------|
| `test_azure_function.ps1` | **Main Test Suite** | Comprehensive testing: Custom Skill, Smart Home Discovery, OAuth Authorization, Key Vault Integration |
| `test_flume_announce.ps1` | **Flume Announce API** | Tests the announce API endpoint used by Flume function for water leak alerts |
| `test_flume_announce.py` | **Flume Announce API (Python)** | Python version of Flume announce API test with detailed options |
| `generate_lwa_token.ps1` | Token Generation | Generate Login with Amazon (LWA) tokens for Alexa API authentication |
| `generate_lwa_token.py` | Token Generation (Python) | Python version of LWA token generator |
| `test_config.json` | Test Configuration | All test parameters, endpoints, and Alexa skill information |
| `lwa_token.json` | Generated Tokens | Auto-generated LWA tokens (gitignored) |
| `requirements.txt` | Python Dependencies | Required packages for Python test scripts |

## Test Scenarios

### Main Test Suite (test_azure_function.ps1)

The main test suite validates 8 comprehensive scenarios:

#### 1. 🚀 LaunchRequest
- **Trigger**: "Alexa, open Home Automation"
- **Tests**: Basic skill launch and welcome message
- **Expected**: Welcome response with session continuation

#### 2. 🚪 DoorEventIntent - Door Opened
- **Trigger**: "Alexa, tell Home Automation the front door opened"
- **Tests**: Door opened event processing
- **Expected**: Confirmation with monitoring promise

#### 3. 🚪 DoorEventIntent - Door Closed
- **Trigger**: "Alexa, tell Home Automation the front door closed"
- **Tests**: Door closed event processing
- **Expected**: Confirmation acknowledgment

#### 4. 📢 AnnounceIntent
- **Trigger**: "Alexa, tell Home Automation announce testing message"
- **Tests**: Message queuing to Service Bus
- **Expected**: Confirmation of message broadcast

#### 5. �� GetAnnouncementForDeviceIntent
- **Trigger**: "Alexa, ask Home Automation for announcements for all"
- **Tests**: Message retrieval from queue
- **Expected**: Playback of queued announcements

#### 6. 🏠 Smart Home Discovery
- **Tests**: Alexa Smart Home device discovery
- **Expected**: Virtual device list with proper capabilities

#### 7. 🔐 OAuth Authorization Request
- **Tests**: Account linking authorization flow
- **Expected**: Authorization URL with proper parameters

#### 8. ✅ OAuth AcceptGrant
- **Tests**: OAuth token exchange and Key Vault storage
- **Expected**: Successful token storage confirmation

### Flume Announce API Tests

#### test_flume_announce.ps1 (PowerShell)
`powershell
# Test with default water leak message
.\test_flume_announce.ps1

# Test with custom message
.\test_flume_announce.ps1 -CustomMessage "Custom water alert message"

# Test against production endpoints
.\test_flume_announce.ps1 -Production

# Show detailed request/response info
.\test_flume_announce.ps1 -Verbose
`

**Test Coverage:**
- **Test 1**: Simulates exact Flume function announce call with "all" device
- **Test 2**: Verifies message was queued by retrieving through GetAnnouncementForDevice
- **Test 3**: Tests alternative device targets (bedroom, downstairs, upstairs) for comparison

#### test_flume_announce.py (Python)
`ash
# Install dependencies
pip install -r requirements.txt

# Test with default message
python test_flume_announce.py

# Test with custom message
python test_flume_announce.py --custom-message "Custom alert"

# Test against production
python test_flume_announce.py --production

# Show detailed output
python test_flume_announce.py --verbose
`

**Key Features:**
- Simulates exact Flume function API call pattern
- Tests message queuing and retrieval workflow
- Validates "all" device targeting used by Flume
- Supports both local and production endpoint testing

## Configuration

### test_config.json Structure
`json
{
  "alexa": {
    "skill_id": "amzn1.ask.skill.YOUR_SKILL_ID",
    "userId": "amzn1.ask.account.YOUR_USER_ID"
  },
  "azure_function": {
    "url": "https://your-function-app.azurewebsites.net",
    "key": "your-function-key"
  },
  "announce": {
    "url": "https://your-function-app.azurewebsites.net/api/announce",
    "key": "your-announce-api-key"
  },
  "oauth": {
    "client_id": "amzn1.application-oa2-client.YOUR_CLIENT_ID",
    "client_secret": "your-client-secret",
    "redirect_uri": "https://your-function-app.azurewebsites.net/api/auth_callback"
  }
}
`

### Local Settings Configuration

The Flume tests automatically load configuration from:
- `test_config.json` - Main test configuration
- `../flume-fn/local.settings.json` - Flume function settings

Required Flume settings:
`json
{
  "Values": {
    "ALEXA_FN_BASE_URL": "http://localhost:7071",
    "ALEXA_FN_API_KEY": "your-api-key"
  }
}
`

## Usage Instructions

### 1. Setup Test Environment
`powershell
# Navigate to tests directory
cd c:\Users\srpadala\workspace\Home\home-automation\tests

# Install Python dependencies (if using Python tests)
pip install -r requirements.txt

# Configure test_config.json with your settings
# Configure local.settings.json files for each function
`

### 2. Generate OAuth Tokens (if needed)
`powershell
# PowerShell version
.\generate_lwa_token.ps1

# Python version
python generate_lwa_token.py
`

### 3. Run Comprehensive Tests
`powershell
# Run all Azure Function tests
.\test_azure_function.ps1

# Run with verbose output
.\test_azure_function.ps1 -Verbose

# Test specific scenario
.\test_azure_function.ps1 -TestScenario "LaunchRequest"
`

### 4. Test Flume Announce API
`powershell
# PowerShell test
.\test_flume_announce.ps1

# Python test with options
python test_flume_announce.py --verbose --custom-message "Test water leak"
`

## Expected Outcomes

### ✅ Success Indicators
- All HTTP requests return 200 OK
- Alexa responses contain expected text and structure
- OAuth tokens are properly generated and stored
- Smart Home devices are discovered correctly
- Announce messages are queued and retrievable
- Flume announce API accepts water leak alerts

### ❌ Potential Issues
- **401 Unauthorized**: Check API keys and OAuth tokens
- **404 Not Found**: Verify endpoint URLs and function deployment
- **500 Internal Server Error**: Check function logs and configuration
- **Connection Refused**: Ensure Azure Functions are running locally
- **Queue Not Found**: Verify Service Bus configuration and connection strings

## Troubleshooting

### Common Issues

1. **LWA Token Generation Fails**
   - Verify OAuth client credentials in test_config.json
   - Check internet connectivity for Amazon API calls
   - Ensure redirect_uri matches Alexa skill configuration

2. **Azure Function Tests Fail**
   - Confirm function app is running (local: func start)
   - Verify API keys are correct
   - Check local.settings.json configuration

3. **Smart Home Discovery Empty**
   - Ensure virtual-devices-config.json is properly formatted
   - Verify function app can read configuration file
   - Check Application Insights logs for errors

4. **Announce API Tests Fail**
   - Verify Service Bus connection strings
   - Check queue names match function configuration
   - Ensure proper authentication headers

### Debug Steps

1. **Enable Verbose Logging**
   `powershell
   # PowerShell tests
   .\test_azure_function.ps1 -Verbose
   .\test_flume_announce.ps1 -Verbose
   
   # Python tests
   python test_flume_announce.py --verbose
   `

2. **Check Function Logs**
   `powershell
   # Local development
   func start --verbose
   
   # Azure portal
   # Navigate to Function App > Functions > Monitor
   `

3. **Validate Configuration**
   - Ensure all required settings are present
   - Verify connection strings and API keys
   - Check file paths and permissions

## Integration with CI/CD

These tests can be integrated into automated deployment pipelines:

`powershell
# Example deployment script integration
# 1. Deploy infrastructure
azd provision

# 2. Deploy function code
azd deploy

# 3. Run validation tests
.\test_azure_function.ps1 -Production
.\test_flume_announce.ps1 -Production

# 4. Verify OAuth integration
.\generate_lwa_token.ps1 -Validate
`

## Test Data and Privacy

- All test data uses synthetic values
- No real personal information is transmitted
- OAuth tokens are generated for testing only
- Service Bus messages use test payloads
- Flume tests simulate water leak scenarios without real alerts

## Contributing

When adding new tests:

1. Follow existing naming conventions
2. Include comprehensive error handling
3. Add verbose logging options
4. Update this README with new test documentation
5. Ensure tests work with both local and production environments
6. Include validation steps and expected outcomes
