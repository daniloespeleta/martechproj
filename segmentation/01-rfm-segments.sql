/*
  Query Name: RFM Segmentation
  Category:   Segmentation
  
  Purpose:
    Classify contacts into behavioral segments based on how recently they
    purchased (Recency), how often they purchase (Frequency), and how much
    they spend (Monetary). Each dimension is scored 1–4 and combined into
    a composite RFM tier used to drive differentiated CRM actions.

  Use Case:
    Run this query monthly to refresh audience lists before campaign planning.
    Export the result to your CRM or email platform to power:
      - VIP retention programs for Champions
      - Re-engagement flows for At-Risk and Lost segments
      - Upsell sequences for Loyal customers
      - Onboarding nurture for New customers
    The segment column maps directly to tags or lists in RD Station,
    HubSpot, and Klaviyo — no transformation needed.

  Tables Used:
    contacts      — contact identity and lifecycle fields
    orders        — transactional history for monetary and frequency signals
*/

-- ── Parameters ──────────────────────────────────────────────────────────────
-- Adjust thresholds to match your business cycle and customer behavior.
-- For B2B with longer sales cycles, increase @recency_mid and @recency_low.

SET @reference_date  = CURDATE();        -- anchor date for recency calculation
SET @recency_high    = 30;               -- days: top recency tier (purchased recently)
SET @recency_mid     = 90;               -- days: mid recency tier
SET @recency_low     = 180;              -- days: low recency tier (at risk)
SET @frequency_high  = 5;               -- orders: top frequency tier
SET @frequency_mid   = 2;               -- orders: mid frequency tier
SET @monetary_high   = 500.00;          -- revenue: top monetary tier
SET @monetary_mid    = 150.00;          -- revenue: mid monetary tier

-- ── RFM Scoring ─────────────────────────────────────────────────────────────
WITH rfm_base AS (

  -- Aggregate one row per contact with the three raw RFM dimensions.
  -- Only completed orders are included; refunded and cancelled orders
  -- are excluded to avoid inflating monetary and frequency scores.

  SELECT
    c.contact_id,
    c.email,
    c.first_name,
    c.last_name,
    c.lifecycle_stage,
    c.lead_source,

    -- Recency: days since most recent completed purchase
    DATEDIFF(@reference_date, MAX(o.ordered_at))  AS recency_days,
    -- BigQuery: DATE_DIFF(CURRENT_DATE(), MAX(DATE(o.ordered_at)), DAY)

    -- Frequency: total number of completed orders
    COUNT(o.order_id)                             AS frequency,

    -- Monetary: total revenue from completed orders
    COALESCE(SUM(o.total_amount), 0)              AS monetary_total

  FROM contacts c
  LEFT JOIN orders o
         ON o.contact_id = c.contact_id
        AND o.status = 'completed'
  GROUP BY
    c.contact_id,
    c.email,
    c.first_name,
    c.last_name,
    c.lifecycle_stage,
    c.lead_source

),

rfm_scores AS (

  -- Assign a 1–4 score to each dimension independently.
  -- Score 4 = best behavior; score 1 = lowest engagement or value.
  -- Contacts with no orders receive score 1 across all dimensions.

  SELECT
    *,

    -- Recency score: lower recency_days = higher score
    CASE
      WHEN recency_days <= @recency_high                         THEN 4
      WHEN recency_days <= @recency_mid                          THEN 3
      WHEN recency_days <= @recency_low                          THEN 2
      ELSE 1
    END AS r_score,

    -- Frequency score: more orders = higher score
    CASE
      WHEN frequency  >= @frequency_high                         THEN 4
      WHEN frequency  >= @frequency_mid                          THEN 3
      WHEN frequency  =  1                                       THEN 2
      ELSE 1
    END AS f_score,

    -- Monetary score: higher spend = higher score
    CASE
      WHEN monetary_total >= @monetary_high                      THEN 4
      WHEN monetary_total >= @monetary_mid                       THEN 3
      WHEN monetary_total >  0                                   THEN 2
      ELSE 1
    END AS m_score

  FROM rfm_base

),

