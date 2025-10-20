#!/usr/bin/env python3
"""
Create AWS Lambda deployment zip
This script creates a deployment-ready zip file with all dependencies
"""

import os
import zipfile
import shutil
import subprocess
import sys

def create_deployment_zip():
    """Create deployment zip for Lambda function"""
    
    print("📦 Creating Lambda deployment zip...")
    
    # Configuration
    zip_name = "alexa-lambda-manual-deployment.zip"
    temp_dir = "temp-lambda-deploy"
    
    # Clean up any existing files
    if os.path.exists(zip_name):
        os.remove(zip_name)
        print(f"🗑️ Removed existing {zip_name}")
    
    if os.path.exists(temp_dir):
        shutil.rmtree(temp_dir)
        print(f"🗑️ Cleaned up existing {temp_dir}")
    
    try:
        # Create temporary directory
        os.makedirs(temp_dir)
        print(f"📁 Created temporary directory: {temp_dir}")
        
        # Copy main Lambda function
        shutil.copy2("lambda_function.py", os.path.join(temp_dir, "lambda_function.py"))
        print("📄 Copied lambda_function.py")
        
        # Copy requirements if it exists
        if os.path.exists("requirements.txt"):
            shutil.copy2("requirements.txt", os.path.join(temp_dir, "requirements.txt"))
            print("📄 Copied requirements.txt")
            
            # Install dependencies
            print("📚 Installing Python dependencies...")
            result = subprocess.run([
                sys.executable, "-m", "pip", "install", 
                "-r", "requirements.txt", 
                "-t", temp_dir,
                "--quiet"
            ], capture_output=True, text=True)
            
            if result.returncode != 0:
                print(f"❌ Error installing dependencies: {result.stderr}")
                return False
            
            print("✅ Dependencies installed successfully")
        
        # Remove unnecessary files to reduce zip size
        for root, dirs, files in os.walk(temp_dir):
            # Remove __pycache__ directories
            dirs[:] = [d for d in dirs if not d.startswith('__pycache__')]
            
            for file in files:
                file_path = os.path.join(root, file)
                if (file.endswith('.pyc') or file.endswith('.pyo') or 
                    '.dist-info' in file or '.egg-info' in file):
                    os.remove(file_path)
        
        print("🧹 Cleaned up unnecessary files")
        
        # Create zip file
        print("🗜️ Creating deployment zip...")
        with zipfile.ZipFile(zip_name, 'w', zipfile.ZIP_DEFLATED) as zipf:
            for root, dirs, files in os.walk(temp_dir):
                for file in files:
                    file_path = os.path.join(root, file)
                    # Calculate relative path from temp_dir
                    arc_name = os.path.relpath(file_path, temp_dir)
                    zipf.write(file_path, arc_name)
        
        # Get zip file size
        zip_size = os.path.getsize(zip_name) / (1024 * 1024)  # Size in MB
        
        print(f"✅ Deployment zip created: {zip_name} ({zip_size:.2f} MB)")
        
        return True
        
    except Exception as e:
        print(f"❌ Error creating deployment zip: {str(e)}")
        return False
        
    finally:
        # Clean up temporary directory
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir)

if __name__ == "__main__":
    success = create_deployment_zip()
    sys.exit(0 if success else 1)