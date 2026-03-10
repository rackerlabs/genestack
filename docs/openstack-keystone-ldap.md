# Deploy Keystone

The OpenStack Identity service supports integration with existing LDAP directories for authentication and authorization services. OpenStack Identity only supports read-only LDAP integration. Integrating Active Directory (AD) with OpenStack Keystone is usually done via LDAP backend. Keystone doesn’t talk to AD “natively” — it treats AD as an LDAP directory.

Keystone → LDAP driver → Active Directory

Auth happens against AD, but Keystone still manages projects, roles, tokens.

## Example LDAP configuration

```bash
---
conf:
  keystone:
    identity:
      driver: sql
      default_domain_id: default
      domain_specific_drivers_enabled: True
      domain_configurations_from_database: True
      domain_config_dir: /etc/keystone/domains
  ks_domains:
    ldapdomain:
      identity:
        driver: ldap
      ldap:
        url: "ldap://ldap.openstack.svc.cluster.local:389" # ADD LDAP or LDAPS URL
        user: "cn=admin,dc=cluster,dc=local"
        password: password
        suffix: "dc=cluster,dc=local"
        user_attribute_ignore: "enabled,email,tenants,default_project_id"
        query_scope: sub
        user_enabled_emulation: True
        user_enabled_emulation_dn: "cn=overwatch,ou=Groups,dc=cluster,dc=local"
        user_tree_dn: "ou=People,dc=cluster,dc=local"
        user_enabled_mask: 2
        user_enabled_default: 512
        user_name_attribute: cn
        user_id_attribute: sn
        user_mail_attribute: mail
        user_pass_attribute: userPassword
        group_tree_dn: "ou=Groups,dc=cluster,dc=local"
        group_filter: ""
        group_objectclass: ""
        group_id_attribute: cn
        group_name_attribute: cn
        group_desc_attribute: description
        group_member_attribute: memberUID
        use_pool: true
        pool_size: 27
        pool_retry_max: 3
        pool_retry_delay: 0.1
        pool_connection_timeout: 15
        pool_connection_lifetime: 600
        use_auth_pool: true
        auth_pool_size: 100
        auth_pool_connection_lifetime: 60
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
