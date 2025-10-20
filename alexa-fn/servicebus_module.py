"""
Azure Service Bus REST API Client Module

This module provides REST API client functionality for Azure Service Bus operations,
replacing the SDK-based approach to avoid dependency conflicts in Azure Functions.
"""

import json
import logging
import os
import requests
import base64
import hmac
import hashlib
import time
from urllib.parse import quote_plus

logger = logging.getLogger(__name__)


class ServiceBusRestClient:
    """REST API client for Azure Service Bus"""
    
    def __init__(self, connection_string):
        self.connection_string = connection_string
        self.namespace = self._extract_namespace()
        self.sas_key_name, self.sas_key = self._extract_sas_credentials()
    
    def _extract_namespace(self):
        """Extract namespace from connection string"""
        try:
            for part in self.connection_string.split(';'):
                if part.startswith('Endpoint='):
                    endpoint = part.split('=', 1)[1]
                    # Extract namespace from endpoint like sb://namespace.servicebus.windows.net/
                    return endpoint.replace('sb://', '').replace('.servicebus.windows.net/', '')
        except Exception as e:
            logger.error(f"Error extracting namespace: {e}")
        return 'srini-home-automation'  # fallback
    
    def _extract_sas_credentials(self):
        """Extract SAS key name and key from connection string"""
        try:
            key_name = None
            key = None
            for part in self.connection_string.split(';'):
                if part.startswith('SharedAccessKeyName='):
                    key_name = part.split('=', 1)[1]
                elif part.startswith('SharedAccessKey='):
                    key = part.split('=', 1)[1]
            return key_name, key
        except Exception as e:
            logger.error(f"Error extracting SAS credentials: {e}")
            return None, None
    
    def _generate_sas_token(self, resource_uri):
        """Generate SAS token for authentication"""
        try:
            # Token expires in 1 hour
            expiry = str(int(time.time() + 3600))
            string_to_sign = f"{quote_plus(resource_uri)}\n{expiry}"
            
            # Create HMAC signature
            signature = base64.b64encode(
                hmac.new(
                    self.sas_key.encode('utf-8'),
                    string_to_sign.encode('utf-8'),
                    hashlib.sha256
                ).digest()
            ).decode()
            
            # Construct the token
            token = f"SharedAccessSignature sr={quote_plus(resource_uri)}&sig={quote_plus(signature)}&se={expiry}&skn={self.sas_key_name}"
            return token
        except Exception as e:
            logger.error(f"Error generating SAS token: {e}")
            return None
    
    def send_message(self, queue_name, message_body, request_id):
        """Send message to Service Bus queue via REST API"""
        try:
            resource_uri = f"https://{self.namespace}.servicebus.windows.net/{queue_name}"
            sas_token = self._generate_sas_token(resource_uri)
            
            if not sas_token:
                logger.error(f"[{request_id}] Failed to generate SAS token")
                return False
            
            headers = {
                'Authorization': sas_token,
                'Content-Type': 'application/json',
                'BrokerProperties': json.dumps({"Label": "alexa-announcement"})
            }
            
            url = f"{resource_uri}/messages"
            response = requests.post(url, data=message_body, headers=headers)
            
            if response.status_code == 201:
                logger.info(f"[{request_id}] Successfully sent message to {queue_name}")
                return True
            else:
                logger.error(f"[{request_id}] Failed to send message: {response.status_code} - {response.text}")
                return False
                
        except Exception as e:
            logger.error(f"[{request_id}] Error sending message to {queue_name}: {e}")
            return False

    def receive_message(self, queue_name, peek_lock=True, timeout=60):
        """Receive message from Service Bus queue via REST API"""
        try:
            resource_uri = f"https://{self.namespace}.servicebus.windows.net/{queue_name}"
            sas_token = self._generate_sas_token(resource_uri)
            
            if not sas_token:
                logger.error(f"Failed to generate SAS token for receiving from {queue_name}")
                return None
            
            headers = {
                'Authorization': sas_token,
                'Content-Type': 'application/json'
            }
            
            # Use peek-lock or receive-and-delete mode
            if peek_lock:
                # Peek-lock: message is locked but not deleted until explicitly completed
                url = f"{resource_uri}/messages/head"
                params = {'timeout': timeout}
            else:
                # Receive-and-delete: message is immediately deleted after receiving
                url = f"{resource_uri}/messages/head"
                params = {'timeout': timeout}
            
            response = requests.delete(url, headers=headers, params=params)
            
            if response.status_code == 200:
                # Parse message content
                message_body = response.text
                
                # Get broker properties from headers
                broker_properties = response.headers.get('BrokerProperties', '{}')
                try:
                    broker_props = json.loads(broker_properties)
                except json.JSONDecodeError:
                    broker_props = {}
                
                # Get custom properties
                custom_properties = {}
                for header_name, header_value in response.headers.items():
                    if header_name.startswith('x-opt-'):
                        # Custom properties are prefixed with x-opt-
                        prop_name = header_name[6:]  # Remove 'x-opt-' prefix
                        custom_properties[prop_name] = header_value
                
                message_info = {
                    'body': message_body,
                    'broker_properties': broker_props,
                    'custom_properties': custom_properties,
                    'message_id': broker_props.get('MessageId'),
                    'lock_token': broker_props.get('LockToken'),
                    'delivery_count': broker_props.get('DeliveryCount', 0),
                    'sequence_number': broker_props.get('SequenceNumber'),
                    'enqueued_time': broker_props.get('EnqueuedTimeUtc'),
                    'expires_at': broker_props.get('ExpiresAtUtc')
                }
                
                logger.info(f"Successfully received message from {queue_name}")
                return message_info
                
            elif response.status_code == 204:
                # No messages available
                logger.info(f"No messages available in queue {queue_name}")
                return None
                
            else:
                logger.error(f"Failed to receive message from {queue_name}: {response.status_code} - {response.text}")
                return None
                
        except Exception as e:
            logger.error(f"Error receiving message from {queue_name}: {e}")
            return None

    def complete_message(self, queue_name, lock_token):
        """Complete (delete) a message using its lock token"""
        try:
            resource_uri = f"https://{self.namespace}.servicebus.windows.net/{queue_name}"
            sas_token = self._generate_sas_token(resource_uri)
            
            if not sas_token:
                logger.error(f"Failed to generate SAS token for completing message in {queue_name}")
                return False
            
            headers = {
                'Authorization': sas_token,
                'Content-Type': 'application/json'
            }
            
            url = f"{resource_uri}/messages/{lock_token}"
            response = requests.delete(url, headers=headers)
            
            if response.status_code == 200:
                logger.info(f"Successfully completed message with lock token {lock_token}")
                return True
            else:
                logger.error(f"Failed to complete message: {response.status_code} - {response.text}")
                return False
                
        except Exception as e:
            logger.error(f"Error completing message: {e}")
            return False

    def abandon_message(self, queue_name, lock_token):
        """Abandon a message, making it available for redelivery"""
        try:
            resource_uri = f"https://{self.namespace}.servicebus.windows.net/{queue_name}"
            sas_token = self._generate_sas_token(resource_uri)
            
            if not sas_token:
                logger.error(f"Failed to generate SAS token for abandoning message in {queue_name}")
                return False
            
            headers = {
                'Authorization': sas_token,
                'Content-Type': 'application/json'
            }
            
            url = f"{resource_uri}/messages/{lock_token}"
            response = requests.put(url, headers=headers)
            
            if response.status_code == 200:
                logger.info(f"Successfully abandoned message with lock token {lock_token}")
                return True
            else:
                logger.error(f"Failed to abandon message: {response.status_code} - {response.text}")
                return False
                
        except Exception as e:
            logger.error(f"Error abandoning message: {e}")
            return False


