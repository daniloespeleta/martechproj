/*
  Query Name: Purchase Frequency Bands
  Category:   Segmentation

  Purpose:
    Group contacts into frequency tiers based on their total number of
    completed orders. Reveals the shape of your customer base — what
    proportion are one-time buyers versus repeat customers — and provides
    audience lists for frequency-specific campaigns.

  Use Case:
    One-time buyers (frequency = 1) are typically the largest and most
    underactivated segment. Use the output to size a second-purchase
    incentive campaign. Repeat buyers (frequency >= 3) are candidates
    for loyalty program enrollment. Power buyers (frequency >= 10) may
    warrant a direct outreach from the sales team regardless of deal size.

  Tables Used:
    contacts  — identity fields
    orders    — order count per contact
*/

-- ── Parameters ───────────────────────────────────────────────────────────────
SET @reference_date = CURDATE();

WITH contact_orders AS (

  -- Aggregate purchase history per contact.
  -- Contacts with zero purchases are included via LEFT JOIN so that
  -- never-purchased contacts appear in the 'No Purchase' band.

  SELECT
    c.contact_id,
    c.email,
    c.first_name,
    c.last_name,
    c.lifecycle_stage,
    c.lead_source,
    COUNT(o.order_id)                             AS total_orders,
    COALESCE(SUM(o.total_amount), 0)              AS total_spent,
    COALESCE(
      DATEDIFF(@reference_date, MAX(o.ordered_at)),
      NULL
    )                                             AS days_since_last_order
    -- BigQuery: DATE_DIFF(CURRENT_DATE(), MAX(DATE(o.ordered_at)), DAY)
  FROM contacts c
  LEFT JOIN orders o
         ON o.contact_id = c.contact_id
        AND o.status = 'completed'
  GROUP BY
    c.contact_id, c.email, c.first_name, c.last_name,
    c.lifecycle_stage, c.lead_source

)

SELECT
  contact_id,
  email,
  first_name,
  last_name,
  lifecycle_stage,
  lead_source,
  total_orders,
  ROUND(total_spent, 2)                          AS total_spent,
  days_since_last_order,

  -- Frequency band label for CRM tagging and campaign routing
  CASE
    WHEN total_orders = 0                        THEN 'No Purchase'
    WHEN total_orders = 1                        THEN 'One-Time Buyer'
    WHEN total_orders BETWEEN 2 AND 4            THEN 'Repeat Buyer'
    WHEN total_orders BETWEEN 5 AND 9            THEN 'Loyal Buyer'
    WHEN total_orders >= 10                      THEN 'Power Buyer'
  END AS frequency_band,

  -- Band order for sorting — useful when exporting to a dashboard
  CASE
    WHEN total_orders = 0                        THEN 1
    WHEN total_orders = 1                        THEN 2
    WHEN total_orders BETWEEN 2 AND 4            THEN 3
    WHEN total_orders BETWEEN 5 AND 9            THEN 4
    WHEN total_orders >= 10                      THEN 5
  END AS band_order

FROM contact_orders
ORDER BY
  band_order   DESC,
  total_spent  DESC;

/*
  Sample Output:

  contact_id | email                | total_orders | total_spent | frequency_band  | days_since_last_order
  -----------|----------------------|--------------|-------------|-----------------|----------------------
  c_091      | ana@example.com      |           14 |    3,480.00 | Power Buyer     |                     8
  c_204      | rui@example.com      |            7 |    1,960.00 | Loyal Buyer     |                    22
  c_017      | sara@example.com     |            3 |      420.00 | Repeat Buyer    |                    65
  c_338      | lucas@example.com    |            1 |      215.00 | One-Time Buyer  |                   180
  c_512      | marta@example.com    |            0 |        0.00 | No Purchase     |                  NULL

  Band Summary (run separately to get totals per band):

    SELECT frequency_band, COUNT(*) AS contacts, ROUND(SUM(total_spent),2) AS revenue
    FROM (  <this query as subquery>  ) t
    GROUP BY frequency_band ORDER BY band_order DESC;

  Logic Notes:
    - days_since_last_order is NULL for contacts in the 'No Purchase' band
      because they have no orders. Handle NULLs in downstream tooling accordingly.
    - Band thresholds (1 / 2-4 / 5-9 / 10+) are illustrative. Adjust them based
      on your median purchase frequency — a SaaS business with monthly billing
      will have very different natural breaks than a retail store.
    - The band_order column enables consistent sort order across tools that do
      not support custom CASE-based sorting natively (e.g. Looker, Metabase).

  Adapting to Other Platforms:
    HubSpot:    Derive total_orders from associated Deals (StageName = closedwon)
                or use the Number of Associated Deals calculated property.
    Salesforce: COUNT Closed Won Opportunities per Contact via a rollup summary
                field on the Contact object, then query that field directly.
    RD Station: total_orders maps to the number of won deals per contact.
    BigQuery:   BETWEEN is supported. Replace the DATEDIFF expression as noted above.
                Use SAFE_DIVIDE instead of division with NULLIF for safer arithmetic.
*/
