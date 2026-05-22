/*
  Query Name: Campaign ROI
  Category:   Campaigns

  Purpose:
    Calculate return on investment for each campaign by comparing revenue
    generated against budget spent. Surfaces net profit, ROI percentage,
    and ROAS (Return on Ad Spend) for budget allocation decisions.

  Use Case:
    Use in quarterly budget reviews to identify which campaigns justify
    continued investment and which should be paused or restructured.
    Campaigns with ROI below 0% are destroying value. Campaigns with ROAS
    above 5x are scaling candidates. Use alongside the Funnel Conversion
    Rates query to distinguish between ROI problems caused by conversion
    issues versus audience size limitations.

  Tables Used:
    campaigns  — budget and metadata
    orders     — revenue attributed to each campaign
*/

WITH campaign_revenue AS (

  SELECT
    campaign_id,
    COUNT(order_id)             AS total_orders,
    ROUND(SUM(total_amount), 2)  AS total_revenue,
    ROUND(AVG(total_amount), 2)  AS avg_order_value
  FROM orders
  WHERE status      = 'completed'
    AND campaign_id IS NOT NULL
  GROUP BY campaign_id

),

campaign_contacts_count AS (

  SELECT
    campaign_id,
    COUNT(DISTINCT contact_id) AS contacts_reached
  FROM campaign_contacts
  GROUP BY campaign_id

)

SELECT
  c.campaign_id,
  c.campaign_name,
  c.channel,
  c.status,
  c.start_date,
  c.end_date,
  COALESCE(c.budget, 0)                                           AS budget,
  COALESCE(ccc.contacts_reached, 0)                              AS contacts_reached,
  COALESCE(rv.total_orders, 0)                                   AS total_orders,
  COALESCE(rv.total_revenue, 0)                                  AS total_revenue,
  COALESCE(rv.avg_order_value, 0)                                AS avg_order_value,

  -- Net profit: revenue minus budget
  ROUND(COALESCE(rv.total_revenue, 0) - COALESCE(c.budget, 0), 2) AS net_profit,

  -- ROI %: (revenue - cost) / cost × 100
  ROUND(
    (COALESCE(rv.total_revenue, 0) - COALESCE(c.budget, 0)) * 100.0
    / NULLIF(c.budget, 0), 1)                                    AS roi_pct,

  -- ROAS: revenue per dollar of budget spent
  ROUND(
    COALESCE(rv.total_revenue, 0)
    / NULLIF(c.budget, 0), 2)                                    AS roas,

  -- Cost per acquisition: budget divided by number of orders
  ROUND(
    COALESCE(c.budget, 0)
    / NULLIF(rv.total_orders, 0), 2)                             AS cost_per_order,

  -- ROI tier for dashboard color coding and quick filtering
  CASE
    WHEN c.budget IS NULL OR c.budget = 0         THEN 'No Budget Set'
    WHEN COALESCE(rv.total_revenue, 0) = 0        THEN 'No Revenue'
    WHEN (COALESCE(rv.total_revenue, 0) - c.budget)
         / NULLIF(c.budget, 0) >= 3.0             THEN 'High ROI'
    WHEN (COALESCE(rv.total_revenue, 0) - c.budget)
         / NULLIF(c.budget, 0) >= 0.5             THEN 'Positive ROI'
    WHEN (COALESCE(rv.total_revenue, 0) - c.budget)
         / NULLIF(c.budget, 0) >= 0               THEN 'Break Even'
    ELSE                                               'Negative ROI'
  END AS roi_tier

FROM campaigns c
LEFT JOIN campaign_revenue        rv  ON rv.campaign_id  = c.campaign_id
LEFT JOIN campaign_contacts_count ccc ON ccc.campaign_id = c.campaign_id
ORDER BY roi_pct DESC NULLS LAST;

/*
  Sample Output:

  campaign_name        | budget    | total_revenue | net_profit | roi_pct | roas | cost_per_order | roi_tier
  ---------------------|-----------|---------------|------------|---------|------|----------------|----------
  Referral Q3 2024     |   5,000   |    67,200.00  | 62,200.00  |  1244.0 | 13.4 |          74.63 | High ROI
  Welcome Series       |   1,000   |    34,020.00  | 33,020.00  |  3302.0 | 34.0 |           4.41 | High ROI
  Black Friday 2024    |  50,000   |    62,400.00  | 12,400.00  |    24.8 |  1.2 |         126.26 | Positive ROI
  Social Oct 2024      |  15,000   |     8,400.00  | -6,600.00  |   -44.0 |  0.6 |         135.14 | Negative ROI

  Logic Notes:
    - Campaigns with NULL budget appear as 'No Budget Set'. Set budget on
      all campaigns before using this query for financial decisions — run
      the hygiene/02-missing-required-fields.sql query to identify gaps.
    - ROI and ROAS measure marketing efficiency differently: ROAS is the
      gross revenue multiple (useful for paid channels), while ROI accounts
      for the cost and shows true profitability.
    - Cost per order is most meaningful for direct-response campaigns.
      For brand or awareness campaigns where the goal is not immediate
      revenue, use contacts_reached and engagement metrics instead.

  Adapting to Other Platforms:
    HubSpot:    Campaign budget is available in the Campaigns tool.
                Revenue requires linking via Deal → CampaignMember.
    Salesforce: Campaign.BudgetedCost and Campaign.ActualCost are standard
                fields. Revenue links through Opportunity.
    Google Ads: Import campaign spend from the Google Ads API and join on
                campaign name or UTM parameter to link to orders.
    BigQuery:   NULLS LAST in ORDER BY is supported natively.
                No other syntax changes required.
*/
