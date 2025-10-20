#!/usr/bin/env powershell
# Comprehensive AWS Lambda Test Suite
# Tests all 4 scenarios: LaunchRequest, DoorEventIntent (opened/closed), Smart Home Discovery

param(
    [switch]$ForceNewToken,
    [switch]$Verbose,
    [string]$ConfigFile = "test_lambda_config.json"
)

Write-Host "🚀 AWS Lambda Function - Comprehensive Test Suite" -ForegroundColor Green
Write-Host "=" * 60

# Function to load configuration
function Get-TestConfiguration {
    param([string]$ConfigPath)
    
    if (-not (Test-Path $ConfigPath)) {
        Write-Host "❌ Configuration file not found: $ConfigPath" -ForegroundColor Red
        Write-Host "💡 Please ensure test_lambda_config.json exists in the tests directory" -ForegroundColor Yellow
        exit 1
    }
    
    try {
        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        return $config
    } catch {
        Write-Host "❌ Error reading configuration: $_" -ForegroundColor Red
        exit 1
    }
}

Write-Host "📋 Loading Configuration..." -ForegroundColor Yellow
$Config = Get-TestConfiguration -ConfigPath $ConfigFile
Write-Host "✅ Configuration loaded from: $ConfigFile" -ForegroundColor Green

Write-Host ""
Write-Host "📋 Test Configuration:" -ForegroundColor Cyan
Write-Host "   Function Name: $($Config.lambda.functionName)" -ForegroundColor White
Write-Host "   Region: $($Config.lambda.region)" -ForegroundColor White
Write-Host "   LWA Token File: $($Config.testing.tokenFile)" -ForegroundColor White
Write-Host "   Auto Run Test: $($Config.testing.autoRunTest)" -ForegroundColor White

# Check AWS CLI
Write-Host ""
Write-Host "🔧 Checking AWS CLI..." -ForegroundColor Yellow
try {
    $awsVersion = aws --version 2>&1
    Write-Host "✅ AWS CLI found: $awsVersion" -ForegroundColor Green
} catch {
    Write-Host "❌ AWS CLI not found. Please install AWS CLI first." -ForegroundColor Red
    exit 1
}

# Verify AWS credentials
try {
    $identity = aws sts get-caller-identity --output json | ConvertFrom-Json
    Write-Host "✅ AWS credentials verified" -ForegroundColor Green
    Write-Host "   Account: $($identity.Account)" -ForegroundColor Gray
    Write-Host "   User: $($identity.Arn)" -ForegroundColor Gray
} catch {
    Write-Host "❌ AWS credentials not configured or invalid" -ForegroundColor Red
    Write-Host "   Run 'aws configure' to set up credentials" -ForegroundColor Yellow
    exit 1
}

# Get the LWA token
$tokenFile = $Config.testing.tokenFile
if (-not (Test-Path $tokenFile)) {
    Write-Host "❌ LWA token file not found: $tokenFile" -ForegroundColor Red
    Write-Host "💡 Run .\generate_lwa_token.ps1 first" -ForegroundColor Yellow
    exit 1
}

if ($ForceNewToken) {
    Write-Host "🔄 Force generating new token..." -ForegroundColor Yellow
    & ".\generate_lwa_token.ps1"
}

$tokenData = Get-Content $tokenFile | ConvertFrom-Json
$token = $tokenData.access_token

Write-Host ""
Write-Host "✅ LWA Token loaded" -ForegroundColor Green
Write-Host "   Token: $($token.Substring(0, 30))..." -ForegroundColor Gray

