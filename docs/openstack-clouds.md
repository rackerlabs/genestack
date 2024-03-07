# Create an OpenStack Cloud Config

There are a lot of ways you can go to connect to your cluster. This example will use your cluster internals to generate a cloud config compatible with your environment using the Admin user.

## Create the needed directories

``` shell
mkdir -p ~/.config/openstack
```

## Generate the cloud config file

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
