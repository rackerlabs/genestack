# Deploy Keystone

The OpenStack Identity service supports integration with existing LDAP directories for authentication and authorization services. OpenStack Identity only supports read-only LDAP integration. Integrating Active Directory (AD) with OpenStack Keystone is usually done via LDAP backend. Keystone doesn’t talk to AD “natively” — it treats AD as an LDAP directory.

Keystone → LDAP driver → Active Directory

Auth happens against AD, but Keystone still manages projects, roles, tokens.

## Example LDAP configuration

!!! example "LDAP/AD config `/etc/genestack/helm-configs/keystone/keystone-helm-overrides-ldap.yaml`"

    ``` shell
    --8<-- "base-helm-configs/keystone/keystone-helm-overrides-ldap.yaml"
    ```

## Install/Reinstall Keystone Service

```bash
/opt/genestack/bin/install-keystone.sh
```

## Validate functionality

``` shell
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack user list --domain <AD domain name>
```

[UPSTREAM-DOCUMENTATION](https://docs.openstack.org/keystone/latest/admin/configuration.html#integrate-identity-with-ldap)
