#!/usr/bin/env powershell
# AWS Lambda Deployment Script using config.env
# This script reads configuration from config.env and deploys the Lambda function

param(
    [switch]$SkipZipCreation,
    [switch]$UpdateOnly,
    [string]$ConfigFile = "config.env"
)

Write-Host "🚀 AWS Lambda Deployment Script" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Green

# Function to read config.env file
function Read-ConfigFile {
    param([string]$FilePath)
    
    $config = @{}
    if (Test-Path $FilePath) {
        Write-Host "📖 Reading configuration from: $FilePath" -ForegroundColor Yellow
        Get-Content $FilePath | ForEach-Object {
            if ($_ -match '^\s*([^#][^=]*?)\s*=\s*"?([^"]*)"?\s*$') {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                $config[$key] = $value
                if ($key -notlike "*SECRET*" -and $key -notlike "*KEY*") {
                    Write-Host "   ✓ $key = $value" -ForegroundColor Gray
                } else {
                    Write-Host "   ✓ $key = [HIDDEN]" -ForegroundColor Gray
                }
            }
        }
    } else {
        Write-Host "❌ Configuration file not found: $FilePath" -ForegroundColor Red
        exit 1
    }
    return $config
}

# Load configuration
$config = Read-ConfigFile -FilePath $ConfigFile

# Required configuration validation
$requiredKeys = @('FUNCTION_NAME', 'REGION', 'RUNTIME', 'IAM_ROLE_NAME', 'AZURE_FUNCTION_URL')
$missingKeys = @()

foreach ($key in $requiredKeys) {
    if (-not $config.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($config[$key])) {
        $missingKeys += $key
    }
}

if ($missingKeys.Count -gt 0) {
    Write-Host "❌ Missing required configuration:" -ForegroundColor Red
    $missingKeys | ForEach-Object { Write-Host "   - $_" -ForegroundColor Red }
    exit 1
}

# Set variables from config
$FunctionName = $config['FUNCTION_NAME']
$Region = $config['REGION']
$Runtime = $config['RUNTIME']
$MemorySize = $config.ContainsKey('MEMORY_SIZE') ? $config['MEMORY_SIZE'] : 128
$Timeout = $config.ContainsKey('TIMEOUT') ? $config['TIMEOUT'] : 30
$RoleName = $config['IAM_ROLE_NAME']
$AzureFunctionUrl = $config['AZURE_FUNCTION_URL']
$AzureFunctionKey = $config['AZURE_FUNCTION_KEY']

Write-Host ""
Write-Host "📋 Deployment Configuration:" -ForegroundColor Cyan
Write-Host "   Function Name: $FunctionName" -ForegroundColor White
Write-Host "   Region: $Region" -ForegroundColor White
Write-Host "   Runtime: $Runtime" -ForegroundColor White
Write-Host "   Memory: $MemorySize MB" -ForegroundColor White
Write-Host "   Timeout: $Timeout seconds" -ForegroundColor White
Write-Host ""

# Check AWS CLI
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

# Create deployment zip if not skipping
$zipFile = "alexa-lambda-deployment.zip"
if (-not $SkipZipCreation) {
    Write-Host ""
    Write-Host "📦 Creating deployment package..." -ForegroundColor Yellow
    
    if (Test-Path $zipFile) {
        Remove-Item $zipFile
    }
    
    # Run the Python script to create zip
    try {
        python create_zip.py
        if (-not (Test-Path "alexa-lambda-manual-deployment.zip")) {
            Write-Host "❌ Failed to create deployment zip" -ForegroundColor Red
            exit 1
        }
        # Rename to expected file name
        Move-Item "alexa-lambda-manual-deployment.zip" $zipFile
        Write-Host "✅ Deployment package created: $zipFile" -ForegroundColor Green
    } catch {
        Write-Host "❌ Error creating deployment package: $_" -ForegroundColor Red
        exit 1
    }
} else {
    if (-not (Test-Path $zipFile)) {
        Write-Host "❌ Deployment zip not found: $zipFile" -ForegroundColor Red
        Write-Host "   Run without -SkipZipCreation to create it" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "📦 Using existing deployment package: $zipFile" -ForegroundColor Yellow
}

# Check if IAM role exists, create if needed
Write-Host ""
Write-Host "🔍 Checking IAM role..." -ForegroundColor Yellow
try {
    $roleArn = aws iam get-role --role-name $RoleName --query 'Role.Arn' --output text 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ IAM role exists: $RoleName" -ForegroundColor Green
        Write-Host "   ARN: $roleArn" -ForegroundColor Gray
    } else {
        throw "Role not found"
    }
} catch {
    Write-Host "📝 Creating IAM role: $RoleName" -ForegroundColor Yellow
    
    # Create trust policy
    $trustPolicy = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
"@
    
    $trustPolicy | Out-File -FilePath "trust-policy.json" -Encoding UTF8
    
    try {
        aws iam create-role --role-name $RoleName --assume-role-policy-document file://trust-policy.json --description "Execution role for Alexa Smart Home proxy Lambda"
        aws iam attach-role-policy --role-name $RoleName --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
        
        Write-Host "✅ IAM role created: $RoleName" -ForegroundColor Green
        
        # Get the ARN
        Start-Sleep -Seconds 5  # Wait for role to be available
        $roleArn = aws iam get-role --role-name $RoleName --query 'Role.Arn' --output text
        
        # Clean up
        Remove-Item "trust-policy.json" -ErrorAction SilentlyContinue
        
        Write-Host "⏳ Waiting for IAM role to be available..." -ForegroundColor Yellow
        Start-Sleep -Seconds 10
        
    } catch {
        Write-Host "❌ Failed to create IAM role: $_" -ForegroundColor Red
        Remove-Item "trust-policy.json" -ErrorAction SilentlyContinue
        exit 1
    }
}

