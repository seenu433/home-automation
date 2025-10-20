"""
Azure Function App for Alexa Skills Kit Integration

This function app provides an HTTP endpoint for handling Alexa skill requests
and integrates with Azure Service Bus for device control messaging.
"""

import azure.functions as func
import json
import logging
import os
import uuid
from datetime import datetime, timedelta

# Import custom modules
from servicebus_module import (
    send_to_servicebus_queue, 
    get_queue_name, 
    get_servicebus_client, 
    receive_from_servicebus_queue,
    complete_message,
    abandon_message,
    get_servicebus_queue_info
)
from auth_module import authenticate_request, authenticate_smart_home_request
from oauth_module import (
    exchange_authorization_code,
    refresh_access_token,
    get_valid_access_token,
    get_user_id_from_access_token,
    extract_user_id_from_token,
    send_change_report,
    revoke_tokens,
    token_manager
)
import requests
import urllib.parse

# Configure logging with detailed format
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(funcName)s:%(lineno)d - %(message)s'
)
logger = logging.getLogger(__name__)

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

# Load virtual devices configuration
def load_virtual_devices_config():
    """Load virtual devices configuration from JSON file"""
    try:
        config_path = os.path.join(os.path.dirname(__file__), 'virtual-devices-config.json')
        logger.info(f"Loading virtual devices config from: {config_path}")
        
        with open(config_path, 'r') as f:
            config = json.load(f)
            logger.info(f"Successfully loaded config with {len(config.get('virtualDevices', {}))} virtual devices")
            logger.debug(f"Config contents: {json.dumps(config, indent=2)}")
            return config
    except FileNotFoundError as e:
        logger.error(f"Virtual devices config file not found at {config_path}: {str(e)}")
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON in virtual devices config: {str(e)}")
    except Exception as e:
        logger.error(f"Unexpected error loading virtual devices config: {str(e)}")
        # Return default configuration
        return {
            "virtualDevices": {
                "all": {"name": "All Devices", "friendlyNames": ["all"], "enablePressEvents": True},
                "bedroom": {"name": "Bedroom", "friendlyNames": ["bedroom"], "enablePressEvents": True},
                "downstairs": {"name": "Downstairs", "friendlyNames": ["downstairs"], "enablePressEvents": True},
                "upstairs": {"name": "Upstairs", "friendlyNames": ["upstairs"], "enablePressEvents": True}
            },
            "settings": {"defaultDevice": "all", "enableSmartHomeDevices": True}
        }

# Global config
VIRTUAL_DEVICES_CONFIG = load_virtual_devices_config()

# Environment variables
SERVICEBUS_CONNECTION_STRING = os.environ.get('sbcon', '')
DOOR_FN_BASE_URL = os.environ.get('DOOR_FN_BASE_URL', '')
DOOR_FN_API_KEY = os.environ.get('DOOR_FN_API_KEY', '')

# Alexa Smart Home configuration for production
ALEXA_EVENT_GATEWAY_URL = os.environ.get('ALEXA_EVENT_GATEWAY_URL', 'https://api.amazonalexa.com/v3/events')

# Smart Home Skill OAuth Configuration (for AcceptGrant authorization code exchange)
ALEXA_SMART_HOME_CLIENT_ID = os.environ.get('ALEXA_SMART_HOME_CLIENT_ID', '')
ALEXA_SMART_HOME_CLIENT_SECRET = os.environ.get('ALEXA_SMART_HOME_CLIENT_SECRET', '')

# LWA (Login with Amazon) Configuration (for API authentication and testing)
ALEXA_LWA_CLIENT_ID = os.environ.get('ALEXA_LWA_CLIENT_ID', '')
ALEXA_LWA_CLIENT_SECRET = os.environ.get('ALEXA_LWA_CLIENT_SECRET', '')

ALLOWED_USER_ID = os.environ.get('ALLOWED_USER_ID', '')

# Configuration for DoorEvent responses
DOOR_EVENT_SILENT_MODE = os.environ.get('DOOR_EVENT_SILENT_MODE', 'false').lower() == 'true'



# Supported door names (matching door-mapping.json)
SUPPORTED_DOORS = [
    "front door",
    "garage door", 
    "garage",
    "sliding door right",
    "sliding door left"
]

# Utility functions for Alexa responses
def create_alexa_response(speech_text, should_end_session=True):
    """Create a properly formatted Alexa response"""
    return {
        "version": "1.0",
        "response": {
            "outputSpeech": {
                "type": "PlainText",
                "text": speech_text
            },
            "shouldEndSession": should_end_session
        }
    }

def create_error_response(error_message):
    """Create an error response for Alexa"""
    return create_alexa_response(f"Sorry, {error_message}")

def extract_intent_name(req_body):
    """Extract intent name from Alexa request"""
    return req_body.get('request', {}).get('intent', {}).get('name', '')

def extract_slot_value(req_body, slot_name):
    """Extract slot value from Alexa request"""
    slots = req_body.get('request', {}).get('intent', {}).get('slots', {})
    slot = slots.get(slot_name, {})
    return slot.get('value', '')

