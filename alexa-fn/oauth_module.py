"""
OAuth 2.0 Module for Alexa Smart Home Skills

This module handles OAuth 2.0 authorization code flow, token management,
and secure storage for Amazon Alexa Smart Home skill integration.

OAuth Credential Configuration:
-----------------------------

1. Smart Home Skill OAuth Credentials (ALEXA_SMART_HOME_*):
   - Used for AcceptGrant authorization code exchange
   - These are the OAuth client credentials from your Smart Home skill in Alexa Developer Console
   - Required for: AcceptGrant directive processing, token refresh operations
   - Format: amzn1.application-oa2-client.xxxxxxxxxxxxxxxxxxxxxxxxx

2. LWA (Login with Amazon) Credentials (ALEXA_LWA_*):
   - Used for API authentication and testing
   - These are for Login with Amazon token generation
   - Required for: Event gateway authentication, API testing, proactive events
   - Format: Usually same as Smart Home credentials but can be different for testing

Environment Variables:
- ALEXA_SMART_HOME_CLIENT_ID: Smart Home skill OAuth client ID
- ALEXA_SMART_HOME_CLIENT_SECRET: Smart Home skill OAuth client secret  
- ALEXA_SMART_HOME_REDIRECT_URI: Smart Home skill OAuth redirect URI
- ALEXA_LWA_CLIENT_ID: LWA client ID for API authentication
- ALEXA_LWA_CLIENT_SECRET: LWA client secret for API authentication
"""

import json
import logging
import os
import requests
import time
import uuid
from datetime import datetime, timedelta
from typing import Dict, Optional, Tuple
import hashlib
import base64

# Azure Key Vault imports
from azure.keyvault.secrets import SecretClient
from azure.identity import DefaultAzureCredential
from azure.core.exceptions import ResourceNotFoundError

logger = logging.getLogger(__name__)

# OAuth configuration
ALEXA_TOKEN_URL = "https://api.amazon.com/auth/o2/token"
ALEXA_EVENT_GATEWAY_URL = "https://api.amazonalexa.com/v3/events"

# Smart Home Skill OAuth Configuration (for AcceptGrant authorization code exchange)
# These are the OAuth client credentials from the Alexa Developer Console for your Smart Home skill
SMART_HOME_CLIENT_ID = os.environ.get('ALEXA_SMART_HOME_CLIENT_ID', '')
SMART_HOME_CLIENT_SECRET = os.environ.get('ALEXA_SMART_HOME_CLIENT_SECRET', '')
SMART_HOME_REDIRECT_URI = os.environ.get('ALEXA_SMART_HOME_REDIRECT_URI', '')

# LWA (Login with Amazon) Configuration (for API authentication and testing)
# These are different credentials used for LWA token generation and API testing
LWA_CLIENT_ID = os.environ.get('ALEXA_LWA_CLIENT_ID', '')
LWA_CLIENT_SECRET = os.environ.get('ALEXA_LWA_CLIENT_SECRET', '')

# Token storage configuration (in production, use Azure Key Vault or Cosmos DB)
TOKEN_STORAGE_TYPE = os.environ.get('TOKEN_STORAGE_TYPE', 'memory')  # memory, file, or azure_key_vault
TOKEN_FILE_PATH = os.environ.get('TOKEN_FILE_PATH', '/tmp/alexa_tokens.json')

# Azure Key Vault configuration
AZURE_KEY_VAULT_URL = os.environ.get('AZURE_KEY_VAULT_URL', '')

# Initialize Azure Key Vault client (only if using Key Vault storage)
_keyvault_client = None
if TOKEN_STORAGE_TYPE == 'azure_key_vault' and AZURE_KEY_VAULT_URL:
    try:
        credential = DefaultAzureCredential()
        _keyvault_client = SecretClient(vault_url=AZURE_KEY_VAULT_URL, credential=credential)
        logger.info("Azure Key Vault client initialized successfully")
    except Exception as e:
        logger.error(f"Failed to initialize Azure Key Vault client: {str(e)}")
        _keyvault_client = None

# In-memory token storage (for development/testing)
_token_cache = {}

