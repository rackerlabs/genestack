# OpenStack Getting Started with CLI

After you have installed the OpenStack command-line tools, you can proceed with initializing your account. This guide will show you how to run a command with an unscoped and scoped token to set up your account.

!!! note

    This document makes the assumption that your account has the `OPENSTACK_FLEX` role assigned to it. If you do not have the `OPENSTACK_FLEX` role, you may not be permitted access to the environment.

## Prerequisites

1. Ensure you have the OpenStack command-line tools installed. If not, follow the instructions in the [Openstack Deploying the Command Line Tools](openstack-deploy-cli.md) documentation.
2. Obtain your OpenStack credentials: **username**, **password**, and **domain**.
3. Obtain the authentication URL.

## Authenticating with OpenStack

Before you can run OpenStack commands, you need to authenticate using your OpenStack credentials. This involves obtaining an unscoped token and then using it to get a scoped token.

### Step 1: Obtain your projects

To obtain a list of our available projects, we'll need to run a command with an unscoped token. Unscoped tokens are used to identify a user but does not define an association with a project.

!!! note

    This step authenticates you with the OpenStack Identity service (Keystone) and is required for first time access to the environment.

Run the following command, replacing the placeholders with your actual OpenStack credentials:

``` shell
openstack project list --os-auth-url ${AUTH_URL} \
                       --os-username ${USERNAME} \
                       --os-password ${PASSWORD} \
                       --os-user-domain-name ${DOMAIN_NAME}
```

> Replace the placeholders with your actual credentials and project name.

This command returns a list of your available projects, the returned information will be used to in later commands

### Step 2: Obtain a Scoped Token

A scoped token is associated with a specific project and is used to perform actions within that project.

Run the following command to obtain a scoped token:

``` shell
openstack token issue --os-auth-url ${AUTH_URL} \
                      --os-username ${USERNAME} \
                      --os-password ${PASSWORD} \
                      --os-user-domain-name ${DOMAIN_NAME} \
                      --os-project-domain-name ${DOMAIN_NAME} \
                      --os-project-name ${PROJECT_NAME}
```

This command returns a scoped token that you will use for subsequent OpenStack commands.

## Running an OpenStack Command

With your scoped token, you can now run OpenStack commands. For example, to list the available flavors, use:

``` shell
openstack flavor list --os-auth-url ${AUTH_URL} \
                      --os-username ${USERNAME} \
                      --os-password ${PASSWORD} \
                      --os-user-domain-name ${DOMAIN_NAME} \
                      --os-project-domain-name ${DOMAIN_NAME} \
                      --os-project-name ${PROJECT_NAME}
```

This command lists all flavors available to your project.

## Further Reading

For more detailed information on OpenStack command-line interface and authentication, refer to the [our documentation](openstack-clouds.md) for creating your `clouds.yaml`.

By following these steps, you should be able to initialize your account and start using the OpenStack CLI.