def handle_custom_task(req_body, request_id):
    """Handle Custom Task requests from Alexa Routines"""
    try:
        task = req_body.get('task', {})
        task_name = task.get('name', '')
        task_version = task.get('version', '')
        task_input = task.get('input', {})
        
        logger.info(f"[{request_id}] Custom Task: {task_name} v{task_version}")
        logger.info(f"[{request_id}] Task Input: {task_input}")
        
        if task_name == 'ProcessDoorOpenEvent':
            # Extract door name parameter
            door_name = task_input.get('doorName', '')
            
            if not door_name:
                return create_task_error_response("Missing doorName parameter")
            
            logger.info(f"[{request_id}] Processing door open event via task: {door_name}")
            
            success = call_door_fn_api(door_name, 15, request_id)
            if success:
                return create_task_success_response(f"Door open event processed: {door_name}")
            else:
                return create_task_error_response("Failed to process door open event")
        
        elif task_name == 'ProcessDoorCloseEvent':
            # Extract door name parameter
            door_name = task_input.get('doorName', '')
            
            if not door_name:
                return create_task_error_response("Missing doorName parameter")
            
            logger.info(f"[{request_id}] Processing door close event via task: {door_name}")
            
            success = call_door_fn_cancel_api(door_name, request_id)
            if success:
                return create_task_success_response(f"Door close event processed: {door_name}")
            else:
                return create_task_error_response("Failed to process door close event")
        
        elif task_name == 'GetAnnouncement':
            # Extract device name parameter
            device_name = task_input.get('deviceName', 'all')
            
            logger.info(f"[{request_id}] Getting announcement via task for device: {device_name}")
            
            try:
                message_data = receive_from_servicebus_queue(device_name, request_id)
                
                if message_data:
                    # Extract message text
                    message_text = None
                    if message_data.get('parsed_body') and isinstance(message_data['parsed_body'], dict):
                        message_text = message_data['parsed_body'].get('message')
                    elif message_data.get('body'):
                        try:
                            body_json = json.loads(message_data['body'])
                            message_text = body_json.get('message')
                        except json.JSONDecodeError:
                            message_text = message_data['body']
                    
                    if not message_text:
                        message_text = "Message content could not be read"
                    
                    return create_task_success_response(message_text)
                else:
                    return create_task_success_response(f"No announcements waiting for {device_name}")
                    
            except Exception as e:
                logger.error(f"[{request_id}] Error retrieving announcement: {str(e)}")
                return create_task_error_response("Failed to retrieve announcement")
        
        else:
            return create_task_error_response(f"Unknown task: {task_name}")
            
    except Exception as e:
        logger.error(f"[{request_id}] Error handling custom task: {str(e)}")
        return create_task_error_response("Internal error processing task")

def create_task_success_response(output_speech):
    """Create a successful task response"""
    return {
        "version": "1.0",
        "response": {
            "outputSpeech": {
                "type": "PlainText",
                "text": output_speech
            },
            "shouldEndSession": True
        }
    }

def create_task_error_response(error_message):
    """Create an error task response"""
    return {
        "version": "1.0", 
        "response": {
            "outputSpeech": {
                "type": "PlainText",
                "text": f"Task failed: {error_message}"
            },
            "shouldEndSession": True
        }
    }

def call_door_fn_api(door_name, delay_seconds=300, request_id=""):
    """Call door-fn API to trigger door event processing"""
    if not DOOR_FN_BASE_URL or not DOOR_FN_API_KEY:
        logger.error(f"[{request_id}] Door-fn configuration missing")
        return False
    
    try:
        # Clean door name for API call
        door_name_clean = door_name.replace(" ", "_").lower()
        
        # Prepare the request
        params = {
            'door': door_name_clean,
            't': str(delay_seconds)
        }
        
        headers = {
            'x-functions-key': DOOR_FN_API_KEY
        }
        
        url = f"{DOOR_FN_BASE_URL}/api/ReceiveRequest"
        
        logger.info(f"[{request_id}] Calling door-fn API: {url} with door={door_name_clean}")
        
        response = requests.get(url, params=params, headers=headers, timeout=10)
        
        if response.status_code == 200:
            logger.info(f"[{request_id}] Door-fn API call successful: {response.text}")
            return True
        else:
            logger.error(f"[{request_id}] Door-fn API call failed: {response.status_code} - {response.text}")
            return False
            
    except requests.exceptions.Timeout:
        logger.error(f"[{request_id}] Door-fn API call timed out")
        return False
    except Exception as e:
        logger.error(f"[{request_id}] Error calling door-fn API: {str(e)}")
        return False