class TokenManager:
    """Manages OAuth 2.0 tokens for Alexa Smart Home skills"""
    
    def __init__(self):
        self.storage_type = TOKEN_STORAGE_TYPE
        logger.info(f"TokenManager initialized with storage type: {self.storage_type}")
    
    def _get_user_key(self, user_id: str) -> str:
        """Generate a secure key for user token storage"""
        return hashlib.sha256(user_id.encode()).hexdigest()
    
    def store_tokens(self, user_id: str, tokens: Dict) -> bool:
        """Store tokens securely"""
        try:
            user_key = self._get_user_key(user_id)
            tokens['updated_at'] = datetime.utcnow().isoformat()
            
            if self.storage_type == 'memory':
                _token_cache[user_key] = tokens
                logger.info(f"Tokens stored in memory for user: {user_id}")
                return True
            
            elif self.storage_type == 'file':
                # Load existing tokens
                all_tokens = {}
                if os.path.exists(TOKEN_FILE_PATH):
                    with open(TOKEN_FILE_PATH, 'r') as f:
                        all_tokens = json.load(f)
                
                # Update with new tokens
                all_tokens[user_key] = tokens
                
                # Save back to file
                os.makedirs(os.path.dirname(TOKEN_FILE_PATH), exist_ok=True)
                with open(TOKEN_FILE_PATH, 'w') as f:
                    json.dump(all_tokens, f, indent=2)
                
                logger.info(f"Tokens stored to file for user: {user_id}")
                return True
            
            elif self.storage_type == 'azure_key_vault':
                if not _keyvault_client:
                    logger.error("Azure Key Vault client not initialized")
                    # Fallback to memory storage
                    _token_cache[user_key] = tokens
                    return True
                
                try:
                    # Store tokens as JSON in Key Vault secret
                    secret_name = f"oauth-tokens-{user_key}"
                    secret_value = json.dumps(tokens)
                    
                    _keyvault_client.set_secret(secret_name, secret_value)
                    logger.info(f"Tokens stored in Azure Key Vault for user: {user_id}")
                    return True
                    
                except Exception as kv_error:
                    logger.error(f"Error storing tokens in Key Vault for user {user_id}: {str(kv_error)}")
                    # Fallback to memory storage
                    _token_cache[user_key] = tokens
                    return True
            
            else:
                logger.error(f"Unknown storage type: {self.storage_type}")
                return False
                
        except Exception as e:
            logger.error(f"Error storing tokens for user {user_id}: {str(e)}")
            return False
    
    def get_tokens(self, user_id: str) -> Optional[Dict]:
        """Retrieve tokens for a user"""
        try:
            user_key = self._get_user_key(user_id)
            
            if self.storage_type == 'memory':
                return _token_cache.get(user_key)
            
            elif self.storage_type == 'file':
                if not os.path.exists(TOKEN_FILE_PATH):
                    return None
                
                with open(TOKEN_FILE_PATH, 'r') as f:
                    all_tokens = json.load(f)
                
                return all_tokens.get(user_key)
            
            elif self.storage_type == 'azure_key_vault':
                if not _keyvault_client:
                    logger.error("Azure Key Vault client not initialized")
                    # Fallback to memory storage
                    return _token_cache.get(user_key)
                
                try:
                    secret_name = f"oauth-tokens-{user_key}"
                    secret = _keyvault_client.get_secret(secret_name)
                    tokens = json.loads(secret.value)
                    logger.debug(f"Tokens retrieved from Azure Key Vault for user: {user_id}")
                    return tokens
                    
                except ResourceNotFoundError:
                    logger.debug(f"No tokens found in Key Vault for user: {user_id}")
                    return None
                    
                except Exception as kv_error:
                    logger.error(f"Error retrieving tokens from Key Vault for user {user_id}: {str(kv_error)}")
                    # Fallback to memory storage
                    return _token_cache.get(user_key)
            
            else:
                logger.error(f"Unknown storage type: {self.storage_type}")
                return None
                
        except Exception as e:
            logger.error(f"Error retrieving tokens for user {user_id}: {str(e)}")
            return None
    
    def delete_tokens(self, user_id: str) -> bool:
        """Delete tokens for a user"""
        try:
            user_key = self._get_user_key(user_id)
            
            if self.storage_type == 'memory':
                if user_key in _token_cache:
                    del _token_cache[user_key]
                    logger.info(f"Tokens deleted from memory for user: {user_id}")
                return True
            
            elif self.storage_type == 'file':
                if not os.path.exists(TOKEN_FILE_PATH):
                    return True
                
                with open(TOKEN_FILE_PATH, 'r') as f:
                    all_tokens = json.load(f)
                
                if user_key in all_tokens:
                    del all_tokens[user_key]
                    
                    with open(TOKEN_FILE_PATH, 'w') as f:
                        json.dump(all_tokens, f, indent=2)
                    
                    logger.info(f"Tokens deleted from file for user: {user_id}")
                
                return True
            
            elif self.storage_type == 'azure_key_vault':
                if not _keyvault_client:
                    logger.error("Azure Key Vault client not initialized")
                    # Fallback to memory storage
                    if user_key in _token_cache:
                        del _token_cache[user_key]
                    return True
                
                try:
                    secret_name = f"oauth-tokens-{user_key}"
                    
                    # Check if secret exists before trying to delete
                    try:
                        _keyvault_client.get_secret(secret_name)
                        # If we get here, secret exists, so delete it
                        _keyvault_client.begin_delete_secret(secret_name)
                        logger.info(f"Tokens deleted from Azure Key Vault for user: {user_id}")
                    except ResourceNotFoundError:
                        # Secret doesn't exist, which is fine
                        logger.debug(f"No tokens to delete in Key Vault for user: {user_id}")
                    
                    return True
                    
                except Exception as kv_error:
                    logger.error(f"Error deleting tokens from Key Vault for user {user_id}: {str(kv_error)}")
                    # Still try to delete from memory cache
                    if user_key in _token_cache:
                        del _token_cache[user_key]
                    return True
            
            else:
                logger.error(f"Unknown storage type: {self.storage_type}")
                return False
                
        except Exception as e:
            logger.error(f"Error deleting tokens for user {user_id}: {str(e)}")
            return False

