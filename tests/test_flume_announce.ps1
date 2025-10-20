# Test Flume Function Announce API Call
# This script tests the announce API endpoint that the Flume function uses to send water leak alerts
#
# Usage:
#   .\test_flume_announce.ps1                    # Test with default message
#   .\test_flume_announce.ps1 -CustomMessage "Custom leak alert message"
#   .\test_flume_announce.ps1 -UseProduction     # Test against production endpoints

param(
    [string]$CustomMessage = "Water leak detected in your home! Please check your Flume sensor immediately.",
    [switch]$UseProduction,
    [switch]$Verbose
)

# Load test configuration
function Load-TestConfig {
    $configPath = Join-Path $PSScriptRoot "test_config.json"
    if (Test-Path $configPath) {
        try {
            return Get-Content $configPath | ConvertFrom-Json
        } catch {
            Write-Host "❌ Error loading test configuration: $($_.Exception.Message)" -ForegroundColor Red
            return $null
        }
    } else {
        Write-Host "❌ Test configuration file not found: $configPath" -ForegroundColor Red
        return $null
    }
}

# Get Flume function configuration
function Get-FlumeConfig {
    $flumeConfigPath = Join-Path $PSScriptRoot "..\flume-fn\local.settings.json"
    if (Test-Path $flumeConfigPath) {
        try {
            $config = Get-Content $flumeConfigPath | ConvertFrom-Json
            return $config.Values
        } catch {
            Write-Host "❌ Error loading Flume configuration: $($_.Exception.Message)" -ForegroundColor Red
            return $null
        }
    } else {
        Write-Host "❌ Flume configuration file not found: $flumeConfigPath" -ForegroundColor Red
        return $null
    }
}

Write-Host "🧪 Testing Flume Function Announce API Call" -ForegroundColor Green
Write-Host "===========================================" -ForegroundColor Green

# Load configurations
$testConfig = Load-TestConfig
$flumeConfig = Get-FlumeConfig

if (-not $testConfig -or -not $flumeConfig) {
    Write-Host "❌ Cannot proceed without valid configuration" -ForegroundColor Red
    exit 1
}

# Determine endpoint URLs
if ($UseProduction) {
    $announceUrl = $testConfig.announce.url
    Write-Host "🌐 Using PRODUCTION endpoint: $announceUrl" -ForegroundColor Yellow
} else {
    $announceUrl = $flumeConfig.ALEXA_FN_BASE_URL + "/api/announce"
    Write-Host "🔧 Using LOCAL endpoint: $announceUrl" -ForegroundColor Cyan
}

# Get API key
$apiKey = $flumeConfig.ALEXA_FN_API_KEY
if (-not $apiKey) {
    Write-Host "❌ No API key found in Flume configuration (ALEXA_FN_API_KEY)" -ForegroundColor Red
    exit 1
}

Write-Host "🔑 Using API Key: $($apiKey.Substring(0, 10))..." -ForegroundColor Gray

# Test 1: Simulate Flume Function Announce Call
Write-Host "`n📡 Test 1: Simulating Flume Function Announce Call" -ForegroundColor Yellow
Write-Host "Message: $CustomMessage" -ForegroundColor Gray
Write-Host "Device: all (hardcoded in Flume function)" -ForegroundColor Gray

# Prepare the payload exactly as Flume function sends it
$payload = @{
    message = $CustomMessage
    device = "all"
} | ConvertTo-Json

$headers = @{
    'Content-Type' = 'application/json'
    'x-functions-key' = $apiKey
}

if ($Verbose) {
    Write-Host "📤 Request Details:" -ForegroundColor Cyan
    Write-Host "   URL: $announceUrl" -ForegroundColor Gray
    Write-Host "   Headers: $($headers | ConvertTo-Json)" -ForegroundColor Gray
    Write-Host "   Payload: $payload" -ForegroundColor Gray
}

try {
    $response = Invoke-RestMethod -Uri $announceUrl -Method POST -Body $payload -Headers $headers -TimeoutSec 30
    
    Write-Host "✅ Announce API call successful!" -ForegroundColor Green
    Write-Host "📥 Response: $($response | ConvertTo-Json -Depth 3)" -ForegroundColor Gray
    
} catch {
    Write-Host "❌ Announce API call failed!" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    
    if ($_.Exception.Response) {
        $statusCode = $_.Exception.Response.StatusCode
        Write-Host "Status Code: $statusCode" -ForegroundColor Red
        
        try {
            $errorBody = $_.Exception.Response | ConvertFrom-Json
            Write-Host "Error Body: $($errorBody | ConvertTo-Json)" -ForegroundColor Red
        } catch {
            Write-Host "Raw Error: $($_.Exception.Response)" -ForegroundColor Red
        }
    }
    
    exit 1
}