# Deploy or update Lambda function
Write-Host ""
Write-Host "🚀 Deploying Lambda function..." -ForegroundColor Yellow

try {
    # Check if function exists
    $functionExists = $false
    try {
        aws lambda get-function --function-name $FunctionName --region $Region --output text >$null 2>&1
        if ($LASTEXITCODE -eq 0) {
            $functionExists = $true
        }
    } catch {
        $functionExists = $false
    }
    
    if ($functionExists -and -not $UpdateOnly) {
        Write-Host "🔄 Updating existing Lambda function..." -ForegroundColor Yellow
        aws lambda update-function-code --function-name $FunctionName --region $Region --zip-file fileb://$zipFile
        
        # Update configuration
        aws lambda update-function-configuration --function-name $FunctionName --region $Region --timeout $Timeout --memory-size $MemorySize --runtime $Runtime --handler "lambda_function.lambda_handler"
        
    } elseif (-not $functionExists) {
        Write-Host "🆕 Creating new Lambda function..." -ForegroundColor Yellow
        aws lambda create-function --function-name $FunctionName --region $Region --runtime $Runtime --role $roleArn --handler "lambda_function.lambda_handler" --zip-file fileb://$zipFile --timeout $Timeout --memory-size $MemorySize --description "Alexa Smart Home proxy that forwards requests to Azure Function"
        
    } else {
        Write-Host "✅ Function exists, skipping creation (UpdateOnly mode)" -ForegroundColor Green
    }
    
    Write-Host "✅ Lambda function deployed successfully" -ForegroundColor Green
    
} catch {
    Write-Host "❌ Failed to deploy Lambda function: $_" -ForegroundColor Red
    exit 1
}

# Set environment variables
Write-Host ""
Write-Host "⚙️ Configuring environment variables..." -ForegroundColor Yellow

$envVars = @{
    "AZURE_FUNCTION_URL" = $AzureFunctionUrl
}

if (-not [string]::IsNullOrWhiteSpace($AzureFunctionKey)) {
    $envVars["AZURE_FUNCTION_KEY"] = $AzureFunctionKey
}

$envVarsJson = ($envVars | ConvertTo-Json -Compress).Replace('"', '\"')

try {
    aws lambda update-function-configuration --function-name $FunctionName --region $Region --environment "Variables=$envVarsJson"
    Write-Host "✅ Environment variables configured" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to set environment variables: $_" -ForegroundColor Red
    exit 1
}

# Get function information
Write-Host ""
Write-Host "📋 Function Information:" -ForegroundColor Cyan

try {
    $functionInfo = aws lambda get-function --function-name $FunctionName --region $Region --output json | ConvertFrom-Json
    $functionArn = $functionInfo.Configuration.FunctionArn
    
    Write-Host "   Function Name: $FunctionName" -ForegroundColor White
    Write-Host "   Function ARN:  $functionArn" -ForegroundColor White
    Write-Host "   Region:        $Region" -ForegroundColor White
    Write-Host "   Runtime:       $($functionInfo.Configuration.Runtime)" -ForegroundColor White
    Write-Host "   Memory:        $($functionInfo.Configuration.MemorySize) MB" -ForegroundColor White
    Write-Host "   Timeout:       $($functionInfo.Configuration.Timeout) seconds" -ForegroundColor White
    
} catch {
    Write-Host "⚠️ Could not retrieve function information" -ForegroundColor Yellow
}

# Cleanup
if ($config.ContainsKey('CLEANUP_ON_COMPLETE') -and $config['CLEANUP_ON_COMPLETE'] -eq 'true') {
    Write-Host ""
    Write-Host "🧹 Cleaning up deployment files..." -ForegroundColor Yellow
    Remove-Item $zipFile -ErrorAction SilentlyContinue
    Write-Host "✅ Cleanup completed" -ForegroundColor Green
}

Write-Host ""
Write-Host "✅ Deployment completed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "🎯 Next Steps:" -ForegroundColor Yellow
Write-Host "1. Configure your Alexa Smart Home skill endpoint:" -ForegroundColor White
Write-Host "   $functionArn" -ForegroundColor Cyan
Write-Host ""
Write-Host "2. Set up Account Linking in Alexa Developer Console with:" -ForegroundColor White
Write-Host "   - Client ID: $LwaClientId" -ForegroundColor Gray
Write-Host "   - Authorization URL: https://www.amazon.com/ap/oa" -ForegroundColor Gray
Write-Host "   - Token URL: https://api.amazon.com/auth/o2/token" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Add Alexa permission to Lambda function:" -ForegroundColor White
Write-Host "   aws lambda add-permission --function-name $FunctionName --region $Region --statement-id alexa-smart-home --action lambda:InvokeFunction --principal alexa-appkit.amazon.com --event-source-token YOUR_SKILL_ID" -ForegroundColor Gray
Write-Host ""

exit 0
