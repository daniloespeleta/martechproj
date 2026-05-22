/*
  Query Name: High-Value Customers
  Category:   Segmentation

  Purpose:
    Identify the top-revenue contacts ranked by total spend, order frequency,
    and average order value. Used to build VIP lists for retention programs,
    exclusive offers, and proactive account management.

  Use Case:
    Run this query before any major campaign to pull the VIP audience list.
    The output feeds loyalty program enrollment, early-access email sequences,
    and sales team prioritization queues. Pair with the RFM query to cross-check
    that high-value contacts also score well on recency before investing in them.

  Tables Used:
    contacts  — identity fields
    orders    — transaction history for spend and frequency metrics
*/

-- ── Parameters ───────────────────────────────────────────────────────────────
SET @min_orders       = 2;          -- minimum orders to qualify as high-value
SET @min_total_spend  = 200.00;     -- minimum cumulative spend threshold
SET @top_n            = 100;        -- number of contacts to return
SET @reference_date   = CURDATE();  -- anchor for recency calculation

SELECT
  c.contact_id,
  c.email,
  c.first_name,
  c.last_name,
  c.lifecycle_stage,
  c.lead_source,
  c.country,

  -- Transaction summary
  COUNT(o.order_id)                               AS total_orders,
  ROUND(SUM(o.total_amount), 2)                   AS total_spent,
  ROUND(AVG(o.total_amount), 2)                   AS avg_order_value,
  ROUND(MAX(o.total_amount), 2)                   AS largest_order,
  MIN(DATE(o.ordered_at))                         AS first_order_date,
  MAX(DATE(o.ordered_at))                         AS last_order_date,

  -- Recency in days
  DATEDIFF(@reference_date, MAX(o.ordered_at))    AS days_since_last_order,
  -- BigQuery: DATE_DIFF(CURRENT_DATE(), MAX(DATE(o.ordered_at)), DAY)

  -- Value tier based on total spend
  -- Thresholds are set via parameters above — adjust to your ACV distribution
  CASE
    WHEN SUM(o.total_amount) >= @min_total_spend * 5  THEN 'Platinum'
    WHEN SUM(o.total_amount) >= @min_total_spend * 2  THEN 'Gold'
    ELSE                                                    'Silver'
  END AS value_tier

FROM contacts c
INNER JOIN orders o
        ON o.contact_id = c.contact_id
       AND o.status = 'completed'
GROUP BY
  c.contact_id,
  c.email,
  c.first_name,
  c.last_name,
  c.lifecycle_stage,
  c.lead_source,
  c.country
HAVING
  COUNT(o.order_id)      >= @min_orders
  AND SUM(o.total_amount) >= @min_total_spend
ORDER BY
  total_spent  DESC,
  total_orders DESC
LIMIT @top_n;
-- BigQuery: LIMIT 100  (variables not supported inline — hardcode the value)

/*
  Sample Output:

  contact_id | email               | total_orders | total_spent | avg_order_value | value_tier
  -----------|---------------------|--------------|-------------|-----------------|------------
  c_091      | ana@example.com     |           14 |    3,480.00 |          248.57 | Platinum
  c_204      | rui@example.com     |            9 |    2,105.50 |          233.94 | Platinum
  c_017      | sara@example.com    |            6 |      892.00 |          148.67 | Gold
  c_338      | lucas@example.com   |            3 |      510.00 |          170.00 | Gold
  c_512      | marta@example.com   |            2 |      215.00 |          107.50 | Silver

  Logic Notes:
    - INNER JOIN (not LEFT JOIN) intentionally excludes contacts with zero purchases.
      This query is strictly about transactional customers, not all contacts.
    - The value_tier thresholds are multiples of @min_total_spend so a single
      parameter change rescales all three tiers proportionally.
    - HAVING filters after aggregation, so the @min_orders and @min_total_spend
      thresholds apply to the full purchase history, not individual orders.

  Adapting to Other Platforms:
    HubSpot:    Map orders to the Deals object (dealstage = 'closedwon').
                Use amount for total_amount and closedate for ordered_at.
    Salesforce: Opportunity (StageName = 'Closed Won', Amount, CloseDate).
                Contact is linked via Opportunity.ContactId.
    RD Station: Map orders to Deals (status = 'won'). The deals.amount field
                maps to total_amount; deals.closed_at maps to ordered_at.
    BigQuery:   Remove SET statements and inline values directly.
                DATEDIFF → DATE_DIFF(CURRENT_DATE(), MAX(DATE(o.ordered_at)), DAY)
*/