# Test 2: Verify Message Queue (if using local endpoint)
if (-not $UseProduction) {
    Write-Host "`n📋 Test 2: Verifying Message was Queued" -ForegroundColor Yellow
    
    # Wait a moment for message to be processed
    Start-Sleep -Seconds 2
    
    # Try to retrieve the message using GetAnnouncementForDevice
    try {
        $retrieveUrl = $flumeConfig.ALEXA_FN_BASE_URL + "/api/alexa_skill"
        
        # Create Alexa request to get announcement
        $alexaRequest = @{
            version = "1.0"
            session = @{
                new = $true
                sessionId = "test-session-flume-announce"
                user = @{
                    userId = $testConfig.alexa.userId
                }
            }
            request = @{
                type = "IntentRequest"
                requestId = "test-request-flume-announce"
                intent = @{
                    name = "GetAnnouncementForDeviceIntent"
                    slots = @{
                        DeviceName = @{
                            name = "DeviceName"
                            value = "all"
                        }
                    }
                }
            }
        } | ConvertTo-Json -Depth 10
        
        $alexaHeaders = @{
            'Content-Type' = 'application/json'
            'x-functions-key' = $apiKey
        }
        
        $retrieveResponse = Invoke-RestMethod -Uri $retrieveUrl -Method POST -Body $alexaRequest -Headers $alexaHeaders -TimeoutSec 30
        
        if ($retrieveResponse.response.outputSpeech.text -and $retrieveResponse.response.outputSpeech.text.Contains("Water leak")) {
            Write-Host "✅ Message successfully queued and retrieved!" -ForegroundColor Green
            Write-Host "📝 Retrieved message: $($retrieveResponse.response.outputSpeech.text)" -ForegroundColor Gray
        } else {
            Write-Host "⚠️  Message may not have been queued properly" -ForegroundColor Yellow
            Write-Host "📝 Retrieved response: $($retrieveResponse.response.outputSpeech.text)" -ForegroundColor Gray
        }
        
    } catch {
        Write-Host "⚠️  Could not verify message queue: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "💡 This is not necessarily an error - the message may have been processed correctly" -ForegroundColor Gray
    }
}

# Test 3: Test Different Device Targets (to show what Flume function could do)
Write-Host "`n🎯 Test 3: Testing Alternative Device Targets (for comparison)" -ForegroundColor Yellow

$deviceTargets = @("bedroom", "downstairs", "upstairs")

foreach ($device in $deviceTargets) {
    Write-Host "   Testing device: $device" -ForegroundColor Gray
    
    $altPayload = @{
        message = "Test water leak alert for $device area"
        device = $device
    } | ConvertTo-Json
    
    try {
        $altResponse = Invoke-RestMethod -Uri $announceUrl -Method POST -Body $altPayload -Headers $headers -TimeoutSec 10
        Write-Host "   ✅ ${device}: Success" -ForegroundColor Green
    } catch {
        Write-Host "   ❌ ${device}: Failed - $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n✅ Flume Function Announce API Test Completed!" -ForegroundColor Green
Write-Host "📋 Summary:" -ForegroundColor Cyan
Write-Host "   • Flume function uses 'all' device for water leak alerts" -ForegroundColor Gray
Write-Host "   • API endpoint: $announceUrl" -ForegroundColor Gray
Write-Host "   • Message format matches Flume function implementation" -ForegroundColor Gray
Write-Host "   • Alternative device targets are available but not used by Flume" -ForegroundColor Gray

if (-not $UseProduction) {
    Write-Host "`n💡 Next Steps:" -ForegroundColor Yellow
    Write-Host "   • Run Flume function locally: func start (in flume-fn directory)" -ForegroundColor Gray
    Write-Host "   • Test production: .\test_flume_announce.ps1 -UseProduction" -ForegroundColor Gray
    Write-Host "   • Monitor actual water leak detection in Flume dashboard" -ForegroundColor Gray
}