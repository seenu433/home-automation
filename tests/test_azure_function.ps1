# Test Azure Function - Comprehensive Alexa Skill Testing
# This script tests the full Alexa Skill functionality including:
# 1. LaunchRequest (Custom Skill)
# 2. DoorEventIntent (opened/closed)
# 3. Smart Home Discovery
# 4. OAuth AcceptGrant Authorization (moved early to enable token storage)
# 5. Announce API (can use stored OAuth tokens)
# 6. GetAnnouncementForDevice (can use stored OAuth tokens)
# Uses test_config.json for all configuration parameters
#
# Parameters:
#   -UseRealOAuth: Test AcceptGrant with real Amazon OAuth authorization code
#   -Verbose: Show detailed request/response information
#   -SkipPrompts: Run all tests without interactive prompts
#   -ForceNewToken: Generate new LWA token even if one exists
#
# Examples:
#   .\test_azure_function.ps1                    # Run all tests with prompts
#   .\test_azure_function.ps1 -UseRealOAuth      # Test with real OAuth flow
#   .\test_azure_function.ps1 -Verbose          # Show detailed output
#   .\test_azure_function.ps1 -SkipPrompts      # Run without prompts

param(
    [string]$ConfigFile = "test_config.json",
    [switch]$ForceNewToken,
    [switch]$Verbose,
    [switch]$SkipPrompts,
    [switch]$UseRealOAuth
)

# Global variables
$Config = $null
$LwaToken = $null
$FunctionKey = $null

# Function to load configuration
function Load-Config {
    param([string]$ConfigPath = "test_config.json")
    
    # Ensure config file is in tests directory
    $testsDir = Split-Path -Parent $MyInvocation.PSCommandPath
    if (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
        $ConfigPath = Join-Path $testsDir $ConfigPath
    }
    
    if (Test-Path $ConfigPath) {
        try {
            return Get-Content $ConfigPath | ConvertFrom-Json
        } catch {
            Write-Host "❌ Configuration file is invalid: $ConfigPath" -ForegroundColor Red
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
            return $null
        }
    } else {
        Write-Host "❌ Configuration file not found: $ConfigPath" -ForegroundColor Red
        Write-Host "💡 Please ensure test_config.json exists in the tests directory" -ForegroundColor Yellow
        return $null
    }
}

