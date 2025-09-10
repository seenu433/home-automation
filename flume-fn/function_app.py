import azure.functions as func
import datetime
import json
import logging
import os
import requests
from pyflume import FlumeAuth, FlumeDeviceList, FlumeLeakList

# Configure logging for Azure Functions
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = func.FunctionApp()

@app.timer_trigger(schedule="0 */5 * * * *", arg_name="myTimer", run_on_startup=True,
              use_monitor=True) 
def leak_detector(myTimer: func.TimerRequest) -> None:
    """
    Timer triggered function that runs every minute to check for Flume water leak notifications
    and announces them via Voice Monkey API on Alexa.
    """
    
    logging.info('=== FLUME LEAK DETECTOR STARTING ===')
    logging.info(f'Function execution time: {datetime.datetime.utcnow()}')
    
    if myTimer.past_due:
        logging.warning('The timer is past due!')

    logging.info('Starting leak detection check...')
    
    try:
        # Check for leak notifications
        leak_detected = check_flume_leaks()
        
        if leak_detected:
            logging.warning('🚨 LEAK DETECTED! Sending alert to Alexa...')
            send_voice_monkey_alert("Water leak detected in your home! Please check your Flume sensor immediately.")
            logging.info('Leak alert sent to Alexa successfully')
        else:
            logging.info('✅ No leaks detected. All systems normal.')
            
    except Exception as e:
        logging.error(f'❌ Error in leak detection: {str(e)}', exc_info=True)
        # Send error notification to Alexa
        try:
            send_voice_monkey_alert("There was an error checking your water leak sensor. Please check the system.")
            logging.info('Error notification sent to Alexa')
        except Exception as alert_error:
            logging.error(f'Failed to send error alert to Alexa: {str(alert_error)}')
    
    logging.info('=== FLUME LEAK DETECTOR COMPLETED ===')

def check_flume_leaks():
    """
    Check Flume devices for leak notifications using PyFlume library.
    Returns True if any leak is detected, False otherwise.
    """
    
    logging.info('🔍 Checking Flume devices for leaks...')
    
    # Get Flume credentials from environment variables
    flume_username = os.environ.get('FLUME_USERNAME')
    flume_password = os.environ.get('FLUME_PASSWORD')
    flume_client_id = os.environ.get('FLUME_CLIENT_ID')
    flume_client_secret = os.environ.get('FLUME_CLIENT_SECRET')
    target_device_id = os.environ.get('FLUME_TARGET_DEVICE_ID')
    
    logging.info(f'Flume configuration - Username: {flume_username}, Client ID: {flume_client_id}, Target Device: {target_device_id}')
    
    if not all([flume_username, flume_password, flume_client_id, flume_client_secret, target_device_id]):
        missing_vars = []
        if not flume_username: missing_vars.append('FLUME_USERNAME')
        if not flume_password: missing_vars.append('FLUME_PASSWORD')
        if not flume_client_id: missing_vars.append('FLUME_CLIENT_ID')
        if not flume_client_secret: missing_vars.append('FLUME_CLIENT_SECRET')
        if not target_device_id: missing_vars.append('FLUME_TARGET_DEVICE_ID')
        
        error_msg = f'Missing Flume environment variables: {", ".join(missing_vars)}'
        logging.error(error_msg)
        raise ValueError(error_msg)
    
    try:
        # Authenticate with Flume
        auth = FlumeAuth(
            username=flume_username,
            password=flume_password,
            client_id=flume_client_id,
            client_secret=flume_client_secret
        )
        
        # Target device ID for leak detection from environment variable
        logging.info(f'Monitoring device {target_device_id} for leaks')
        
        # Create Flume leak list manager for the specific device
        flume_leaks = FlumeLeakList(auth, device_id=target_device_id)
        
        # Get all active leaks for this device
        leaks = flume_leaks.get_leaks()
        
        if leaks:
            logging.info(f'Found {len(leaks)} leak records for device {target_device_id}: {leaks}')
            
            # Check if any leak is currently active
            active_leaks = [leak for leak in leaks if leak.get('active', False) == True]
            
            if active_leaks:
                logging.warning(f'Found {len(active_leaks)} ACTIVE leaks for device {target_device_id}')
                
                for leak in active_leaks:
                    leak_type = leak.get('type', 'unknown')
                    leak_message = leak.get('message', 'Active leak detected')
                    leak_timestamp = leak.get('created_datetime', 'unknown time')
                    
                    logging.warning(f'ACTIVE LEAK DETECTED - Type: {leak_type}, Message: {leak_message}, Time: {leak_timestamp}')
                
                return True
            else:
                logging.info(f'Found leak records but none are currently active for device {target_device_id}')
                return False
        else:
            logging.info(f'No leak records found for device {target_device_id}')
            return False
        
    except Exception as e:
        logging.error(f'Error connecting to Flume API: {str(e)}')
        raise

def send_voice_monkey_alert(message):
    """
    Send alert message to Alexa via Voice Monkey API.
    """
    
    logging.info(f'📢 Sending Voice Monkey alert: {message}')
    
    voice_monkey_token = os.environ.get('VOICE_MONKEY_TOKEN')
    voice_monkey_device = os.environ.get('VOICE_MONKEY_DEVICE', 'default')
    
    logging.info(f'Voice Monkey configuration - Device: {voice_monkey_device}, Token configured: {bool(voice_monkey_token)}')
    
    if not voice_monkey_token:
        error_msg = 'Voice Monkey token not configured (VOICE_MONKEY_TOKEN environment variable missing)'
        logging.error(error_msg)
        raise ValueError(error_msg)
    
    try:
        # Voice Monkey v2 Announcement API endpoint with GET parameters
        url = 'https://api-v2.voicemonkey.io/announcement'
        
        params = {
            'token': voice_monkey_token,
            'device': voice_monkey_device,
            'text': message
        }
        
        logging.info(f'Making Voice Monkey API request to: {url}')
        logging.info(f'Request parameters: device={voice_monkey_device}, message_length={len(message)}')
        
        response = requests.get(url, params=params, timeout=30)
        response.raise_for_status()
        
        logging.info(f'✅ Voice Monkey alert sent successfully!')
        logging.info(f'Response status: {response.status_code}')
        logging.info(f'Response content: {response.text}')
        
    except requests.exceptions.RequestException as e:
        logging.error(f'❌ Error sending Voice Monkey alert: {str(e)}', exc_info=True)
        raise
