#!/bin/bash
rm ~/key*
rm ~/inventory.yaml
yes y | openstack --os-cloud ftc stack delete testing
