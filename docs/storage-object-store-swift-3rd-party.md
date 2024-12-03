# Swift 3rd party client use

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
