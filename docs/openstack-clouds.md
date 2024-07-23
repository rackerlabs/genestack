# Create an OpenStack Cloud Config

There are a lot of ways you can go to connect to your cluster. This example will use your cluster internals to generate a cloud config compatible with your environment using the Admin user.

## Create the needed directories

``` shell
mkdir -p ~/.config/openstack
```

## Token Caching

In the following examples authentication caching is able by default in config, however, to make this work on most modern operating systems you will need to install the `keyring` package. Installing the `keyring` is simple and can be done across a number of operating systems with the default package manager.

#### MacOS

``` shell
brew install keyring
```

#### Ubuntu or Debian

``` shell
apt install python3-keyring
```

#### Enterprise Linux

``` shell
dnf install python3-keyring
```

#### Source

!!! tip

    Users may want to use a Virtual Environment so that they do not have any risk of hurting their default Python environment. For more information on seting up a venv please visit the python [documentation](https://packaging.python.org/en/latest/tutorials/installing-packages/#creating-and-using-virtual-environments) on working with virtual environments.

``` shell
python -m pip install keyring
```

##### Microsoft Windows Example

Ensure that the C:\Python27\Scripts directory is defined in the PATH environment variable, and use the easy_install command from the setuptools package:

``` shell
C:> py -m pip install keyring
```

## Generate the cloud config file from within the environment

``` shell
cat >  ~/.config/openstack/clouds.yaml <<EOF
cache:
  auth: true
  expiration_time: 3600
clouds:
  default:
    auth:
      auth_url: $(kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_AUTH_URL}' | base64 -d)
      project_name: $(kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_PROJECT_NAME}' | base64 -d)
      tenant_name: $(kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_USER_DOMAIN_NAME}' | base64 -d)
      project_domain_name: $(kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_PROJECT_DOMAIN_NAME}' | base64 -d)
      username: $(kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_USERNAME}' | base64 -d)
      password: $(kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_PASSWORD}' | base64 -d)
      user_domain_name: $(kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_USER_DOMAIN_NAME}' | base64 -d)
    region_name: $(kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_REGION_NAME}' | base64 -d)
    interface: $(kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_INTERFACE}' | base64 -d)
    identity_api_version: "3"
EOF
```

## Configure openstack client by hand

Creating the `clouds.yaml` file by hand is fairly simple you just need a couple pieces of information to fill out the file.

| Key                 | Description      | Type   | Required |
| ------------------- | ---------------- | ------ | -------- |
| PROJECT_NAME        | The project name | STRING | False    |
| PROJECT_ID          | The project ID   | STRING | False    |
| PROJECT_DOMAIN_NAME | Domain name      | STRING | True     |
| USERNAME            | Username         | STRING | True     |
| PASSWORD_OR_APIKEY  | Secure Key       | STRING | True     |
| PROJECT_DOMAIN_NAME | Domain name      | STRING | True     |

### Simple example for public access

``` yaml
cache:
  auth: true
  expiration_time: 3600
clouds:
  regionone:
    auth:
      auth_url: https://$KEYSTONE_URL/v3
      project_name: $PROJECT_NAME
      project_domain_name: $PROJECT_DOMAIN_NAME
      username: $USERNAME
      password: $PASSWORD_OR_APIKEY
      user_domain_name: $PROJECT_DOMAIN_NAME
    region_name:
      - RegionOne
    interface: public
    identity_api_version: "3"
```

### Simple example for public access with Multi-factor Authentication

``` yaml
clouds:
  regionone-mfa:
    auth_type: "v3multifactor"
    auth_methods:
      - v3password
      - v3totp
    auth:
      auth_url: https://$YOUR_KEYSTONE_HOST/v3
      project_name: $PROJECT_NAME
      project_domain_name: $PROJECT_DOMAIN_NAME
      username: $USERNAME
      password: $PASSWORD_OR_APIKEY
      user_domain_name: $PROJECT_DOMAIN_NAME
    region_name:
      - RegionOne
    interface: public
    identity_api_version: "3"
  regionone-token:
    auth_type: "v3token"
    auth:
      auth_url: https://$YOUR_KEYSTONE_HOST/v3
      project_name: $PROJECT_NAME
      project_domain_name: $PROJECT_DOMAIN_NAME
    region_name:
      - RegionOne
    interface: public
    identity_api_version: "3"
```

When working with MFA enabled accounts we generally recommend a two step process. While a single multi-factor enabled cloud account is more than enough to run commands within the cloud, the client will require a one time use token every time a command is executed. For this reason we recommend two cloud stanzas which provide a much better over all user experience with working with MFA.

#### Step one - MFA

``` shell
export OS_TOKEN=$(openstack --os-cloud regionone-mfa token issue -c id -f value)
```

!!! Note

    This command will prompt you for your TOTP key before returning a valid token.

This command will return the token ID and store the value within an environment variable which will be used within Step Two.

#### Step Two - Token Auth

Run project specific commands within the defined token

``` shell
openstack --os-cloud regionone-token ...
```
