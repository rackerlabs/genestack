import os
import sys
import boto3
from botocore.client import Config
from botocore.exceptions import NoCredentialsError, PartialCredentialsError, ClientError


def get_env_variables():
    """Get environment variables."""
    access_key = os.getenv("ACCESS_KEY")
    secret_key = os.getenv("SECRET_KEY")
    host = os.getenv("S3_HOST")
    region = os.getenv("S3_REGION", "SJC3")

    if not all([access_key, secret_key, host]):
        print(
            "Error: Missing one or more environment variables: ACCESS_KEY, SECRET_KEY, S3_HOST"
        )
        sys.exit(1)

    return access_key, secret_key, host, region


def create_s3_connection(access_key, secret_key, host, region):
    """Create S3 connection using Boto3 with error handling."""
    try:
        s3_client = boto3.client(
            "s3",
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
            endpoint_url=host,
            region_name=region,
            config=Config(signature_version="s3v4"),  # Swift often requires SigV4
        )
        # Test connection
        s3_client.list_buckets()
        return s3_client
    except NoCredentialsError:
        print("Error: No credentials provided.")
    except PartialCredentialsError:
        print("Error: Incomplete credentials provided.")
    except ClientError as e:
        print(f"Client error while creating connection: {e}")
    except Exception as e:
        print(f"Unexpected error creating S3 connection: {e}")

    return None


def upload_file_to_bucket(conn, file_to_upload, bucket_name):
    """Upload a file to a specific S3 bucket using Boto3."""
    try:
        # Check if the bucket exists
        conn.head_bucket(Bucket=bucket_name)
    except ClientError as e:
        print(f"Bucket '{bucket_name}' does not exist or is not accessible.")
        return

    key = os.path.basename(file_to_upload)

    try:
        conn.upload_file(file_to_upload, bucket_name, key)
        print(f"File '{file_to_upload}' uploaded successfully to {bucket_name}/{key}.")
    except FileNotFoundError:
        print(f"Error: File '{file_to_upload}' not found.")
    except ClientError as e:
        print(f"Client error during upload: {e}")
    except Exception as e:
        print(f"Unexpected error uploading file: {e}")


def list_all_buckets(conn):
    """List all buckets using Boto3."""
    try:
        response = conn.list_buckets()
        for bucket in response["Buckets"]:
            print(f"{bucket['Name']}\t{bucket['CreationDate']}")
    except ClientError as e:
        print(f"Client error listing buckets: {e}")
    except Exception as e:
        print(f"Unexpected error listing buckets: {e}")


def create_bucket_if_not_exists(conn, bucket_name):
    """Create the bucket if it does not exist."""
    try:
        conn.head_bucket(Bucket=bucket_name)
    except ClientError as e:
        error_code = e.response["Error"]["Code"]
        if error_code == "404":
            try:
                conn.create_bucket(Bucket=bucket_name)
                print(f"Bucket '{bucket_name}' created successfully.")
            except ClientError as create_error:
                print(f"Client error creating bucket: {create_error}")
            except Exception as create_error:
                print(f"Unexpected error creating bucket: {create_error}")
        else:
            print(f"Error accessing bucket '{bucket_name}': {e}")
    except Exception as e:
        print(f"Unexpected error checking bucket: {e}")


def main():
    """Main function."""
    if len(sys.argv) != 2:
        print("Usage: python backup.py <file_to_upload>")
        sys.exit(1)

    file_to_upload = sys.argv[1]
    access_key, secret_key, host, region = get_env_variables()
    conn = create_s3_connection(access_key, secret_key, host, region)

    if not conn:
        print("Failed to create S3 connection.")
        sys.exit(1)

    create_bucket_if_not_exists(conn, "etcd-backups")
    upload_file_to_bucket(conn, file_to_upload, "etcd-backups")
    # list_all_buckets(conn)


if __name__ == "__main__":
    main()
