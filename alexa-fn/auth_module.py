"""
Authentication Module for Alexa Skills

This module handles authentication and token validation for Amazon Alexa skills,
including OAuth 2.0 tokens and AWS Login with Amazon (LWA) token validation.
"""

import json
import logging
import os
import requests

logger = logging.getLogger(__name__)

# Authentication configuration
AMAZON_LWA_TOKEN_URL = os.environ.get('AMAZON_LWA_TOKEN_URL', 'https://api.amazon.com/auth/o2/tokeninfo')
ALLOWED_USER_ID = os.environ.get('ALLOWED_USER_ID', '')
BYPASS_AUTH = os.environ.get('BYPASS_AUTH', 'false').lower() == 'true'


def validate_amazon_token(access_token):
    """
    Validate Amazon access token and return user information
    Returns tuple: (is_valid, user_id, error_message)
    """
    logger.info("Validating Amazon access token")
    
    try:
        if not access_token:
            logger.warning("No access token provided for validation")
            return False, None, "No access token provided"
        
        # Call Amazon's token validation endpoint
        params = {'access_token': access_token}
        response = requests.get(AMAZON_LWA_TOKEN_URL, params=params, timeout=10)
        
        logger.info(f"Token validation response status: {response.status_code}")
        
        if response.status_code == 200:
            token_data = response.json()
            user_id = token_data.get('user_id')
            
            if user_id:
                logger.info(f"Token validation successful for user: {user_id}")
                return True, user_id, None
            else:
                logger.warning("Valid token but no user_id in response")
                return False, None, "Invalid token format"
        else:
            logger.error(f"Token validation failed with status {response.status_code}")
            return False, None, f"Token validation failed: {response.status_code}"
            
    except Exception as e:
        logger.error(f"Error validating access token: {str(e)}")
        return False, None, f"Token validation error: {str(e)}"


def extract_token_from_alexa_request(req_body, req_headers=None):
    """
    Extract access token from Alexa request or Authorization header
    
    Priority order:
    1. Authorization header (from Lambda proxy)
    2. Smart Home directive tokens
    3. Custom skill session tokens
    """
    
    # First check Authorization header (from Lambda proxy)
    if req_headers:
        auth_header = req_headers.get('Authorization') or req_headers.get('authorization')
        if auth_header and auth_header.startswith('Bearer '):
            token = auth_header[7:]  # Remove 'Bearer ' prefix
            logger.info("Found access token in Authorization header")
            return token
    
    # Check for Smart Home directive tokens
    if 'directive' in req_body:
        directive = req_body['directive']
        
        # Check endpoint scope token (most common for Smart Home)
        if 'endpoint' in directive and 'scope' in directive['endpoint']:
            scope = directive['endpoint']['scope']
            if 'token' in scope:
                logger.info("Found access token in directive.endpoint.scope.token")
                return scope['token']
        
        # Check payload scope token
        if 'payload' in directive and 'scope' in directive['payload']:
            scope = directive['payload']['scope']
            if 'token' in scope:
                logger.info("Found access token in directive.payload.scope.token")
                return scope['token']
    
    # Check for Custom skill access token
    if 'context' in req_body and 'System' in req_body['context']:
        system = req_body['context']['System']
        if 'user' in system and 'accessToken' in system['user']:
            logger.info("Found access token in context.System.user.accessToken")
            return system['user']['accessToken']
    
    # Check for session access token (Custom skills)
    if 'session' in req_body and 'user' in req_body['session']:
        user = req_body['session']['user']
        if 'accessToken' in user:
            logger.info("Found access token in session.user.accessToken")
            return user['accessToken']
    
    logger.warning("No access token found in Alexa request")
    return None


def extract_token_from_http_request(req):
    """
    Extract access token from HTTP request headers or query parameters
    Returns the access token or None if not found
    """
    logger.info("Extracting access token from HTTP request")
    
    try:
        # Check Authorization header (Bearer token)
        auth_header = req.headers.get('Authorization', '')
        logger.info(f"Authorization header present: {'Yes' if auth_header else 'No'}")
        
        if auth_header.startswith('Bearer '):
            token = auth_header[7:]  # Remove 'Bearer ' prefix
            logger.info(f"Found Bearer token in Authorization header (length: {len(token)})")
            return token
        elif auth_header:
            logger.warning(f"Authorization header present but not Bearer format: {auth_header[:20]}...")
        
        # Check query parameter
        access_token = req.params.get('access_token')
        if access_token:
            logger.info(f"Found access_token in query parameters (length: {len(access_token)})")
            return access_token
        else:
            logger.info("No access_token query parameter found")
            
        # Check request body for token
        try:
            req_body = req.get_json()
            if req_body and 'access_token' in req_body:
                token = req_body['access_token']
                logger.info(f"Found access_token in request body (length: {len(token)})")
                return token
            else:
                logger.info("No access_token found in request body")
        except Exception as body_error:
            logger.info(f"Could not parse request body for token: {str(body_error)}")
            
        logger.warning("No access token found in Authorization header, query params, or request body")
        return None
        
    except Exception as e:
        logger.error(f"Error extracting token from HTTP request: {str(e)}")
        return None


