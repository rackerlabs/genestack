#!/usr/bin/python3

# Copyright 2019-Present, Rackspace Technology, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# (C) 2019, Bjoern Teipel <bjoern.teipel@rackspace.com>
#

from ruamel.yaml import YAML
from pprint import pprint

import argparse
import copy
import json
import logging
import parser
import sys

logger = logging.getLogger("convert_osa_inventory")

inventory_skel = {
    "all": {
        "hosts": {},
        "children": {},
        "vars": {},
    }
}


def parse_args(args):
    parser = argparse.ArgumentParser(
        usage="%(prog)s",
        description="OSA Inventory Converter to k8s",
        epilog='Generator Licensed "Apache 2.0"',
    )

    parser.add_argument(
        "-d",
        "--debug",
        help=("Append output debug messages to log file."),
        action="store_true",
        default=False,
    )

    parser.add_argument(
        "--hosts_file",
        help=("Defines the output file for the k8s hosts inventory"),
        nargs="?",
        default="/etc/genestack/inventory/hosts.yml",
    )

    parser.add_argument(
        "--ansible_user",
        help=("Set user for ansible logins with implies use of become directive"),
        nargs="?",
        default="root",
    )

    return vars(parser.parse_args(args))


def load_osa_inventory(file="/etc/openstack_deploy/openstack_inventory.json"):
    try:
        with open(file) as fp:
            inventory = json.load(fp)
    except Exception as ex:
        logger.debug("load_inventory: %s", ex)
        raise SystemExit

    return inventory


def hosts_from_group(inventory=dict(), groups=list()):
    hosts = list()

    try:
        for group in groups:
            for host in inventory[group]["hosts"]:
                if host not in hosts:
                    hosts.append(host)
    except KeyError:
        pass
    finally:
        return hosts


def main(debug=False, **kwargs):
    """Run the main application.
    :param debug: ``bool`` enables debug logging
    :param kwargs: ``dict`` for passing command line arguments
    """

    if debug:
        log_fmt = "%(lineno)d - %(funcName)s: %(message)s"
        logging.basicConfig(format=log_fmt, filename="convert_osa_inventory.log")
        logger.setLevel(logging.DEBUG)

    osa_inv = load_osa_inventory()
    k8s_inv = copy.deepcopy(inventory_skel)
    yaml_inv = YAML()

    """ Determine basic hosts groups to build new inventory
        and filter controller hosts from the nova_compute group
        in situations where ironic compute services are deployed
    """
    controller_nodes = hosts_from_group(osa_inv, ["os-infra_hosts"])
    # worker_nodes = [ h for h in hosts_from_group(osa_inv, ['nova_compute', 'storage_hosts', 'osds', 'mon'])
    worker_nodes = [
        h
        for h in hosts_from_group(osa_inv, ["nova_compute", "storage_hosts"])
        if h not in hosts_from_group(osa_inv, ["os-infra_hosts"])
    ]

    if len(controller_nodes) < 3 or len(worker_nodes) < 1:
        logger.debug(
            "No controller_nodes/worker_nodes %d / %d", controller_nodes, worker_nodes
        )
        raise SystemExit(
            "Insufficient controller (os-infra_hosts) and "
            "worker hosts (compute etc) defined in OSA Inventory"
        )

    logger.debug("Controller Nodes: %s", controller_nodes)
    logger.debug("Worker Nodes: %s", worker_nodes)

    """ Constructing all group
    """
    for host in controller_nodes + worker_nodes:
        try:
            ansible_host = osa_inv["_meta"]["hostvars"][host]["ansible_host"]
        except KeyError:
            ansible_host = osa_inv["_meta"]["hostvars"][host]["ansible_ssh_host"]

        become_user = kwargs["ansible_user"]

        k8s_inv["all"]["hosts"][host] = {
            "ansible_host": ansible_host,
            "access_ip": ansible_host,
            "become_user": become_user,
        }
        if become_user != "root":
            k8s_inv["all"]["hosts"][host]["ansible_become"] = "yes"

        logger.debug(
            "Adding host (group all): %s %s", host, k8s_inv["all"]["hosts"][host]
        )

    """ Constructing children
    """
    k8s_inv["all"]["children"] = {
        "kube-master": {"hosts": {}},
        "kube-node": {"hosts": {}},
        "etcd": {"hosts": {}},
        "openstack_control_plane": {"hosts": {}},
        "openstack-compute-node": {"hosts": {}},
        "k8s_cluster": {
            "children": {
                "kube-master": {},
                "kube-node": {},
                "openstack_control_plane": {},
                "openstack_compute_node": {},
            }
        },
        "calico-rr": {"hosts": {}},
    }

    for group in ["kube-master", "etcd", "openstack_control_plane"]:
        for host in controller_nodes:
            logger.debug("Adding host (group %s): %s", group, host)
            k8s_inv["all"]["children"][group]["hosts"][host] = {}

    for group in ["kube-node", "openstack-compute-node"]:
        for host in worker_nodes:
            logger.debug("Adding host (group %s): %s", group, host)
            k8s_inv["all"]["children"][group]["hosts"][host] = {}

    """ Dump dictionary to a human readable inventory
        to stdout. This can be used to create the inventory file
    """
    try:
        with open(args["hosts_file"], "w") as hosts_yaml:
            yaml_inv.dump(k8s_inv, hosts_yaml)

        logger.info("Inventory written to: %s", k8s_inv)
        hosts_yaml.close()
    except Exception as ex:
        logger.error("Could not dump YAML to file: %s", args["hosts_file"])
        raise SystemExit


if __name__ == "__main__":
    args = parse_args(sys.argv[1:])
    main(**args)
