# OpenStack Ironic Policy Configuration

This document explains how to enable and manage policy enforcement for OpenStack Ironic. It covers the `oslo_policy` settings used to enable modern RBAC behavior and shows how to reference a custom `policy.yaml` file for Ironic-specific access control.

## Introduction

OpenStack Ironic uses `oslo.policy` to authorize API operations. These policy rules determine which users and roles can view, create, update, and manage bare metal resources such as nodes, ports, port groups, allocations, and chassis objects.

In many deployments, Ironic starts with compatibility-oriented policy behavior. To align the service with modern OpenStack RBAC expectations, enable scoped policy enforcement and newer default rules in the Ironic configuration.

## Enable Policy Enforcement

The two main `oslo_policy` settings are:

- `enforce_scope`
- `enforce_new_defaults`

These settings are configured under `conf.ironic.oslo_policy` in the Ironic Helm overrides.

When enabled, these options make Ironic evaluate authorization using scoped tokens and newer policy defaults.

## What These Settings Mean

### `enforce_scope`

When `enforce_scope` is set to `true`, Ironic validates whether the token scope matches the requested action. This is important for distinguishing between system-scoped and project-scoped access.

Use this setting when you want stricter and more predictable RBAC evaluation.

### `enforce_new_defaults`

When `enforce_new_defaults` is set to `true`, Ironic uses the newer default policy rules provided by the service and the OpenStack policy framework.

Use this setting when your deployment is ready to move away from legacy compatibility behavior and adopt current default policy expectations.

## Update Helm Overrides

In your Helm override values, update the `conf.ironic.oslo_policy` section.

The current configuration looks like this:

```yaml
conf:
  ironic:
    oslo_policy:
      enforce_scope: false
      enforce_new_defaults: false
```

change it to:

```yaml
conf:
  policy:
    # Define or reference custom policy rules here if needed
  ironic:
    oslo_policy:
      enforce_scope: true
      enforce_new_defaults: true
```

This change is typically made in `ironic-helm-overrides.yaml`

## Custom Policy File

If you need behavior beyond the shipped defaults, define a custom `policy.yaml` file. This file explicitly controls which roles can perform which Ironic operations.

The reusable example policy for this guide is available at 

!!! example "Example custom Ironic policy file `/ironic-policy.yaml`"

    ```yaml
    --8<-- "base-helm-configs/ironic/ironic-policy.yaml.example"
    ```

## Policy Design Overview

The example `policy.yaml` implements a multi-tenant bare metal access model. It includes rules for:

- Node creation and deletion
- Owner and lessee access
- Driver information visibility
- Maintenance and provisioning actions
- Port and port group operations
- Allocation handling
- Chassis and inspection rule management
- Virtual media operations

This model is useful for environments where bare metal is exposed beyond cloud administrators and needs a controlled tenant-aware RBAC design.

## Example Access Model

The policy file supports patterns such as:

- System administrators retain cloud-wide control
- Project managers can manage nodes owned by their project
- Project members can operate nodes they own or lease
- Readers can view allowed resources without modifying them
- Service roles can continue to perform automation and control plane actions

This approach works well for bring-your-own-node and shared bare metal environments.

## Recommended Rollout

When enabling stricter policy behavior, use a staged rollout:

1. Review the custom `policy.yaml` against the exact Ironic release you are running.
2. Enable `enforce_scope` in a test environment.
3. Enable `enforce_new_defaults` after confirming expected role behavior.
4. Validate system-scoped, project-scoped, and service-role access paths.
5. Promote the updated policy and Helm configuration into production.

This reduces the risk of unintentionally blocking operators, services, or tenants.

## Operational Considerations

Keep the following points in mind:

- Policy behavior can vary between OpenStack releases.
- Scope enforcement can expose old role assignments that no longer behave correctly under stricter RBAC checks.
- Custom policy rules should be reviewed carefully before exposing operations such as power control, driver updates, node reassignment, or provisioning state changes.
- Sensitive fields such as credentials should remain masked unless there is a specific operational reason to reveal them.

## Validation

After enabling policy enforcement and applying the custom policy file, validate access with representative user roles.

Examples include:

- Listing nodes as a reader
- Updating a node as a project manager
- Changing node provision state as an authorized operator
- Confirming that unauthorized roles are denied restricted actions

This validation is important because policy problems often appear only when real scoped tokens are used against the API.

## References

- [Ironic policy configuration](https://docs.openstack.org/ironic/latest/configuration/policy.html)
- [OpenStack RBAC and scope concepts](https://docs.openstack.org/oslo.policy/latest/user/usage.html)