def call_door_fn_cancel_api(door_name, request_id=""):
    """Call door-fn CancelRequest API to cancel pending door notifications"""
    if not DOOR_FN_BASE_URL or not DOOR_FN_API_KEY:
        logger.error(f"[{request_id}] Door-fn configuration missing")
        return False
    
    try:
        # Clean door name for API call
        door_name_clean = door_name.replace(" ", "_").lower()
        
        # Prepare the request
        params = {
            'door': door_name_clean
        }
        
        headers = {
            'x-functions-key': DOOR_FN_API_KEY
        }
        
        url = f"{DOOR_FN_BASE_URL}/api/CancelRequest"
        
        logger.info(f"[{request_id}] Calling door-fn CancelRequest API: {url} with door={door_name_clean}")
        
        response = requests.get(url, params=params, headers=headers, timeout=10)
        
        if response.status_code == 200:
            logger.info(f"[{request_id}] Door-fn CancelRequest API call successful: {response.text}")
            return True
        else:
            logger.error(f"[{request_id}] Door-fn CancelRequest API call failed: {response.status_code} - {response.text}")
            return False
            
    except requests.exceptions.Timeout:
        logger.error(f"[{request_id}] Door-fn CancelRequest API call timed out")
        return False
    except Exception as e:
        logger.error(f"[{request_id}] Error calling door-fn CancelRequest API: {str(e)}")
        return False

# Smart Home skill handlers
def handle_smart_home_directive(request_body, request_id, req_headers=None):
    """Handle Smart Home skill directives for virtual device discovery and control"""
    try:
        directive = request_body.get('directive', {})
        header = directive.get('header', {})
        namespace = header.get('namespace', '')
        name = header.get('name', '')
        
        logger.info(f"[{request_id}] Smart Home directive: {namespace}.{name}")
        
        # Skip authentication for AcceptGrant directive (it establishes the auth)
        if namespace == 'Alexa.Authorization' and name == 'AcceptGrant':
            logger.info(f"[{request_id}] Skipping authentication for AcceptGrant directive")
            
        else:
            # Authenticate user for all other Smart Home directives
            logger.info(f"[{request_id}] Authenticating Smart Home directive")
            is_valid, user_info, error_msg = authenticate_smart_home_request(request_body, req_headers, request_id)
            if not is_valid:
                logger.error(f"[{request_id}] Smart Home authentication failed: {error_msg}")
                return create_error_response_smart_home(directive, "INVALID_AUTHORIZATION_CREDENTIAL", "Authentication failed")
            logger.info(f"[{request_id}] Smart Home authentication successful for user: {user_info}")
        
        if namespace == 'Alexa.Discovery' and name == 'Discover':
            return handle_discovery_directive(directive, request_id)
        
        elif namespace == 'Alexa.Authorization':
            return handle_authorization_directive(directive, request_id)
        
        elif namespace == 'Alexa.PowerController':
            return handle_power_controller_directive(directive, request_id)
        
        elif namespace == 'Alexa':
            return handle_alexa_directive(directive, request_id)
        
        else:
            logger.warning(f"[{request_id}] Unsupported Smart Home directive: {namespace}.{name}")
            return create_error_response_smart_home(directive, "INVALID_DIRECTIVE", "Unsupported directive")
            
    except Exception as e:
        logger.error(f"[{request_id}] Error handling Smart Home directive: {str(e)}")
        return create_error_response_smart_home(directive, "INTERNAL_ERROR", "Internal server error")

def handle_discovery_directive(directive, request_id):
    """Handle device discovery for Smart Home skill"""
    logger.info(f"[{request_id}] Handling device discovery")
    
    endpoints = []
    
    for device_key, device_config in VIRTUAL_DEVICES_CONFIG.get('virtualDevices', {}).items():
        device_name = device_config.get('name', device_key.title())
        friendly_names = device_config.get('friendlyNames', [device_key])
        
        endpoint = {
            "endpointId": f"virtual-{device_key}-device",
            "manufacturerName": "Home Automation",
            "friendlyName": device_name,
            "description": f"Virtual doorbell for {device_key} announcements",
            "displayCategories": ["DOORBELL"],
            "additionalAttributes": {
                "manufacturer": "Home Automation System",
                "model": "Virtual Announcement Doorbell v1.0",
                "serialNumber": f"HAS-{device_key.upper()}-001"
            },
            "capabilities": [
                {
                    "type": "AlexaInterface",
                    "interface": "Alexa",
                    "version": "3"
                },
                {
                    "interface": "Alexa.DoorbellEventSource",
                    "type": "AlexaInterface",
                    "version": "3",
                    "proactivelyReported": True
                }
            ]
        }
        endpoints.append(endpoint)
    
    response = {
        "event": {
            "header": {
                "namespace": "Alexa.Discovery",
                "name": "Discover.Response",
                "payloadVersion": "3",
                "messageId": str(uuid.uuid4())
            },
            "payload": {
                "endpoints": endpoints
            }
        }
    }
    
    logger.info(f"[{request_id}] Discovery response: {len(endpoints)} virtual doorbell devices")
    return response

