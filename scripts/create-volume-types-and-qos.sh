#!/bin/bash


## Create commodity LVM volume types
openstack volume type create --description 'Capacity with LUKS encryption' \
	--encryption-provider luks \
	--encryption-cipher aes-xts-plain64 \
	--encryption-key-size 256 \
	--encryption-control-location front-end \
	--property volume_backend_name=LVM_iSCSI \
	--property provisioning:max_vol_size='2048' \
	--property provisioning:min_vol_size='100' \
    --property :price='0.000123288' Capacity

openstack volume type create --description 'Standard with LUKS encryption' \
	--encryption-provider luks \
	--encryption-cipher aes-xts-plain64 \
	--encryption-key-size 256 \
	--encryption-control-location front-end \
	--property volume_backend_name=LVM_iSCSI \
	--property provisioning:max_vol_size='2048' \
	--property provisioning:min_vol_size='10' \
    --property :price='0.000136986' Standard

openstack volume type create --description 'Performance with LUKS encryption' \
	--encryption-provider luks \
	--encryption-cipher aes-xts-plain64 \
	--encryption-key-size 256 \
	--encryption-control-location front-end \
	--property volume_backend_name=LVM_iSCSI \
	--property provisioning:max_vol_size='2048' \
	--property provisioning:min_vol_size='10' \
    --property :price='0.000157534' Performance

## Create NetApp volume types
openstack volume type create --description 'HA Block Standard with at rest encryption' \
	--property volume_backend_name=ha-block \
	--property provisioning:max_vol_size='2048' \
	--property provisioning:min_vol_size='5' \
	--property netapp:qos_policy_group_is_adaptive='true' \
	--property netapp_compression='true' \
	--property netapp_dedup='true' \
	--property netapp_qos_min_support='true' \
    --property :price='0.000205479' HA-Standard

openstack volume type create --description 'HA Block Performance with at rest encryption' \
	--property volume_backend_name=ha-block \
	--property provisioning:max_vol_size='2048' \
	--property provisioning:min_vol_size='5' \
	--property netapp:qos_policy_group_is_adaptive='true' \
	--property netapp_compression='true' \
	--property netapp_dedup='true' \
	--property netapp_qos_min_support='true' \
    --property :price='0.000246575' HA-Performance

## Create LVM volume type QoS policies
openstack volume qos create \
	--property read_iops_sec_per_gb='1' \
	--property write_iops_sec_per_gb='1' Capacity-Block

openstack volume qos create \
	--property read_iops_sec_per_gb='5' \
	--property write_iops_sec_per_gb='5' Standard-Block

openstack volume qos create \
	--property read_iops_sec_per_gb='10' \
	--property write_iops_sec_per_gb='10' Performance-Block

## Create NetApp volume type QoS policies
openstack volume qos create \
	--property absoluteMinIOPS='128' \
	--property expectedIOPSAllocation='allocated-space' \
	--property expectedIOPSperGiB='10' \
	--property peakIOPSAllocation='allocated-space' \
	--property peakIOPSperGiB='20' \
	--consumer back-end HA-Standard-Block

openstack volume qos create \
	--property absoluteMinIOPS='256' \
	--property expectedIOPSAllocation='allocated-space' \
	--property expectedIOPSperGiB='20' \
	--property peakIOPSAllocation='allocated-space' \
	--property peakIOPSperGiB='40' \
	--consumer back-end HA-Performance-Block

## Associate LVM QoS policies to LVM volume types
openstack volume qos associate Capacity-Block Capacity
openstack volume qos associate Standard-Block Standard
openstack volume qos associate Performance-Block Performance

## Associate NetApp QoS policies to NetApp volume types
openstack volume qos associate HA-Standard-Block HA-Standard
openstack volume qos associate HA-Performance-Block HA-Performance

## Hide unsightly __DEFAULT__ from Skyline
openstack volume type set --private __DEFAULT__

