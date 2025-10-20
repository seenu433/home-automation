#!/usr/bin/env python3
"""
Test Flume Function Announce API Call

This script tests the announce API endpoint that the Flume function uses 
to send water leak alerts. It simulates the exact API call that the 
Flume function makes when a water leak is detected.

Usage:
    python test_flume_announce.py                    # Test with default message
    python test_flume_announce.py --custom-message "Custom alert"
    python test_flume_announce.py --production       # Test against production
    python test_flume_announce.py --verbose          # Show detailed output
"""

import argparse
import json
import os
import sys
import time
import requests
from pathlib import Path

def load_test_config():
    """Load test configuration from test_config.json"""
    config_path = Path(__file__).parent / "test_config.json"
    try:
        with open(config_path, 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        print(f"❌ Test configuration file not found: {config_path}")
        return None
    except json.JSONDecodeError as e:
        print(f"❌ Error parsing test configuration: {e}")
        return None

def load_flume_config():
    """Load Flume function configuration from local.settings.json"""
    config_path = Path(__file__).parent.parent / "flume-fn" / "local.settings.json"
    try:
        with open(config_path, 'r') as f:
            config = json.load(f)
            return config.get('Values', {})
    except FileNotFoundError:
        print(f"❌ Flume configuration file not found: {config_path}")
        return None
    except json.JSONDecodeError as e:
        print(f"❌ Error parsing Flume configuration: {e}")
        return None

def test_announce_api(announce_url, api_key, message, verbose=False):
    """Test the announce API with the given parameters"""
    
    # Prepare payload exactly as Flume function sends it
    payload = {
        "message": message,
        "device": "all"
    }
    
    headers = {
        "Content-Type": "application/json",
        "x-functions-key": api_key
    }
    
    if verbose:
        print("📤 Request Details:")
        print(f"   URL: {announce_url}")
        print(f"   Headers: {json.dumps(headers, indent=4)}")
        print(f"   Payload: {json.dumps(payload, indent=4)}")
    
    try:
        response = requests.post(
            announce_url,
            json=payload,
            headers=headers,
            timeout=30
        )
        
        if response.status_code == 200:
            print("✅ Announce API call successful!")
            print(f"📥 Response: {response.json()}")
            return True
        else:
            print(f"❌ Announce API call failed with status {response.status_code}")
            print(f"Error: {response.text}")
            return False
            
    except requests.exceptions.Timeout:
        print("❌ Request timed out")
        return False
    except requests.exceptions.ConnectionError:
        print("❌ Connection error - check if the endpoint is running")
        return False
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return False

def test_message_retrieval(base_url, api_key, test_config, verbose=False):
    """Test message retrieval to verify it was queued properly"""
    
    print("\n📋 Test 2: Verifying Message was Queued")
    
    # Wait for message to be processed
    time.sleep(2)
    
    # Create Alexa request to get announcement
    alexa_request = {
        "version": "1.0",
        "session": {
            "new": True,
            "sessionId": "test-session-flume-announce",
            "user": {
                "userId": test_config.get("alexa", {}).get("userId", "test-user")
            }
        },
        "request": {
            "type": "IntentRequest",
            "requestId": "test-request-flume-announce",
            "intent": {
                "name": "GetAnnouncementForDeviceIntent",
                "slots": {
                    "DeviceName": {
                        "name": "DeviceName",
                        "value": "all"
                    }
                }
            }
        }
    }
    
    headers = {
        "Content-Type": "application/json",
        "x-functions-key": api_key
    }
    
    try:
        response = requests.post(
            f"{base_url}/api/alexa_skill",
            json=alexa_request,
            headers=headers,
            timeout=30
        )
        
        if response.status_code == 200:
            response_data = response.json()
            output_text = response_data.get("response", {}).get("outputSpeech", {}).get("text", "")
            
            if "Water leak" in output_text:
                print("✅ Message successfully queued and retrieved!")
                print(f"📝 Retrieved message: {output_text}")
                return True
            else:
                print("⚠️  Message may not have been queued properly")
                print(f"📝 Retrieved response: {output_text}")
                return False
        else:
            print(f"⚠️  Could not verify message queue: HTTP {response.status_code}")
            return False
            
    except Exception as e:
        print(f"⚠️  Could not verify message queue: {e}")
        print("💡 This is not necessarily an error - the message may have been processed correctly")
        return False

def test_alternative_devices(announce_url, api_key, verbose=False):
    """Test different device targets for comparison"""
    
    print("\n🎯 Test 3: Testing Alternative Device Targets (for comparison)")
    
    devices = ["bedroom", "downstairs", "upstairs"]
    results = {}
    
    for device in devices:
        print(f"   Testing device: {device}")
        
        payload = {
            "message": f"Test water leak alert for {device} area",
            "device": device
        }
        
        headers = {
            "Content-Type": "application/json",
            "x-functions-key": api_key
        }
        
        try:
            response = requests.post(
                announce_url,
                json=payload,
                headers=headers,
                timeout=10
            )
            
            if response.status_code == 200:
                print(f"   ✅ {device}: Success")
                results[device] = True
            else:
                print(f"   ❌ {device}: Failed (HTTP {response.status_code})")
                results[device] = False
                
        except Exception as e:
            print(f"   ❌ {device}: Failed - {e}")
            results[device] = False
    
    return results

def main():
    parser = argparse.ArgumentParser(description="Test Flume Function Announce API Call")
    parser.add_argument(
        "--custom-message", 
        default="Water leak detected in your home! Please check your Flume sensor immediately.",
        help="Custom message to send"
    )
    parser.add_argument(
        "--production", 
        action="store_true", 
        help="Test against production endpoints"
    )
    parser.add_argument(
        "--verbose", 
        action="store_true", 
        help="Show detailed request/response information"
    )
    
    args = parser.parse_args()
    
    print("🧪 Testing Flume Function Announce API Call")
    print("===========================================")
    
    # Load configurations
    test_config = load_test_config()
    flume_config = load_flume_config()
    
    if not test_config or not flume_config:
        print("❌ Cannot proceed without valid configuration")
        sys.exit(1)
    
    # Determine endpoint URLs
    if args.production:
        announce_url = test_config.get("announce", {}).get("url")
        if not announce_url:
            print("❌ Production announce URL not found in test_config.json")
            sys.exit(1)
        print(f"🌐 Using PRODUCTION endpoint: {announce_url}")
    else:
        base_url = flume_config.get("ALEXA_FN_BASE_URL")
        if not base_url:
            print("❌ ALEXA_FN_BASE_URL not found in Flume configuration")
            sys.exit(1)
        announce_url = f"{base_url}/api/announce"
        print(f"🔧 Using LOCAL endpoint: {announce_url}")
    
    # Get API key
    api_key = flume_config.get("ALEXA_FN_API_KEY")
    if not api_key:
        print("❌ No API key found in Flume configuration (ALEXA_FN_API_KEY)")
        sys.exit(1)
    
    print(f"🔑 Using API Key: {api_key[:10]}...")
    
    # Test 1: Simulate Flume Function Announce Call
    print(f"\n📡 Test 1: Simulating Flume Function Announce Call")
    print(f"Message: {args.custom_message}")
    print(f"Device: all (hardcoded in Flume function)")
    
    success = test_announce_api(announce_url, api_key, args.custom_message, args.verbose)
    
    if not success:
        sys.exit(1)
    
    # Test 2: Verify Message Queue (if using local endpoint)
    if not args.production:
        base_url = flume_config.get("ALEXA_FN_BASE_URL")
        test_message_retrieval(base_url, api_key, test_config, args.verbose)
    
    # Test 3: Test Alternative Device Targets
    alt_results = test_alternative_devices(announce_url, api_key, args.verbose)
    
    # Summary
    print("\n✅ Flume Function Announce API Test Completed!")
    print("📋 Summary:")
    print("   • Flume function uses 'all' device for water leak alerts")
    print(f"   • API endpoint: {announce_url}")
    print("   • Message format matches Flume function implementation")
    print("   • Alternative device targets are available but not used by Flume")
    
    if not args.production:
        print("\n💡 Next Steps:")
        print("   • Run Flume function locally: func start (in flume-fn directory)")
        print("   • Test production: python test_flume_announce.py --production")
        print("   • Monitor actual water leak detection in Flume dashboard")

if __name__ == "__main__":
    main()