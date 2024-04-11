import os
import sys
import boto
import boto.s3.connection


def get_env_variables():
    """Get environment variables."""
    access_key = os.getenv("ACCESS_KEY")
    secret_key = os.getenv("SECRET_KEY")
    host = os.getenv("S3_HOST")

    port_str = os.getenv("S3_PORT", "8081")
    try:
        port = int(port_str)
    except ValueError:
        raise ValueError(
            f"Environment variable 'S3_PORT' has an invalid value: {port_str}"
        )

    # Properly convert the 'S3_HOST_SSL' environment variable to a boolean
    secure_str = os.getenv("S3_HOST_SSL", "false").lower()
    secure = secure_str in ["true", "1", "t", "y", "yes"]

    return access_key, secret_key, host, port, secure


def create_s3_connection(access_key, secret_key, host, port, secure):
    """Create S3 connection."""
    conn = boto.connect_s3(
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        host=host,
        port=port,
        is_secure=secure,
        calling_format=boto.s3.connection.OrdinaryCallingFormat(),
    )
    return conn


def upload_file_to_bucket(conn, file_to_upload):
    """Upload a file to a specific S3 bucket."""
    bucket_name = "etcd-backup-bucket"
    bucket = conn.get_bucket(bucket_name)
    key = bucket.new_key(os.path.basename(file_to_upload))
    key.set_contents_from_filename(file_to_upload)


def list_all_buckets(conn):
    """List all buckets."""
    for bucket in conn.get_all_buckets():
        print(
            "{name}\t{created}".format(
                name=bucket.name,
                created=bucket.creation_date,
            )
        )


def main():
    """Main function."""
    if len(sys.argv) != 2:
        print("Usage: python your_script.py <file_to_upload>")
        sys.exit(1)

    file_to_upload = sys.argv[1]
    access_key, secret_key, host, port, secure = get_env_variables()
    conn = create_s3_connection(access_key, secret_key, host, port, secure)
    upload_file_to_bucket(conn, file_to_upload)
    list_all_buckets(conn)


if __name__ == "__main__":
    main()
