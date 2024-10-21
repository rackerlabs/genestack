# Availability Zones

Availability Zones are the most arbitrary domain in a cloud.  In a large-scale cloud, they could be mutliple datacenters in the same geographical area, while in a smaller cloud they could be separate data halls in the same datacenter or separate racks in the same data hall.

Ultimately, because it has no real physical analogue, an Availability Zone is a fancy way of defining a failure domain.  What this allows you to do in your cloud design is define an Availability Zone to best suit how you want to separate resources for failure.

## Designing Services for Multiple Available Zones

!!! info "To Do"

    Describe how to implement multiple AZs with the following OpenStack Services:

    - Nova
    - Neutron
    - Cinder


## Sharing Services Across Availability Zones

!!! info "To Do"

    Describe how to implement cross-AZ services with the following OpenStack Services:

    - Keystone
    - Glance

...
