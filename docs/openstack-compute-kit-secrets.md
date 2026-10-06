# Creating the Compute Kit Secrets

Part of running Nova is also running placement. Setup all credentials now so we can use them across the nova and placement services.

!!! note "Information about the secrets used"

    Service secrets are managed idempotently by this service's install script. The installer creates any missing Kubernetes secrets and reuses existing values.
