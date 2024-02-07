Role k8s_install
================

Role to install k8s distributions and apply configurations tasks post install including

- Pull kubctl configuration from the first cluster node
- Node labeling (install only)

A kubespray like inventory is expected, supplying at a minimum:

`k8s_cluster` setting `cluster_name` and consisting of the children
`kube_control_plane`, `kube_node`.

The `cluster_name` variable must be configured to a desired FQDN, outside of  `cluster.local` for obvious reasons
such a tld `.local` can not utilize EV certificates.

At this time only the kubespray installer is supported, others can be added over time.
The override `kube_install_mode` defaults to `install` which utilizes the kubespray `cluster.yml`.
By setting this override to `upgrade`, the role delegates to the `upgrade.yml` playbook preceded by a version check.
Other modes such as scaling out, increasing k8s node count, will be added over time.

Requirements
------------

- Supplied kubespray code to run the cluster playbook

Role Variables
--------------

See [defaults](defaults/main.yml)


Dependencies
------------

N/A


Example Playbook
----------------

```shell
- hosts: localhost
  become: True
  gather_facts: "{{ gather_facts | default(true) }}"
  vars_files:
    - 'vars/default.yml'
  roles:
    - role: "k8s_install"
      pre_execution_hook: "source env.rc"
      kubeprovider:
        name: "kubespray"
        path: "/opt/kubespray"
```

License
-------

[![Apache License, Version 2.0](https://img.shields.io/badge/License-Apache-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0.html)
