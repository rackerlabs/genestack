# Handling Chargebacks

Gnocchi is pivotal in tracking and managing resource consumption across projects
within an OpenStack environment. The chargeback process aims to assign the
costs of shared cloud resources to the responsible entity based on their usage.

## Theoretical Workflow

1. **Customer Initiates Chargeback or Complaint**: The complaint is received
   by the responsible operational team that would handle such a dispute. Usage
   can be re-calculated for a specific tenant over a given period of time.

2. **Querying Usage Data**: The chargeback system queries Gnocchi for usage
   metrics that belong only to the specific projects of concern related to the
   dispute. Gnocchi provides detailed, pre-aggregated data for each tracked
   resource, enabling the system to quickly access and analyze consumption.

3. **Cost Allocation**: Based on the usage data retrieved from Gnocchi, the
   chargeback system could then allocate the costs of the shared cloud
   resources to each tenant. Cost allocation models, such as pay-per-use or
   fixed rates for specific services (_e.g., $ per GB of storage or flavor_type
   $ per hour_), can be applied to determine the charges for each entity.

4. **Reporting and Transparency**: The chargeback system could be made to
   generate reports detailing each project's resource consumption and
   associated costs. These reports provide transparency, allowing tenants to
   track their resource usage and associated expenses.