# Function to test Lambda with payload
function Test-LambdaWithPayload {
    param([string]$TestName, [object]$Payload, [object]$Config, [bool]$VerboseOutput = $false)
    
    Write-Host ""
    Write-Host "📋 Test: $TestName" -ForegroundColor Cyan
    
    if ($VerboseOutput) {
        Write-Host "Lambda Function: $($Config.lambda.functionName)" -ForegroundColor Gray
        Write-Host "Region: $($Config.lambda.region)" -ForegroundColor Gray
    }
    
    $payloadJson = $Payload | ConvertTo-Json -Depth 10
    $tempFile = "temp-test-payload.json"
    $payloadJson | Set-Content -Path $tempFile -Encoding UTF8
    
    try {
        $result = aws lambda invoke --function-name $Config.lambda.functionName --region $Config.lambda.region --payload file://$tempFile --cli-binary-format raw-in-base64-out response-test.json 2>&1
        
        if ($LASTEXITCODE -eq 0 -and (Test-Path "response-test.json")) {
            $response = Get-Content "response-test.json" -Raw | ConvertFrom-Json
            Write-Host "✅ Test successful!" -ForegroundColor Green
            Write-Host "Response:" -ForegroundColor Gray
            Write-Host ($response | ConvertTo-Json -Depth 10) -ForegroundColor White
            return $true
        } else {
            Write-Host "❌ Test failed: $result" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "❌ Test failed: $_" -ForegroundColor Red
        return $false
    } finally {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        Remove-Item "response-test.json" -Force -ErrorAction SilentlyContinue
    }
}

# Test 1: LaunchRequest
$launchPayload = @{
    version = "1.0"
    session = @{
        new = $true
        sessionId = $Config.alexa.sessionId
        application = @{ applicationId = $Config.alexa.applicationId }
        user = @{ 
            userId = $Config.alexa.userId
            accessToken = $token
        }
        attributes = @{}
    }
    context = @{
        System = @{
            application = @{ applicationId = $Config.alexa.applicationId }
            user = @{ 
                userId = $Config.alexa.userId
                accessToken = $token
            }
            device = @{ 
                deviceId = $Config.alexa.deviceId
                supportedInterfaces = @{}
            }
            apiEndpoint = $Config.alexa.apiEndpoint
            apiAccessToken = $Config.alexa.apiAccessToken
        }
    }
    request = @{
        type = "LaunchRequest"
        requestId = $Config.alexa.requestId
        timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        locale = $Config.alexa.locale
        shouldLinkResultBeReturned = $false
    }
}

$test1Result = Test-LambdaWithPayload -TestName "LaunchRequest (Alexa, open Home Automation)" -Payload $launchPayload -Config $Config -VerboseOutput:($Config.testing.verbose -or $Verbose)

# Test 2: DoorEventIntent - Opened
$doorOpenedPayload = @{
    version = "1.0"
    session = @{
        new = $false
        sessionId = $Config.alexa.sessionId
        application = @{ applicationId = $Config.alexa.applicationId }
        user = @{ 
            userId = $Config.alexa.userId
            accessToken = $token
        }
        attributes = @{}
    }
    context = @{
        System = @{
            application = @{ applicationId = $Config.alexa.applicationId }
            user = @{ 
                userId = $Config.alexa.userId
                accessToken = $token
            }
            device = @{ 
                deviceId = $Config.alexa.deviceId
                supportedInterfaces = @{}
            }
            apiEndpoint = $Config.alexa.apiEndpoint
            apiAccessToken = $Config.alexa.apiAccessToken
        }
    }
    request = @{
        type = "IntentRequest"
        requestId = $Config.alexa.requestId
        timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        locale = $Config.alexa.locale
        intent = @{
            name = $Config.doorEvent.intentName
            slots = @{
                DoorName = @{
                    name = "DoorName"
                    value = $Config.doorEvent.doorName
                }
                DoorAction = @{
                    name = "DoorAction"
                    value = "opened"
                }
            }
        }
    }
}

$test2Result = Test-LambdaWithPayload -TestName "DoorEventIntent - Door Opened" -Payload $doorOpenedPayload -Config $Config -VerboseOutput:($Config.testing.verbose -or $Verbose)

# Test 3: DoorEventIntent - Closed
$doorClosedPayload = @{
    version = "1.0"
    session = @{
        new = $false
        sessionId = $Config.alexa.sessionId
        application = @{ applicationId = $Config.alexa.applicationId }
        user = @{ 
            userId = $Config.alexa.userId
            accessToken = $token
        }
        attributes = @{}
    }
    context = @{
        System = @{
            application = @{ applicationId = $Config.alexa.applicationId }
            user = @{ 
                userId = $Config.alexa.userId
                accessToken = $token
            }
            device = @{ 
                deviceId = $Config.alexa.deviceId
                supportedInterfaces = @{}
            }
            apiEndpoint = $Config.alexa.apiEndpoint
            apiAccessToken = $Config.alexa.apiAccessToken
        }
    }
    request = @{
        type = "IntentRequest"
        requestId = $Config.alexa.requestId
        timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        locale = $Config.alexa.locale
        intent = @{
            name = $Config.doorEvent.intentName
            slots = @{
                DoorName = @{
                    name = "DoorName"
                    value = $Config.doorEvent.doorName
                }
                DoorAction = @{
                    name = "DoorAction"
                    value = "closed"
                }
            }
        }
    }
}

$test3Result = Test-LambdaWithPayload -TestName "DoorEventIntent - Door Closed" -Payload $doorClosedPayload -Config $Config -VerboseOutput:($Config.testing.verbose -or $Verbose)

# Test 4: Smart Home Discovery
$discoveryPayload = @{
    directive = @{
        header = @{
            namespace = "Alexa.Discovery"
            name = "Discover"
            messageId = $Config.smartHome.messageId
            payloadVersion = $Config.smartHome.payloadVersion
        }
        payload = @{
            scope = @{
                type = "BearerToken"
                token = $token
            }
        }
    }
}

$test4Result = Test-LambdaWithPayload -TestName "Smart Home Discovery (Device Discovery)" -Payload $discoveryPayload -Config $Config -VerboseOutput:($Config.testing.verbose -or $Verbose)

# Summary
Write-Host ""
Write-Host "📊 Test Results Summary:" -ForegroundColor Cyan
Write-Host "   LaunchRequest: $(if($test1Result) {'✅ PASSED'} else {'❌ FAILED'})" -ForegroundColor $(if($test1Result) {'Green'} else {'Red'})
Write-Host "   DoorEventIntent (opened): $(if($test2Result) {'✅ PASSED'} else {'❌ FAILED'})" -ForegroundColor $(if($test2Result) {'Green'} else {'Red'})
Write-Host "   DoorEventIntent (closed): $(if($test3Result) {'✅ PASSED'} else {'❌ FAILED'})" -ForegroundColor $(if($test3Result) {'Green'} else {'Red'})
Write-Host "   Smart Home Discovery: $(if($test4Result) {'✅ PASSED'} else {'❌ FAILED'})" -ForegroundColor $(if($test4Result) {'Green'} else {'Red'})

if ($test1Result -and $test2Result -and $test3Result -and $test4Result) {
    Write-Host ""
    Write-Host "🎉 All tests completed successfully!" -ForegroundColor Green
    Write-Host "✅ Your AWS Lambda function is ready for full Alexa integration (Custom + Smart Home)" -ForegroundColor Green
    Write-Host ""
    Write-Host "🔗 Lambda Function ARN:" -ForegroundColor Yellow
    Write-Host "   arn:aws:lambda:$($Config.lambda.region):$($identity.Account):function:$($Config.lambda.functionName)" -ForegroundColor White
    Write-Host ""
    Write-Host "📝 Next Steps:" -ForegroundColor Cyan
    Write-Host "   1. Configure your Alexa skill endpoint to use this Lambda ARN" -ForegroundColor White
    Write-Host "   2. Enable Account Linking in Alexa Developer Console" -ForegroundColor White
    Write-Host "   3. Test with real Alexa devices" -ForegroundColor White
    Write-Host ""
    Write-Host "📝 Configuration Management:" -ForegroundColor Cyan
    Write-Host "   Config File: $ConfigFile" -ForegroundColor Gray
    Write-Host "   Edit config: code $ConfigFile" -ForegroundColor Gray
    Write-Host "   Force new token: .\test_lambda_comprehensive.ps1 -ForceNewToken" -ForegroundColor Gray
    Write-Host "   Verbose output: .\test_lambda_comprehensive.ps1 -Verbose" -ForegroundColor Gray
} else {
    Write-Host ""
    Write-Host "⚠️  Some tests failed - check the errors above" -ForegroundColor Yellow
    exit 1
}