/*
  Query Name: Geographic Segmentation
  Category:   Segmentation

  Purpose:
    Break down contact volume, revenue, and conversion rates by country
    and state. Identifies regional strengths and underperforming markets
    to inform geo-targeted campaigns and resource allocation.

  Use Case:
    Use before launching regional campaigns to size each market and set
    realistic targets. The output also feeds geo-based suppression lists —
    contacts in states with low conversion rates can be excluded from
    broad campaigns to protect deliverability and budget efficiency.

  Tables Used:
    contacts  — country and state fields
    orders    — purchase volume and revenue
*/

WITH geo_summary AS (

  SELECT
    COALESCE(c.country, 'unknown')                AS country,
    COALESCE(c.state,   'unknown')                AS state,
    c.contact_id,
    COUNT(o.order_id)                             AS orders,
    COALESCE(SUM(o.total_amount), 0)              AS spent
  FROM contacts c
  LEFT JOIN orders o
         ON o.contact_id = c.contact_id
        AND o.status = 'completed'
  GROUP BY
    COALESCE(c.country, 'unknown'),
    COALESCE(c.state,   'unknown'),
    c.contact_id

)

SELECT
  country,
  state,
  COUNT(contact_id)                                               AS total_contacts,
  SUM(CASE WHEN orders > 0 THEN 1 ELSE 0 END)                   AS buyers,
  ROUND(
    SUM(CASE WHEN orders > 0 THEN 1 ELSE 0 END) * 100.0
    / NULLIF(COUNT(contact_id), 0), 1)                           AS buyer_rate_pct,
  ROUND(SUM(spent), 2)                                           AS total_revenue,
  ROUND(SUM(spent) / NULLIF(SUM(orders), 0), 2)                 AS avg_order_value,
  ROUND(SUM(spent) / NULLIF(COUNT(contact_id), 0), 2)           AS revenue_per_contact,

  -- Revenue share within country — useful for identifying dominant states
  ROUND(
    SUM(spent) * 100.0
    / NULLIF(SUM(SUM(spent)) OVER (PARTITION BY country), 0), 1) AS pct_of_country_revenue
  -- BigQuery: same syntax — window functions are supported identically

FROM geo_summary
GROUP BY country, state
ORDER BY total_revenue DESC;

/*
  Sample Output:

  country | state | total_contacts | buyers | buyer_rate_pct | total_revenue | revenue_per_contact | pct_of_country_revenue
  --------|-------|----------------|--------|----------------|---------------|---------------------|------------------------
  BR      | SP    |          4,820 |  1,446 |           30.0 |    312,840.00 |               64.90 |                   42.1
  BR      | RJ    |          2,105 |    568 |           27.0 |    148,500.00 |               70.55 |                   20.0
  BR      | MG    |          1,840 |    423 |           23.0 |     92,000.00 |               50.00 |                   12.4
  US      | CA    |            630 |    189 |           30.0 |     56,700.00 |               90.00 |                   55.2
  US      | NY    |            420 |    105 |           25.0 |     31,500.00 |               75.00 |                   30.7

  Logic Notes:
    - pct_of_country_revenue uses a window function partitioned by country so
      each state's share is calculated within its own country group, not globally.
    - States with a high buyer_rate_pct but low revenue_per_contact indicate
      a market with frequent but small purchases — a candidate for AOV uplift campaigns.
    - States with high revenue_per_contact but low buyer_rate_pct indicate
      a high-value niche that may respond to targeted acquisition investment.

  Adapting to Other Platforms:
    HubSpot:    country → country property; state → state/region property.
    Salesforce: Contact.MailingCountry, Contact.MailingState.
    RD Station: Map to the contact's address fields (state, city).
    BigQuery:   Window functions (SUM OVER PARTITION BY) are fully supported.
                No syntax changes needed.
*/
