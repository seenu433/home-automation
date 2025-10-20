"""
AWS Lambda Proxy for Alexa Smart Home Skill

This proxy validates LWA tokens for Smart Home requests and forwards ALL requests 
to the Azure Function. Authorization directives are forwarded without validation 
to allow Azure Function to handle complete OAuth flow and store tokens in Azure Key Vault.

Simplified Architecture:
- Authorization directives → Forwarded directly to Azure Function (no local handling)
- Smart Home requests → LWA token validation → Forward to Azure Function with validated token
- Azure Function handles all OAuth token exchange, storage, and management
"""

import json
import urllib3
import os
import threading
import uuid

# Azure Function endpoint
AZURE_FUNCTION_URL = os.environ.get('AZURE_FUNCTION_URL', 'https://srp-alexa-fn.azurewebsites.net/api/alexa_skill')
AZURE_FUNCTION_KEY = os.environ.get('AZURE_FUNCTION_KEY', '')

# Amazon LWA token validation endpoint (for validating tokens before forwarding)
AMAZON_TOKEN_VALIDATION_URL = 'https://api.amazon.com/user/profile'

# Initialize HTTP client
http = urllib3.PoolManager()

def is_authorization_directive(event):
    """Check if this is an Alexa.Authorization directive"""
    try:
        if 'directive' in event:
            directive = event['directive']
            header = directive.get('header', {})
            return header.get('namespace') == 'Alexa.Authorization'
    except:
        pass
    return False

def validate_lwa_token(access_token):
    """
    Validate LWA (Login with Amazon) token with Amazon's API
    Returns user profile if valid, None if invalid
    """
    if not access_token:
        return None
    
    try:
        print(f"Validating LWA token with Amazon...")
        
        # Call Amazon's user profile API to validate token
        response = http.request(
            'GET',
            AMAZON_TOKEN_VALIDATION_URL,
            headers={
                'Authorization': f'Bearer {access_token}',
                'Content-Type': 'application/json'
            },
            timeout=10.0
        )
        
        if response.status == 200:
            user_profile = json.loads(response.data.decode('utf-8'))
            print(f"Token validation successful for user: {user_profile.get('user_id', 'unknown')}")
            return user_profile
        else:
            print(f"Token validation failed: {response.status} - {response.data.decode('utf-8')}")
            return None
            
    except Exception as e:
        print(f"Error validating LWA token: {str(e)}")
        return None

def extract_lwa_token(event):
    """
    Extract LWA (Login with Amazon) token from Alexa request
    
    For Smart Home directives, the token can be in:
    - directive.endpoint.scope.token (device-specific)
    - directive.payload.scope.token (payload-level)
    - context.System.user.accessToken (Custom skills)
    """
    try:
        # Check for Smart Home directive tokens
        if 'directive' in event:
            directive = event['directive']
            
            # Check endpoint scope token (most common for Smart Home)
            if 'endpoint' in directive and 'scope' in directive['endpoint']:
                scope = directive['endpoint']['scope']
                if 'token' in scope:
                    return scope['token']
            
            # Check payload scope token
            if 'payload' in directive and 'scope' in directive['payload']:
                scope = directive['payload']['scope']
                if 'token' in scope:
                    return scope['token']
        
        # Check for Custom skill access token
        if 'context' in event and 'System' in event['context']:
            system = event['context']['System']
            if 'user' in system and 'accessToken' in system['user']:
                return system['user']['accessToken']
        
        # Check for session access token (Custom skills)
        if 'session' in event and 'user' in event['session']:
            user = event['session']['user']
            if 'accessToken' in user:
                return user['accessToken']
                
    except Exception as e:
        print(f"Error extracting LWA token: {str(e)}")
    
    return None

def lambda_handler(event, context):
    """
    AWS Lambda handler that validates LWA tokens for non-authorization requests
    and forwards all requests (including Authorization directives) to Azure Function
    """
    
    print(f"Received Alexa request: {json.dumps(event, indent=2)}")
    
    try:
        # Check if this is an authorization directive (OAuth flow)
        if is_authorization_directive(event):
            directive = event.get('directive', {})
            header = directive.get('header', {})
            directive_name = header.get('name', '')
            
            if directive_name == 'AcceptGrant':
                print("AcceptGrant directive detected - processing asynchronously")
                
                # Start async call to Azure Function
                thread = threading.Thread(
                    target=forward_to_azure_function_async,
                    args=(event, context.aws_request_id if context else 'unknown')
                )
                thread.start()
                
                # Return immediate AcceptGrant.Response to Alexa
                return create_accept_grant_response(header.get('messageId'))
            else:
                print("Authorization directive detected - forwarding to Azure Function for OAuth handling")
                # Forward other Authorization directives synchronously
                return forward_to_azure_function(event, skip_auth=True)
        
        # For all other Smart Home requests, require authentication
        # Extract and validate LWA token
        lwa_token = extract_lwa_token(event)
        
        if not lwa_token:
            print("No LWA token found in request")
            return create_authentication_error_response()
        
        # Validate token with Amazon
        user_profile = validate_lwa_token(lwa_token)
        if not user_profile:
            print("LWA token validation failed")
            return create_authentication_error_response()
        
        print(f"Authentication successful for user: {user_profile.get('user_id', 'unknown')}")
        
        # Forward the authenticated request to Azure Function
        return forward_to_azure_function(event, lwa_token=lwa_token)
        
    except Exception as e:
        print(f"Error processing request: {str(e)}")
        return create_error_response()

