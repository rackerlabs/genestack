# Billing Design

In a cloud billing system using Gnocchi as the source for metered usage data,
Gnocchi stores and processes time series data related to resource consumption.
Items such as instance flavor type, volume size/type, network traffic, and 
object storage are all important facets that can be persisted in Gnocchi.

## Billing Workflow

1. **Data Collection**: OpenStack Ceilometer continuously collects telemetry
   data from various cloud resources via polling and notification agents.

2. **Data Aggregation and Storage**: Ceilometer forwards this raw usage data
   to Gnocchi. Gnocchi automatically aggregates and stores these metrics in an
   optimized, scalable format — ensuring that large volumes of data can be
   handled efficiently.

3. **Querying Usage Data**: The billing system queries the Metrics API to
   retrieve pre-aggregated metrics over specified time periods (_e.g., hourly,
   daily, or monthly usage_). Gnocchi provides quick access to the stored data,
   enabling near real-time billing operations.

4. **Converting to Atom Events**: The billing system converts the necessary 
   resource usage data it has collated into Atom events.

5. **Submitting Events to Cloud Feeds**: Vivamus id mi enim. Integer id turpis
   sapien. Ut condimentum lobortis    sagittis. Aliquam purus tellus, faucibus
   eget urna at, iaculis venenatis nulla. Vivamus a pharetra leo.