# Global token manager instance
token_manager = TokenManager()

def extract_user_id_from_token(access_token: str, request_id: str) -> Optional[str]:
    """
    Extract user ID from Alexa access token
    Alexa access tokens may be JWTs or opaque tokens, so we handle both cases
    """
    try:
        # First, log some basic info about the token
        logger.info(f"[{request_id}] Attempting to extract user ID from access token (length: {len(access_token)})")
        
        # Check if this looks like a JWT token (has 3 parts separated by dots)
        parts = access_token.split('.')
        if len(parts) == 3:
            logger.info(f"[{request_id}] Token appears to be JWT format, attempting to decode")
            
            # Decode the payload (second part)
            payload_encoded = parts[1]
            
            # Add padding if needed for base64 decoding
            padding = len(payload_encoded) % 4
            if padding:
                payload_encoded += '=' * (4 - padding)
            
            try:
                payload_bytes = base64.urlsafe_b64decode(payload_encoded)
                payload = json.loads(payload_bytes.decode('utf-8'))
                
                logger.debug(f"[{request_id}] JWT payload decoded successfully")
                logger.debug(f"[{request_id}] Available payload keys: {list(payload.keys())}")
                
                # Extract user ID from the token payload
                # Alexa tokens typically have 'sub' (subject) or 'user_id' field
                user_id = payload.get('sub') or payload.get('user_id') or payload.get('userId') or payload.get('aud')
                
                if user_id:
                    logger.info(f"[{request_id}] Extracted user ID from JWT access token: {user_id}")
                    return user_id
                else:
                    logger.warning(f"[{request_id}] No user ID found in JWT payload")
                    logger.debug(f"[{request_id}] Full JWT payload: {json.dumps(payload, indent=2)}")
                    
            except (json.JSONDecodeError, UnicodeDecodeError) as e:
                logger.error(f"[{request_id}] Error decoding JWT payload: {str(e)}")
                logger.debug(f"[{request_id}] Payload encoded: {payload_encoded}")
        
        # If not JWT or JWT decoding failed, return None for opaque tokens
        # Opaque tokens don't contain user identification information that we can extract
        # The calling code should handle this by using a configured user ID (like ALLOWED_USER_ID)
        logger.info(f"[{request_id}] Token is not JWT or JWT decode failed - cannot extract user ID from opaque token")
        logger.info(f"[{request_id}] Caller should use a configured user ID for opaque tokens")
        
        return None
                
    except Exception as e:
        logger.error(f"[{request_id}] Error extracting user ID from token: {str(e)}")
        logger.error(f"[{request_id}] Token preview: {access_token[:50]}...")
        return None

