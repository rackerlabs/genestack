# Swift 3rd party clients, SDK's and API

## Openstack Swift SDK and Projects

A complete list of SDKs, integrations and libraries can be found here [Swift Associated Projects](https://docs.openstack.org/swift/latest/associated_projects.html)

## Getting started with S3

Using the openstack CLI issue the following command to generate a S3 token

``` shell
openstack ec2 credentials create
```

To view all ec2 credentials use issue the following command:

``` shell
openstack credential list
```

To view access and secret keys issue the following command:

``` shell
openstack credential show <credential-id>
```

!!! note
credential-id is obtained from credentials list command

## Using S3 boto3

S3 boto3 is a python library that can be imported into your python code to perform object tasks such as, uploading, deleting and reading objects from a Flex Object endpoint.

Using the access and secret keys from the commands above you can start using Flex Object storage in your python application.  An example of using S3 Boto3 in python can be found here:

``` python
import boto3
import botocore
boto3.set_stream_logger(name='botocore')  # this enables debug tracing
session = boto3.session.Session()
s3_client = session.client(
    service_name='s3',
    aws_access_key_id='ACCESS',
    aws_secret_access_key='SECRET',
    endpoint_url='https://YOUR.ENDPOINT.HOST/',
    # The next option is only required because my provider only offers "version 2"
    # authentication protocol. Otherwise this would be 's3v4' (the default, version 4).
    config=botocore.client.Config(signature_version='s3'),
)
s3_client.list_objects(Bucket='bucket_name')
```

More information on boto3 can be found here: [S3 Boto3 Reference](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/s3.html)

## Rclone

Rclone is a powerful sync tool, much like rsync, Rclone can sync local and remote containers and buckets.

Setup is simple, download rclone from [Rclone Download](https://rclone.org/downloads/)  Once downloaded configuration for Flex Object / Swift can be found here: [Rclone setup for Swift](https://rclone.org/swift/)