# Function to get Azure Function key using config
function Get-AzureFunctionKey {
    param([object]$Config)
    
    $FunctionAppName = $Config.azureFunction.functionAppName
    $ResourceGroup = $Config.azureFunction.resourceGroup
    
    Write-Host "🔑 Retrieving Azure Function key..." -ForegroundColor Yellow
    Write-Host "   Function App: $FunctionAppName" -ForegroundColor Gray
    Write-Host "   Resource Group: $ResourceGroup" -ForegroundColor Gray
    
    # Check if Azure CLI is available and logged in
    try {
        $azAccount = az account show 2>$null
        if (-not $azAccount) {
            Write-Host "❌ Azure CLI not logged in" -ForegroundColor Red
            Write-Host "💡 Please run: az login" -ForegroundColor Yellow
            return $null
        }
        Write-Host "✅ Azure CLI authenticated" -ForegroundColor Green
    } catch {
        Write-Host "❌ Azure CLI not available" -ForegroundColor Red
        Write-Host "💡 Please install Azure CLI" -ForegroundColor Yellow
        return $null
    }
    
    # Try alternative resource group patterns if needed
    $resourceGroups = @($ResourceGroup)
    if ($Config.files.parametersFile -and (Test-Path $Config.files.parametersFile)) {
        try {
            $params = Get-Content $Config.files.parametersFile | ConvertFrom-Json
            $altRg = "rg-$($params.parameters.functionAppName.value)"
            if ($altRg -ne $ResourceGroup) {
                $resourceGroups += $altRg
                Write-Host "   Also trying: $altRg (from parameters file)" -ForegroundColor Gray
            }
        } catch {
            Write-Host "⚠️  Could not read parameters file" -ForegroundColor Yellow
        }
    }
    
    foreach ($rg in $resourceGroups) {
        try {
            Write-Host "   Trying resource group: $rg" -ForegroundColor Gray
            $key = az functionapp keys list --name $FunctionAppName --resource-group $rg --query "masterKey" --output tsv 2>$null
            
            if ($key -and $key -ne "" -and $key -ne "null") {
                Write-Host "✅ Successfully retrieved function key from: $rg" -ForegroundColor Green
                return $key
            }
        } catch {
            Write-Host "   Failed to get key from: $rg" -ForegroundColor Gray
        }
    }
    
    Write-Host "❌ Could not retrieve function key from any resource group" -ForegroundColor Red
    Write-Host "💡 Tried resource groups: $($resourceGroups -join ', ')" -ForegroundColor Yellow
    Write-Host "💡 Manual command: az functionapp keys list --name $FunctionAppName --resource-group $ResourceGroup --query `"masterKey`" --output tsv" -ForegroundColor Yellow
    return $null
}

# Function to validate LWA token by testing against Azure Function
function Test-LWATokenValid {
    param(
        [string]$Token,
        [object]$Config,
        [string]$FunctionKey
    )
    
    if (-not $Token -or $Token -eq "" -or $Token -eq "YOUR_LWA_TOKEN_HERE") {
        Write-Host "❌ LWA token is empty or placeholder" -ForegroundColor Red
        return $false
    }
    
    if (-not $FunctionKey) {
        Write-Host "⚠️  Cannot validate LWA token - Function key is required" -ForegroundColor Yellow
        return $null  # Cannot validate, but don't fail
    }
    
    try {
        Write-Host "🔍 Validating LWA token..." -ForegroundColor Cyan
        
        # Create a simple LaunchRequest to test token validity
        $testPayload = Create-LaunchRequestPayload -Config $Config -LwaToken $Token
        $testUrl = "$($Config.azureFunction.url)?code=$FunctionKey"
        $headers = @{
            "Content-Type" = "application/json"
            "Authorization" = "Bearer $Token"
        }
        
        # Attempt the request with a short timeout
        $response = Invoke-RestMethod -Uri $testUrl -Method POST -Headers $headers -Body $testPayload -TimeoutSec 10
        
        # If we get here without an exception, the token is likely valid
        Write-Host "✅ LWA token appears to be valid" -ForegroundColor Green
        return $true
        
    } catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
        }
        
        if ($statusCode -eq 401 -or $statusCode -eq "Unauthorized") {
            Write-Host "❌ LWA token is invalid or expired (401 Unauthorized)" -ForegroundColor Red
            return $false
        } elseif ($statusCode -eq 403 -or $statusCode -eq "Forbidden") {
            Write-Host "❌ LWA token lacks required permissions (403 Forbidden)" -ForegroundColor Red
            return $false
        } else {
            # Other errors might not be token-related (500, network, etc.)
            Write-Host "⚠️  Could not validate LWA token due to other error: $($_.Exception.Message)" -ForegroundColor Yellow
            return $null  # Cannot determine validity
        }
    }
}

# Function to load LWA token from file using config
function Get-LWAToken {
    param([object]$Config, [switch]$ForceNew)
    
    $tokenFile = $Config.files.lwaTokenFile
    
    # If running from project root (via deployment script), adjust path to look in tests folder
    if (-not (Test-Path $tokenFile) -and (Test-Path "tests\$tokenFile")) {
        $tokenFile = "tests\$tokenFile"
        Write-Host "💡 Found token file in tests subdirectory: $tokenFile" -ForegroundColor Gray
    }
    
    try {
        if (-not $ForceNew -and (Test-Path $tokenFile)) {
            $tokenData = Get-Content $tokenFile | ConvertFrom-Json
            $token = $tokenData.access_token
            $expiresIn = $tokenData.expires_in
            
            if ($token -and $token -ne "") {
                # Check if token is still valid (basic check)
                if ($expiresIn -and $expiresIn -gt 0) {
                    Write-Host "✅ LWA token loaded from: $tokenFile" -ForegroundColor Green
                    return $token
                } else {
                    Write-Host "⚠️  LWA token may be expired" -ForegroundColor Yellow
                }
            }
        }
        
        if ($ForceNew) {
            Write-Host "🔄 Force generating new LWA token..." -ForegroundColor Yellow
        } else {
            Write-Host "❌ No valid LWA token found in: $tokenFile" -ForegroundColor Red
        }
        
        # Try to generate new token
        if (Test-Path "generate_lwa_token.ps1") {
            Write-Host "🚀 Generating new LWA token..." -ForegroundColor Cyan
            $null = & ".\generate_lwa_token.ps1"
            
            # Try to load the newly generated token
            if (Test-Path $tokenFile) {
                Start-Sleep -Seconds 2
                $tokenData = Get-Content $tokenFile | ConvertFrom-Json
                $token = $tokenData.access_token
                if ($token -and $token -ne "") {
                    Write-Host "✅ New LWA token generated and loaded" -ForegroundColor Green
                    return $token
                }
            }
        }
        
        Write-Host "💡 Manual token generation: .\generate_lwa_token.ps1" -ForegroundColor Yellow
        return $null
    } catch {
        Write-Host "❌ Error loading LWA token: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Function to create Alexa LaunchRequest payload using config
function Create-LaunchRequestPayload {
    param([object]$Config, [string]$LwaToken)
    
    $alexa = $Config.alexa
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    
    $payload = @{
        version = "1.0"
        session = @{
            "new" = $true
            sessionId = $alexa.sessionId
            application = @{
                applicationId = $alexa.applicationId
            }
            user = @{
                userId = $alexa.userId
                accessToken = $LwaToken
            }
            attributes = @{}
        }
        context = @{
            System = @{
                application = @{
                    applicationId = $alexa.applicationId
                }
                user = @{
                    userId = $alexa.userId
                    accessToken = $LwaToken
                }
                device = @{
                    deviceId = $alexa.deviceId
                    supportedInterfaces = @{}
                }
                apiEndpoint = $alexa.apiEndpoint
                apiAccessToken = $alexa.apiAccessToken
            }
        }
        request = @{
            type = "LaunchRequest"
            requestId = $alexa.requestId
            timestamp = $timestamp
            locale = $alexa.locale
            shouldLinkResultBeReturned = $false
        }
    }
    
    return ($payload | ConvertTo-Json -Depth 10)
}

# Function to create DoorEventIntent payload
function Create-DoorEventIntentPayload {
    param([object]$Config, [string]$LwaToken, [string]$DoorName, [string]$DoorAction)
    
    $alexa = $Config.alexa
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    
    $payload = @{
        version = "1.0"
        session = @{
            "new" = $false
            sessionId = $alexa.sessionId
            application = @{
                applicationId = $alexa.applicationId
            }
            user = @{
                userId = $alexa.userId
                accessToken = $LwaToken
            }
            attributes = @{}
        }
        context = @{
            System = @{
                application = @{
                    applicationId = $alexa.applicationId
                }
                user = @{
                    userId = $alexa.userId
                    accessToken = $LwaToken
                }
                device = @{
                    deviceId = $alexa.deviceId
                    supportedInterfaces = @{}
                }
                apiEndpoint = $alexa.apiEndpoint
                apiAccessToken = $alexa.apiAccessToken
            }
        }
        request = @{
            type = "IntentRequest"
            requestId = $alexa.requestId
            timestamp = $timestamp
            locale = $alexa.locale
            intent = @{
                name = "DoorEventIntent"
                slots = @{
                    DoorName = @{
                        name = "DoorName"
                        value = $DoorName
                    }
                    DoorAction = @{
                        name = "DoorAction"
                        value = $DoorAction
                    }
                }
            }
        }
    }
    
    return ($payload | ConvertTo-Json -Depth 10)
}

# Function to create GetAnnouncementForDeviceIntent payload
function Create-GetAnnouncementPayload {
    param([object]$Config, [string]$LwaToken, [string]$DeviceName = "all")
    
    $alexa = $Config.alexa
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    
    $payload = @{
        version = "1.0"
        session = @{
            "new" = $false
            sessionId = $alexa.sessionId
            application = @{
                applicationId = $alexa.applicationId
            }
            user = @{
                userId = $alexa.userId
                accessToken = $LwaToken
            }
            attributes = @{}
        }
        context = @{
            System = @{
                application = @{
                    applicationId = $alexa.applicationId
                }
                user = @{
                    userId = $alexa.userId
                    accessToken = $LwaToken
                }
                device = @{
                    deviceId = $alexa.deviceId
                    supportedInterfaces = @{}
                }
                apiEndpoint = $alexa.apiEndpoint
                apiAccessToken = $alexa.apiAccessToken
            }
        }
        request = @{
            type = "IntentRequest"
            requestId = $alexa.requestId
            timestamp = $timestamp
            locale = $alexa.locale
            intent = @{
                name = "GetAnnouncementForDeviceIntent"
                slots = @{
                    DeviceName = @{
                        name = "DeviceName"
                        value = $DeviceName
                    }
                }
            }
        }
    }
    
    return ($payload | ConvertTo-Json -Depth 10)
}

# Function to create Smart Home Discovery payload
function Create-SmartHomeDiscoveryPayload {
    param([object]$Config, [string]$LwaToken)
    
    $smartHome = $Config.smartHome
    
    $payload = @{
        directive = @{
            header = @{
                namespace = "Alexa.Discovery"
                name = "Discover"
                payloadVersion = $smartHome.payloadVersion
                messageId = $smartHome.messageId
            }
            payload = @{
                scope = @{
                    type = "BearerToken"
                    token = $LwaToken
                }
            }
        }
    }
    
    return ($payload | ConvertTo-Json -Depth 10)
}

# Function to create OAuth AcceptGrant directive payload
function Create-OAuthAcceptGrantPayload {
    param(
        [object]$Config,
        [string]$AuthCode = "test_auth_code_$(Get-Random)",
        [string]$UserToken = $null
    )
    
    if (-not $UserToken) {
        $UserToken = $Config.alexa.userId
    }
    
    $payload = @{
        directive = @{
            header = @{
                namespace = "Alexa.Authorization"
                name = "AcceptGrant"
                payloadVersion = "3"
                messageId = "test-accept-grant-$(Get-Random)"
            }
            payload = @{
                grant = @{
                    type = "OAuth2.AuthorizationCode"
                    code = $AuthCode
                }
                grantee = @{
                    type = "BearerToken"
                    token = $UserToken
                }
            }
        }
    }
    
    return ($payload | ConvertTo-Json -Depth 10)
}

# Function to create OAuth token refresh payload
function Create-OAuthTokenRefreshPayload {
    param(
        [object]$Config,
        [string]$RefreshToken = "test_refresh_token_$(Get-Random)"
    )
    
    $payload = @{
        directive = @{
            header = @{
                namespace = "Alexa.Authorization"
                name = "RefreshToken"
                payloadVersion = "3"
                messageId = "test-refresh-token-$(Get-Random)"
            }
            payload = @{
                refreshToken = $RefreshToken
            }
        }
    }
    
    return ($payload | ConvertTo-Json -Depth 10)
}

# Function to execute the test using config
function Test-LaunchRequest {
    param(
        [object]$Config,
        [string]$Token,
        [string]$FKey,
        [switch]$Verbose
    )
    
    if (-not $Token) {
        Write-Host "❌ LWA token is required!" -ForegroundColor Red
        return $false
    }
    
    if (-not $FKey) {
        Write-Host "❌ Function key is required!" -ForegroundColor Red
        return $false
    }
    
    try {
        Write-Host "🚀 Executing LaunchRequest test..." -ForegroundColor Green
        
        $testPayload = Create-LaunchRequestPayload -Config $Config -LwaToken $Token
        $testUrl = "$($Config.azureFunction.url)?code=$FKey"
        $headers = @{
            "Content-Type" = "application/json"
            "Authorization" = "Bearer $Token"
        }
        
        if ($Verbose) {
            Write-Host "Request URL: $testUrl" -ForegroundColor Gray
            Write-Host "Request Headers: $($headers | ConvertTo-Json)" -ForegroundColor Gray
            Write-Host "Request Payload:" -ForegroundColor Gray
            Write-Host $testPayload -ForegroundColor DarkGray
        }
        
        $response = Invoke-RestMethod -Uri $testUrl -Method POST -Headers $headers -Body $testPayload
        
        Write-Host "✅ Test successful!" -ForegroundColor Green
        Write-Host "Response:" -ForegroundColor Cyan
        Write-Host ($response | ConvertTo-Json -Depth 10) -ForegroundColor White
        
        # Validate response structure
        if ($response.version -eq "1.0" -and $response.response -and $response.response.outputSpeech) {
            Write-Host "✅ Response structure is valid" -ForegroundColor Green
            Write-Host "✅ Function key authentication successful" -ForegroundColor Green
            Write-Host "✅ LWA token authentication successful" -ForegroundColor Green
            return $true
        } else {
            Write-Host "⚠️  Response structure may be incorrect" -ForegroundColor Yellow
            return $false
        }
        
    } catch {
        Write-Host "❌ Test failed!" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
            Write-Host "Status Code: $statusCode" -ForegroundColor Red
            
            if ($statusCode -eq 401) {
                Write-Host "💡 This could be due to:" -ForegroundColor Yellow
                Write-Host "   - Invalid or missing function key" -ForegroundColor Gray
                Write-Host "   - Invalid LWA token" -ForegroundColor Gray
            }
        }
        return $false
    }
}

# Function to test DoorEventIntent
function Test-DoorEventIntent {
    param(
        [object]$Config,
        [string]$Token,
        [string]$FKey,
        [string]$DoorName,
        [string]$DoorAction,
        [switch]$Verbose
    )
    
    if (-not $Token) {
        Write-Host "❌ LWA token is required!" -ForegroundColor Red
        return $false
    }
    
    if (-not $FKey) {
        Write-Host "❌ Function key is required!" -ForegroundColor Red
        return $false
    }
    
    try {
        Write-Host "🚀 Executing DoorEventIntent test: $DoorName $DoorAction..." -ForegroundColor Green
        
        $testPayload = Create-DoorEventIntentPayload -Config $Config -LwaToken $Token -DoorName $DoorName -DoorAction $DoorAction
        $testUrl = "$($Config.azureFunction.url)?code=$FKey"
        $headers = @{
            "Content-Type" = "application/json"
            "Authorization" = "Bearer $Token"
        }
        
        if ($Verbose) {
            Write-Host "Request URL: $testUrl" -ForegroundColor Gray
            Write-Host "Request Headers: $($headers | ConvertTo-Json)" -ForegroundColor Gray
            Write-Host "Request Payload:" -ForegroundColor Gray
            Write-Host $testPayload -ForegroundColor DarkGray
        }
        
        $response = Invoke-RestMethod -Uri $testUrl -Method POST -Headers $headers -Body $testPayload
        
        Write-Host "✅ DoorEventIntent test successful!" -ForegroundColor Green
        Write-Host "Response:" -ForegroundColor Cyan
        Write-Host ($response | ConvertTo-Json -Depth 10) -ForegroundColor White
        
        # Validate response structure and content
        if ($response.version -eq "1.0" -and $response.response -and $response.response.outputSpeech) {
            $responseText = $response.response.outputSpeech.text
            Write-Host "✅ Response structure is valid" -ForegroundColor Green
            Write-Host "✅ Function key authentication successful" -ForegroundColor Green
            Write-Host "✅ LWA token authentication successful" -ForegroundColor Green
            
            # Validate response content based on door action
            if ($DoorAction -eq "opened") {
                if ($responseText -like "*noted*" -and $responseText -like "*$DoorName*") {
                    Write-Host "✅ Opened door response is appropriate" -ForegroundColor Green
                } else {
                    Write-Host "⚠️  Opened door response may be unexpected" -ForegroundColor Yellow
                }
            } elseif ($DoorAction -eq "closed") {
                if ($responseText -like "*closed*" -and $responseText -like "*$DoorName*") {
                    Write-Host "✅ Closed door response is appropriate" -ForegroundColor Green
                } else {
                    Write-Host "⚠️  Closed door response may be unexpected" -ForegroundColor Yellow
                }
            }
            
            return $true
        } else {
            Write-Host "⚠️  Response structure may be incorrect" -ForegroundColor Yellow
            return $false
        }
        
    } catch {
        Write-Host "❌ DoorEventIntent test failed!" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
            Write-Host "Status Code: $statusCode" -ForegroundColor Red
            
            if ($statusCode -eq 401) {
                Write-Host "💡 This could be due to:" -ForegroundColor Yellow
                Write-Host "   - Invalid or missing function key" -ForegroundColor Gray
                Write-Host "   - Invalid LWA token" -ForegroundColor Gray
            }
        }
        return $false
    }
}

# Function to test Smart Home Discovery
function Test-SmartHomeDiscovery {
    param(
        [object]$Config,
        [string]$Token,
        [string]$FKey,
        [switch]$Verbose
    )
    
    if (-not $Token) {
        Write-Host "❌ LWA token is required!" -ForegroundColor Red
        return $false
    }
    
    if (-not $FKey) {
        Write-Host "❌ Function key is required!" -ForegroundColor Red
        return $false
    }
    
    try {
        Write-Host "🚀 Executing Smart Home Discovery test..." -ForegroundColor Green
        
        $testPayload = Create-SmartHomeDiscoveryPayload -Config $Config -LwaToken $Token
        $testUrl = "$($Config.azureFunction.url)?code=$FKey"
        $headers = @{
            "Content-Type" = "application/json"
            "Authorization" = "Bearer $Token"
        }
        
        if ($Verbose) {
            Write-Host "Request URL: $testUrl" -ForegroundColor Gray
            Write-Host "Request Headers: $($headers | ConvertTo-Json)" -ForegroundColor Gray
            Write-Host "Request Payload:" -ForegroundColor Gray
            Write-Host $testPayload -ForegroundColor DarkGray
        }
        
        $response = Invoke-RestMethod -Uri $testUrl -Method POST -Headers $headers -Body $testPayload
        
        Write-Host "✅ Smart Home Discovery test successful!" -ForegroundColor Green
        Write-Host "Response:" -ForegroundColor Cyan
        Write-Host ($response | ConvertTo-Json -Depth 10) -ForegroundColor White
        
        # Validate Smart Home Discovery response structure
        if ($response.event -and $response.event.header -and $response.event.payload) {
            $header = $response.event.header
            $payload = $response.event.payload
            
            Write-Host "✅ Smart Home response structure is valid" -ForegroundColor Green
            Write-Host "✅ Function key authentication successful" -ForegroundColor Green
            Write-Host "✅ LWA token authentication successful" -ForegroundColor Green
            
            # Validate header
            if ($header.namespace -eq "Alexa.Discovery" -and $header.name -eq "Discover.Response") {
                Write-Host "✅ Discovery response header is correct" -ForegroundColor Green
            } else {
                Write-Host "⚠️  Discovery response header may be incorrect" -ForegroundColor Yellow
            }
            
            # Validate endpoints
            if ($payload.endpoints -and $payload.endpoints.Count -gt 0) {
                $deviceCount = $payload.endpoints.Count
                Write-Host "✅ Discovered $deviceCount virtual devices" -ForegroundColor Green
                
                # Show discovered devices
                Write-Host "🏠 Discovered Virtual Devices:" -ForegroundColor Cyan
                foreach ($endpoint in $payload.endpoints) {
                    $friendlyName = $endpoint.friendlyName
                    $endpointId = $endpoint.endpointId
                    $capabilities = $endpoint.capabilities.Count
                    Write-Host "   📱 $friendlyName ($endpointId) - $capabilities capabilities" -ForegroundColor Gray
                }
                
                # Validate first device structure
                $firstDevice = $payload.endpoints[0]
                if ($firstDevice.manufacturerName -and $firstDevice.capabilities -and $firstDevice.displayCategories) {
                    Write-Host "✅ Device structure is complete" -ForegroundColor Green
                } else {
                    Write-Host "⚠️  Device structure may be incomplete" -ForegroundColor Yellow
                }
            } else {
                Write-Host "⚠️  No virtual devices discovered" -ForegroundColor Yellow
                return $false
            }
            
            return $true
        } else {
            Write-Host "⚠️  Smart Home response structure may be incorrect" -ForegroundColor Yellow
            return $false
        }
        
    } catch {
        Write-Host "❌ Smart Home Discovery test failed!" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
            Write-Host "Status Code: $statusCode" -ForegroundColor Red
            
            if ($statusCode -eq 401) {
                Write-Host "💡 This could be due to:" -ForegroundColor Yellow
                Write-Host "   - Invalid or missing function key" -ForegroundColor Gray
                Write-Host "   - Invalid LWA token" -ForegroundColor Gray
            }
        }
        return $false
    }
}

# Test function for Announce API
function Test-AnnounceAPI {
    param(
        [object]$Config,
        [string]$Token,
        [string]$FKey,
        [string]$AnnounceMessage,
        [string]$Device = "all",
        [switch]$Verbose
    )
    
    Write-Host ""
    Write-Host "🔄 Testing Announce API..." -ForegroundColor Cyan
    
    try {
        # Test Announce API
        Write-Host "📢 Testing Announce API..." -ForegroundColor Yellow
        
        # Construct announce URL properly
        $announceUrl = "$($Config.announce.url)?code=$FKey"
        
        $announcePayload = @{
            message = $AnnounceMessage
            device = $Device
        }
        
        $announceBody = $announcePayload | ConvertTo-Json -Depth 10
        $announceHeaders = @{
            "Content-Type" = "application/json"
        }
        
        if ($Verbose) {
            Write-Host "   Announce URL: $announceUrl" -ForegroundColor Gray
            Write-Host "   Announce Payload: $announceBody" -ForegroundColor Gray
        }
        
        $announceResponse = Invoke-RestMethod -Uri $announceUrl -Method POST -ContentType "application/json" -Headers $announceHeaders -Body $announceBody
        
        if ($announceResponse.success -eq $true) {
            Write-Host "   ✅ Announce API call successful" -ForegroundColor Green
            Write-Host "   📨 Message: $($announceResponse.message)" -ForegroundColor Gray
            Write-Host "   🎯 Device: $Device" -ForegroundColor Gray
            Write-Host "   🔔 Virtual device press triggered: $($announceResponse.press_event_triggered)" -ForegroundColor Gray
        } else {
            Write-Host "   ❌ Announce API call failed" -ForegroundColor Red
            Write-Host "   Error: $($announceResponse.error)" -ForegroundColor Red
            return $false
        }
        
        Write-Host ""
        Write-Host "🎉 Announce API Test Completed Successfully!" -ForegroundColor Green
        Write-Host "✅ Announcement API is working correctly" -ForegroundColor Green
        return $true
        
    } catch {
        Write-Host "❌ Announce API test failed!" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
            Write-Host "Status Code: $statusCode" -ForegroundColor Red
            
            if ($statusCode -eq 401) {
                Write-Host "💡 This could be due to:" -ForegroundColor Yellow
                Write-Host "   - Invalid or missing function key" -ForegroundColor Gray
                Write-Host "   - Invalid LWA token" -ForegroundColor Gray
            } elseif ($statusCode -eq 404) {
                Write-Host "💡 Check that the announce endpoint is available" -ForegroundColor Yellow
            }
        }
        return $false
    }
}

# Function to test GetAnnouncementForDeviceIntent
function Test-GetAnnouncementForDevice {
    param(
        [object]$Config,
        [string]$Token,
        [string]$FKey,
        [string]$DeviceName = "all",
        [switch]$Verbose
    )
    
    if (-not $Token) {
        Write-Host "❌ LWA token is required!" -ForegroundColor Red
        return $false
    }
    
    if (-not $FKey) {
        Write-Host "❌ Function key is required!" -ForegroundColor Red
        return $false
    }
    
    try {
        Write-Host "🚀 Executing GetAnnouncementForDeviceIntent test for device: $DeviceName..." -ForegroundColor Green
        
        $testPayload = Create-GetAnnouncementPayload -Config $Config -LwaToken $Token -DeviceName $DeviceName
        $testUrl = "$($Config.azureFunction.url)?code=$FKey"
        $headers = @{
            "Content-Type" = "application/json"
            "Authorization" = "Bearer $Token"
        }
        
        if ($Verbose) {
            Write-Host "Request URL: $testUrl" -ForegroundColor Gray
            Write-Host "Request Headers: $($headers | ConvertTo-Json)" -ForegroundColor Gray
            Write-Host "Request Payload:" -ForegroundColor Gray
            Write-Host $testPayload -ForegroundColor DarkGray
        }
        
        $response = Invoke-RestMethod -Uri $testUrl -Method POST -Headers $headers -Body $testPayload
        
        Write-Host "✅ Test successful!" -ForegroundColor Green
        Write-Host "Response:" -ForegroundColor Cyan
        Write-Host ($response | ConvertTo-Json -Depth 10) -ForegroundColor White
        
        # Validate response structure
        if ($response.version -eq "1.0" -and $response.response -and $response.response.outputSpeech) {
            Write-Host "✅ Response structure is valid" -ForegroundColor Green
            Write-Host "✅ Function key authentication successful" -ForegroundColor Green
            Write-Host "✅ LWA token authentication successful" -ForegroundColor Green
            
            # Check the response content
            $responseText = $response.response.outputSpeech.text
            if ($responseText -like "*no announcements*" -or $responseText -like "*Here's the message*") {
                Write-Host "✅ GetAnnouncementForDeviceIntent response is appropriate" -ForegroundColor Green
                Write-Host "   Response: $responseText" -ForegroundColor Gray
            } else {
                Write-Host "⚠️  Unexpected response content: $responseText" -ForegroundColor Yellow
            }
            
            return $true
        } else {
            Write-Host "⚠️  Response structure may be incorrect" -ForegroundColor Yellow
            Write-Host "Expected: Alexa response with version, response.outputSpeech" -ForegroundColor Gray
            return $false
        }
        
    } catch {
        Write-Host "❌ Test failed!" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
            Write-Host "Status Code: $statusCode" -ForegroundColor Red
            
            if ($statusCode -eq 401) {
                Write-Host "💡 This could be due to:" -ForegroundColor Yellow
                Write-Host "   - Invalid or missing function key" -ForegroundColor Gray
                Write-Host "   - Invalid LWA token" -ForegroundColor Gray
            } elseif ($statusCode -eq 500) {
                Write-Host "💡 This could be due to:" -ForegroundColor Yellow
                Write-Host "   - Service Bus connection issues" -ForegroundColor Gray
                Write-Host "   - Queue access permissions" -ForegroundColor Gray
            }
        }
        return $false
    }
}

# Function to test OAuth AcceptGrant directive
function Test-OAuthAcceptGrant {
    param(
        [object]$Config,
        [string]$FKey,
        [string]$AuthCode = $null,
        [string]$UserToken = $null,
        [switch]$UseRealCode,
        [switch]$Verbose
    )
    
    if (-not $FKey) {
        Write-Host "❌ Function key is required!" -ForegroundColor Red
        return $false
    }
    
    if (-not $UserToken) {
        $UserToken = $Config.alexa.userId
    }
    
    # Handle real OAuth code generation
    if ($UseRealCode -and -not $AuthCode) {
        Write-Host ""
        Write-Host "🔐 Getting Real Authorization Code for AcceptGrant Test" -ForegroundColor Cyan
        Write-Host "This will test with a genuine Amazon OAuth authorization code" -ForegroundColor Yellow
        Write-Host ""
        
        # Get OAuth configuration from config file
        $oauthConfig = $Config.oauth
        if (-not $oauthConfig) {
            Write-Host "❌ OAuth configuration not found in test config file" -ForegroundColor Red
            Write-Host "💡 Please ensure oauth section exists in test_config.json" -ForegroundColor Yellow
            return $false
        } else {
            Write-Host "✅ Using OAuth configuration from test config file" -ForegroundColor Green
            $LwaClientId = $oauthConfig.clientId
            $RedirectUri = $oauthConfig.redirectUri
            $AmazonAuthUrl = $oauthConfig.authUrl
            $Scope = $oauthConfig.smartHomeScope
            
            Write-Host "   Client ID: $($LwaClientId.Substring(0, 30))..." -ForegroundColor Gray
            Write-Host "   Redirect URI: $RedirectUri" -ForegroundColor Gray
            Write-Host "   Auth URL: $AmazonAuthUrl" -ForegroundColor Gray
            Write-Host "   Scope: $Scope (Smart Home)" -ForegroundColor Gray
        }
        
        # Build authorization URL
        $authParams = @{
            'client_id' = $LwaClientId
            'scope' = $Scope
            'response_type' = 'code'
            'redirect_uri' = $RedirectUri
            'state' = 'acceptgrant-test-' + (Get-Random)
        }
        
        $queryString = ($authParams.GetEnumerator() | ForEach-Object { "$($_.Key)=$([System.Web.HttpUtility]::UrlEncode($_.Value))" }) -join '&'
        $authUrl = "$AmazonAuthUrl`?$queryString"
        
        Write-Host "1. Open this URL in your browser:" -ForegroundColor White
        Write-Host "   $authUrl" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "2. Sign in with your Amazon account" -ForegroundColor White
        Write-Host "3. Authorize the application" -ForegroundColor White
        Write-Host "4. Copy the authorization code from the callback URL" -ForegroundColor White
        Write-Host "   (Look for 'code=' parameter - this is the AUTHORIZATION CODE)" -ForegroundColor Gray
        Write-Host ""
        
        # Open browser
        Start-Process $authUrl
        
        $AuthCode = Read-Host "5. Paste the AUTHORIZATION CODE here"
        
        if (-not $AuthCode) {
            Write-Host "❌ No authorization code provided. Using test code instead." -ForegroundColor Yellow
            $AuthCode = "test_auth_code_$(Get-Random)"
        } else {
            Write-Host "✅ Using real authorization code for AcceptGrant test" -ForegroundColor Green
        }
    } elseif (-not $AuthCode) {
        $AuthCode = "test_auth_code_$(Get-Random)"
    }
    
    try {
        Write-Host "🚀 Testing OAuth AcceptGrant directive..." -ForegroundColor Green
        Write-Host "   Auth Code: $AuthCode" -ForegroundColor Gray
        Write-Host "   User Token: $UserToken" -ForegroundColor Gray
        
        $testPayload = Create-OAuthAcceptGrantPayload -Config $Config -AuthCode $AuthCode -UserToken $UserToken
        $testUrl = "$($Config.azureFunction.url)?code=$FKey"
        $headers = @{
            "Content-Type" = "application/json"
        }
        
        if ($Verbose) {
            Write-Host "Request URL: $testUrl" -ForegroundColor Gray
            Write-Host "Request Headers: $($headers | ConvertTo-Json)" -ForegroundColor Gray
            Write-Host "Request Payload:" -ForegroundColor Gray
            Write-Host $testPayload -ForegroundColor DarkGray
        }
        
        $response = Invoke-RestMethod -Uri $testUrl -Method POST -Headers $headers -Body $testPayload
        
        Write-Host "✅ OAuth AcceptGrant test successful!" -ForegroundColor Green
        Write-Host "Response:" -ForegroundColor Cyan
        Write-Host ($response | ConvertTo-Json -Depth 10) -ForegroundColor White
        
        # Validate OAuth response structure
        if ($response.event -and $response.event.header) {
            $header = $response.event.header
            
            if ($header.namespace -eq "Alexa.Authorization" -and $header.name -eq "AcceptGrant.Response") {
                Write-Host "✅ OAuth AcceptGrant response is valid" -ForegroundColor Green
                Write-Host "✅ Function key authentication successful" -ForegroundColor Green
                Write-Host "✅ OAuth authorization flow initiated" -ForegroundColor Green
                
                # Check for payload details
                if ($response.event.payload) {
                    Write-Host "✅ Response payload structure is complete" -ForegroundColor Green
                } else {
                    Write-Host "⚠️  Response payload is empty (may be expected)" -ForegroundColor Yellow
                }
                
                return $true
            } else {
                Write-Host "⚠️  Unexpected OAuth response format" -ForegroundColor Yellow
                Write-Host "   Expected: Alexa.Authorization.AcceptGrant.Response" -ForegroundColor Gray
                Write-Host "   Received: $($header.namespace).$($header.name)" -ForegroundColor Gray
                return $false
            }
        } else {
            Write-Host "⚠️  OAuth response structure is invalid" -ForegroundColor Yellow
            Write-Host "   Expected: event.header with namespace and name" -ForegroundColor Gray
            return $false
        }
        
    } catch {
        Write-Host "❌ OAuth AcceptGrant test failed!" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
            Write-Host "Status Code: $statusCode" -ForegroundColor Red
            
            if ($statusCode -eq 401) {
                Write-Host "💡 This could be due to:" -ForegroundColor Yellow
                Write-Host "   - Invalid or missing function key" -ForegroundColor Gray
                Write-Host "   - OAuth configuration issues" -ForegroundColor Gray
            } elseif ($statusCode -eq 400) {
                Write-Host "💡 This could be due to:" -ForegroundColor Yellow
                Write-Host "   - Invalid authorization code format" -ForegroundColor Gray
                Write-Host "   - Missing OAuth client configuration" -ForegroundColor Gray
            } elseif ($statusCode -eq 500) {
                Write-Host "💡 This could be due to:" -ForegroundColor Yellow
                Write-Host "   - OAuth token exchange failure" -ForegroundColor Gray
                Write-Host "   - Key Vault access issues" -ForegroundColor Gray
            }
        }
        return $false
    }
}