def handle_authorization_directive(directive, request_id):
    """Handle Alexa.Authorization directives for OAuth 2.0 flow"""
    try:
        header = directive.get('header', {})
        name = header.get('name', '')
        payload = directive.get('payload', {})
        
        logger.info(f"[{request_id}] Handling authorization directive: {name}")
        
        if name == 'AcceptGrant':
            return handle_accept_grant(directive, payload, request_id)
        
        else:
            logger.warning(f"[{request_id}] Unsupported authorization directive: {name}")
            return create_error_response_smart_home(directive, "INVALID_DIRECTIVE", f"Unsupported authorization directive: {name}")
            
    except Exception as e:
        logger.error(f"[{request_id}] Error handling authorization directive: {str(e)}")
        return create_error_response_smart_home(directive, "INTERNAL_ERROR", "Internal server error")

def handle_accept_grant(directive, payload, request_id):
    """Handle AcceptGrant directive for OAuth 2.0 authorization code flow"""
    try:
        logger.info(f"[{request_id}] Processing AcceptGrant directive")
        
        # Log complete directive for debugging
        logger.info(f"[{request_id}] Complete AcceptGrant directive: {json.dumps(directive, indent=2)}")
        logger.info(f"[{request_id}] AcceptGrant payload: {json.dumps(payload, indent=2)}")
        
        # Extract authorization code and user token
        grant = payload.get('grant', {})
        auth_code = grant.get('code')
        user_token = payload.get('grantee', {}).get('token')
        
        if not auth_code:
            logger.error(f"[{request_id}] No authorization code in AcceptGrant payload")
            return create_error_response_smart_home(directive, "INVALID_AUTHORIZATION_CREDENTIAL", "Missing authorization code")
        
        if not user_token:
            logger.error(f"[{request_id}] No user token in AcceptGrant payload")
            return create_error_response_smart_home(directive, "INVALID_AUTHORIZATION_CREDENTIAL", "Missing user token")
        
        logger.info(f"[{request_id}] AcceptGrant: user_token length={len(user_token)}, code_length={len(auth_code)}")
        
        # Determine user ID for token storage
        # The grantee token in AcceptGrant is typically an opaque token, not a JWT
        # Check if it's a JWT format first, otherwise use ALLOWED_USER_ID
        if user_token.count('.') == 2:
            # Looks like JWT format, try to extract user ID
            logger.info(f"[{request_id}] Grantee token appears to be JWT format, extracting user ID")
            user_id = extract_user_id_from_token(user_token, request_id)
            if not user_id:
                logger.warning(f"[{request_id}] Failed to extract user ID from JWT token, using ALLOWED_USER_ID")
                user_id = ALLOWED_USER_ID
        else:
            # Not JWT format, use configured ALLOWED_USER_ID
            logger.info(f"[{request_id}] Grantee token is not JWT format, using ALLOWED_USER_ID")
            user_id = ALLOWED_USER_ID
        
        if not user_id:
            logger.error(f"[{request_id}] No user ID available - ALLOWED_USER_ID not configured")
            return create_error_response_smart_home(directive, "INVALID_AUTHORIZATION_CREDENTIAL", "User identification failed")
        
        logger.info(f"[{request_id}] Using user ID for token storage: {user_id}")
        
        # Exchange authorization code for tokens
        success, tokens, error = exchange_authorization_code(auth_code, user_id, request_id)
        
        if not success:
            logger.error(f"[{request_id}] Failed to exchange authorization code: {error}")
            return create_error_response_smart_home(directive, "ACCEPT_GRANT_FAILED", f"Authorization failed: {error}")
        
        logger.info(f"[{request_id}] Successfully processed AcceptGrant and stored tokens")
        
        # Return successful response
        response = {
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
        
        return response
        
    except Exception as e:
        logger.error(f"[{request_id}] Error processing AcceptGrant: {str(e)}")
        return create_error_response_smart_home(directive, "ACCEPT_GRANT_FAILED", "Internal server error")

def handle_power_controller_directive(directive, request_id):
    """Handle power control directives for virtual devices"""
    header = directive.get('header', {})
    endpoint = directive.get('endpoint', {})
    endpoint_id = endpoint.get('endpointId', '')
    
    # Extract device name from endpoint ID
    device_name = None
    for device_key in VIRTUAL_DEVICES_CONFIG.get('virtualDevices', {}):
        if f"virtual-{device_key}-device" == endpoint_id:
            device_name = device_key
            break
    
    if not device_name:
        logger.error(f"[{request_id}] Unknown endpoint ID: {endpoint_id}")
        return create_error_response_smart_home(directive, "NO_SUCH_ENDPOINT", "Unknown device")
    
    directive_name = header.get('name', '')
    
    if directive_name in ['TurnOn', 'TurnOff']:
        # When virtual device is turned on/off, this triggers the routine
        power_state = "ON" if directive_name == "TurnOn" else "OFF"
        
        logger.info(f"[{request_id}] Virtual device '{device_name}' turned {power_state} - this should trigger Alexa routine")
        
        # Extract user ID from the access token in the directive scope
        access_token = endpoint.get('scope', {}).get('token')
        user_id = None
        
        if access_token:
            # Extract user ID from the access token
            success, extracted_user_id, error = get_user_id_from_access_token(access_token, request_id)
            if success:
                user_id = extracted_user_id
                logger.info(f"[{request_id}] Extracted user ID from access token: {user_id}")
            else:
                logger.warning(f"[{request_id}] Failed to extract user ID from access token: {error}")
        else:
            logger.warning(f"[{request_id}] No access token found in directive scope")
        
        # Send ChangeReport asynchronously (optional - don't fail if it doesn't work)
        if user_id:
            try:
                success, error = send_change_report(user_id, endpoint_id, power_state, request_id)
                if success:
                    logger.info(f"[{request_id}] ChangeReport sent successfully")
                else:
                    logger.warning(f"[{request_id}] ChangeReport failed: {error}")
            except Exception as e:
                logger.warning(f"[{request_id}] ChangeReport error (non-critical): {str(e)}")
        
        # Return success response
        response = {
            "event": {
                "header": {
                    "namespace": "Alexa",
                    "name": "Response",
                    "payloadVersion": "3",
                    "messageId": str(uuid.uuid4()),
                    "correlationToken": header.get('correlationToken')
                },
                "endpoint": endpoint,
                "payload": {}
            },
            "context": {
                "properties": [
                    {
                        "namespace": "Alexa.PowerController",
                        "name": "powerState",
                        "value": power_state,
                        "timeOfSample": datetime.utcnow().isoformat() + "Z",
                        "uncertaintyInMilliseconds": 50
                    }
                ]
            }
        }
        
        return response
    
    else:
        logger.warning(f"[{request_id}] Unsupported PowerController directive: {directive_name}")
        return create_error_response_smart_home(directive, "INVALID_DIRECTIVE", "Unsupported power controller directive")

def handle_alexa_directive(directive, request_id):
    """Handle general Alexa directives like ReportState"""
    header = directive.get('header', {})
    endpoint = directive.get('endpoint', {})
    directive_name = header.get('name', '')
    
    if directive_name == 'ReportState':
        # Report current state of virtual device
        response = {
            "event": {
                "header": {
                    "namespace": "Alexa",
                    "name": "StateReport",
                    "payloadVersion": "3",
                    "messageId": str(uuid.uuid4()),
                    "correlationToken": header.get('correlationToken')
                },
                "endpoint": endpoint,
                "payload": {}
            },
            "context": {
                "properties": [
                    {
                        "namespace": "Alexa.PowerController",
                        "name": "powerState",
                        "value": "OFF",  # Default to OFF
                        "timeOfSample": datetime.utcnow().isoformat() + "Z",
                        "uncertaintyInMilliseconds": 50
                    }
                ]
            }
        }
        
        return response
    
    else:
        logger.warning(f"[{request_id}] Unsupported Alexa directive: {directive_name}")
        return create_error_response_smart_home(directive, "INVALID_DIRECTIVE", "Unsupported Alexa directive")

def create_error_response_smart_home(directive, error_type, error_message):
    """Create error response for Smart Home directive"""
    header = directive.get('header', {})
    endpoint = directive.get('endpoint', {})
    
    return {
        "event": {
            "header": {
                "namespace": "Alexa",
                "name": "ErrorResponse",
                "payloadVersion": "3",
                "messageId": str(uuid.uuid4()),
                "correlationToken": header.get('correlationToken')
            },
            "endpoint": endpoint,
            "payload": {
                "type": error_type,
                "message": error_message
            }
        }
    }


def validate_alexa_configuration():
    """Validate that all required Alexa configuration is present"""
    missing_configs = []
    
    # Check Smart Home OAuth credentials (required for AcceptGrant)
    if not ALEXA_SMART_HOME_CLIENT_ID:
        missing_configs.append('ALEXA_SMART_HOME_CLIENT_ID')
    if not ALEXA_SMART_HOME_CLIENT_SECRET:
        missing_configs.append('ALEXA_SMART_HOME_CLIENT_SECRET')
    
    # Check LWA credentials (required for event sending and API calls)
    if not ALEXA_LWA_CLIENT_ID:
        missing_configs.append('ALEXA_LWA_CLIENT_ID')
    if not ALEXA_LWA_CLIENT_SECRET:
        missing_configs.append('ALEXA_LWA_CLIENT_SECRET')
    
    return len(missing_configs) == 0, missing_configs


def trigger_virtual_device_press(device, request_id):
    """Trigger virtual doorbell press event by sending DoorbellPress event to Alexa"""
    try:
        # Validate Alexa configuration
        is_configured, missing_configs = validate_alexa_configuration()
        if not is_configured:
            logger.error(f"[{request_id}] Alexa integration not configured. Missing: {', '.join(missing_configs)}")
            return False
        
        endpoint_id = f"virtual-{device}-device"
        
        # Create DoorbellPress event for the virtual doorbell device
        doorbell_event = {
            "event": {
                "header": {
                    "namespace": "Alexa.DoorbellEventSource",
                    "name": "DoorbellPress",
                    "payloadVersion": "3",
                    "messageId": str(uuid.uuid4())
                },
                "endpoint": {
                    "scope": {
                        "type": "BearerToken",
                        "token": "placeholder"  # Will be replaced with real access token
                    },
                    "endpointId": endpoint_id
                },
                "payload": {
                    "cause": {
                        "type": "PHYSICAL_INTERACTION"
                    },
                    "timestamp": datetime.utcnow().isoformat() + "Z"
                }
            }
        }
        
        # Log the doorbell event that would be sent to Alexa
        logger.info(f"[{request_id}] Virtual doorbell '{endpoint_id}' DoorbellPress event created - this would trigger Alexa routines")
        logger.debug(f"[{request_id}] DoorbellPress payload: {json.dumps(doorbell_event, indent=2)}")
        
        # Send DoorbellPress event to Alexa Event Gateway for production
        # Use the configured ALLOWED_USER_ID for Service Bus triggered events
        # This allows the system to retrieve OAuth tokens and send proper DoorbellPress events
        user_id = ALLOWED_USER_ID if ALLOWED_USER_ID else None
        
        if not user_id:
            logger.warning(f"[{request_id}] No ALLOWED_USER_ID configured - DoorbellPress event cannot be sent")
            return True  # Allow success for testing without user context
            
        logger.info(f"[{request_id}] Using configured user ID for DoorbellPress event: {user_id}")
        result = send_change_report_to_alexa(doorbell_event, request_id, user_id=user_id)
        if not result:
            logger.warning(f"[{request_id}] DoorbellPress event not sent - allowing success for testing")
            return True  # Allow success for testing without user context
        return result
        
    except Exception as e:
        logger.error(f"[{request_id}] Error creating virtual doorbell press event: {str(e)}")
        return False


# Note: The old get_alexa_access_token function using client_credentials has been replaced
# with proper OAuth 2.0 user token management in oauth_module.py

def send_change_report_to_alexa(change_report, request_id, user_id=None):
    """Send ChangeReport to Alexa Event Gateway using OAuth user tokens"""
    try:
        if not user_id:
            logger.warning(f"[{request_id}] No user_id provided for ChangeReport - cannot send without user context")
            return False
        
        # Get valid OAuth access token for the user (automatically refreshes if needed)
        success, access_token, error = get_valid_access_token(user_id, request_id)
        if not success:
            logger.error(f"[{request_id}] Cannot send ChangeReport: {error}")
            return False
        
        # Update the change report with the valid access token
        change_report['event']['endpoint']['scope']['token'] = access_token
        
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {access_token}"
        }
        
        # Send the ChangeReport
        response = requests.post(
            ALEXA_EVENT_GATEWAY_URL,
            headers=headers,
            json=change_report,
            timeout=10
        )
        
        if response.status_code == 202:
            logger.info(f"[{request_id}] ChangeReport sent successfully to Alexa Event Gateway")
            return True
        elif response.status_code == 401:
            logger.warning(f"[{request_id}] OAuth token expired during ChangeReport - attempting refresh")
            # Try to refresh token and retry once
            success, new_token, error = refresh_access_token(user_id, request_id)
            if success and new_token:
                # Retry with refreshed token
                change_report['event']['endpoint']['scope']['token'] = new_token.get('access_token')
                headers["Authorization"] = f"Bearer {new_token.get('access_token')}"
                
                retry_response = requests.post(
                    ALEXA_EVENT_GATEWAY_URL,
                    headers=headers,
                    json=change_report,
                    timeout=10
                )
                
                if retry_response.status_code == 202:
                    logger.info(f"[{request_id}] ChangeReport sent successfully after token refresh")
                    return True
                else:
                    logger.error(f"[{request_id}] ChangeReport failed even after token refresh: {retry_response.status_code}")
                    return False
            else:
                logger.error(f"[{request_id}] Token refresh failed during ChangeReport retry: {error}")
                return False
        elif response.status_code == 403:
            logger.error(f"[{request_id}] Alexa API access forbidden - check skill permissions")
            return False
        else:
            logger.error(f"[{request_id}] Failed to send ChangeReport: {response.status_code} - {response.text}")
            return False
            
    except requests.exceptions.Timeout:
        logger.error(f"[{request_id}] Timeout sending ChangeReport to Alexa Event Gateway")
        return False
    except Exception as e:
        logger.error(f"[{request_id}] Error sending ChangeReport to Alexa: {str(e)}")
        return False

