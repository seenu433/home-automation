#!/usr/bin/env python3
"""
Generate LWA (Login with Amazon) Token for Testing

This script helps generate an LWA access token that can be used to test
the Azure Function and Lambda proxy authentication without going through
the full Alexa skill flow.
"""

import requests
import json
import webbrowser
import urllib.parse
from http.server import HTTPServer, BaseHTTPRequestHandler
import threading
import time
import os
import json

def load_config(config_file="test_config.json"):
    """Load configuration from JSON file"""
    try:
        with open(config_file, 'r') as f:
            return json.load(f)
    except Exception as e:
        print(f"Error loading config: {e}")
        return None

# Load configuration
config = load_config()
if not config:
    print("❌ Could not load configuration from test_config.json")
    exit(1)

oauth_config = config.get('oauth', {})
azure_config = config.get('azureFunction', {})

# Validate required OAuth configuration
required_oauth_keys = ['clientId', 'clientSecret', 'authUrl', 'tokenUrl', 'profileUrl']
missing_keys = [key for key in required_oauth_keys if not oauth_config.get(key)]

if missing_keys:
    print(f"❌ Missing OAuth configuration keys: {', '.join(missing_keys)}")
    print("💡 Please ensure oauth section in test_config.json has all required values")
    exit(1)

if not azure_config.get('url'):
    print("❌ Missing Azure Function URL in configuration")
    print("💡 Please ensure azureFunction.url is set in test_config.json")
    exit(1)

print("✅ Configuration loaded successfully")
print(f"   Client ID: {oauth_config.get('clientId')[:30]}...")
print(f"   Azure Function URL: {azure_config.get('url')}")

# LWA OAuth Configuration from config
LWA_CLIENT_ID = oauth_config.get('clientId')
LWA_CLIENT_SECRET = oauth_config.get('clientSecret')
REDIRECT_URI = "http://localhost:3000/auth/callback"

# Amazon OAuth URLs from config
AMAZON_AUTH_URL = oauth_config.get('authUrl')
AMAZON_TOKEN_URL = oauth_config.get('tokenUrl')
AMAZON_PROFILE_URL = oauth_config.get('profileUrl')

# Azure Function URL from config
AZURE_FUNCTION_URL = azure_config.get('url')

class AuthCallbackHandler(BaseHTTPRequestHandler):
    """Handle OAuth callback from Amazon"""
    
    def do_GET(self):
        if self.path.startswith('/auth/callback'):
            # Parse the callback URL for authorization code
            query_string = self.path.split('?', 1)[1] if '?' in self.path else ''
            params = urllib.parse.parse_qs(query_string)
            
            if 'code' in params:
                auth_code = params['code'][0]
                print(f"\n✅ Authorization code received: {auth_code[:20]}...")
                
                # Exchange code for access token
                token_data = exchange_code_for_token(auth_code)
                
                if token_data:
                    # Test the token
                    test_token(token_data['access_token'])
                    
                    # Save token for reuse
                    save_token(token_data)
                    
                    # Send success response
                    self.send_response(200)
                    self.send_header('Content-type', 'text/html')
                    self.end_headers()
                    success_html = """
                    <html><body>
                    <h2>✅ Authentication Successful!</h2>
                    <p>You can close this window and return to the terminal.</p>
                    <script>setTimeout(() => window.close(), 3000);</script>
                    </body></html>
                    """
                    self.wfile.write(success_html.encode('utf-8'))
                else:
                    # Send error response
                    self.send_response(400)
                    self.send_header('Content-type', 'text/html')
                    self.end_headers()
                    error_html = """
                    <html><body>
                    <h2>Token Exchange Failed</h2>
                    <p>Check the terminal for error details.</p>
                    </body></html>
                    """
                    self.wfile.write(error_html.encode('utf-8'))
            
            elif 'error' in params:
                error = params['error'][0]
                print(f"\n❌ OAuth error: {error}")
                
                self.send_response(400)
                self.send_header('Content-type', 'text/html')
                self.end_headers()
                self.wfile.write(f"""
                <html><body>
                <h2>❌ Authentication Error</h2>
                <p>Error: {error}</p>
                </body></html>
                """.encode())
        
        # Stop the server after handling the callback
        threading.Thread(target=self.server.shutdown).start()
    
    def log_message(self, format, *args):
        # Suppress default HTTP server logs
        pass

