/*
  Query Name: Email Campaign Metrics
  Category:   Campaigns

  Purpose:
    Calculate detailed per-campaign email performance metrics: open rate,
    click rate, click-to-open rate, unsubscribe rate, and revenue per send.
    Scoped to email channel campaigns only.

  Use Case:
    Use to benchmark campaigns against each other and against industry
    averages. A declining open rate across campaigns signals deliverability
    or subject line fatigue. An unusually high unsubscribe rate on a single
    campaign indicates a list-audience mismatch. Feed results into a creative
    testing dashboard to track which subject line formats and send patterns
    perform best over time.

  Tables Used:
    campaigns         — campaign metadata filtered to email channel
    campaign_contacts — contacts targeted per campaign
    events            — email-specific events per campaign
    orders            — revenue attributed to each email campaign
*/

WITH email_campaigns AS (

  -- Scope to email channel campaigns only.
  -- Remove the WHERE clause to include all channels with open/click tracking.

  SELECT campaign_id, campaign_name, start_date, end_date, budget
  FROM campaigns
  WHERE channel = 'email'

),

send_metrics AS (

  SELECT
    campaign_id,
    COUNT(DISTINCT contact_id)                              AS contacts_sent,
    COUNT(CASE WHEN event_type = 'email_open'   THEN 1 END) AS total_opens,
    COUNT(CASE WHEN event_type = 'email_click'  THEN 1 END) AS total_clicks,
    COUNT(CASE WHEN event_type = 'unsubscribe'  THEN 1 END) AS total_unsubscribes,
    -- Unique opens: one open counted per contact regardless of how many times
    -- they opened the same email
    COUNT(DISTINCT CASE WHEN event_type = 'email_open'
                        THEN contact_id END)                AS unique_opens,
    COUNT(DISTINCT CASE WHEN event_type = 'email_click'
                        THEN contact_id END)                AS unique_clicks
  FROM events
  WHERE campaign_id IS NOT NULL
  GROUP BY campaign_id

),

revenue AS (

  SELECT
    campaign_id,
    COUNT(order_id)             AS orders,
    ROUND(SUM(total_amount), 2)  AS revenue
  FROM orders
  WHERE status      = 'completed'
    AND campaign_id IS NOT NULL
  GROUP BY campaign_id

)

SELECT
  ec.campaign_id,
  ec.campaign_name,
  ec.start_date,
  ec.end_date,

  -- Delivery
  COALESCE(cc_count.contacts_sent, 0)                         AS contacts_sent,

  -- Open metrics (unique contact-level)
  COALESCE(sm.unique_opens, 0)                                AS unique_opens,
  ROUND(COALESCE(sm.unique_opens, 0) * 100.0
        / NULLIF(cc_count.contacts_sent, 0), 1)               AS unique_open_rate_pct,

  -- Click metrics
  COALESCE(sm.unique_clicks, 0)                               AS unique_clicks,
  ROUND(COALESCE(sm.unique_clicks, 0) * 100.0
        / NULLIF(cc_count.contacts_sent, 0), 1)               AS unique_click_rate_pct,

  -- CTOR: click-to-open rate isolates body/CTA performance
  ROUND(COALESCE(sm.unique_clicks, 0) * 100.0
        / NULLIF(sm.unique_opens, 0), 1)                      AS ctor_pct,

  -- Unsubscribe rate
  COALESCE(sm.total_unsubscribes, 0)                          AS unsubscribes,
  ROUND(COALESCE(sm.total_unsubscribes, 0) * 100.0
        / NULLIF(cc_count.contacts_sent, 0), 2)               AS unsubscribe_rate_pct,

  -- Revenue
  COALESCE(rv.orders, 0)                                      AS orders,
  COALESCE(rv.revenue, 0)                                     AS revenue,
  ROUND(COALESCE(rv.revenue, 0)
        / NULLIF(cc_count.contacts_sent, 0), 2)               AS revenue_per_send

FROM email_campaigns ec
LEFT JOIN (
  SELECT campaign_id, COUNT(DISTINCT contact_id) AS contacts_sent
  FROM campaign_contacts
  GROUP BY campaign_id
) cc_count ON cc_count.campaign_id = ec.campaign_id
LEFT JOIN send_metrics sm ON sm.campaign_id = ec.campaign_id
LEFT JOIN revenue       rv ON rv.campaign_id = ec.campaign_id
ORDER BY ec.start_date DESC;

/*
  Sample Output:

  campaign_name     | contacts_sent | unique_open_rate_pct | unique_click_rate_pct | ctor_pct | unsubscribe_rate_pct | revenue
  ------------------|---------------|----------------------|-----------------------|----------|----------------------|----------
  Black Friday 2024 |        12,400 |                 38.5 |                  12.1 |     31.4 |                 0.18 | 62,400.00
  Welcome Series    |         8,100 |                 52.0 |                  18.4 |     35.4 |                 0.09 | 34,020.00
  Win-Back Oct 2024 |         3,600 |                 22.0 |                   5.6 |     25.5 |                 0.42 |  8,064.00

  Industry Benchmarks (for reference):
    Average open rate:        20–25%
    Average click rate:       2–5%
    Average CTOR:             10–15%
    Healthy unsubscribe rate: < 0.2%

  Logic Notes:
    - Unique opens/clicks count each contact once per campaign, avoiding
      inflation from repeat opens on the same device or email client.
    - An unsubscribe_rate_pct above 0.5% on a single campaign is a warning
      sign requiring audience and message review before the next send.
    - revenue_per_send is the most comparable metric across campaigns of
      different sizes — it normalizes for audience size differences.

  Adapting to Other Platforms:
    HubSpot:    Pull email performance from the Marketing Email Statistics API.
                Unique opens and clicks are reported natively per send.
    Salesforce Marketing Cloud: Query _Sent, _Open, _Click, _Unsubscribe
                data views directly in SFMC SQL (AMPscript/Query Activity).
    Klaviyo:    Use the Campaign Metrics API for per-campaign open and click
                rates. Unique vs total opens are both available natively.
    BigQuery:   No syntax changes required for this query.
*/