def exchange_authorization_code(auth_code: str, user_id: str, request_id: str) -> Tuple[bool, Optional[Dict], Optional[str]]:
    """
    Exchange authorization code for access and refresh tokens using Smart Home skill OAuth credentials
    Returns: (success, tokens_dict, error_message)
    """
    logger.info(f"[{request_id}] Exchanging authorization code for tokens using Smart Home OAuth credentials")
    
    if not SMART_HOME_CLIENT_ID or not SMART_HOME_CLIENT_SECRET:
        error_msg = "Smart Home OAuth client credentials not configured"
        logger.error(f"[{request_id}] {error_msg}")
        logger.error(f"[{request_id}] Required: ALEXA_SMART_HOME_CLIENT_ID and ALEXA_SMART_HOME_CLIENT_SECRET")
        return False, None, error_msg
    
    try:
        # Prepare token request using Smart Home skill credentials
        token_data = {
            'grant_type': 'authorization_code',
            'code': auth_code,
            'client_id': SMART_HOME_CLIENT_ID,
            'client_secret': SMART_HOME_CLIENT_SECRET,
        }
        
        if SMART_HOME_REDIRECT_URI:
            token_data['redirect_uri'] = SMART_HOME_REDIRECT_URI
        
        # Request tokens from Alexa
        logger.info(f"[{request_id}] Requesting tokens from Alexa OAuth endpoint using Smart Home credentials")
        response = requests.post(
            ALEXA_TOKEN_URL,
            data=token_data,
            headers={'Content-Type': 'application/x-www-form-urlencoded'},
            timeout=10
        )
        
        logger.info(f"[{request_id}] Token exchange response status: {response.status_code}")
        
        if response.status_code == 200:
            tokens = response.json()
            
            # Extract actual user ID from the access token
            access_token = tokens.get('access_token')
            if not access_token:
                error_msg = "No access token in response"
                logger.error(f"[{request_id}] {error_msg}")
                return False, None, error_msg
            
            # Get the real user ID from the access token
            actual_user_id = extract_user_id_from_token(access_token, request_id)
            if not actual_user_id:
                # Fallback to using the provided user_id if we can't extract from access token
                logger.warning(f"[{request_id}] Could not extract user ID from access token, using provided user_id as fallback")
                actual_user_id = user_id
            
            # Add metadata
            tokens['user_id'] = actual_user_id
            tokens['original_user_token'] = user_id  # Keep the original token for reference
            tokens['obtained_at'] = datetime.utcnow().isoformat()
            
            # Calculate expiration time
            if 'expires_in' in tokens:
                expires_at = datetime.utcnow() + timedelta(seconds=tokens['expires_in'])
                tokens['expires_at'] = expires_at.isoformat()
            
            # Store tokens securely using the actual user ID
            if token_manager.store_tokens(actual_user_id, tokens):
                logger.info(f"[{request_id}] Successfully exchanged authorization code and stored tokens for user: {actual_user_id}")
                return True, tokens, None
            else:
                error_msg = "Failed to store tokens"
                logger.error(f"[{request_id}] {error_msg}")
                return False, None, error_msg
        
        else:
            error_msg = f"Token exchange failed: {response.status_code} - {response.text}"
            logger.error(f"[{request_id}] {error_msg}")
            return False, None, error_msg
            
    except Exception as e:
        error_msg = f"Error exchanging authorization code: {str(e)}"
        logger.error(f"[{request_id}] {error_msg}")
        return False, None, error_msg