def check_user_authorization(user_id, request_id=None):
    """
    Check if user is authorized to access the system
    Returns tuple: (is_authorized, error_message)
    """
    if not ALLOWED_USER_ID:
        # No user restriction configured
        return True, None
    
    if user_id == ALLOWED_USER_ID:
        logger.info(f"[{request_id}] User {user_id} is authorized")
        return True, None
    else:
        logger.warning(f"[{request_id}] User {user_id} is not authorized")
        return False, f"User not authorized: {user_id}"


def authenticate_smart_home_request(req_body, req_headers, request_id):
    """
    Authenticate Smart Home directive using OAuth 2.0 or LWA token
    Returns tuple: (is_authenticated, user_id, error_message)
    """
    # Skip authentication if bypass is enabled
    if BYPASS_AUTH:
        logger.info(f"[{request_id}] Authentication bypassed")
        return True, 'bypass', None
    
    # Extract access token from Smart Home directive or headers
    access_token = extract_token_from_alexa_request(req_body, req_headers)
    
    if not access_token:
        logger.warning(f"[{request_id}] No access token found in Smart Home directive")
        return False, None, "Authentication required"
    
    # First try OAuth token validation (check if token is in our storage)
    user_id = validate_oauth_token(access_token, request_id)
    if user_id:
        logger.info(f"[{request_id}] OAuth token validation successful for user: {user_id}")
        
        # Check authorization
        is_authorized, auth_error = check_user_authorization(user_id, request_id)
        if not is_authorized:
            return False, user_id, auth_error
        
        return True, user_id, None
    
    # Fallback to LWA token validation
    is_valid, user_id, error_msg = validate_amazon_token(access_token)
    if not is_valid:
        logger.warning(f"[{request_id}] Invalid access token: {error_msg}")
        return False, None, f"Invalid access token: {error_msg}"
    
    # Check authorization
    is_authorized, auth_error = check_user_authorization(user_id, request_id)
    if not is_authorized:
        return False, user_id, auth_error
    
    logger.info(f"[{request_id}] LWA token authentication successful for user: {user_id}")
    return True, user_id, None

def validate_oauth_token(access_token, request_id):
    """
    Validate OAuth token from our token storage
    Returns user_id if valid, None if not found or invalid
    """
    try:
        # Import here to avoid circular imports
        from oauth_module import token_manager
        
        # Check all stored tokens to find matching access token
        # In production, you'd want a more efficient lookup mechanism
        logger.info(f"[{request_id}] Checking OAuth token in storage")
        
        # For now, we'll implement a simple approach
        # In production, consider using a token hash lookup table
        
        # This is a placeholder - you'd need to implement proper token lookup
        # based on your token storage strategy
        
        return None  # Will fall back to LWA validation
        
    except Exception as e:
        logger.warning(f"[{request_id}] Error validating OAuth token: {str(e)}")
        return None


def authenticate_request(req, request_id, is_alexa_request=False):
    """
    Authenticate a request (either Alexa or HTTP)
    Returns tuple: (is_authenticated, user_id, error_message)
    """
    # Skip authentication if bypass is enabled
    if BYPASS_AUTH:
        logger.info(f"[{request_id}] Authentication bypassed")
        return True, 'bypass', None
    
    # Extract token based on request type
    if is_alexa_request:
        req_body = req.get_json() if hasattr(req, 'get_json') else req
        access_token = extract_token_from_alexa_request(req_body)
    else:
        access_token = extract_token_from_http_request(req)
    
    if not access_token:
        logger.warning(f"[{request_id}] No access token provided")
        return False, None, "Authentication required"
    
    # Validate token
    is_valid, user_id, error_msg = validate_amazon_token(access_token)
    if not is_valid:
        logger.warning(f"[{request_id}] Invalid access token: {error_msg}")
        return False, None, f"Invalid access token: {error_msg}"
    
    # Check authorization
    is_authorized, auth_error = check_user_authorization(user_id, request_id)
    if not is_authorized:
        return False, user_id, auth_error
    
    logger.info(f"[{request_id}] Authentication successful for user: {user_id}")
    return True, user_id, None
