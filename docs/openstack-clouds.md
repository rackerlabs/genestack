# Create an OpenStack Cloud Config

There are a lot of ways you can go to connect to your cluster. This example will use your cluster internals to generate a cloud config compatible with your environment using the Admin user.

## Create the needed directories

``` shell
mkdir -p ~/.config/openstack
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

!!! note

    Multi-factor authentication will prompt you for a token for every CLI interaction, unless you have caching enabled, where tokens can be cached for a set amount of time.

``` yaml
cache:
  auth: true
  expiration_time: 3600
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
```