def refresh_access_token(user_id: str, request_id: str) -> Tuple[bool, Optional[Dict], Optional[str]]:
    """
    Refresh access token using refresh token and Smart Home skill OAuth credentials
    Returns: (success, tokens_dict, error_message)
    """
    logger.info(f"[{request_id}] Refreshing access token for user: {user_id}")
    
    # Get current tokens
    current_tokens = token_manager.get_tokens(user_id)
    if not current_tokens:
        error_msg = "No tokens found for user"
        logger.error(f"[{request_id}] {error_msg}")
        return False, None, error_msg
    
    refresh_token = current_tokens.get('refresh_token')
    if not refresh_token:
        error_msg = "No refresh token available"
        logger.error(f"[{request_id}] {error_msg}")
        return False, None, error_msg
    
    if not SMART_HOME_CLIENT_ID or not SMART_HOME_CLIENT_SECRET:
        error_msg = "Smart Home OAuth client credentials not configured"
        logger.error(f"[{request_id}] {error_msg}")
        logger.error(f"[{request_id}] Required: ALEXA_SMART_HOME_CLIENT_ID and ALEXA_SMART_HOME_CLIENT_SECRET")
        return False, None, error_msg
    
    try:
        # Prepare refresh request using Smart Home skill credentials
        refresh_data = {
            'grant_type': 'refresh_token',
            'refresh_token': refresh_token,
            'client_id': SMART_HOME_CLIENT_ID,
            'client_secret': SMART_HOME_CLIENT_SECRET,
        }
        
        # Request new tokens from Alexa
        logger.info(f"[{request_id}] Requesting token refresh from Alexa OAuth endpoint using Smart Home credentials")
        response = requests.post(
            ALEXA_TOKEN_URL,
            data=refresh_data,
            headers={'Content-Type': 'application/x-www-form-urlencoded'},
            timeout=10
        )
        
        logger.info(f"[{request_id}] Token refresh response status: {response.status_code}")
        
        if response.status_code == 200:
            new_tokens = response.json()
            
            # Preserve refresh token if not provided in response
            if 'refresh_token' not in new_tokens:
                new_tokens['refresh_token'] = refresh_token
            
            # Add metadata
            new_tokens['user_id'] = user_id
            new_tokens['obtained_at'] = datetime.utcnow().isoformat()
            new_tokens['refreshed_at'] = datetime.utcnow().isoformat()
            
            # Calculate expiration time
            if 'expires_in' in new_tokens:
                expires_at = datetime.utcnow() + timedelta(seconds=new_tokens['expires_in'])
                new_tokens['expires_at'] = expires_at.isoformat()
            
            # Store updated tokens
            if token_manager.store_tokens(user_id, new_tokens):
                logger.info(f"[{request_id}] Successfully refreshed and stored tokens")
                return True, new_tokens, None
            else:
                error_msg = "Failed to store refreshed tokens"
                logger.error(f"[{request_id}] {error_msg}")
                return False, None, error_msg
        
        else:
            error_msg = f"Token refresh failed: {response.status_code} - {response.text}"
            logger.error(f"[{request_id}] {error_msg}")
            return False, None, error_msg
            
    except Exception as e:
        error_msg = f"Error refreshing access token: {str(e)}"
        logger.error(f"[{request_id}] {error_msg}")
        return False, None, error_msg

def get_valid_access_token(user_id: str, request_id: str) -> Tuple[bool, Optional[str], Optional[str]]:
    """
    Get a valid access token, refreshing if necessary
    Returns: (success, access_token, error_message)
    """
    logger.info(f"[{request_id}] Getting valid access token for user: {user_id}")
    
    # Get current tokens
    tokens = token_manager.get_tokens(user_id)
    if not tokens:
        error_msg = "No tokens found for user"
        logger.warning(f"[{request_id}] {error_msg}")
        return False, None, error_msg
    
    access_token = tokens.get('access_token')
    if not access_token:
        error_msg = "No access token available"
        logger.error(f"[{request_id}] {error_msg}")
        return False, None, error_msg
    
    # Check if token is expired
    expires_at_str = tokens.get('expires_at')
    if expires_at_str:
        try:
            expires_at = datetime.fromisoformat(expires_at_str.replace('Z', '+00:00'))
            # Refresh if expires within next 5 minutes
            if expires_at <= datetime.utcnow() + timedelta(minutes=5):
                logger.info(f"[{request_id}] Access token expires soon, refreshing")
                success, new_tokens, error = refresh_access_token(user_id, request_id)
                if success and new_tokens:
                    return True, new_tokens.get('access_token'), None
                else:
                    logger.error(f"[{request_id}] Failed to refresh token: {error}")
                    return False, None, f"Token refresh failed: {error}"
        except Exception as e:
            logger.warning(f"[{request_id}] Error parsing token expiration: {str(e)}")
    
    logger.info(f"[{request_id}] Using existing access token")
    return True, access_token, None

