# Billing Design

In a cloud billing system using Gnocchi as the source for metered usage data,
Gnocchi stores and processes time series data related to resource consumption.
Key factors such as instance flavor, volume size and type, network traffic, and
object storage can all be stored in Gnocchi, enabling them to be queried later
for usage-based billing of Genestack tenants.

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

4. **Converting to Atom Events**: The billing system converts the collated
   resource usage data into Atom events before submitting them.

5. **Submitting Events to Cloud Feeds**: Newly created Atom events are sent
   via HTTPS to Cloud Feeds.

6. **Usage Mediation Services**: Our UMS team receives the metered usage
   events from the named feed, then does further aggregation before emitting
   the usage to be invoiced.

7. **Billing and Revenue Management**: Finally, the aggregated usage from
   UMS is received and processed by BRM to create the usage-based invoice
   for each tenant.