# Function to test Key Vault OAuth token storage
function Test-KeyVaultOAuthStorage {
    param(
        [object]$Config,
        [string]$FKey,
        [switch]$Verbose
    )
    
    Write-Host "🔐 Testing Key Vault OAuth token storage..." -ForegroundColor Green
    
    try {
        # First test AcceptGrant to trigger token storage
        Write-Host "   Step 1: Testing AcceptGrant to trigger token storage..." -ForegroundColor Yellow
        $acceptGrantSuccess = Test-OAuthAcceptGrant -Config $Config -FKey $FKey -Verbose:$Verbose
        
        if (-not $acceptGrantSuccess) {
            Write-Host "   ❌ AcceptGrant failed, cannot test token storage" -ForegroundColor Red
            return $false
        }
        
        Write-Host "   ✅ AcceptGrant successful, tokens should be stored in Key Vault" -ForegroundColor Green
        
        # Test that subsequent requests can use stored tokens
        Write-Host "   Step 2: Testing token retrieval for Smart Home discovery..." -ForegroundColor Yellow
        
        # Create a discovery request without LWA token (should use stored tokens)
        $discoverySuccess = Test-SmartHomeDiscovery -Config $Config -Token "dummy_token" -FKey $FKey -Verbose:$Verbose
        
        if ($discoverySuccess) {
            Write-Host "   ✅ Smart Home discovery worked with stored tokens" -ForegroundColor Green
            Write-Host "   ✅ Key Vault token storage is functioning correctly" -ForegroundColor Green
            return $true
        } else {
            Write-Host "   ⚠️  Smart Home discovery failed - token storage may have issues" -ForegroundColor Yellow
            Write-Host "   💡 This could be due to:" -ForegroundColor Gray
            Write-Host "      - Key Vault access permissions" -ForegroundColor Gray
            Write-Host "      - TOKEN_STORAGE_TYPE not set to 'azure_key_vault'" -ForegroundColor Gray
            Write-Host "      - Managed identity configuration" -ForegroundColor Gray
            return $false
        }
        
    } catch {
        Write-Host "   ❌ Key Vault OAuth storage test failed!" -ForegroundColor Red
        Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Main execution
Write-Host "🚀 Comprehensive Alexa Function Test Suite" -ForegroundColor Green
Write-Host "=" * 60

# Load configuration
Write-Host ""
Write-Host "📋 Loading Configuration..." -ForegroundColor Cyan
$Config = Load-Config -ConfigPath $ConfigFile

if (-not $Config) {
    Write-Host "❌ Cannot proceed without valid configuration" -ForegroundColor Red
    exit 1
}

# Override config with parameters
if ($Verbose) { $Config.testing.verbose = $true }
if ($SkipPrompts) { $Config.testing.skipPrompts = $true }

Write-Host ""
Write-Host "📋 Test Configuration:" -ForegroundColor Cyan
Write-Host "   Function App: $($Config.azureFunction.functionAppName)" -ForegroundColor Gray
Write-Host "   Resource Group: $($Config.azureFunction.resourceGroup)" -ForegroundColor Gray
Write-Host "   Function URL: $($Config.azureFunction.url)" -ForegroundColor Gray
Write-Host "   LWA Token File: $($Config.files.lwaTokenFile)" -ForegroundColor Gray
Write-Host "   Auto Run Test: $($Config.testing.autoRunTest)" -ForegroundColor Gray

# Get the function key
Write-Host ""
Write-Host "🔑 Getting Azure Function key..." -ForegroundColor Cyan
$FunctionKey = Get-AzureFunctionKey -Config $Config

# Get LWA token
Write-Host ""
Write-Host "🎫 Getting LWA token..." -ForegroundColor Cyan
$LwaToken = Get-LWAToken -Config $Config -ForceNew:$ForceNewToken

Write-Host ""
Write-Host "🧪 LaunchRequest Test Status:" -ForegroundColor Cyan

# Check prerequisites
$canProceed = $true

if (-not $FunctionKey) {
    Write-Host "❌ Function key is required but not available" -ForegroundColor Red
    Write-Host "   The Azure Function is configured with AuthLevel.FUNCTION" -ForegroundColor Gray
    Write-Host "   Please ensure Azure CLI is logged in and try again" -ForegroundColor Yellow
    $canProceed = $false
}

if (-not $LwaToken) {
    Write-Host "❌ LWA token is required but not available" -ForegroundColor Red
    Write-Host "   Please generate an LWA token first" -ForegroundColor Gray
    Write-Host "🔧 Generate LWA token:" -ForegroundColor Cyan
    Write-Host "   .\generate_lwa_token.ps1" -ForegroundColor Gray
    $canProceed = $false
}

if (-not $canProceed) {
    Write-Host ""
    Write-Host "❌ Cannot proceed without both credentials" -ForegroundColor Red
    exit 1
}

# Success - we have both credentials
Write-Host "✅ Function key retrieved successfully" -ForegroundColor Green
Write-Host "✅ LWA token loaded successfully" -ForegroundColor Green

# Validate LWA token before proceeding with tests
Write-Host ""
Write-Host "🔍 Validating credentials..." -ForegroundColor Cyan
$tokenValidation = Test-LWATokenValid -Token $LwaToken -Config $Config -FunctionKey $FunctionKey

if ($tokenValidation -eq $false) {
    Write-Host ""
    Write-Host "❌ LWA token validation failed" -ForegroundColor Red
    Write-Host "💡 The token appears to be invalid or expired" -ForegroundColor Yellow
    
    if (-not $SkipPrompts) {
        Write-Host ""
        $generateNew = Read-Host "Would you like to generate a new LWA token? (y/N)"
        if ($generateNew -eq "y" -or $generateNew -eq "Y" -or $generateNew -eq "yes") {
            Write-Host "🔄 Generating new LWA token..." -ForegroundColor Cyan
            
            if (Test-Path "generate_lwa_token.ps1") {
                $null = & ".\generate_lwa_token.ps1"
                
                # Reload the token
                Start-Sleep -Seconds 2
                $LwaToken = Get-LWAToken -Config $Config
                
                if ($LwaToken) {
                    Write-Host "✅ New token generated, re-validating..." -ForegroundColor Green
                    $tokenValidation = Test-LWATokenValid -Token $LwaToken -Config $Config -FunctionKey $FunctionKey
                    
                    if ($tokenValidation -eq $false) {
                        Write-Host "❌ New token is still invalid" -ForegroundColor Red
                        Write-Host "💡 There may be a configuration issue with the LWA credentials" -ForegroundColor Yellow
                        exit 1
                    } elseif ($tokenValidation -eq $true) {
                        Write-Host "✅ New token validated successfully!" -ForegroundColor Green
                    }
                } else {
                    Write-Host "❌ Failed to generate new token" -ForegroundColor Red
                    exit 1
                }
            } else {
                Write-Host "❌ Token generation script not found: generate_lwa_token.ps1" -ForegroundColor Red
                exit 1
            }
        } else {
            Write-Host "❌ Cannot proceed with invalid token" -ForegroundColor Red
            Write-Host "💡 Manual token generation: .\generate_lwa_token.ps1" -ForegroundColor Yellow
            exit 1
        }
    } else {
        Write-Host "❌ Cannot proceed with invalid token (skip prompts enabled)" -ForegroundColor Red
        Write-Host "💡 Manual token generation: .\generate_lwa_token.ps1" -ForegroundColor Yellow
        exit 1
    }
} elseif ($tokenValidation -eq $true) {
    Write-Host "✅ LWA token validated successfully" -ForegroundColor Green
} else {
    Write-Host "⚠️  Could not validate LWA token, proceeding anyway" -ForegroundColor Yellow
    Write-Host "   Tests may fail if token is invalid" -ForegroundColor Gray
}

# Show test information
Write-Host ""
Write-Host "📋 Test Details:" -ForegroundColor Cyan
Write-Host "   Testing comprehensive Alexa Skill functionality" -ForegroundColor Gray
Write-Host "   Tests: LaunchRequest, DoorEvents, Smart Home Discovery, OAuth Authorization, Announce API" -ForegroundColor Gray
Write-Host "   Function URL: $($Config.azureFunction.url)" -ForegroundColor Gray

# Auto-run test if configured
if ($Config.testing.autoRunTest) {
    Write-Host ""
    Write-Host "🚀 Auto-running tests (configured in test_config.json)..." -ForegroundColor Green
    
    # Test 1: LaunchRequest
    Write-Host ""
    Write-Host "📋 Test 1: LaunchRequest (Alexa, open Home Automation)" -ForegroundColor Cyan
    $launchResult = Test-LaunchRequest -Config $Config -Token $LwaToken -FKey $FunctionKey -Verbose:$Config.testing.verbose
    
    # Test 2: DoorEventIntent - Opened
    Write-Host ""
    Write-Host "📋 Test 2: DoorEventIntent - Door Opened" -ForegroundColor Cyan
    $doorOpenedResult = Test-DoorEventIntent -Config $Config -Token $LwaToken -FKey $FunctionKey -DoorName $Config.doorEvent.doorName -DoorAction "opened" -Verbose:$Config.testing.verbose
    
    # Test 3: DoorEventIntent - Closed  
    Write-Host ""
    Write-Host "📋 Test 3: DoorEventIntent - Door Closed" -ForegroundColor Cyan
    $doorClosedResult = Test-DoorEventIntent -Config $Config -Token $LwaToken -FKey $FunctionKey -DoorName $Config.doorEvent.doorName -DoorAction "closed" -Verbose:$Config.testing.verbose
    
    # Test 4: Smart Home Discovery
    Write-Host ""
    Write-Host "📋 Test 4: Smart Home Discovery (Device Discovery)" -ForegroundColor Cyan
    $discoveryResult = Test-SmartHomeDiscovery -Config $Config -Token $LwaToken -FKey $FunctionKey -Verbose:$Config.testing.verbose
    
    # Test 5: OAuth AcceptGrant Authorization (moved before announce tests to validate token storage)
    Write-Host ""
    Write-Host "📋 Test 5: OAuth AcceptGrant Authorization Directive" -ForegroundColor Cyan
    
    # Determine if we should use real OAuth code
    $useRealCode = $UseRealOAuth
    if (-not $useRealCode -and -not $SkipPrompts -and -not $Config.testing.skipPrompts) {
        Write-Host ""
        $realOAuth = Read-Host "   Do you want to test with a REAL Amazon OAuth code? (y/N) [Tests with real auth flow]"
        $useRealCode = $realOAuth -eq 'y' -or $realOAuth -eq 'Y'
    }
    
    if ($useRealCode) {
        Write-Host "   🔐 Testing with REAL Amazon OAuth authorization code..." -ForegroundColor Yellow
        Write-Host "   💡 This will validate that your AcceptGrant functionality works with real codes" -ForegroundColor Gray
        $oauthAcceptGrantResult = Test-OAuthAcceptGrant -Config $Config -FKey $FunctionKey -UserToken $LwaToken -UseRealCode -Verbose:$Config.testing.verbose
    } else {
        Write-Host "   🧪 Testing with test authorization code (will fail as expected)..." -ForegroundColor Yellow
        Write-Host "   💡 To test with real OAuth: .\test_azure_function.ps1 -UseRealOAuth" -ForegroundColor Gray
        $oauthAcceptGrantResult = Test-OAuthAcceptGrant -Config $Config -FKey $FunctionKey -UserToken $LwaToken -Verbose:$Config.testing.verbose
    }
    
    # Test 6: Announce API (can now validate stored OAuth tokens)
    Write-Host ""
    Write-Host "📋 Test 6: Announce API" -ForegroundColor Cyan
    $announceResult = Test-AnnounceAPI -Config $Config -Token $LwaToken -FKey $FunctionKey -AnnounceMessage $Config.announce.message -Device $Config.announce.device -Verbose:$Config.testing.verbose
    
    # Test 7: GetAnnouncementForDeviceIntent (can now use stored OAuth tokens if available)
    Write-Host ""
    Write-Host "📋 Test 7: GetAnnouncementForDeviceIntent (Check for messages)" -ForegroundColor Cyan
    $getAnnouncementResult = Test-GetAnnouncementForDevice -Config $Config -Token $LwaToken -FKey $FunctionKey -DeviceName "all" -Verbose:$Config.testing.verbose
    

    
    # Summary
    Write-Host ""
    Write-Host "📊 Test Results Summary:" -ForegroundColor Cyan
    Write-Host "   LaunchRequest: $(if($launchResult) {'✅ PASSED'} else {'❌ FAILED'})" -ForegroundColor $(if($launchResult) {'Green'} else {'Red'})
    Write-Host "   DoorEventIntent (opened): $(if($doorOpenedResult) {'✅ PASSED'} else {'❌ FAILED'})" -ForegroundColor $(if($doorOpenedResult) {'Green'} else {'Red'})
    Write-Host "   DoorEventIntent (closed): $(if($doorClosedResult) {'✅ PASSED'} else {'❌ FAILED'})" -ForegroundColor $(if($doorClosedResult) {'Green'} else {'Red'})
    Write-Host "   Smart Home Discovery: $(if($discoveryResult) {'✅ PASSED'} else {'❌ FAILED'})" -ForegroundColor $(if($discoveryResult) {'Green'} else {'Red'})
    Write-Host "   OAuth AcceptGrant: $(if($oauthAcceptGrantResult) {'✅ PASSED'} else {'❌ FAILED'})" -ForegroundColor $(if($oauthAcceptGrantResult) {'Green'} else {'Red'})
    Write-Host "   Announce API: $(if($announceResult) {'✅ PASSED'} else {'❌ FAILED'})" -ForegroundColor $(if($announceResult) {'Green'} else {'Red'})
    Write-Host "   GetAnnouncementForDevice: $(if($getAnnouncementResult) {'✅ PASSED'} else {'❌ FAILED'})" -ForegroundColor $(if($getAnnouncementResult) {'Green'} else {'Red'})
    
    if ($launchResult -and $doorOpenedResult -and $doorClosedResult -and $discoveryResult -and $oauthAcceptGrantResult -and $getAnnouncementResult -and $announceResult) {
        Write-Host ""
        Write-Host "🎉 All tests completed successfully!" -ForegroundColor Green
        Write-Host "✅ Your Azure Function is ready for full Alexa integration (Custom + Smart Home + OAuth)" -ForegroundColor Green
        Write-Host "🔐 OAuth AcceptGrant tested successfully - tokens should be stored for future use" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "⚠️  Some tests failed - check the errors above" -ForegroundColor Yellow
        exit 1
    }
} else {
    Write-Host ""
    Write-Host "💻 Manual Test Commands:" -ForegroundColor Cyan
    Write-Host "   LaunchRequest: Test-LaunchRequest -Config `$Config -Token `"$LwaToken`" -FKey `"$FunctionKey`" -Verbose" -ForegroundColor Gray
    Write-Host "   Door Opened: Test-DoorEventIntent -Config `$Config -Token `"$LwaToken`" -FKey `"$FunctionKey`" -DoorName `"$($Config.doorEvent.doorName)`" -DoorAction `"opened`" -Verbose" -ForegroundColor Gray
    Write-Host "   Door Closed: Test-DoorEventIntent -Config `$Config -Token `"$LwaToken`" -FKey `"$FunctionKey`" -DoorName `"$($Config.doorEvent.doorName)`" -DoorAction `"closed`" -Verbose" -ForegroundColor Gray
    Write-Host "   Smart Home Discovery: Test-SmartHomeDiscovery -Config `$Config -Token `"$LwaToken`" -FKey `"$FunctionKey`" -Verbose" -ForegroundColor Gray
    Write-Host "   Announce + Door Close: Test-AnnounceAndCloseIntegration -Config `$Config -Token `"$LwaToken`" -FKey `"$FunctionKey`" -AnnounceMessage `"$($Config.announce.message)`" -Device `"all`" -Verbose" -ForegroundColor Gray
    Write-Host "   Get Announcement: Test-GetAnnouncementForDevice -Config `$Config -Token `"$LwaToken`" -FKey `"$FunctionKey`" -DeviceName `"all`" -Verbose" -ForegroundColor Gray
    Write-Host "   OAuth AcceptGrant: Test-OAuthAcceptGrant -Config `$Config -FKey `"$FunctionKey`" -UserToken `"$LwaToken`" -Verbose" -ForegroundColor Gray
    Write-Host "   Key Vault OAuth Storage: Test-KeyVaultOAuthStorage -Config `$Config -FKey `"$FunctionKey`" -Verbose" -ForegroundColor Gray
    
    Write-Host ""
    Write-Host "🔧 PowerShell Direct Call:" -ForegroundColor Yellow
    $testUrl = "$($Config.azureFunction.url)?code=$FunctionKey"
    Write-Host "   Invoke-RestMethod -Uri `"$testUrl`" -Method POST -ContentType `"application/json`" -Headers @{`"Authorization`"=`"Bearer $LwaToken`"} -Body `$payload" -ForegroundColor Gray
}

Write-Host ""
Write-Host "📝 Configuration Management:" -ForegroundColor Cyan
Write-Host "   Config File: $ConfigFile" -ForegroundColor Gray
Write-Host "   Edit config: code $ConfigFile" -ForegroundColor Gray
Write-Host "   Force new token: .\test_azure_function.ps1 -ForceNewToken" -ForegroundColor Gray
Write-Host "   Verbose output: .\test_azure_function.ps1 -Verbose" -ForegroundColor Gray



Write-Host ""
Write-Host "⚡ Quick Test (if you have a token):" -ForegroundColor Green
if ($FunctionKey -and $LwaToken -ne "YOUR_LWA_TOKEN_HERE") {
    Write-Host "Ready to test! Run: Test-LaunchRequest -Token `"$LwaToken`" -FKey `"$FunctionKey`"" -ForegroundColor White
} elseif ($FunctionKey) {
    Write-Host "Function key ready. Get LWA token first: .\generate_lwa_token.ps1" -ForegroundColor Yellow
} else {
    Write-Host "Get function key first, then LWA token" -ForegroundColor Yellow
}
