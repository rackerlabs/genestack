<!-- DOCSIBLE START -->

# 📃 Role overview

## cinder_volumes





| Field                | Value           |
|--------------------- |-----------------|
| Readme update        | 2026/04/08 |








### Defaults

**These are static variables with lower priority**

#### File: defaults/main.yml

| Var          | Type         | Value       |
|--------------|--------------|-------------|
| [cinder_release_branch](defaults/main.yml#L3)   | str | `unmaintained/2024.1` |
| [storage_network_interface](defaults/main.yml#L4)   | str | `ansible_br_storage` |
| [storage_network_interface_secondary](defaults/main.yml#L5)   | NoneType | `None` |
| [cinder_backend_name](defaults/main.yml#L6)   | str |  |
| [cinder_worker_name](defaults/main.yml#L7)   | str | `netapp` |
| [cinder_virtualenv_path](defaults/main.yml#L9)   | str | `/opt/cinder` |
| [storage_network_multipath](defaults/main.yml#L10)   | bool | `False` |
| [cinder_enable_storage_ssl](defaults/main.yml#L11)   | bool | `False` |
| [cinder_storage_cert_src_dir](defaults/main.yml#L12)   | str | `/opt/genestack/ansible/playbooks/templates/` |
| [cinder_storage_cert_filenames](defaults/main.yml#L13)   | list | `[]` |
| [cinder_storage_cert_filenames.**0**](defaults/main.yml#L14)   | str | `ontap-cluster-host.crt` |
| [cinder_storage_cert_filenames.**1**](defaults/main.yml#L15)   | str | `ontap-vserver-host.crt` |
| [cinder_volume_package_state](defaults/main.yml#L17)   | str | `latest` |


### Vars

**These are variables with higher priority**
#### File: vars/debian.yaml

| Var          | Type         | Value       |
|--------------|--------------|-------------|
| [cinder_volume_package_list](vars/debian.yaml#L3)   | list | `[]` |
| [cinder_volume_package_list.**0**](vars/debian.yaml#L4)   | str | `build-essential` |
| [cinder_volume_package_list.**1**](vars/debian.yaml#L5)   | str | `git` |
| [cinder_volume_package_list.**2**](vars/debian.yaml#L6)   | str | `open-iscsi` |
| [cinder_volume_package_list.**3**](vars/debian.yaml#L7)   | str | `python3-venv` |
| [cinder_volume_package_list.**4**](vars/debian.yaml#L8)   | str | `python3-dev` |
| [cinder_volume_package_list.**5**](vars/debian.yaml#L9)   | str | `qemu-block-extra` |
| [cinder_volume_package_list.**6**](vars/debian.yaml#L10)   | str | `qemu-utils` |
| [cinder_backend_packages](vars/debian.yaml#L12)   | dict | `{}` |
| [cinder_backend_packages.**netapp**](vars/debian.yaml#L13)   | list | `[]` |
| [cinder_backend_packages.**storage**](vars/debian.yaml#L14)   | list | `[]` |
| [cinder_backend_packages.**lvm**](vars/debian.yaml#L15)   | list | `[]` |
| [cinder_backend_packages.lvm.**0**](vars/debian.yaml#L16)   | str | `tgt` |
#### File: vars/ubuntu.yaml

| Var          | Type         | Value       |
|--------------|--------------|-------------|
| [cinder_volume_package_list](vars/ubuntu.yaml#L3)   | list | `[]` |
| [cinder_volume_package_list.**0**](vars/ubuntu.yaml#L4)   | str | `build-essential` |
| [cinder_volume_package_list.**1**](vars/ubuntu.yaml#L5)   | str | `git` |
| [cinder_volume_package_list.**2**](vars/ubuntu.yaml#L6)   | str | `open-iscsi` |
| [cinder_volume_package_list.**3**](vars/ubuntu.yaml#L7)   | str | `python3-venv` |
| [cinder_volume_package_list.**4**](vars/ubuntu.yaml#L8)   | str | `python3-dev` |
| [cinder_volume_package_list.**5**](vars/ubuntu.yaml#L9)   | str | `qemu-block-extra` |
| [cinder_volume_package_list.**6**](vars/ubuntu.yaml#L10)   | str | `qemu-utils` |
| [cinder_backend_packages](vars/ubuntu.yaml#L12)   | dict | `{}` |
| [cinder_backend_packages.**netapp**](vars/ubuntu.yaml#L13)   | list | `[]` |
| [cinder_backend_packages.**storage**](vars/ubuntu.yaml#L14)   | list | `[]` |
| [cinder_backend_packages.**lvm**](vars/ubuntu.yaml#L15)   | list | `[]` |
| [cinder_backend_packages.lvm.**0**](vars/ubuntu.yaml#L16)   | str | `tgt` |


### Tasks


#### File: tasks/cleanup.yaml

| Name | Module | Has Conditions |
| ---- | ------ | -------------- |
| Remove storage-cinder conf staging file | ansible.builtin.file | False |
| Remove cinder conf staging file | ansible.builtin.file | False |

#### File: tasks/configure_backend.yaml

| Name | Module | Has Conditions |
| ---- | ------ | -------------- |
| Set enabled backend fact | set_fact | False |
| Create the cinder-volume-{{ cinder_worker_name }} backend configuration | ansible.builtin.copy | False |
| Create the cinder-volume-{{ cinder_worker_name }} configuration stage file | ansible.builtin.copy | False |
| Ensure the backend configuration is set to our expected value | community.general.ini_file | False |
| Override host value in {{ cinder_worker_name }}-cinder.conf.stage | community.general.ini_file | False |
| Create the cinder-volume-{{ cinder_worker_name }} configuration | ansible.builtin.copy | False |
| Create the cinder-volume-{{ cinder_worker_name }} systemd service units | ansible.builtin.template | False |

#### File: tasks/configure_backend_lvm.yaml

| Name | Module | Has Conditions |
| ---- | ------ | -------------- |
| Unnamed | set_fact | False |
| Create the cinder-volume backend configuration | ansible.builtin.copy | False |
| Ensure the backend configuration is set to our expected value | community.general.ini_file | False |
| Create the cinder-volume configuration | ansible.builtin.copy | False |
| Create the cinder-volume-{{ cinder_worker_name }} systemd service units | ansible.builtin.copy | False |
| Create the cinder tgtd integration | ansible.builtin.copy | False |
| Create the cinder-volume systemd service units | ansible.builtin.copy | False |

#### File: tasks/configure_storage_certificate.yaml

| Name | Module | Has Conditions |
| ---- | ------ | -------------- |
| Copy storage client certificates Debian | ansible.builtin.copy | True |
| Copy storage client certificates Redhat | ansible.builtin.copy | True |
| Update CA certificate trust Debian | ansible.builtin.command | True |
| Update CA certificate trust Redhat | ansible.builtin.command | True |

#### File: tasks/main.yaml

| Name | Module | Has Conditions | Tags |
| ---- | ------ | -------------- | -----|
| Gather variables for each operating system | ansible.builtin.include_vars | False | always |
| Unnamed | ansible.builtin.debug | False |  |
| K8S Facts block | block | False |  |
| Ensure python3-kubernetes is available | ansible.builtin.package | False |  |
| Read cinder-etc secrets | kubernetes.core.k8s_info | False |  |
| Install cinder distro packages | ansible.builtin.package | True |  |
| Install cinder-backend distro packages | ansible.builtin.package | True |  |
| Determine iscsi initiator name | set_fact | False |  |
| Set iscsi initiator name if not set | ansible.builtin.lineinfile | False |  |
| Configure SSL certificate for storage API access | ansible.builtin.include_tasks | True |  |
| Upgrade pip and install required packages | ansible.builtin.pip | False |  |
| Get Python site-packages path from virtualenv | command | False |  |
| Normalize site-packages path | set_fact | False |  |
| Ensure site-packages exists | file | True |  |
| Install eventlet SSL patch | ansible.builtin.copy | True |  |
| Create the cinder system user | ansible.builtin.user | False |  |
| Create the cinder system group | ansible.builtin.group | False |  |
| Create the cinder service directory | ansible.builtin.file | False |  |
| Create symlink for the etc directory | ansible.builtin.file | False |  |
| Create the cinder-volume filters and logging configuration | ansible.builtin.copy | False |  |
| Create the cinder-volume configuration stage file | ansible.builtin.copy | False |  |
| Replace the host in the cinder.conf.stage with the current Ansible FQDN in the stage file | community.general.ini_file | False |  |
| Replace exec path in rootwrap | community.general.ini_file | False |  |
| Configure storage backend | ansible.builtin.include_tasks | True |  |
| Configure lvm backend | ansible.builtin.include_tasks | True |  |
| Cleanup | ansible.builtin.include_tasks | False |  |









#### Dependencies

No dependencies specified.
<!-- DOCSIBLE END -->
