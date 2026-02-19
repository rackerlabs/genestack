# Creating the Compute Kit Secrets

Part of running Nova is also running placement. Setup all credentials now so we can use them across the nova and placement services.

!!! note "Secret generation has been moved to the install-<service>.sh script"
    The individual service scripts now handle their own secret lifecycle management.

!!! note "EXPERIMENTAL"
    The `install-<service>.sh` scripts now support a `--rotate-secret` command line argument that will create new secrets for the service and redeploy it.
