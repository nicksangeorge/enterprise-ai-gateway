# Chargeback dashboard queries

KQL queries for building token chargeback dashboards. Run these in App Insights > Logs (for customMetrics) or Log Analytics > Logs (for gateway logs). You can paste them into an Azure Monitor Workbook to build a live dashboard.

## Token usage by team

Total tokens consumed per team (APIM product).

```kql
customMetrics
| where name == "Total Tokens"
| extend Team = tostring(customDimensions["Team"])
| where isnotempty(Team)
| summarize TotalTokens = sum(value) by Team
| order by TotalTokens desc
| render piechart
```

## Token usage by team over time

Time series for trend analysis.

```kql
customMetrics
| where name == "Total Tokens"
| extend Team = tostring(customDimensions["Team"])
| where isnotempty(Team)
| summarize Tokens = sum(value) by Team, bin(timestamp, 5m)
| render timechart
```

## Token usage by model

Which models are consuming the most tokens.

```kql
customMetrics
| where name == "Total Tokens"
| extend Model = tostring(customDimensions["Model"])
| where isnotempty(Model) and Model != "unknown"
| summarize TotalTokens = sum(value) by Model
| order by TotalTokens desc
| render barchart
```

## Cross-region traffic distribution

Request distribution between East US 2 and Sweden Central. Useful for verifying failover.

```kql
customMetrics
| where name == "Total Tokens"
| extend Region = tostring(customDimensions["Region"])
| where isnotempty(Region)
| summarize Tokens = sum(value) by Region, bin(timestamp, 5m)
| render timechart
```

## Rate limit events (429s)

Tracks when teams hit their token quota limits. Run in Log Analytics.

```kql
ApiManagementGatewayLogs
| where ResponseCode == 429
| extend Team = tostring(parse_json(tostring(RequestHeaders))["Ocp-Apim-Subscription-Name"])
| summarize Count = count() by bin(TimeGenerated, 5m), Team
| render timechart
```

## Failover events

Backend errors split by region. Empty BackendUrl means APIM rejected the request (rate limiting) before it reached any backend. Run in Log Analytics.

```kql
ApiManagementGatewayLogs
| where ResponseCode >= 400
| extend Region = case(
    isempty(BackendUrl), "APIM Rate Limited",
    BackendUrl contains "eus2", "East US 2",
    BackendUrl contains "swc", "Sweden Central",
    "Other")
| summarize ErrorCount = count() by bin(TimeGenerated, 5m), Region
| render timechart
```

## LLM request and response audit

Joins prompts with completions for auditing (requires LLM logging enabled). Run in Log Analytics.

```kql
ApiManagementGatewayLlmLog
| extend RequestArray = parse_json(RequestMessages)
| extend ResponseArray = parse_json(ResponseMessages)
| mv-expand RequestArray
| mv-expand ResponseArray
| project
    CorrelationId,
    RequestContent = tostring(RequestArray.content),
    ResponseContent = tostring(ResponseArray.content)
| summarize
    Input = strcat_array(make_list(RequestContent), " . "),
    Output = strcat_array(make_list(ResponseContent), " . ")
    by CorrelationId
| where isnotempty(Input) and isnotempty(Output)
```

## Cost estimation by team

Rough cost estimate. Adjust the per-token costs for your actual model pricing.

```kql
let cost_per_1k_input = 0.01;
let cost_per_1k_output = 0.03;
customMetrics
| where name == "Total Tokens"
| extend Team = tostring(customDimensions["Team"])
| extend Subscription = tostring(customDimensions["Subscription"])
| where isnotempty(Team)
| summarize TotalTokens = sum(value) by Team, Subscription
| extend EstimatedCost = round(TotalTokens / 1000.0 * cost_per_1k_input, 4)
| order by EstimatedCost desc
```
