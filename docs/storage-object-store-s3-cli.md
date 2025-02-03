
# Object Store Management using the S3 client

## Goal

Use the command-line utility `aws` to perform operations on your object store.

!!! note

    Before getting started, generate credentials that will be used to authenticate the S3 API provided by OpenStack Flex Object Storage.

## Install the `awscli` package

Before we get started, we need to install the `awscli` package. You can install it using the following command:

``` shell
pip install awscli awscli-plugin-endpoint
```

## Generate the S3 credentials

The following credentials will be used to authenticate the S3 API provided by OpenStack Flex Object Storage.

``` shell
openstack --os-cloud default ec2 credentials create
```

!!! example "The output should look similar to the following"

    ``` shell
    +------------+---------------------------------------------------------------------------------------------------------+
    | Field      | Value                                                                                                   |
    +------------+---------------------------------------------------------------------------------------------------------+
    | access     | $ACCESS_ID                                                                                              |
    | links      | {'self': 'http://keystone.api.sjc3.rackspacecloud.com/v3/users/$USER_ID/credentials/OS-EC2/$ACCESS_ID'} |
    | project_id | $PROJECT_ID                                                                                             |
    | secret     | $SECRET_VALUE                                                                                           |
    | trust_id   | None                                                                                                    |
    | user_id    | $USER_ID                                                                                                |
    +------------+---------------------------------------------------------------------------------------------------------+
    ```

## Create the AWS CLI Configuration Files

Create an aws-config file. Be sure to replace `sjc3` with the region of your object store.

!!! example "`~/aws-config` file"

    ``` conf
    [plugins]
    endpoint = awscli_plugin_endpoint

    [profile default]
    region = sjc3
    s3 =
    endpoint_url = https://swift.api.sjc3.rackspacecloud.com
    signature_version = s3v4
    s3api =
    endpoint_url = https://swift.api.sjc3.rackspacecloud.com
    ```

Create an aws-credentials file. Be sure to replace `ACCESS` and `SECRET` with the values from the credential generation command.

!!! example "`~/aws-credentials` file"

    ``` conf
    [default]
    aws_access_key_id = $ACCESS_ID
    aws_secret_access_key = $SECRET_VALUE
    ```

## Using the `aws` CLI and Validating the Configuration

To validate the configuration, run the following command to create a `newbucket` in the object store.

``` shell
aws --profile default s3api create-bucket --bucket newbucket
```

Ensure the new bucket exists by listing all buckets.

``` shell
aws --profile default s3api list-buckets
```

!!! example "Output"

    ``` json
    {
        "Buckets": [
            {
                "Name": "newbucket",
                "CreationDate": "2009-02-03T16:45:09.000Z"
            }
        ],
        "Owner": {
            "DisplayName": "$USER_ID:$USER_NAME",
            "ID": "$USER_ID:$USER_NAME"
        },
        "Prefix": null
    }

For more information on the `awscli` tooling use the `help` flag for a detailed breakdown.

``` shell
aws --profile default help
```