@app.route(route="alexa_skill", methods=["POST"])
def alexa_skill(req: func.HttpRequest) -> func.HttpResponse:
    """Main Alexa skill endpoint - handles both Custom and Smart Home requests"""
    request_id = str(uuid.uuid4())
    logger.info(f"[{request_id}] Alexa skill request received")
    
    try:
        req_body = req.get_json()
        if not req_body:
            logger.error(f"[{request_id}] No JSON body in request")
            return func.HttpResponse(
                json.dumps(create_error_response("Invalid request format")),
                status_code=400,
                headers={'Content-Type': 'application/json'}
            )
        
        # Check if this is a Smart Home directive
        if 'directive' in req_body:
            logger.info(f"[{request_id}] Smart Home skill request detected")
            req_headers = dict(req.headers)
            smart_home_response = handle_smart_home_directive(req_body, request_id, req_headers)
            return func.HttpResponse(
                json.dumps(smart_home_response),
                status_code=200,
                headers={'Content-Type': 'application/json'}
            )
        
        # Check if this is a Custom Task request
        if 'task' in req_body:
            logger.info(f"[{request_id}] Custom Task request detected")
            task_response = handle_custom_task(req_body, request_id)
            return func.HttpResponse(
                json.dumps(task_response),
                status_code=200,
                headers={'Content-Type': 'application/json'}
            )
        
        # Handle Custom skill requests
        logger.info(f"[{request_id}] Custom skill request type: {req_body.get('request', {}).get('type')}")
        
        # Authenticate request for custom skill
        is_auth, user_id, auth_error = authenticate_request(req, request_id, is_alexa_request=True)
        if not is_auth:
            logger.warning(f"[{request_id}] Authentication failed: {auth_error}")
            return func.HttpResponse(
                json.dumps(create_error_response("Authentication required")),
                status_code=401,
                headers={'Content-Type': 'application/json'}
            )
        
        logger.info(f"[{request_id}] Authenticated user: {user_id}")
        
        # Handle different request types
        request_type = req_body.get('request', {}).get('type')
        
        if request_type == 'LaunchRequest':
            response = create_alexa_response(
                "Welcome to the Home Automation system! You can report door events or check for messages.",
                should_end_session=False
            )
        
        elif request_type == 'IntentRequest':
            intent_name = extract_intent_name(req_body)
            logger.info(f"[{request_id}] Processing intent: {intent_name}")
            
            if intent_name == 'DoorEventIntent':
                door_name = extract_slot_value(req_body, 'DoorName')
                door_action = extract_slot_value(req_body, 'DoorAction')
                
                if not door_name or not door_action:
                    response = create_error_response("I didn't understand the door name or action")
                else:
                    logger.info(f"[{request_id}] Processing door event: {door_name} {door_action}")
                    
                    if door_action.lower() == 'opened':
                        # Call door-fn API to trigger the door event processing
                        success = call_door_fn_api(door_name, 15, request_id)  # 15 second delay
                        
                        if success:
                            if DOOR_EVENT_SILENT_MODE:
                                response = create_alexa_response("")  # Empty response on success
                            else:
                                response = create_alexa_response(f"Okay, I've noted that the {door_name} is open. I'll announce if it stays open too long.")
                        else:
                            # Always send error response, even in silent mode
                            response = create_error_response("I had trouble processing that door event")
                    
                    elif door_action.lower() == 'closed':
                        # For closed events, call door-fn CancelRequest API to cancel pending notifications
                        success = call_door_fn_cancel_api(door_name, request_id)
                        
                        if success:
                            if DOOR_EVENT_SILENT_MODE:
                                response = create_alexa_response("")  # Empty response on success
                            else:
                                response = create_alexa_response(f"Okay, the {door_name} is now closed. I've cancelled any pending announcements.")
                        else:
                            # Always send response on failure, even in silent mode
                            response = create_alexa_response("I had trouble processing that door event")
                    
                    else:
                        response = create_error_response("I only understand opened or closed door actions")
            
            elif intent_name == 'GetAnnouncementForDeviceIntent':
                device_name = extract_slot_value(req_body, 'DeviceName') or 'all'
                
                logger.info(f"[{request_id}] Getting announcement for device: {device_name}")
                
                try:
                    # Try to receive a message from the Service Bus queue for this device
                    message_data = receive_from_servicebus_queue(device_name, request_id)
                    
                    if message_data:
                        # Extract just the message text from the Service Bus message
                        try:
                            message_text = None
                            
                            # First try to get from parsed_body (if JSON was parsed)
                            if message_data.get('parsed_body') and isinstance(message_data['parsed_body'], dict):
                                message_text = message_data['parsed_body'].get('message')
                            
                            # If that fails, try to parse the body directly
                            if not message_text and message_data.get('body'):
                                try:
                                    body_json = json.loads(message_data['body'])
                                    message_text = body_json.get('message')
                                except json.JSONDecodeError:
                                    # If not JSON, use the raw body
                                    message_text = message_data['body']
                            
                            # Final fallback
                            if not message_text:
                                message_text = "I found a message but couldn't read the content"
                            
                            response = create_alexa_response(f"{message_text}")
                            logger.info(f"[{request_id}] Retrieved and announced message for {device_name}: {message_text}")
                            
                        except Exception as e:
                            logger.error(f"[{request_id}] Error parsing message: {str(e)}")
                            response = create_alexa_response(f"I found a message for {device_name} but couldn't read it properly.")
                    else:
                        response = create_alexa_response(f"There are no announcements waiting for {device_name}.")
                        
                except Exception as e:
                    logger.error(f"[{request_id}] Error retrieving announcement: {str(e)}")
                    response = create_error_response("I had trouble checking for announcements")
            
            elif intent_name == 'AMAZON.HelpIntent':
                response = create_alexa_response(
                    "You can report door events like 'the front door is opened', or get messages with 'get announcement for bedroom'.",
                    should_end_session=False
                )
            
            elif intent_name in ['AMAZON.CancelIntent', 'AMAZON.StopIntent']:
                response = create_alexa_response("Goodbye!")
            
            else:
                logger.warning(f"[{request_id}] Unknown intent: {intent_name}")
                response = create_error_response("I don't understand that request")
        
        elif request_type == 'SessionEndedRequest':
            logger.info(f"[{request_id}] Session ended")
            response = {"version": "1.0"}
        
        else:
            logger.warning(f"[{request_id}] Unknown request type: {request_type}")
            response = create_error_response("Unknown request type")
        
        logger.info(f"[{request_id}] Sending response")
        return func.HttpResponse(
            json.dumps(response),
            status_code=200,
            headers={'Content-Type': 'application/json'}
        )
        
    except Exception as e:
        logger.error(f"[{request_id}] Error processing Alexa request: {str(e)}")
        return func.HttpResponse(
            json.dumps(create_error_response("An error occurred processing your request")),
            status_code=500,
            headers={'Content-Type': 'application/json'}
        )