def get_servicebus_client():
    """Get or create Service Bus client"""
    global servicebus_client
    
    if servicebus_client is None:
        sbcon = os.environ.get('sbcon', '')
        if not sbcon:
            logger.warning("Service Bus connection string not found in environment")
            return None
        return ServiceBusRestClient(sbcon)
    
    return servicebus_client


def get_queue_name(device_id):
    """Get Service Bus queue name for device"""
    return f"announcements-{device_id}"


def send_to_servicebus_queue(device, message_data):
    """Send message to Service Bus queue for device"""
    try:
        client = get_servicebus_client()
        if not client:
            logging.error("Service Bus client not available - check connection string")
            return False
            
        queue_name = get_queue_name(device)
        
        # Use REST API to send message
        request_id = message_data.get('id', str(__import__('uuid').uuid4()))
        success = client.send_message(queue_name, json.dumps(message_data), request_id)
        
        if success:
            logger.info(f"Successfully sent message to {device} queue: {queue_name}")
            return True
        else:
            logger.error(f"Failed to send message to {device} queue: {queue_name}")
            return False
                
    except Exception as e:
        logging.error(f"Error sending to Service Bus queue {device}: {str(e)}")
        return False


def receive_from_servicebus_queue(device, peek_lock=True, timeout=60):
    """Receive message from Service Bus queue for device"""
    try:
        client = get_servicebus_client()
        if not client:
            logger.error("Service Bus client not available - check connection string")
            return None
            
        queue_name = get_queue_name(device)
        
        # Use REST API to receive message
        message_info = client.receive_message(queue_name, peek_lock=peek_lock, timeout=timeout)
        
        if message_info:
            logger.info(f"Successfully received message from {device} queue: {queue_name}")
            
            # Parse the message body if it's JSON
            try:
                if message_info['body']:
                    message_info['parsed_body'] = json.loads(message_info['body'])
            except (json.JSONDecodeError, KeyError):
                # If not JSON, keep original body
                pass
                
            return message_info
        else:
            logger.info(f"No messages available in {device} queue: {queue_name}")
            return None
                
    except Exception as e:
        logger.error(f"Error receiving from Service Bus queue {device}: {str(e)}")
        return None


def complete_message(device, lock_token):
    """Complete (delete) a message using its lock token"""
    try:
        client = get_servicebus_client()
        if not client:
            logger.error("Service Bus client not available - check connection string")
            return False
            
        queue_name = get_queue_name(device)
        return client.complete_message(queue_name, lock_token)
                
    except Exception as e:
        logger.error(f"Error completing message in {device} queue: {str(e)}")
        return False


def abandon_message(device, lock_token):
    """Abandon a message, making it available for redelivery"""
    try:
        client = get_servicebus_client()
        if not client:
            logger.error("Service Bus client not available - check connection string")
            return False
            
        queue_name = get_queue_name(device)
        return client.abandon_message(queue_name, lock_token)
                
    except Exception as e:
        logger.error(f"Error abandoning message in {device} queue: {str(e)}")
        return False


def get_servicebus_queue_info(device):
    """Get queue information (count, etc.) for device"""
    try:
        # Note: Getting queue message count requires management operations
        # For now, return basic info. In production, you might use ServiceBusAdministrationClient
        return {
            "queueName": get_queue_name(device),
            "device": device,
            "status": "available" if get_servicebus_client() else "unavailable"
        }
    except Exception as e:
        logging.error(f"Error getting queue info for {device}: {str(e)}")
        return {"queueName": get_queue_name(device), "device": device, "status": "error", "error": str(e)}


# Global Service Bus client instance
servicebus_client = None
