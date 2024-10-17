# Ceilometer (Metering and Event Collection)

Ceilometer is the telemetry service in OpenStack responsible for collecting
usage data related to different resources (e.g., instances, volumes,
and network usage). It compiles various types of metrics (referred to as
meters), such as CPU utilization, disk I/O, and network traffic, by
gathering data from other OpenStack components like Nova (compute), Cinder
(block storage), and Neutron (networking). It also captures event data such
as instance creation and volume attachment via hooks into the message
notification system (RabbitMQ).

## Meters

Meters are quantitative measures like CPU time, memory usage, or disk 
operations. Ceilometer provides several useful metrics by default, but new 
definitions can be added to suit almost every need. To read more about
measurements and how they are captured, see the [telemetry-measurements][ceilometer-telemetry]
section of Ceilometer documentation.

??? example "Example metric definition for volume.size"
    ```
    - name: 'volume.size'
    event_type:
      - 'volume.exists'
      - 'volume.retype'
      - 'volume.create.*'
      - 'volume.delete.*'
      - 'volume.resize.*'
      - 'volume.attach.*'
      - 'volume.detach.*'
      - 'volume.update.*'
      - 'volume.manage.*'
    type: 'gauge'
    unit: 'GB'
    volume: $.payload.size
    user_id: $.payload.user_id
    project_id: $.payload.tenant_id
    resource_id: $.payload.volume_id
    metadata:
      display_name: $.payload.display_name
      volume_type: $.payload.volume_type
      image_id: $.payload.glance_metadata[?key=image_id].value
      instance_id: $.payload.volume_attachment[0].instance_uuid
    ```

## Events

Events are discrete occurrences, such as the starting or stopping of
instances or attaching a volume which are captured and stored. Ceilometer
builds event data from the messages it receives from other OpenStack 
services. Event definitions can be complex. Typically, a given message will
match one or more event definitions that describe what the incoming payload
should be flattened to. See the [telemetry-events][ceilometer-events]
section of Ceilometer's documentation for more information.

??? example "Example event definitions for cinder volumes"

    ```
    - event_type: ['volume.exists', 'volume.retype', 'volume.create.*', 'volume.delete.*', 'volume.resize.*', 'volume.attach.*', 'volume.detach.*', 'volume.update.*', 'snapshot.exists', 'snapshot.create.*', 'snapshot.delete.*', 'snapshot.update.*', 'volume.transfer.accept.end', 'snapshot.transfer.accept.end']
      traits: &cinder_traits
        user_id:
          fields: payload.user_id
        project_id:
          fields: payload.tenant_id
        availability_zone:
          fields: payload.availability_zone
        display_name:
          fields: payload.display_name
        replication_status:
          fields: payload.replication_status
        status:
          fields: payload.status
        created_at:
          type: datetime
          fields: payload.created_at
        image_id:
          fields: payload.glance_metadata[?key=image_id].value
        instance_id:
          fields: payload.volume_attachment[0].instance_uuid
    - event_type: ['volume.transfer.*', 'volume.exists', 'volume.retype', 'volume.create.*', 'volume.delete.*', 'volume.resize.*', 'volume.attach.*', 'volume.detach.*', 'volume.update.*', 'snapshot.transfer.accept.end']
      traits:
        <<: *cinder_traits
        resource_id:
          fields: payload.volume_id
        host:
          fields: payload.host
        size:
          type: int
          fields: payload.size
        type:
          fields: payload.volume_type
        replication_status:
          fields: payload.replication_status
    ```

[ceilometer-telemetry]: https://docs.openstack.org/ceilometer/latest/admin/telemetry-measurements.html "The Telemetry service collects meters within an OpenStack deployment. This section provides a brief summary about meters format, their origin, and also contains the list of available meters."

[ceilometer-events]: https://docs.openstack.org/ceilometer/latest/admin/telemetry-events.html "In addition to meters, the Telemetry service collects events triggered within an OpenStack environment. This section provides a brief summary of the events format in the Telemetry service."
