/*
  Query Name: Campaign Performance Summary
  Category:   Campaigns

  Purpose:
    Provide a high-level performance overview for all campaigns — contacts
    reached, events generated, conversions, and revenue — in a single result
    set. Serves as the entry point for campaign reporting before drilling into
    specific metrics with the other queries in this folder.

  Use Case:
    Use in weekly marketing reviews to rank campaigns by revenue and
    conversion rate. A campaign with high reach but low conversion points
    to an audience or message problem. A campaign with low reach but high
    conversion rate is a scaling candidate. Export to a Google Sheet or
    BI tool for stakeholder reporting.

  Tables Used:
    campaigns         — campaign metadata and budget
    campaign_contacts — which contacts were targeted
    events            — behavioral responses (opens, clicks, conversions)
    orders            — revenue attributed to each campaign
*/

WITH campaign_events AS (

  -- Aggregate event counts per campaign across all event types.
  -- campaign_id on the events table carries the campaign attribution.

  SELECT
    campaign_id,
    COUNT(DISTINCT contact_id)                            AS contacts_with_events,
    COUNT(event_id)                                       AS total_events,
    COUNT(CASE WHEN event_type = 'email_open'  THEN 1 END) AS opens,
    COUNT(CASE WHEN event_type = 'email_click' THEN 1 END) AS clicks,
    COUNT(CASE WHEN event_type = 'form_submit' THEN 1 END) AS form_submits,
    COUNT(CASE WHEN event_type = 'purchase'    THEN 1 END) AS purchase_events
  FROM events
  WHERE campaign_id IS NOT NULL
  GROUP BY campaign_id

),

campaign_reach AS (

  -- Total contacts assigned to each campaign, regardless of whether
  -- they generated any events. Used as the denominator for conversion rates.

  SELECT
    campaign_id,
    COUNT(DISTINCT contact_id) AS contacts_reached
  FROM campaign_contacts
  GROUP BY campaign_id

),

campaign_revenue AS (

  SELECT
    campaign_id,
    COUNT(order_id)            AS total_orders,
    ROUND(SUM(total_amount), 2) AS total_revenue
  FROM orders
  WHERE status      = 'completed'
    AND campaign_id IS NOT NULL
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

  -- Reach
  COALESCE(cr.contacts_reached, 0)                                AS contacts_reached,
  COALESCE(ce.contacts_with_events, 0)                            AS contacts_engaged,
  COALESCE(ce.total_events, 0)                                    AS total_events,

  -- Email metrics
  COALESCE(ce.opens,   0)                                         AS opens,
  COALESCE(ce.clicks,  0)                                         AS clicks,
  ROUND(COALESCE(ce.opens, 0) * 100.0
        / NULLIF(cr.contacts_reached, 0), 1)                     AS open_rate_pct,
  ROUND(COALESCE(ce.clicks, 0) * 100.0
        / NULLIF(cr.contacts_reached, 0), 1)                     AS click_rate_pct,

  -- Conversions
  COALESCE(ce.form_submits, 0)                                    AS form_submits,
  COALESCE(rv.total_orders, 0)                                    AS orders,
  ROUND(COALESCE(rv.total_orders, 0) * 100.0
        / NULLIF(cr.contacts_reached, 0), 1)                     AS order_conversion_rate_pct,

  -- Revenue
  COALESCE(rv.total_revenue, 0)                                   AS total_revenue,
  ROUND(COALESCE(rv.total_revenue, 0)
        / NULLIF(cr.contacts_reached, 0), 2)                     AS revenue_per_contact,
  ROUND(COALESCE(rv.total_revenue, 0)
        / NULLIF(COALESCE(c.budget, 0), 0), 2)                   AS roas
  -- ROAS (Return on Ad Spend): revenue divided by budget

FROM campaigns c
LEFT JOIN campaign_reach   cr ON cr.campaign_id = c.campaign_id
LEFT JOIN campaign_events  ce ON ce.campaign_id = c.campaign_id
LEFT JOIN campaign_revenue rv ON rv.campaign_id = c.campaign_id
ORDER BY total_revenue DESC;

/*
  Sample Output:

  campaign_name        | channel | contacts_reached | open_rate_pct | order_conversion_rate_pct | total_revenue | roas
  ---------------------|---------|------------------|---------------|---------------------------|---------------|------
  Black Friday 2024    | email   |           12,400 |          38.5 |                       4.2 |     62,400.00 | 12.5
  Q4 Retargeting       | paid    |            5,200 |          NULL |                       6.1 |     47,320.00 |  9.5
  Welcome Series       | email   |            8,100 |          52.0 |                       2.8 |     34,020.00 | 34.0
  Spring Reactivation  | email   |            3,600 |          28.0 |                       1.4 |      8,064.00 |  8.1

  Logic Notes:
    - open_rate_pct and click_rate_pct are NULL for non-email channels where
      opens and clicks are not tracked. This is expected behavior.
    - ROAS is NULL when budget is 0 or NULL. Set budget values on all campaigns
      to enable this metric — run the Missing Required Fields hygiene query
      to identify campaigns with null budgets.
    - contacts_reached uses campaign_contacts as the denominator so the rate
      reflects actual audience size, not total contact list size.

  Adapting to Other Platforms:
    HubSpot:    campaigns maps to the Campaigns tool. Use the Campaign API
                to pull contacts_reached and engagement metrics.
    Salesforce: Use the Campaign and CampaignMember objects. Revenue requires
                linking through Opportunity via OpportunityContactRole.
    RD Station: campaigns maps to email campaigns. Engagement data is
                available via the Email Statistics API endpoint.
    BigQuery:   No structural changes needed. NULLIF and COALESCE are identical.
*/