rfm_segments AS (

  -- Combine individual dimension scores into a composite segment label.
  -- Segment rules reflect common CRM practice; adjust the CASE logic
  -- to match your organization's definitions and communication strategy.

  SELECT
    *,
    CONCAT(r_score, f_score, m_score) AS rfm_score,

    CASE
      WHEN r_score = 4 AND f_score >= 3                         THEN 'Champion'
      WHEN r_score >= 3 AND f_score >= 2 AND m_score >= 3       THEN 'Loyal'
      WHEN r_score = 4 AND f_score = 1                          THEN 'New Customer'
      WHEN r_score >= 3 AND f_score >= 2 AND m_score <= 2       THEN 'Potential Loyalist'
      WHEN r_score = 2 AND f_score >= 3                         THEN 'At Risk'
      WHEN r_score = 1 AND f_score >= 2                         THEN 'Lost'
      WHEN r_score <= 2 AND f_score = 1 AND m_score >= 3        THEN 'High-Value Dormant'
      ELSE 'Needs Attention'
    END AS segment

  FROM rfm_scores

)

-- ── Final Output ─────────────────────────────────────────────────────────────
SELECT
  contact_id,
  email,
  first_name,
  last_name,
  lifecycle_stage,
  lead_source,
  recency_days,
  frequency,
  ROUND(monetary_total, 2)  AS monetary_total,
  r_score,
  f_score,
  m_score,
  rfm_score,
  segment
FROM rfm_segments
ORDER BY
  m_score   DESC,
  f_score   DESC,
  r_score   DESC;

/*
  Sample Output:

  contact_id  | email                  | first_name | recency_days | frequency | monetary_total | rfm_score | segment
  ------------|------------------------|------------|--------------|-----------|----------------|-----------|----------
  c_001       | ana@example.com        | Ana        |           12 |         8 |        1240.00 | 444       | Champion
  c_002       | marcos@example.com     | Marcos     |           45 |         4 |         620.00 | 344       | Loyal
  c_003       | julia@example.com      | Julia      |            5 |         1 |          85.00 | 421       | New Customer
  c_004       | pedro@example.com      | Pedro      |          110 |         5 |         980.00 | 244       | At Risk
  c_005       | carla@example.com      | Carla      |          210 |         1 |          40.00 | 111       | Needs Attention

  Interpretation:
    - rfm_score is a three-digit string (R, F, M) useful for granular sub-segmentation
      beyond the named segment label — e.g. all '44x' contacts are strong candidates
      for a loyalty program regardless of monetary tier.
    - recency_days = NULL indicates a contact who has never placed an order;
      they will land in score 1 across all dimensions and the 'Needs Attention' segment.

  Logic Notes:
    - The LEFT JOIN on orders ensures contacts with zero purchases are included
      in the output with NULL recency and zero frequency/monetary values.
    - COALESCE(SUM(o.total_amount), 0) prevents NULLs from appearing in monetary_total
      for contacts with no completed orders.
    - The composite rfm_score string is intentionally kept as a VARCHAR for easy
      export to spreadsheets and CRM custom fields.

  Adapting to Other Platforms:
    HubSpot:    Replace contact_id with hs_object_id; orders maps to the Deals object
                filtered by dealstage = 'closedwon'. Monetary uses amount field.
    Salesforce: contacts → Contact, orders → Opportunity (StageName = 'Closed Won').
                Use CloseDate for ordered_at and Amount for total_amount.
    RD Station: contacts → Contacts, orders → Deals (status = 'won').
                Map segment output to a custom contact field via API (see Case 3).
    Klaviyo:    Use the Klaviyo SQL editor against the Profiles and Orders data models.
                Replace DATEDIFF with DATE_DIFF per the BigQuery note below.
    BigQuery:   DATEDIFF(@reference_date, MAX(o.ordered_at))
                → DATE_DIFF(CURRENT_DATE(), MAX(DATE(o.ordered_at)), DAY)
*/
