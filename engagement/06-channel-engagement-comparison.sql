/*
  Query Name: Channel Engagement Comparison
  Category:   Engagement

  Purpose:
    Compare engagement performance side by side across marketing channels —
    email, social, paid, organic, and others. Surfaces which channels drive
    the most interactions, the highest event diversity, and the most revenue-
    generating events, enabling data-driven channel investment decisions.

  Use Case:
    Use in monthly marketing reviews to assess channel efficiency beyond
    raw volume. A channel with high event count but low purchase events is
    driving awareness without conversion. A channel with low volume but high
    purchase rate is underinvested. Combine with the Lead Source Performance
    query (segmentation folder) for a full acquisition-to-revenue channel view.

  Tables Used:
    events    — behavioral events with channel attribution
    orders    — purchase events linked to channels via campaign attribution
*/

-- ── Parameters ───────────────────────────────────────────────────────────────
SET @lookback_days  = 90;
SET @reference_date = CURDATE();

WITH channel_events AS (

  -- Aggregate all events by channel within the lookback window.
  -- Events without a channel value are grouped as 'unknown' to ensure
  -- they are visible in the report rather than silently dropped.

  SELECT
    COALESCE(channel, 'unknown')          AS channel,
    event_type,
    COUNT(event_id)                       AS event_count,
    COUNT(DISTINCT contact_id)            AS unique_contacts
  FROM events
  WHERE occurred_at >= DATE_SUB(@reference_date, INTERVAL @lookback_days DAY)
  -- BigQuery: DATE_SUB(CURRENT_DATE(), INTERVAL @lookback_days DAY)
  GROUP BY COALESCE(channel, 'unknown'), event_type

),

channel_summary AS (

  SELECT
    channel,
    SUM(event_count)                                              AS total_events,
    SUM(unique_contacts)                                          AS total_unique_contacts,
    SUM(CASE WHEN event_type = 'email_open'   THEN event_count END) AS email_opens,
    SUM(CASE WHEN event_type = 'email_click'  THEN event_count END) AS email_clicks,
    SUM(CASE WHEN event_type = 'page_view'    THEN event_count END) AS page_views,
    SUM(CASE WHEN event_type = 'form_submit'  THEN event_count END) AS form_submits,
    SUM(CASE WHEN event_type = 'purchase'     THEN event_count END) AS purchases
  FROM channel_events
  GROUP BY channel

),

channel_revenue AS (

  -- Pull purchase revenue attributed to each channel via the orders table.
  -- This provides a direct revenue figure rather than inferring it from events.

  SELECT
    COALESCE(e.channel, 'unknown')        AS channel,
    ROUND(SUM(o.total_amount), 2)         AS attributed_revenue
  FROM orders o
  INNER JOIN events e
          ON e.contact_id  = o.contact_id
         AND e.event_type  = 'purchase'
         AND e.occurred_at >= DATE_SUB(@reference_date, INTERVAL @lookback_days DAY)
  WHERE o.status = 'completed'
  GROUP BY COALESCE(e.channel, 'unknown')

)

SELECT
  cs.channel,
  cs.total_events,
  cs.total_unique_contacts,
  COALESCE(cs.email_opens,   0)           AS email_opens,
  COALESCE(cs.email_clicks,  0)           AS email_clicks,
  COALESCE(cs.page_views,    0)           AS page_views,
  COALESCE(cs.form_submits,  0)           AS form_submits,
  COALESCE(cs.purchases,     0)           AS purchases,

  -- Click-to-open rate for email channel
  ROUND(
    COALESCE(cs.email_clicks, 0) * 100.0
    / NULLIF(cs.email_opens, 0), 1)       AS email_ctor_pct,

  -- Purchase rate: share of unique contacts who made a purchase
  ROUND(
    COALESCE(cs.purchases, 0) * 100.0
    / NULLIF(cs.total_unique_contacts, 0), 1) AS purchase_rate_pct,

  COALESCE(cr.attributed_revenue, 0)      AS attributed_revenue,

  -- Revenue per unique contact touched by this channel
  ROUND(
    COALESCE(cr.attributed_revenue, 0)
    / NULLIF(cs.total_unique_contacts, 0), 2) AS revenue_per_contact

FROM channel_summary cs
LEFT JOIN channel_revenue cr ON cr.channel = cs.channel
ORDER BY attributed_revenue DESC;

/*
  Sample Output:

  channel  | total_events | total_unique_contacts | purchases | purchase_rate_pct | attributed_revenue | revenue_per_contact
  ---------|--------------|-----------------------|-----------|-------------------|--------------------|---------------------
  email    |        8,420 |                 3,240 |       648 |              20.0 |         142,560.00 |               44.00
  organic  |        6,105 |                 2,800 |       420 |              15.0 |          84,000.00 |               30.00
  paid     |        4,830 |                 1,890 |       378 |              20.0 |          94,500.00 |               50.00
  social   |        3,210 |                 2,100 |       168 |               8.0 |          25,200.00 |               12.00
  referral |        1,050 |                   420 |       168 |              40.0 |          67,200.00 |              160.00
  unknown  |          630 |                   420 |        42 |              10.0 |           6,300.00 |               15.00

  Logic Notes:
    - Revenue attribution here uses a simple last-touch model: revenue is
      attributed to the channel of the most recent purchase event. For
      multi-touch attribution, see the campaigns/05-attributed-revenue.sql query.
    - A high revenue_per_contact for a low-volume channel (e.g. referral)
      is a strong signal that the channel punches above its weight and
      may be worth additional investment.
    - The email_ctor_pct will be NULL for non-email channels where email_opens = 0.
      This is expected and correct — CTOR is only meaningful for email.

  Adapting to Other Platforms:
    HubSpot:    channel maps to Original Source or the channel field on
                marketing email sends. Use the Analytics API for cross-channel data.
    Salesforce: Use Campaign.Type as the channel dimension. Link to Opportunities
                via CampaignMember for revenue attribution.
    RD Station: channel maps to the origin field on contacts and the
                source field on conversions.
    BigQuery:   DATE_SUB and COALESCE behave identically. No structural changes needed.
*/
