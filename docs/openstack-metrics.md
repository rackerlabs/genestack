# OpenStack Metrics

This page summarizes usage of common `openstack metric` commands, which are used
to interact with the Telemetry service (_[Gnocchi](metering-gnocchi.md)_) for
managing metrics, measures, and resources in OpenStack.

## CLI Commands

### **metric list**

Lists all metrics available in the environment.

**Usage:**

```shell
openstack metric list
```
**Options:**

- `--details`: Show detailed information about each metric.

### **metric show**

Shows detailed information about a specific metric.

**Usage**:

```shell
openstack metric show <metric_id>
```

### **metric create**

Creates a new metric for a resource

**Usage**:

```shell
openstack metric create <metric_name> \
  --resource-id <resource_id> \
  --archive-policy-name <policy_name>
```

**Options**:

- `--unit <unit>`: Specify the unit of measurement (e.g., MB, GB).
- `--resource-id <resource_id>`: ID of the resource to associate the metric
  with.
- `--archive-policy-name <policy_name>`: Name of the archive policy

### **metric delete**

Deletes a specific metric.

**Usage**:

```shell
openstack metric delete <metric_id>
```

### **metric measures show**

Retrieves the measures (data points) of a metric.

**Usage**:

```shell
openstack metric measures show <metric_id>
```

**Options**:

- `--aggregation <method>`: Aggregation method to apply (e.g., mean, sum).
- `--start <datetime>`: Start time for retrieving measures.
- `--stop <datetime>`: End time for retrieving measures.

### **metric resource list**

Lists all resources that are associated with metrics.

**Usage**:

```shell
openstack metric resource list
```

**Options**:

- `--type <resource_type>`: Filter by resource type (e.g., instance, volume).

### **metric resource show**

Shows detailed information about a specific resource, including its metrics.

**Usage**:

```shell
openstack metric resource show <resource_id>
```

### **metric resource create**

Creates a new resource and associates it with metrics.

**Usage**:

```shell
openstack metric resource create --type <type> <other_opts> <resource_id>
```

**Options**:

- `--type <resource_type>`: Type of resource (e.g., instance, volume).
- `--attribute <attribute>`: Name and value of an attribute separated with a ':'
- `--add-metric <add_metric>`: name:id of a metric to add
- `--create-metric <create_metric`: name:archive_policy_name of a metric to
   create

### **metric resource update**

Updates attributes of an existing resource.

**Usage**:

```shell
openstack metric resource update --type <type> <other_opts> <resource_id>
```

**Options**:

- `--type <resource_type>`: Type of resource (e.g., instance, volume).
- `--attribute <attribute>`: Name and value of an attribute separated with a ':'
- `--add-metric <add_metric>`: name:id of a metric to add
- `--create-metric <create_metric`: name:archive_policy_name of a metric to
   create
- `--delete-metric <delete_metric>`: Name of a metric to delete

### **metric resource delete**

Deletes a specific resource and its associated metrics.

**Usage**:

```shell
openstack metric resource delete <resource_id>
```

### **metric resource-type list**

List all existing resource types

**Usage**:

```shell
openstack metric resource-type list
```

### **metric resource-type show**

Show a specific resource type

**Usage**:

```shell
openstack metric resource-type show <resource_type_name>
```

### **metric resource-type create**

Creates a new resource-type

```shell
openstack metric resource-type create <resource_type_name> \
  --attribute <attributes>
```

**Options**:

- `--attribute <display_name:string:true:max_length=255>`: attribute definition
  > attribute_name:attribute_type:attribute_is_required:attribute_type_option_name=attribute_type_option_value

### **metric resource-type update**

Updates an existing resource-type

```shell
openstack metric resource-type update <resource_type_name> \
  --attribute <attributes> \
  --remove-attribute <attribute_name>
```

**Options**:

- `--attribute <display_name:string:true:max_length=255>`: attribute definition
  > attribute_name:attribute_type:attribute_is_required:attribute_type_option_name=attribute_type_option_value
- `--remove-attribute <attribute_name>`: removes named
  attribute

### **metric archive-policy list**

List all archive policies

**Usage**:

```shell
openstack metric archive-policy list
```

### **metric archive-policy show**

Shows a specific archive policy

**Usage**:

```shell
openstack metric archive-policy show <policy_name>
```

### **metric archive-policy create**

Creates a new archive policy

**Usage**:

```shell
openstack metric archive-policy create <policy_name> \
  --definition <policy_definition> \
  --back-window <back_window> \
  --aggregation-method <method>
```

**Options**:

- `--definition <definition>`: two attributes (comma separated) of an archive
  policy definition with its name and value separated with a ':'
- `--back-window <window>`: back window of the archive policy
  > If we define a policy that specifies a granularity of 1 hour then set the
    back_window to 3, Gnocchi will process data points that arrive up to 3 hours
    late.
- `--aggregation-method <method(s)>`: aggregation method of the archive policy

### **metric archive-policy update**

Updates an existing archive policy

**Usage**:

```shell
openstack metric archive-policy update <policy_name> \
  --definition <policy_definition>
```

**Options**:

- `--definition <definition>`: two attributes (comma separated) of an archive
  policy definition with its name and value separated with a ':'

## Example Use Cases

### **Show Measures of a Specific Metric**

```shell
openstack metric measures show <metric_id> --aggregation mean --start 2024-01-01 --stop 2024-01-31
```

### **Create a New Resource with a Metric**

```shell
openstack metric resource create instance --name my_instance
openstack metric create cpu_usage --resource-id <resource_id> --unit GHz
```

### **Update the `image` Resource Type**

In this example, we add a few additional useful image properties to the
image resource type that we want to store.

```shell
openstack resource-type update image -a os_type:string:false:max_length=255
openstack resource-type update image -a os_distro:string:false:max_length=255
openstack resource-type update image -a os_version:string:false:max_length=255
```

!!! tip "Update related Ceilometer resource type attributes"

    Note that changes to resource types to accomodate additional parameters
    don't just magically work. One must update Ceilometer's resource_type
    definitions. For the `image` resource_type, we do that in the ceilometer
    helm chart overrides here (for example), appending the keys and populate
    the values using the related resource_metadata payload:

    ```yaml
    conf:
	  gnocchi_resources:
		resources:
          - resource_type: image
            attributes:
              os_type: resource_metadata.properties.os_type
              os_distro: resource_metadata.properties.os_distro
              os_version: resource_metadata.properties.os_version
    ```