def exchange_code_for_token(auth_code):
    """Exchange authorization code for access token"""
    print("🔄 Exchanging authorization code for access token...")
    
    try:
        data = {
            'grant_type': 'authorization_code',
            'code': auth_code,
            'redirect_uri': REDIRECT_URI,
            'client_id': LWA_CLIENT_ID,
            'client_secret': LWA_CLIENT_SECRET
        }
        
        response = requests.post(AMAZON_TOKEN_URL, data=data, timeout=10)
        
        if response.status_code == 200:
            token_data = response.json()
            print("✅ Token exchange successful!")
            print(f"   Access Token: {token_data['access_token'][:20]}...")
            print(f"   Token Type: {token_data.get('token_type', 'Bearer')}")
            print(f"   Expires In: {token_data.get('expires_in', 'Unknown')} seconds")
            return token_data
        else:
            print(f"❌ Token exchange failed: {response.status_code}")
            print(f"   Response: {response.text}")
            return None
            
    except Exception as e:
        print(f"❌ Error exchanging code for token: {str(e)}")
        return None

def test_token(access_token):
    """Test the access token by calling Amazon's profile API"""
    print("\n🧪 Testing access token...")
    
    try:
        headers = {
            'Authorization': f'Bearer {access_token}',
            'Content-Type': 'application/json'
        }
        
        response = requests.get(AMAZON_PROFILE_URL, headers=headers, timeout=10)
        
        if response.status_code == 200:
            profile = response.json()
            print("✅ Token validation successful!")
            print(f"   User ID: {profile.get('user_id', 'Unknown')}")
            print(f"   Name: {profile.get('name', 'Unknown')}")
            print(f"   Email: {profile.get('email', 'Unknown')}")
            return True
        else:
            print(f"❌ Token validation failed: {response.status_code}")
            print(f"   Response: {response.text}")
            return False
            
    except Exception as e:
        print(f"❌ Error validating token: {str(e)}")
        return False

def save_token(token_data):
    """Save token data to file for reuse"""
    try:
        with open('lwa_token.json', 'w') as f:
            json.dump(token_data, f, indent=2)
        print(f"💾 Token saved to: lwa_token.json")
    except Exception as e:
        print(f"⚠️ Could not save token: {str(e)}")

def load_saved_token():
    """Load previously saved token"""
    try:
        if os.path.exists('lwa_token.json'):
            with open('lwa_token.json', 'r') as f:
                token_data = json.load(f)
            
            # Test if token is still valid
            if test_token(token_data['access_token']):
                return token_data['access_token']
            else:
                print("⚠️ Saved token is no longer valid")
                os.remove('lwa_token.json')
        return None
    except Exception as e:
        print(f"⚠️ Could not load saved token: {str(e)}")
        return None

def test_azure_function(access_token):
    """Test the Azure Function with the access token"""
    print("\n🧪 Testing Azure Function...")
    
    azure_url = AZURE_FUNCTION_URL
    
    # Test Smart Home Discovery request
    discovery_payload = {
        "directive": {
            "header": {
                "namespace": "Alexa.Discovery",
                "name": "Discover",
                "payloadVersion": "3",
                "messageId": "test-message-id"
            },
            "payload": {
                "scope": {
                    "type": "BearerToken",
                    "token": access_token
                }
            }
        }
    }
    
    headers = {
        'Content-Type': 'application/json',
        'Authorization': f'Bearer {access_token}'
    }
    
    try:
        response = requests.post(azure_url, json=discovery_payload, headers=headers, timeout=30)
        
        if response.status_code == 200:
            result = response.json()
            print("✅ Azure Function test successful!")
            print(f"   Discovered {len(result.get('event', {}).get('payload', {}).get('endpoints', []))} devices")
            return True
        else:
            print(f"❌ Azure Function test failed: {response.status_code}")
            print(f"   Response: {response.text}")
            return False
            
    except Exception as e:
        print(f"❌ Error testing Azure Function: {str(e)}")
        return False

