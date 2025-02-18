#!/bin/bash
cd testing || exit
rm ./key*
rm ./inventory.yaml
yes y | openstack --os-cloud default stack delete testing
