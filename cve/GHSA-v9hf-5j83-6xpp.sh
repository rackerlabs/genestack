#!/bin/bash
echo "Applying GHSA-v9hf-5j83-6xpp fix"
/var/lib/openstack/bin/pip install --upgrade pymysql==1.1.1