def forward_to_azure_function(event, lwa_token=None, skip_auth=False):
    """
    Forward request to Azure Function with proper headers
    """
    try:
        # Prepare headers for Azure Function call
        headers = {
            'Content-Type': 'application/json',
            'User-Agent': 'AWS-Lambda-Proxy/1.0'
        }
        
        # Add function key if provided
        if AZURE_FUNCTION_KEY:
            headers['x-functions-key'] = AZURE_FUNCTION_KEY
        
        # Add LWA token for authenticated requests
        if lwa_token and not skip_auth:
            headers['Authorization'] = f'Bearer {lwa_token}'
            print(f"Forwarding validated LWA token to Azure Function")
        elif skip_auth:
            print(f"Forwarding Authorization directive to Azure Function without pre-authentication")
        
        # Forward the request to Azure Function
        response = http.request(
            'POST',
            AZURE_FUNCTION_URL,
            body=json.dumps(event),
            headers=headers,
            timeout=30.0
        )
        
        print(f"Azure Function response status: {response.status}")
        print(f"Azure Function response: {response.data.decode('utf-8')}")
        
        # Parse and return the response
        if response.status == 200:
            azure_response = json.loads(response.data.decode('utf-8'))
            print(f"Returning response to Alexa: {json.dumps(azure_response, indent=2)}")
            return azure_response
        else:
            print(f"Error from Azure Function: {response.status} - {response.data.decode('utf-8')}")
            return create_error_response()
            
    except Exception as e:
        print(f"Error forwarding to Azure Function: {str(e)}")
        return create_error_response()

def create_authentication_error_response():
    """Create an authentication error response for Alexa Smart Home"""
    return {
        "event": {
            "header": {
                "namespace": "Alexa",
                "name": "ErrorResponse",
                "payloadVersion": "3",
                "messageId": "auth-error-response"
            },
            "payload": {
                "type": "INVALID_AUTHORIZATION_CREDENTIAL",
                "message": "Authentication failed - invalid or missing access token"
            }
        }
    }

def create_accept_grant_response(correlation_message_id=None):
    """Create an immediate AcceptGrant.Response for Alexa"""
    return {
        "event": {
            "header": {
                "namespace": "Alexa.Authorization",
                "name": "AcceptGrant.Response",
                "payloadVersion": "3",
                "messageId": str(uuid.uuid4())
            },
            "payload": {}
        }
    }

def forward_to_azure_function_async(event, request_id):
    """
    Asynchronously forward AcceptGrant to Azure Function
    This runs in a separate thread and doesn't return to Lambda handler
    """
    try:
        print(f"[{request_id}] Starting async AcceptGrant processing")
        
        # Prepare headers for Azure Function call
        headers = {
            'Content-Type': 'application/json',
            'User-Agent': 'AWS-Lambda-Proxy-Async/1.0',
            'X-Lambda-Request-ID': request_id
        }
        
        # Add function key if provided
        if AZURE_FUNCTION_KEY:
            headers['x-functions-key'] = AZURE_FUNCTION_KEY
        
        print(f"[{request_id}] Forwarding AcceptGrant to Azure Function asynchronously")
        
        # Forward the request to Azure Function
        response = http.request(
            'POST',
            AZURE_FUNCTION_URL,
            body=json.dumps(event),
            headers=headers,
            timeout=60.0  # Longer timeout for async processing
        )
        
        print(f"[{request_id}] Async Azure Function response status: {response.status}")
        print(f"[{request_id}] Async Azure Function response: {response.data.decode('utf-8')}")
        
        if response.status == 200:
            print(f"[{request_id}] AcceptGrant processed successfully by Azure Function")
        else:
            print(f"[{request_id}] Error in async AcceptGrant processing: {response.status}")
            
    except Exception as e:
        print(f"[{request_id}] Error in async AcceptGrant processing: {str(e)}")

def create_error_response():
    """Create a generic error response for Alexa Smart Home"""
    return {
        "event": {
            "header": {
                "namespace": "Alexa",
                "name": "ErrorResponse",
                "payloadVersion": "3",
                "messageId": "error-response"
            },
            "payload": {
                "type": "INTERNAL_ERROR",
                "message": "Unable to process request"
            }
        }
    }
