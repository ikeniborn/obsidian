#!/usr/bin/env python3
"""
S3 Upload Script for CouchDB Backups

Uploads backup files to S3-compatible storage using boto3.
Supports AWS S3, Yandex Object Storage, MinIO, etc.
"""

import os
import sys
import boto3
from botocore.exceptions import ClientError, NoCredentialsError
from pathlib import Path

def load_env_file(env_path="/opt/notes/.env"):
    """Load environment variables from .env file"""
    env_vars = {}
    if os.path.exists(env_path):
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#'):
                    key, _, value = line.partition('=')
                    env_vars[key.strip()] = value.strip()
    return env_vars

def upload_to_s3(file_path, s3_prefix=""):
    """Upload file to S3-compatible storage"""

    # Load config from .env
    env = load_env_file()

    access_key = env.get('S3_ACCESS_KEY_ID') or os.getenv('S3_ACCESS_KEY_ID')
    secret_key = env.get('S3_SECRET_ACCESS_KEY') or os.getenv('S3_SECRET_ACCESS_KEY')
    bucket_name = env.get('S3_BUCKET_NAME') or os.getenv('S3_BUCKET_NAME')
    endpoint_url = env.get('S3_ENDPOINT_URL') or os.getenv('S3_ENDPOINT_URL')
    region = env.get('S3_REGION', 'ru-central1')

    if not all([access_key, secret_key, bucket_name]):
        print("ERROR: S3 credentials not configured in .env")
        return False

    # Create S3 client
    try:
        s3_client = boto3.client(
            's3',
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
            endpoint_url=endpoint_url,
            region_name=region
        )
    except Exception as e:
        print(f"ERROR: Failed to create S3 client: {e}")
        return False

    # Upload file
    file_name = Path(file_path).name
    s3_key = f"{s3_prefix}{file_name}"

    try:
        print(f"Uploading {file_name} to s3://{bucket_name}/{s3_key}...")
        s3_client.upload_file(
            file_path,
            bucket_name,
            s3_key,
            ExtraArgs={'StorageClass': 'STANDARD'}
        )
        print(f"✅ Upload successful: s3://{bucket_name}/{s3_key}")
        return True

    except FileNotFoundError:
        print(f"ERROR: File not found: {file_path}")
        return False
    except NoCredentialsError:
        print("ERROR: Invalid S3 credentials")
        return False
    except ClientError as e:
        print(f"ERROR: S3 upload failed: {e}")
        return False

def test_s3_connection():
    """Test S3 connection without uploading"""
    env = load_env_file()

    access_key = env.get('S3_ACCESS_KEY_ID') or os.getenv('S3_ACCESS_KEY_ID')
    secret_key = env.get('S3_SECRET_ACCESS_KEY') or os.getenv('S3_SECRET_ACCESS_KEY')
    bucket_name = env.get('S3_BUCKET_NAME') or os.getenv('S3_BUCKET_NAME')
    endpoint_url = env.get('S3_ENDPOINT_URL') or os.getenv('S3_ENDPOINT_URL')
    region = env.get('S3_REGION', 'ru-central1')

    if not all([access_key, secret_key, bucket_name]):
        print("ERROR: S3 credentials not configured")
        return False

    try:
        s3_client = boto3.client(
            's3',
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
            endpoint_url=endpoint_url,
            region_name=region
        )
        s3_client.head_bucket(Bucket=bucket_name)
        print(f"✅ S3 connection successful: bucket '{bucket_name}' is accessible")
        return True

    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        if error_code == '404':
            print(f"ERROR: Bucket '{bucket_name}' not found")
        elif error_code == '403':
            print(f"ERROR: Access denied to bucket '{bucket_name}'")
        else:
            print(f"ERROR: S3 connection failed: {e}")
        return False
    except Exception as e:
        print(f"ERROR: Failed to connect to S3: {e}")
        return False

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: s3_upload.py <file_path> [s3_prefix]")
        print("       s3_upload.py --test")
        sys.exit(1)

    if sys.argv[1] == "--test":
        success = test_s3_connection()
        sys.exit(0 if success else 1)

    file_path = sys.argv[1]
    s3_prefix = sys.argv[2] if len(sys.argv) > 2 else ""

    success = upload_to_s3(file_path, s3_prefix)
    sys.exit(0 if success else 1)
