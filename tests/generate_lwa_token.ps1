# Generate LWA Token for Testing - PowerShell Version
# This script helps generate an LWA access token for testing Azure Function authentication

param(
    [switch]$UseExisting,
    [switch]$TestOnly,
    [string]$SavedTokenFile = "lwa_token.json",
    [string]$ConfigFile = "test_config.json"
)

# Function to load OAuth configuration from test config file
function Get-OAuthConfig {
    param([string]$ConfigPath = "test_config.json")
    
    if (Test-Path $ConfigPath) {
        try {
            $config = Get-Content $ConfigPath | ConvertFrom-Json
            if ($config.oauth) {
                Write-Host "✅ Using OAuth configuration from: $ConfigPath" -ForegroundColor Green
                return $config.oauth
            }
        } catch {
            Write-Host "⚠️ Could not read config file: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    
    Write-Host "❌ OAuth configuration not found in config file" -ForegroundColor Red
    Write-Host "💡 Please ensure oauth section exists in test_config.json" -ForegroundColor Yellow
    return $null
}

# Load OAuth configuration
$OAuthConfig = Get-OAuthConfig -ConfigPath $ConfigFile

if (-not $OAuthConfig) {
    Write-Host "❌ Cannot proceed without OAuth configuration" -ForegroundColor Red
    exit 1
}

# LWA Configuration
$LwaClientId = $OAuthConfig.clientId
$RedirectUri = $OAuthConfig.redirectUri

# LWA Client Secret - Get from config or Azure Key Vault
$LwaClientSecret = $null
if ($OAuthConfig.clientSecret) {
    $LwaClientSecret = $OAuthConfig.clientSecret
} else {
    # Try to get from Azure Key Vault
    try {
        Write-Host "🔑 Attempting to get client secret from Azure Key Vault..." -ForegroundColor Cyan
        $LwaClientSecret = az keyvault secret show --vault-name srp-kv-home-auto --name oauth-client-secret --query value -o tsv 2>$null
        if ($LwaClientSecret) {
            Write-Host "✅ Client secret retrieved from Key Vault" -ForegroundColor Green
        }
    } catch {
        Write-Host "⚠️  Could not retrieve from Key Vault" -ForegroundColor Yellow
    }
}

# Amazon URLs from config
$AmazonAuthUrl = $OAuthConfig.authUrl
$AmazonTokenUrl = $OAuthConfig.tokenUrl
$AmazonProfileUrl = $OAuthConfig.profileUrl

function Test-LwaToken {
    param([string]$AccessToken)
    
    Write-Host "🧪 Testing LWA token..." -ForegroundColor Yellow
    
    try {
        $headers = @{
            'Authorization' = "Bearer $AccessToken"
            'Content-Type' = 'application/json'
        }
        
        $response = Invoke-RestMethod -Uri $AmazonProfileUrl -Headers $headers -Method Get -TimeoutSec 10
        
        Write-Host "✅ Token validation successful!" -ForegroundColor Green
        Write-Host "   User ID: $($response.user_id)" -ForegroundColor Gray
        Write-Host "   Name: $($response.name)" -ForegroundColor Gray
        Write-Host "   Email: $($response.email)" -ForegroundColor Gray
        
        return $true
    }
    catch {
        Write-Host "❌ Token validation failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Save-Token {
    param([hashtable]$TokenData)
    
    try {
        $TokenData | ConvertTo-Json | Out-File -FilePath $SavedTokenFile -Encoding UTF8
        Write-Host "💾 Token saved to: $SavedTokenFile" -ForegroundColor Green
    }
    catch {
        Write-Host "⚠️ Could not save token: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Load-SavedToken {
    try {
        if (Test-Path $SavedTokenFile) {
            $tokenData = Get-Content $SavedTokenFile | ConvertFrom-Json
            
            # Test if token is still valid
            if (Test-LwaToken -AccessToken $tokenData.access_token) {
                return $tokenData.access_token
            }
            else {
                Write-Host "⚠️ Saved token is no longer valid" -ForegroundColor Yellow
                Remove-Item $SavedTokenFile -ErrorAction SilentlyContinue
            }
        }
        return $null
    }
    catch {
        Write-Host "⚠️ Could not load saved token: $($_.Exception.Message)" -ForegroundColor Yellow
        return $null
    }
}

function Start-ManualTokenGeneration {
    Write-Host ""
    Write-Host "🔐 Manual Token Generation Process" -ForegroundColor Cyan
    Write-Host "Since automatic OAuth flow is complex in PowerShell, here's the manual process:" -ForegroundColor Yellow
    Write-Host ""
    
    # Build authorization URL
    $authParams = @{
        'client_id' = $LwaClientId
        'scope' = $OAuthConfig.scope
        'response_type' = 'code'
        'redirect_uri' = $RedirectUri
        'state' = 'home-automation-test'
    }
    
    $queryString = ($authParams.GetEnumerator() | ForEach-Object { "$($_.Key)=$([System.Web.HttpUtility]::UrlEncode($_.Value))" }) -join '&'
    $authUrl = "$($OAuthConfig.authUrl)`?$queryString"
    
    Write-Host "1. Open this URL in your browser:" -ForegroundColor White
    Write-Host "   $authUrl" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "2. Sign in with your Amazon account" -ForegroundColor White
    Write-Host "3. Authorize the application" -ForegroundColor White
    Write-Host "4. Copy the authorization code from the callback URL" -ForegroundColor White
    Write-Host "   (Look for 'code=' parameter in the redirected URL)" -ForegroundColor Gray
    Write-Host ""
    
    # Open browser
    Start-Process $authUrl
    
    $authCode = Read-Host "5. Paste the authorization code here"
    
    if ($authCode) {
        Write-Host "🔄 Exchanging authorization code for access token..." -ForegroundColor Yellow
        
        $tokenData = @{
            'grant_type' = 'authorization_code'
            'code' = $authCode
            'redirect_uri' = $RedirectUri
            'client_id' = $LwaClientId
            'client_secret' = $LwaClientSecret
        }
        
        try {
            $response = Invoke-RestMethod -Uri $AmazonTokenUrl -Method Post -Body $tokenData -TimeoutSec 10
            
            Write-Host "✅ Token exchange successful!" -ForegroundColor Green
            Write-Host "   Access Token: $($response.access_token.Substring(0, 20))..." -ForegroundColor Gray
            Write-Host "   Token Type: $($response.token_type)" -ForegroundColor Gray
            Write-Host "   Expires In: $($response.expires_in) seconds" -ForegroundColor Gray
            
            # Save token
            Save-Token -TokenData @{
                access_token = $response.access_token
                token_type = $response.token_type
                expires_in = $response.expires_in
            }
            
            # Test the token
            Test-LwaToken -AccessToken $response.access_token
            
            Write-Host ""
            Write-Host "🎯 Your LWA Token for testing:" -ForegroundColor Green
            Write-Host $response.access_token -ForegroundColor White
            
            return $response.access_token
        }
        catch {
            Write-Host "❌ Token exchange failed: $($_.Exception.Message)" -ForegroundColor Red
            return $null
        }
    }
}

# Main script logic
Write-Host "🚀 LWA Token Generator for Home Automation Testing" -ForegroundColor Green
Write-Host "=" * 60

Write-Host ""
Write-Host "📋 OAuth Configuration:" -ForegroundColor Cyan
Write-Host "   Client ID: $($LwaClientId.Substring(0, 30))..." -ForegroundColor Gray
Write-Host "   Redirect URI: $RedirectUri" -ForegroundColor Gray
Write-Host "   Auth URL: $($OAuthConfig.authUrl)" -ForegroundColor Gray
Write-Host "   Scope: $($OAuthConfig.scope)" -ForegroundColor Gray

if ($TestOnly) {
    $savedToken = Load-SavedToken
    if ($savedToken) {
        Test-LwaToken -AccessToken $savedToken
        Write-Host ""
        Write-Host "🎯 Current Token: $savedToken" -ForegroundColor Green
    }
    else {
        Write-Host "❌ No valid saved token found. Run without -TestOnly to generate a new one." -ForegroundColor Red
    }
}
elseif ($UseExisting) {
    $savedToken = Load-SavedToken
    if ($savedToken) {
        Write-Host "✅ Using saved valid token" -ForegroundColor Green
        Test-LwaToken -AccessToken $savedToken
        Write-Host ""
        Write-Host "🎯 Current Token: $savedToken" -ForegroundColor Green
    }
    else {
        Write-Host "❌ No valid saved token found. Generating new token..." -ForegroundColor Yellow
        Start-ManualTokenGeneration
    }
}
else {
    Start-ManualTokenGeneration
}

Write-Host ""
Write-Host "💡 Usage Examples:" -ForegroundColor Cyan
Write-Host "   Use saved token:      .\generate_lwa_token.ps1 -UseExisting" -ForegroundColor Gray
Write-Host "   Test only:            .\generate_lwa_token.ps1 -TestOnly" -ForegroundColor Gray
Write-Host "   Run full tests:       .\test_azure_function.ps1" -ForegroundColor Gray
