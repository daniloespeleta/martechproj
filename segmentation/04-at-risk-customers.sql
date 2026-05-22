/*
  Query Name: At-Risk Customers
  Category:   Segmentation

  Purpose:
    Identify previously active customers who have gone silent — defined as
    contacts with a purchase history but no completed order in a configurable
    recency window. These contacts are candidates for win-back campaigns
    before they become permanently lost.

  Use Case:
    Schedule this query to run weekly and feed a re-engagement automation.
    The risk_level column lets you apply different messaging intensity:
    High-risk contacts warrant a direct offer; Medium-risk contacts can
    receive a lighter-touch check-in. Feed the output into a suppression
    list for acquisition campaigns — at-risk customers should not receive
    new-customer messaging.

  Tables Used:
    contacts  — identity and lifecycle fields
    orders    — purchase recency signals
*/

-- ── Parameters ───────────────────────────────────────────────────────────────
SET @reference_date    = CURDATE();
SET @high_risk_days    = 180;   -- silent for 180+ days = high risk of permanent churn
SET @medium_risk_days  = 90;    -- silent for 90–179 days = medium risk
SET @min_past_orders   = 1;     -- must have had at least this many past orders

WITH customer_recency AS (

  -- Build one row per contact with their full purchase summary.
  -- Only contacts with at least one completed order are included;
  -- never-purchased contacts are outside the scope of win-back.

  SELECT
    c.contact_id,
    c.email,
    c.first_name,
    c.last_name,
    c.lifecycle_stage,
    c.lead_source,
    c.country,
    COUNT(o.order_id)                               AS total_orders,
    ROUND(SUM(o.total_amount), 2)                   AS total_spent,
    MAX(DATE(o.ordered_at))                         AS last_order_date,
    DATEDIFF(@reference_date, MAX(o.ordered_at))    AS days_since_last_order
    -- BigQuery: DATE_DIFF(CURRENT_DATE(), MAX(DATE(o.ordered_at)), DAY)
  FROM contacts c
  INNER JOIN orders o
          ON o.contact_id = c.contact_id
         AND o.status = 'completed'
  GROUP BY
    c.contact_id, c.email, c.first_name, c.last_name,
    c.lifecycle_stage, c.lead_source, c.country
  HAVING COUNT(o.order_id) >= @min_past_orders

)

SELECT
  contact_id,
  email,
  first_name,
  last_name,
  lifecycle_stage,
  lead_source,
  country,
  total_orders,
  total_spent,
  last_order_date,
  days_since_last_order,

  CASE
    WHEN days_since_last_order >= @high_risk_days   THEN 'High'
    WHEN days_since_last_order >= @medium_risk_days THEN 'Medium'
  END AS risk_level,

  -- Suggested action maps risk level to a CRM automation trigger.
  -- Use this column to populate a custom field in your CRM for workflow routing.
  CASE
    WHEN days_since_last_order >= @high_risk_days   THEN 'Win-back offer — aggressive discount'
    WHEN days_since_last_order >= @medium_risk_days THEN 'Re-engagement sequence — soft check-in'
  END AS suggested_action

FROM customer_recency
WHERE days_since_last_order >= @medium_risk_days
ORDER BY
  days_since_last_order DESC,
  total_spent           DESC;

/*
  Sample Output:

  contact_id | email                | total_orders | total_spent | days_since_last_order | risk_level | suggested_action
  -----------|----------------------|--------------|-------------|----------------------|------------|----------------------------------
  c_042      | paulo@example.com    |            6 |      940.00 |                   312 | High       | Win-back offer — aggressive discount
  c_118      | ines@example.com     |            3 |      415.00 |                   225 | High       | Win-back offer — aggressive discount
  c_307      | tiago@example.com    |            2 |      180.00 |                   147 | Medium     | Re-engagement sequence — soft check-in
  c_521      | beatriz@example.com  |            1 |       95.00 |                    98 | Medium     | Re-engagement sequence — soft check-in

  Logic Notes:
    - The WHERE clause ensures only at-risk contacts are returned. Remove it
      to see all customers with their recency status for a full health report.
    - Contacts in the 'High' risk tier who also have high total_spent are
      the highest-priority win-back targets — consider sorting by a combined
      score of days_since_last_order × total_spent for prioritization.
    - This query does not include contacts currently in an active win-back
      campaign. Add a NOT EXISTS subquery against campaign_contacts if you
      want to suppress already-enrolled contacts.

  Adapting to Other Platforms:
    HubSpot:    last_order_date → Last Purchase Date (custom property).
                Use a HubSpot workflow to set a contact property from the
                query output and trigger the re-engagement enrollment.
    Salesforce: Last purchase date is derived from the most recent
                Closed Won Opportunity CloseDate per Contact.
    RD Station: Map last_order_date to a custom date field on the contact.
                Use the field in a segmentation rule to trigger the flow.
    BigQuery:   Replace SET variables with a WITH params AS (SELECT ...) CTE
                and reference its columns throughout the query.
*/
