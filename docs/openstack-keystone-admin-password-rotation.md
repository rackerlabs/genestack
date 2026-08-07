# Background

- This contains the steps to rotate the `admin` password for _Keystone_.

# Hyperconverged lab testing

- If testing in a hyperconverged lab, install _Octavia_ or build the
  hyperconverged lab with `-x`
- Install Blazar as this component embeds the admin password in its config
- Install _prometheus-openstack-exporter_ / `os-metrics` as per [Openstack Exporter](https://docs.rackspacecloud.com/prometheus-openstack-metrics-exporter/)

# Preliminaries

- You can execute steps in the "preliminaries" section outside of a
  change window or just prior to the start of the change window to
  have as much as possible prepared when starting impacting changes
- **Record information when directed.**
    - You will collect and record some values useful for later use,
      such as base64 encodings of passwords and the sha256 checksums
      of them
- **Set aliases when directed**, as subsequent steps may depend on them

1. Retrieve the `keystone-admin` secret

    **command**:

    ```
    kubectl -n openstack get secret keystone-admin -o json | \
    jq -r '.data.password | @base64d'
    ```

    **example output**:

    ```
    REDACTED
    ```

1. Verify the retrieved `admin` password matches external secure
   password or credential stores

    - You may wish to ensure you have the old password recorded in the
      event that you would like to identify any missed rotation
      locations in current configurations, etc.
    - Record the location or bookmark your credential store

1. Retrieve the current `admin` password and its base64 encoding from
   `/etc/genestack/kubesecrets.yaml`
    - You may record the base64 encoding now, or wait until directed
      in later steps
    - You can skip this step if your installation doesn't have this file
    - If it exists, verify that it matches the password you retrieved
      in the previous step.

    ```
    cd /etc/genestack
    yq 'select(.metadata.name == "keystone-admin") |
      .data.password' kubesecrets.yaml | base64 -d ; echo
    yq 'select(.metadata.name == "keystone-admin") |
      .data.password' kubesecrets.yaml
    ```

1. Generate and record a list of where the current admin password
   occurs in the _namespace_ `openstack` secrets

    ```
    /opt/genestack/scripts/find-old-password-in-secrets.sh
    ```

    See example output in footnotes output.

    This list will likely look intimidating, but a script will change
    the password for the ones that include `keystone-admin` in the name

    If you see paths like `.data["blazar.conf"]` (or
    `".data[\"blazar.conf\"]` from the JSON-escaped output), indicating
    the password embedded in a configuration file, for any services
    besides _Blazar_ or _Octavia_, stop and assess how to deal with
    this. At the time of writing of this procedure, this only affected
    _Blazar_ and _Octavia_, so the steps below only account for the
    admin password occurring in the configuration file for those two
    services.

    If secrets `openstack-config` and `clouds-yaml-secret` show up, the
    steps for `os-metrics` / _prometheus_-openstack-exporter take care
    of that later.

1. Generate two passwords and record them for use
    - We will use one as the password for a temporary "breakglass"
      alternative admin account, and the other for the actual
      password we use as the new password for the existing admin user
    - The original password looks has 32 characters, includes upper
      and lowercase letters, numbers, and underscores
    - The `pwgen` command below will generate passwords like this
        - It runs a bit long and ugly because to get an underscore you
         have to use the switch to include special characters, then
         exclude all of them except for the _
    - As a precaution, you may wish to avoid passwords with leading
      underscores, although it should not cause a problem
    - If you don't have `pwgen`, just make a 32 character password with
      mixed case letters, digits, and the underscore

    ```
    pwgen \
    --capitalize \
    --numerals \
    --secure \
    --symbols \
    --remove-chars="%{},!~|/()<>&\"[]=.+';?\$-*#`:^\\@" 32 3 | \
    grep -vE '^_'
    ```

1. Create the `breakglass` account
    - This creates a temporary backup admin account for the duration
      of this procedure in case issues occur with the `admin` account
      itself
    - Use the password you generated in the previous step for this account

    ```
    openstack user create \
    --domain default \
    --password-prompt \
    breakglass
    ```

1. Add the admin role for the `breakglass` account

    ```
    openstack role add \
    --user breakglass \
    --user-domain default \
    --project admin \
    --project-domain default \
    admin
    ```

1. Verify roles for the `breakglass` account
    - You should see that it has the admin role

    **command**:

    ```
    openstack role assignment list \
    --user breakglass \
    --user-domain default \
    --project admin \
    --project-domain default \
    --names
    ```

    **example output**:

    ```
    +-------+--------------------+-------+---------------+--------+--------+-----------+
    | Role  | User               | Group | Project       | Domain | System | Inherited |
    +-------+--------------------+-------+---------------+--------+--------+-----------+
    | admin | breakglass@Default |       | admin@Default |        |        | False     |
    +-------+--------------------+-------+---------------+--------+--------+-----------+
    ```

1. Make a temporary `clouds.yaml` for the `breakglass` account
    - This user gets deleted later, so this just copies `clouds.yaml`
      to a new location and uses that
    - When invoking `vi`, change the `admin` account to the
      `breakglass` account
        - Change the username and the cloud to `breakglass`

    ```
    sudo cp ~/.config/openstack/clouds.yaml ~/breakglass.yaml
    sudo vi ~/breakglass.yaml
    ```

    As an example from a hyperconverged lab, having changed `default`
    for the "os-cloud" to `breakglass`, and using `breakglass` for the
    username instead of `admin`. You do keep the string `admin` in
    places, so do not blindly replace `admin` with `breakglass`:

    ```
    cache:
      auth: true
      expiration_time: 3600
    clouds:
      breakglass:
        auth:
          auth_url: http://keystone-api.openstack.svc.cluster.local:5000/v3
          project_name: admin
          tenant_name: default
          project_domain_name: default
          username: breakglass
          password: REDACTED
          user_domain_name: default
        region_name: RegionOne
        interface: internal
        identity_api_version: "3"
    ```

1. Make sure `openstack token issue` works for the `breakglass` account

    **command**:

    ```
    env OS_CLIENT_CONFIG_FILE=~/breakglass.yaml \
    openstack --os-cloud breakglass token issue
    ```

    **example output**:

    ```
    +------------+------------------------------------------------+
    | Field      | Value                                          |
    +------------+------------------------------------------------+
    | expires    | 2026-08-07T03:25:44+0000                       |
    | id         | gAAAAABqdKd4bQ9PHXiiOj33ge2i_-REDACTEDBLAHBLAH |
    | project_id | a723633c55b946b9b4d8ab70015004bf               |
    | user_id    | 5d778914fe3e4045948e6b7288ada546               |
    +------------+------------------------------------------------+
    ```

1. Set an alias for the `breakglass account`
   - **Modify as needed** based on how you ensured you could invoke it
     last step.
   - The procedure doesn't actually use this; you may simply record the
     command instead

     **command**:

     ```
     alias openstack_breakglass=\
     'env OS_CLIENT_CONFIG_FILE=~/breakglass.yaml openstack --os-cloud breakglass'
     ```

1. base64 encode the old and new password and record the base64 and
   sha256 checksums of them both for later use
    - Record and keep both of these values
    - Watch carefully when cutting and pasting, as double-clicking
      often excludes trailing `=` characters as word boundaries if
      you select for copy and paste that way

    command (run twice, once for each password, and obviously,
    paste the password):

    ```
    printf 'Password: ' >&2
    stty -echo
    IFS= read -r password
    stty echo
    printf '\n' >&2

    printf '%s' "$password" |
    perl -MDigest::SHA=sha256_hex -MMIME::Base64=encode_base64 -0777 -e '
        my $password = <STDIN> // "";
        $password =~ s/\r?\n\z//;
        print "base64: ", encode_base64($password, ""), "\n";
        print "sha256: ", sha256_hex($password), "\n";
    '

    unset password
    ```

    **example output**:

    ```
    Password:
    base64: REDACTED
    sha256: 3bbf200cb7b29bbfebdd78110a82250b3548ef008ad2fb0b3cff7829427f0b3f
    ```

1. Base64 decode what you encoded and ensure you get your original
   password back
    - Obviously, paste the base64 encoding and ensure you get the
      original password back

    command (run twice, for each base64 encoding):

    ```
    base64 -d; echo
    ```

    **example output**:

    ```
    REDACTED
    ```

1. Verify the base64 encoding of the old password matches
  `/etc/genestack/kubesecrets.yaml`
    - Previous steps directed recording the base64 encoding of the old
      password
    - This should match the base64 encoding you generated if you did
      that in previous steps
   - Your installation may not have this file; if so, skip this step

    ```
    cd /etc/genestack
    yq 'select(.metadata.name == "keystone-admin") | .data.password' kubesecrets.yaml
    ```

# Execute

1. Backup the current `/etc/genestack/kubesecrets.yaml` file
   - Your installation may not have this file. If so, skip this step.

    ```
    cd /etc/genestack
    TS="$(date +%s)"
    cp kubesecrets.yaml kubesecrets.yaml.${TS}.bak
    ```

1. Edit `/etc/genestack/kubesecrets.yaml` and put in the base64
   encoding of the new password
    - Your installation may not have this file. If so, skip this step.
    - Replace the base64 encoding for keystone-admin with the base64
      encoding of the new password as previously recorded in the
      preliminary steps

    ```
    vi kubesecrets.yaml
    ```

1. Confirm the form of the `openstack` command to operate as the `admin`
   user and set an alias
    - You can issue a token then check the user
    - `openstack user password set` works for the active user
        - You could specify the user with `--os-cloud` if necessary,
         or by setting the `OS_CLOUD` environment variable
            - Obviously, the credentials come from `clouds.yaml` for
               the `openstack` command in any case

    **command**:

    ```
    openstack token issue
    ```

    **example output**:

    ```
    +------------+----------------------------------+
    | Field      | Value                            |
    +------------+----------------------------------+
    | expires    | 2026-07-14T08:31:19+0000         |
    | id         | REDACTED                         |
    | project_id | bbcf3b75782e4221ace13cd9c6412e63 |
    | user_id    | 22ead96ded004f4f851fdb29a4a888fc |
    +------------+----------------------------------+
    ```

    **command**:

    ```
    export USER_ID=<user ID from above>
    openstack user show $USER_ID
    ```

    **example output**:

    ```
    +---------------------+----------------------------------+
    | Field               | Value                            |
    +---------------------+----------------------------------+
    | default_project_id  | None                             |
    | domain_id           | default                          |
    | email               | None                             |
    | enabled             | True                             |
    | id                  | 22ead96ded004f4f851fdb29a4a888fc |
    | name                | admin                            |
    | description         | None                             |
    | password_expires_at | None                             |
    | options             | {}                               |
    +---------------------+----------------------------------+
    ```

1. Set an `openstack_admin` alias to operate as admin
   - The rest of the procedure uses this alias
   - **Use information from the previous step to set an alias that
     actually invokes `openstack` as the `admin` account**

    **command**:

    ```
    alias openstack_admin="openstack --os-cloud default"
    openstack_admin token issue
    ```

    Verify the `user_id` matches the previous step when doing the
    `token issue`

1. Make a directory to capture log output, etc. and define aliases for
   the procedure

   copy and paste this into your shell:

   ```
   export ADMIN_PASSWORD_ROTATION_LOG_DIR=~/admin-password-rotation-log-dir
   mkdir $ADMIN_PASSWORD_ROTATION_LOG_DIR

   restart-daemonset() {
       kubectl rollout restart daemonset $1 -n openstack && \
       kubectl rollout status daemonset $1 -n openstack
   }


   # positional args: <step name> <daemonset to restart>
   logs-daemonset() {
       if [[ -n "$ADMIN_PASSWORD_ROTATION_LOG_DIR" ]]
       then
           kubectl -n openstack logs daemonset/$2 \
           --all-pods=true \
           --tail=20 \
           --prefix | \
           tee $ADMIN_PASSWORD_ROTATION_LOG_DIR/$1-$2.txt | \
           less
           echo "output saved to $ADMIN_PASSWORD_ROTATION_LOG_DIR/$1-$2.txt"
       else
           echo "set ADMIN_PASSWORD_ROTATION_LOG_DIR" and try again
       fi
   }

   check-daemonsets() {
       kubectl -n openstack get ds \
       neutron-netns-cleanup-cron-default \
       octavia-health-manager-default \
       octavia-worker-default | \
       tee $ADMIN_PASSWORD_ROTATION_LOG_DIR/$1-daemonset-check.txt
   }
   ```

1. Pre-check the _DaemonSets_ that will need restart:

    **command**:

    ```
    check-daemonsets pre neutron-netns-cleanup-cron-default
    ```

    **example output**:

    ```
    NAME                                 DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR                     AGE
    neutron-netns-cleanup-cron-default   3         3         3       3            3           openstack-control-plane=enabled   150m
    octavia-health-manager-default       3         3         3       3            3           openstack-control-plane=enabled   133m
    octavia-worker-default               3         3         3       3            3           openstack-control-plane=enabled   133m
    ```

1. Canary Pre-check `neutron-netns-cleanup-cron-default` logs
    - The `neutron-netns-cleanup-cron-default` _DaemonSet_ uses the
      admin password
    - The canary check ensures that all nodes running pods for
      affected _DaemonSets_ for the admin password rotation can
      successfully restart pods
        - _DaemonSet_ pods typically run on multiple nodes, so this
         makes it possible to bump into a problem with any node
         running a pod for the _DaemonSet_, so it seems wise to
         start with the `neutron-netns-cleanup-cron-default` and watch
         it complete before reinstalling _Octavia_, which will
         typically run _DaemonSets_ with pods on the same nodes but
         has more potential impact
    - `neutron-netns-cleanup-cron-default` runs a cleanup cron, so it
      should catch up when it gets fixed
    - This will ALSO need restart after actually changing the password.

    ```
    logs-daemonset canary-pre neutron-netns-cleanup-cron-default
    ```

1. Canary restart the `neutron-netns-cleanup-cron-default` _DaemonSet_

    ```
    restart-daemonset neutron-netns-cleanup-cron-default
    ```

    You should resolve any problems here before actually changing the
    `admin` password. These should all get restarted cleanly.

1. Canary post check `neutron-netns-cleanup-cron-default` _DaemonSet_
   logs

    ```
    logs-daemonset canary-post neutron-netns-cleanup-cron-default
    ```

1. Disable lockout for `admin` user
    - The old password will get tried in a few places in the
      procedure, which can lock out the `admin` account entirely so
      we disable lockouts:

    ```
    openstack_admin user set --ignore-lockout-failure-attempts admin
    ```

    (As an aside, in a typical installation, the `admin` account
     almost certainly *WILL* get locked out without this step.)

1. Pre-Note `User-Agent`s getting 401s in Keystone
    - Record this information to eliminate any confusion later
    - The logs do not provide anything more informative as to the
      source than the `User-Agent` string captured with count here

    ```
    kubectl -n openstack logs \
      -c keystone-api \
      -l 'application=keystone,component=api' \
      --tail=-1 |
    perl -F'"' \
    -lane 'print $F[5] if m{POST /v3/auth/tokens} && /\s401\s/' | \
    sort | uniq -c
    ```

    **example output**:

    ```
          1 Apache-HttpClient/4.5.14 (Java/17.0.19)
         92 magnum-conductor keystoneauth1/5.10.0 python-requests/2.32.4 CPython/3.12.13
    ```

1. Change the password with an `openstack_admin user password set`
   **command**:
    - This uses the alias recorded in the previous step where you
      verified this alias operates as the admin user
        - Otherwise, simply don't forget an `--os-cloud` argument or
         anything else you determined you would need to make the
         command operate as/for the admin user
        - You should additionally get stopped attempting to operate on
         the wrong user here by the necessity of supplying the old
         password

    **command**:

    ```
    openstack_admin user password set
    ```

    **example output**:

    ```
    Current Password:
    New Password:
    Repeat New Password:
    ```

1. Backup the current `clouds.yaml`

    ```
    cd ~/.config/openstack
    TS="$(date +%s)"
    sudo cp clouds.yaml clouds.yaml.${TS}.bak
    ```

1. Change the password in `clouds.yaml`
    - Since you have recorded the old password, you can `/` search and
      replace all instances of the old password

    ```
    sudo vi ~/.config/openstack/clouds.yaml
    ```

1. Verify you can issue issue a token after changing the password in
   `clouds.yaml`

    ```
    openstack_admin token issue
    ```

1. Update the password in secrets with `keystone-admin` in the name
    - Pay attention to the base64 encoding and SHA256 sum
    - **Answer NO unless the base64 encoding and SHA256 sum of the two
      passwords looks right**
        - compare with what you've recorded

    **command**:
    ```
    /opt/genestack/scripts/rotate-openstack-admin-secret-passwords.sh
    ```

    **example output**:

    ```
    Old admin password:
    New admin password:
    Confirm new admin password:

    Namespace: openstack
    Mode:      LIVE

    Old password:
      SHA-256: 7cbc866e08f92759dd679c90547279ead61775eb0b39f040e4a99b81b87e734e
      Base64:  REDACTED=

    New password:
      SHA-256: 81ef54d33b953695c53b2da53c50e02a0bdf81bc06d6adb479e625f3361246d9
      Base64:  REDACTED=

    Exact matches: 11 field(s) in 11 Secret(s)
      secret/barbican-keystone-admin  .data[OS_PASSWORD]
      secret/blazar-keystone-admin  .data[OS_PASSWORD]
      secret/cinder-keystone-admin  .data[OS_PASSWORD]
      secret/glance-keystone-admin  .data[OS_PASSWORD]
      secret/keystone-admin  .data[password]
      secret/keystone-keystone-admin  .data[OS_PASSWORD]
      secret/neutron-keystone-admin  .data[OS_PASSWORD]
      secret/nova-keystone-admin  .data[OS_PASSWORD]
      secret/octavia-keystone-admin  .data[OS_PASSWORD]
      secret/placement-keystone-admin  .data[OS_PASSWORD]
      secret/skyline-keystone-admin  .data[OS_PASSWORD]

    Proceed with modifying these fields? [yes/no] yes
      patched: secret/barbican-keystone-admin
      patched: secret/blazar-keystone-admin
      patched: secret/cinder-keystone-admin
      patched: secret/glance-keystone-admin
      patched: secret/keystone-admin
      patched: secret/keystone-keystone-admin
      patched: secret/neutron-keystone-admin
      patched: secret/nova-keystone-admin
      patched: secret/octavia-keystone-admin
      patched: secret/placement-keystone-admin
      patched: secret/skyline-keystone-admin

    Verification: originally matched fields should contain the new value.
      ok: secret/barbican-keystone-admin  .data[OS_PASSWORD]
      ok: secret/blazar-keystone-admin  .data[OS_PASSWORD]
      ok: secret/cinder-keystone-admin  .data[OS_PASSWORD]
      ok: secret/glance-keystone-admin  .data[OS_PASSWORD]
      ok: secret/keystone-admin  .data[password]
      ok: secret/keystone-keystone-admin  .data[OS_PASSWORD]
      ok: secret/neutron-keystone-admin  .data[OS_PASSWORD]
      ok: secret/nova-keystone-admin  .data[OS_PASSWORD]
      ok: secret/octavia-keystone-admin  .data[OS_PASSWORD]
      ok: secret/placement-keystone-admin  .data[OS_PASSWORD]
      ok: secret/skyline-keystone-admin  .data[OS_PASSWORD]

    Live run complete: 11 Secret(s) patched.
    Exact old-value matches remaining: 0
    ```

1. Pre-check `neutron-netns-cleanup-cron-default` logs (not canary)
    - This mirrors the canary step above, but the _DaemonSet_ needs a
      restart at this time.
    - See information from previous canary step

    ```
    logs-daemonset pre neutron-netns-cleanup-cron-default
    ```

1. Restart the `neutron-netns-cleanup-cron-default` _DaemonSet_
  (not canary)

    ```
    restart-daemonset neutron-netns-cleanup-cron-default
    ```

1. post check `neutron-netns-cleanup-cron-default` _DaemonSet_ logs
  (not canary)
    - Output after restart usually looks as below
        - Check to see if we get any not-expected errors. Address or
          explain errors if you happen to see any

    **command**:

    ```
    logs-daemonset post neutron-netns-cleanup-cron-default
    ```

    **example output**:

    ```
    [pod/neutron-netns-cleanup-cron-default-nbsft/neutron-netns-cleanup-cron] + sleep 300
    [pod/neutron-netns-cleanup-cron-default-hxwsm/neutron-netns-cleanup-cron] + sleep 300
    [pod/neutron-netns-cleanup-cron-default-cfwbh/neutron-netns-cleanup-cron] + sleep 300
    ```

## chart reinstallation for configuration files

- This section covers reinstalling services with the admin password
   embedded directly in their configuration files

### Reinstall Octavia

1. Pre-check _Octavia_ to ensure all pods running, etc.
    - Perform any steps you would like to pre-check octavia
    - Preferably, you have all pods running normally before proceeding

    **command**:

    ```
    kubectl -n openstack get pod | grep -i octavia
    ```

    **expected output**:


    ```
    OMITTED, LONG
    ```

    You should see all pods in state `Running` or `Completed`, no crash loop backoff, etc.

1. Reinstall _Octavia_ if installed
    - Unfortunately, _Octavia_ embeds the admin password in its
      configuration files

    ```
    cd /opt/genestack
    bin/install-octavia.sh
    ```

1. Post-check _Octavia_ to ensure all pods running, etc.
    - Perform any steps you would like to post-check octavia

    **command**:

    ```
    kubectl -n openstack get pod | grep -i octavia
    ```

    **expected output**:

    ```
    OMITTED, LONG
    ```

    You should see all pods in state `Running` or `Completed`, no
    crash loop backoff, etc.

### Reinstall Blazar

1. Pre-check _Blazar_ to ensure all pods running, etc.
    - Perform any steps you would like to pre-check Blazar
    - Preferably, you see  all pods running normally before proceeding

    **command**:

    ```
    kubectl -n openstack get pod | grep -i blazar
    ```

    **expected output**:

    ```
    OMITTED, LONG
    ```

    You should see all pods in state `Running` or `Completed`, no
    crash loop backoff, etc.

1. Reinstall _Blazar_ if installed
    - Unfortunately, _Blazar_ embeds the admin password in its
      configuration files

    ```
    cd /opt/genestack
    bin/install-blazar.sh
    ```

1. Post-check _Blazar_ to ensure all pods running, etc.
    - Perform any steps you would like to post-check Blazar

    **command**:

    ```
    kubectl -n openstack get pod | grep -i blazar
    ```

    **expected output**:

    ```
    OMITTED, LONG
    ```

    You should see all pods in state `Running` or `Completed`, no
    crash loop backoff, etc.

### os-metrics / `prometheus-openstack-exporter` chart reinstallation

1. Check if you need steps in this `Execute -> os-metrics related` subsection
    - You need this if you have installed the Helm chart
      `prometheus-openstack-exporter`, typically with release name
      `os-metrics`, referred to as `Openstack Exporter` in the
      _Genestack_ documentation, as seen at page
      [Openstack Exporter](https://docs.rackspacecloud.com/prometheus-openstack-metrics-exporter/)
      in the _Genestack_ documentation.

    **command**:

    ```
    helm -n openstack list | grep -i openstack-exporter
    ```

    **example output** (if installed):

    ```
    os-metrics         	openstack	5       	2024-12-10 19:48:40.217246458 +0000 UTC	deployed	prometheus-openstack-exporter-0.4.3	v1.6.0
    ```

    command to check for secret:

    ```
    kubectl -n openstack get secret | grep -i clouds-yaml-secret
    ```

    **example output** if you have the related secret:

    ```
    clouds-yaml-secret                                               Opaque                                1      2y83d
    ```

    **You may proceed to the next subsection of execution, "Finalize
      Execution" below, if you do not have these**. Otherwise,
      proceed with the rest of the steps in this section.

1. Check for `clouds.yaml` in _openstack-metrics-exporter_ configs
    - Some installations may have avoided overriding OpenStack metrics
      exporter's `clouds.yaml` overrides to avoid getting the
      password into version control, but check and update your
      overrides if applicable:

    **command**:

    ```
    grep -R 'clouds.yaml:' /etc/genestack/helm-configs/openstack-metrics-exporter
    ```

    **example output**:

    ```
    SPACE INTENTIONALLY BLANK, NO OUTPUT IS GOOD
    ```

    The
    [Openstack Exporter](https://docs.rackspacecloud.com/prometheus-openstack-metrics-exporter/)
    page installs this with the secret directly `--set` on the
    installation command, so you may have only the live namespace
    `openstack` name `clouds-yaml-secret` secret to alter on the live
    cluster prior to reinstallation

1. Update `clouds.yaml` related overrides if found in the previous step
    - You may or may not have these as described there.

1. View and record the contents of the secret
    - You may have no other copy of this secret, so I recommend
      recording it before you attempt to alter it
    - This will give you an idea of what needs changing before the
      next step; you should see the old admin password, where you
      will want to replace it with the new one

    ```
    kubectl -n openstack get secret clouds-yaml-secret -o json | \
    jq -r '.data["generated-clouds-yaml"] | @base64d'
    ```

1. Change the admin password in namespace `openstack` name `clouds-yaml-secret` if it exists
    - You can see the installation documentation dealing with the secret [here](https://docs.rackspacecloud.com/prometheus-openstack-metrics-exporter/#create-clouds-yaml-secret)
        - Since you only need to change the admin password here, you can
          alter the data from the existing secret
    - The script below simply base64 decodes the secret, invokes
      `$EDITOR` on it (or `vi` if `$EDITOR` has no value), and prompts you
      to patch the secret with your change ("yes"), edit again, or
      say "no" to abort
    - Replace the old admin password with the new one

    ```
    /opt/genestack/scripts/edit-clouds-yaml-secret.sh
    ```

1. Review the changed secret

    ```
    kubectl -n openstack get secret clouds-yaml-secret -o json | \
    jq -r '.data["generated-clouds-yaml"] | @base64d'
    ```

1. Reinstall the _openstack-metrics-exporter_
    - You can, again, see the documentation at the
     [Openstack Exporter](https://docs.rackspacecloud.com/prometheus-openstack-metrics-exporter/)
     page
        - Choose the correct version based on whether your secret
         contains self-signed certificates.

    commands:

    ```
    READ THE LINKED PAGE, CHOOSE ONLY THE CORRECT INSTALL COMMAND,
    IGNORE OTHER PARTS
    ```

1. Check for running `openstack-metrics-exporter` running pod
    - **The installation may not restart the pod**
    - **DELETE THE POD IF NECESSARY**
    - **YOU MAY SEE AUTHENTICATION ERRORS IF INSTALLATION DOES NOT
      RESTART THE POD**
        - The pod trying the old password will likely eventually cause
          the pod to crash and get the correct password, however.
    - Ensure the restart count has stopped incrementing if the error
      appears to resolve by itself, as by pod restart from crashing
      due to authentication errors

    **command**:

    ```
    kubectl -n openstack  get pods | grep os-metrics
    ```

    **example output**:

    ```
    os-metrics-prometheus-openstack-exporter-7584457dd7-lrfs7   1/1     Running     0          39m
    ```

### Conclude execution

1. Record a timestamp to find new 401s
    - This should take care of everything using the admin password and
      getting 401s
    - We record a timestamp so that we can find new 401s after this time.

   ```
   date -u +'%Y-%m-%dT%H:%M:%SZ'
   ```

## Verification

1. Confirm the old password does not appear in the secrets anywhere

    1. Check the secrets for the password
        - **supply the old password when prompted for the password**
        - example output shows a hyperconverged lab without the
          rotation happened at all

        **command**:

        ```
        /opt/genestack/scripts/find-old-password-in-secrets.sh
        ```

        **example bad output**, listing paths with the old password,
        possibly base64 encoded in a configuration file:

        ```JSON
        [
          {
            "name": "barbican-keystone-admin",
            "list_of_paths_containing_the_string": [
              ".data.OS_PASSWORD"
            ]
          },
          {
            "name": "blazar-etc",
            "list_of_paths_containing_the_string": [
              ".data[\"blazar.conf\"]"
            ]
          }
        ]
        ```

        **example good output**, an empty JSON list, indicating the old
        password found nowhere:

        ```
        []
        ```

1. Post-check _Keystone_ for `User-Agent`s getting 401s
    - This will often return something even if you completed
      everything successfully
    - Remember that you recorded the output of this earlier to help
      disambiguate results as expected vs caused by rotating the
      admin password

   **command**:

    ```
    TS=<your recorded timestamp for procedure completion>
    kubectl -n openstack logs \
      -c keystone-api \
      -l 'application=keystone,component=api' \
      --tail=-1 --since-time="$TS" |
    perl -F'"' -lane 'print $F[5] if m{POST /v3/auth/tokens} && /\s401\s/' | \
    sort | uniq -c; echo
    ```

    **example output**:

    ```
    11 magnum-conductor keystoneauth1/5.10.0 python-requests/2.32.4 CPython/3.12.13
    ```

# Cleanup

1. Re-enable admin user

    ```
    openstack_admin user set --no-ignore-lockout-failure-attempts admin
    ```

1. Delete the `breakglass` account
    - We have finished the rotation, so we can delete the `breakglass`
      account

    ```
    openstack_admin user delete --domain default breakglass
    ```

1. Remove the `breakglass` clouds.yaml

    ```
    sudo rm ~/breakglass.yaml
    ```

1. Record the new password in any external credentials stores you use
   if applicable

# Footnotes

## Example of finding the paths in current secrets

```JSON
[
  {
    "name": "barbican-keystone-admin",
    "list_of_paths_containing_the_string": [
      ".data.OS_PASSWORD"
    ]
  },
  {
    "name": "blazar-etc",
    "list_of_paths_containing_the_string": [
      ".data[\"blazar.conf\"]"
    ]
  },
  {
    "name": "blazar-keystone-admin",
    "list_of_paths_containing_the_string": [
      ".data.OS_PASSWORD"
    ]
  },
  {
    "name": "ceilometer-keystone-admin",
    "list_of_paths_containing_the_string": [
      ".data.OS_PASSWORD"
    ]
  },
  {
    "name": "cinder-keystone-admin",
    "list_of_paths_containing_the_string": [
      ".data.OS_PASSWORD"
    ]
  },
  {
    "name": "clouds-yaml-secret",
    "list_of_paths_containing_the_string": [
      ".data[\"generated-clouds-yaml\"]"
    ]
  },
  {
    "name": "glance-keystone-admin",
    "list_of_paths_containing_the_string": [
      ".data.OS_PASSWORD"
    ]
  },
  {
    "name": "gnocchi-keystone-admin",
    "list_of_paths_containing_the_string": [
      ".data.OS_PASSWORD"
    ]
  },
  {
    "name": "heat-keystone-admin",
    "list_of_paths_containing_the_string": [
      ".data.OS_PASSWORD"
    ]
  },
  {
    "name": "keystone-admin",
    "list_of_paths_containing_the_string": [
      ".data.password"
    ]
  },
  {
    "name": "keystone-keystone-admin",
    "list_of_paths_containing_the_string": [
      ".data.OS_PASSWORD"
    ]
  },
  {
    "name": "magnum-keystone-admin",
    "list_of_paths_containing_the_string": [
      ".data.OS_PASSWORD"
    ]
  },
  {
    "name": "neutron-keystone-admin",
    "list_of_paths_containing_the_string": [
      ".data.OS_PASSWORD"
    ]
  },
  {
    "name": "nova-keystone-admin",
    "list_of_paths_containing_the_string": [
      ".data.OS_PASSWORD"
    ]
  },
  {
    "name": "octavia-etc",
    "list_of_paths_containing_the_string": [
      ".data[\"octavia.conf\"]"
    ]
  },
  {
    "name": "octavia-health-manager-default",
    "list_of_paths_containing_the_string": [
      ".data[\"octavia.conf\"]"
    ]
  },
  {
    "name": "octavia-keystone-admin",
    "list_of_paths_containing_the_string": [
      ".data.OS_PASSWORD"
    ]
  },
  {
    "name": "octavia-worker-default",
    "list_of_paths_containing_the_string": [
      ".data[\"octavia.conf\"]"
    ]
  },
  {
    "name": "openstack-config",
    "list_of_paths_containing_the_string": [
      ".data[\"clouds.yaml\"]"
    ]
  },
  {
    "name": "placement-keystone-admin",
    "list_of_paths_containing_the_string": [
      ".data.OS_PASSWORD"
    ]
  },
  {
    "name": "skyline-keystone-admin",
    "list_of_paths_containing_the_string": [
      ".data.OS_PASSWORD"
    ]
  },
  {
    "name": "zaqar-keystone-admin",
    "list_of_paths_containing_the_string": [
      ".data.OS_PASSWORD"
    ]
  }
]
```