def test_lambda_proxy(access_token):
    """Test the Lambda proxy with the access token"""
    print("\n🧪 Testing Lambda Proxy...")
    
    lambda_url = "https://your-lambda-url-here.execute-api.us-east-1.amazonaws.com/default/alexa-smart-home-proxy"
    
    # Test Smart Home Discovery request
    discovery_payload = {
        "directive": {
            "header": {
                "namespace": "Alexa.Discovery",
                "name": "Discover",
                "payloadVersion": "3",
                "messageId": "test-message-id"
            },
            "payload": {
                "scope": {
                    "type": "BearerToken",
                    "token": access_token
                }
            }
        }
    }
    
    headers = {
        'Content-Type': 'application/json'
    }
    
    try:
        print(f"⚠️ Note: Update lambda_url in the script with your actual Lambda URL")
        print(f"   Current URL: {lambda_url}")
        # Uncomment the lines below when you have the actual Lambda URL
        # response = requests.post(lambda_url, json=discovery_payload, headers=headers, timeout=30)
        # 
        # if response.status_code == 200:
        #     result = response.json()
        #     print("✅ Lambda Proxy test successful!")
        #     return True
        # else:
        #     print(f"❌ Lambda Proxy test failed: {response.status_code}")
        #     return False
            
    except Exception as e:
        print(f"❌ Error testing Lambda Proxy: {str(e)}")
        return False

def generate_token():
    """Main function to generate LWA token"""
    print("🚀 LWA Token Generator for Home Automation Testing")
    print("=" * 60)
    
    # Check for existing valid token
    saved_token = load_saved_token()
    if saved_token:
        print("✅ Using saved valid token")
        test_azure_function(saved_token)
        test_lambda_proxy(saved_token)
        print(f"\n🎯 Your LWA Token: {saved_token}")
        return saved_token
    
    print("🔐 Starting OAuth flow...")
    print("1. A browser window will open")
    print("2. Sign in with your Amazon account")
    print("3. Authorize the application")
    print("4. Return to this terminal")
    print()
    
    # Build authorization URL
    auth_params = {
        'client_id': LWA_CLIENT_ID,
        'scope': oauth_config.get('scope', 'profile'),
        'response_type': 'code',
        'redirect_uri': REDIRECT_URI,
        'state': 'home-automation-test'
    }
    
    auth_url = f"{AMAZON_AUTH_URL}?{urllib.parse.urlencode(auth_params)}"
    
    # Start local server to handle callback
    server = HTTPServer(('localhost', 3000), AuthCallbackHandler)
    server_thread = threading.Thread(target=server.serve_forever)
    server_thread.daemon = True
    server_thread.start()
    
    print(f"🌐 Opening browser: {auth_url}")
    print("📡 Local callback server started on: http://localhost:3000")
    
    # Open browser
    webbrowser.open(auth_url)
    
    print("\n⏳ Waiting for authorization...")
    print("   (Close this script with Ctrl+C if needed)")
    
    # Wait for the callback
    try:
        while server_thread.is_alive():
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n⏹️ Cancelled by user")
        server.shutdown()

def main():
    """Main entry point"""
    print("Choose an option:")
    print("1. Generate new LWA token")
    print("2. Test with existing token")
    print("3. Exit")
    
    choice = input("\nEnter choice (1-3): ").strip()
    
    if choice == '1':
        generate_token()
    elif choice == '2':
        saved_token = load_saved_token()
        if saved_token:
            test_azure_function(saved_token)
            test_lambda_proxy(saved_token)
            print(f"\n🎯 Your LWA Token: {saved_token}")
        else:
            print("❌ No valid saved token found. Please generate a new one.")
    elif choice == '3':
        print("👋 Goodbye!")
    else:
        print("❌ Invalid choice")

if __name__ == "__main__":
    main()