def get_user_id_from_access_token(access_token: str, request_id: str) -> Tuple[bool, Optional[str], Optional[str]]:
    """
    Extract user ID from an access token for Smart Home directive processing
    This is used when we receive a Smart Home directive with an access token
    and need to retrieve the stored OAuth tokens for that user
    Returns: (success, user_id, error_message)
    """
    logger.info(f"[{request_id}] Extracting user ID from provided access token")
    
    user_id = extract_user_id_from_token(access_token, request_id)
    if user_id:
        return True, user_id, None
    else:
        error_msg = "Could not extract user ID from access token"
        logger.error(f"[{request_id}] {error_msg}")
        return False, None, error_msg

def send_change_report(user_id: str, endpoint_id: str, power_state: str, request_id: str) -> Tuple[bool, Optional[str]]:
    """
    Send ChangeReport to Alexa Event Gateway
    Returns: (success, error_message)
    """
    logger.info(f"[{request_id}] Sending ChangeReport for endpoint: {endpoint_id}, state: {power_state}")
    
    # Get valid access token
    success, access_token, error = get_valid_access_token(user_id, request_id)
    if not success:
        return False, f"Authentication failed: {error}"
    
    try:
        # Create ChangeReport event
        event = {
            "event": {
                "header": {
                    "namespace": "Alexa",
                    "name": "ChangeReport",
                    "payloadVersion": "3",
                    "messageId": str(uuid.uuid4())
                },
                "endpoint": {
                    "scope": {
                        "type": "BearerToken",
                        "token": access_token
                    },
                    "endpointId": endpoint_id
                },
                "payload": {
                    "change": {
                        "cause": {
                            "type": "VOICE_INTERACTION"
                        },
                        "properties": [
                            {
                                "namespace": "Alexa.PowerController",
                                "name": "powerState",
                                "value": power_state,
                                "timeOfSample": datetime.utcnow().isoformat() + "Z",
                                "uncertaintyInMilliseconds": 500
                            }
                        ]
                    }
                }
            },
            "context": {
                "properties": [
                    {
                        "namespace": "Alexa.PowerController",
                        "name": "powerState",
                        "value": power_state,
                        "timeOfSample": datetime.utcnow().isoformat() + "Z",
                        "uncertaintyInMilliseconds": 500
                    }
                ]
            }
        }
        
        # Send to Alexa Event Gateway
        headers = {
            'Authorization': f'Bearer {access_token}',
            'Content-Type': 'application/json'
        }
        
        logger.info(f"[{request_id}] Sending ChangeReport to Alexa Event Gateway")
        response = requests.post(
            ALEXA_EVENT_GATEWAY_URL,
            json=event,
            headers=headers,
            timeout=10
        )
        
        logger.info(f"[{request_id}] ChangeReport response status: {response.status_code}")
        
        if response.status_code == 202:
            logger.info(f"[{request_id}] ChangeReport sent successfully")
            return True, None
        else:
            error_msg = f"ChangeReport failed: {response.status_code} - {response.text}"
            logger.error(f"[{request_id}] {error_msg}")
            return False, error_msg
            
    except Exception as e:
        error_msg = f"Error sending ChangeReport: {str(e)}"
        logger.error(f"[{request_id}] {error_msg}")
        return False, error_msg

def revoke_tokens(user_id: str, request_id: str) -> Tuple[bool, Optional[str]]:
    """
    Revoke tokens and clean up storage
    Returns: (success, error_message)
    """
    logger.info(f"[{request_id}] Revoking tokens for user: {user_id}")
    
    try:
        # Delete tokens from storage
        if token_manager.delete_tokens(user_id):
            logger.info(f"[{request_id}] Tokens revoked successfully")
            return True, None
        else:
            error_msg = "Failed to delete tokens"
            logger.error(f"[{request_id}] {error_msg}")
            return False, error_msg
            
    except Exception as e:
        error_msg = f"Error revoking tokens: {str(e)}"
        logger.error(f"[{request_id}] {error_msg}")
        return False, error_msg