@app.route(route="announce", methods=["POST"])
def announce(req: func.HttpRequest) -> func.HttpResponse:
    """Endpoint for sending announcements to devices"""
    request_id = str(uuid.uuid4())
    logger.info(f"[{request_id}] Announce request received")
    
    try:
        req_body = req.get_json()
        if not req_body:
            return func.HttpResponse(
                json.dumps({"error": "Request body is required"}),
                status_code=400,
                headers={'Content-Type': 'application/json'}
            )
        
        message = req_body.get('message', '')
        device = req_body.get('device', 'all')
        
        if not message:
            return func.HttpResponse(
                json.dumps({"error": "Message is required"}),
                status_code=400,
                headers={'Content-Type': 'application/json'}
            )
        
        # Send to Service Bus
        message_data = {
            "message": message,
            "id": request_id,
            "timestamp": datetime.utcnow().isoformat(),
            "device": device
        }
        success = send_to_servicebus_queue(device, message_data)
        
        if success:
            # Trigger virtual device press event
            press_event_sent = trigger_virtual_device_press(device, request_id)
            
            # Both steps must succeed for the API to return success
            if press_event_sent:
                # Both Service Bus and virtual device press succeeded
                return func.HttpResponse(
                    json.dumps({
                        "success": True,
                        "message": f"Announcement sent to {device}",
                        "press_event_triggered": True
                    }),
                    status_code=200,
                    headers={'Content-Type': 'application/json'}
                )
            else:
                # Service Bus succeeded but virtual device press failed - treat as overall failure
                logger.error(f"[{request_id}] Announcement failed: Virtual device press failed despite Service Bus success")
                return func.HttpResponse(
                    json.dumps({
                        "success": False,
                        "error": "Failed to trigger Alexa routine - announcement not fully processed",
                        "details": "Message queued to Service Bus but virtual device press failed",
                        "request_id": request_id
                    }),
                    status_code=500,  # Return error since full workflow failed
                    headers={'Content-Type': 'application/json'}
                )
        else:
            return func.HttpResponse(
                json.dumps({
                    "success": False,
                    "error": "Failed to send announcement",
                    "request_id": request_id
                }),
                status_code=500,
                headers={'Content-Type': 'application/json'}
            )
            
    except Exception as e:
        logger.error(f"[{request_id}] Error processing announce request: {str(e)}")
        return func.HttpResponse(
            json.dumps({
                "success": False,
                "error": "Internal server error",
                "request_id": request_id
            }),
            status_code=500,
            headers={'Content-Type': 'application/json'}
        )


@app.route(route="health", methods=["GET"])
def health_check(req: func.HttpRequest) -> func.HttpResponse:
    """Health check endpoint"""
    try:
        alexa_configured, _ = validate_alexa_configuration()
        
        status = {
            "status": "healthy",
            "service_bus": bool(SERVICEBUS_CONNECTION_STRING),
            "door_function": bool(DOOR_FN_BASE_URL and DOOR_FN_API_KEY),
            "alexa_integration": alexa_configured,
            "devices": len(VIRTUAL_DEVICES_CONFIG.get('virtualDevices', {}))
        }
        
        return func.HttpResponse(
            json.dumps(status),
            status_code=200,
            headers={'Content-Type': 'application/json'}
        )
        
    except Exception as e:
        return func.HttpResponse(
            json.dumps({"status": "error", "message": str(e)}),
            status_code=500,
            headers={'Content-Type': 'application/json'}
        )