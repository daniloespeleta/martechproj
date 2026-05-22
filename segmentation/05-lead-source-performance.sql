/*
  Query Name: Lead Source Performance
  Category:   Segmentation

  Purpose:
    Compare acquisition channels by volume, conversion rate, revenue
    contribution, and average order value. Surfaces which lead sources
    deliver the highest-quality contacts — not just the highest volume.

  Use Case:
    Run before budget planning cycles to inform channel investment decisions.
    A lead source with low volume but high conversion rate and AOV often
    warrants more spend. Pair with campaign ROI queries (campaigns folder)
    for a full picture of channel efficiency from first touch to revenue.

  Tables Used:
    contacts  — lead_source field and lifecycle_stage
    orders    — revenue and frequency per contact
*/

-- ── Parameters ───────────────────────────────────────────────────────────────
SET @min_leads = 10;  -- exclude sources with fewer leads to avoid noisy small samples

WITH source_contacts AS (

  -- One row per contact with their purchase summary.
  -- LEFT JOIN keeps contacts who never purchased so conversion rate
  -- denominators are accurate — a contact with no order counts as
  -- a non-converting lead for the source that acquired them.

  SELECT
    c.contact_id,
    COALESCE(c.lead_source, 'unknown')   AS lead_source,
    c.lifecycle_stage,
    COUNT(o.order_id)                    AS total_orders,
    COALESCE(SUM(o.total_amount), 0)     AS total_spent
  FROM contacts c
  LEFT JOIN orders o
         ON o.contact_id = c.contact_id
        AND o.status = 'completed'
  GROUP BY
    c.contact_id,
    COALESCE(c.lead_source, 'unknown'),
    c.lifecycle_stage

)

SELECT
  lead_source,
  COUNT(contact_id)                                                 AS total_leads,
  SUM(CASE WHEN total_orders > 0 THEN 1 ELSE 0 END)                AS converted_leads,
  ROUND(
    SUM(CASE WHEN total_orders > 0 THEN 1 ELSE 0 END) * 100.0
    / NULLIF(COUNT(contact_id), 0), 1)                             AS conversion_rate_pct,
  ROUND(SUM(total_spent), 2)                                        AS total_revenue,
  ROUND(AVG(NULLIF(total_spent, 0)), 2)                             AS avg_revenue_per_converted_lead,
  ROUND(SUM(total_spent) / NULLIF(COUNT(contact_id), 0), 2)        AS revenue_per_lead,
  SUM(CASE WHEN lifecycle_stage = 'customer' THEN 1 ELSE 0 END)    AS current_customers
FROM source_contacts
GROUP BY lead_source
HAVING COUNT(contact_id) >= @min_leads
ORDER BY total_revenue DESC;

/*
  Sample Output:

  lead_source    | total_leads | converted_leads | conversion_rate_pct | total_revenue | revenue_per_lead
  ---------------|-------------|-----------------|---------------------|---------------|------------------
  organic        |       3,240 |             648 |                20.0 |    142,560.00 |            44.00
  paid_search    |       1,890 |             472 |                25.0 |    118,000.00 |            62.43
  referral       |         420 |             168 |                40.0 |     67,200.00 |           160.00
  social         |       2,100 |             273 |                13.0 |     41,000.00 |            19.52
  email          |         630 |             189 |                30.0 |     37,800.00 |            60.00
  unknown        |         840 |              84 |                10.0 |     12,600.00 |            15.00

  Logic Notes:
    - revenue_per_lead is the most actionable metric for budget allocation:
      it accounts for both conversion rate and average order value in one number.
    - avg_revenue_per_converted_lead uses NULLIF(total_spent, 0) to exclude
      non-converting leads from the average — it reflects AOV among buyers only.
    - The @min_leads threshold suppresses sources with very few contacts whose
      rates would be statistically unstable. Lower it to 1 to see all sources.

  Adapting to Other Platforms:
    HubSpot:    lead_source maps to the Original Source contact property.
                Standard values: ORGANIC_SEARCH, PAID_SEARCH, SOCIAL_MEDIA,
                EMAIL_MARKETING, REFERRALS, DIRECT_TRAFFIC, OTHER_CAMPAIGNS.
    Salesforce: Use Lead.LeadSource (pre-conversion) and Contact.LeadSource
                (post-conversion). Combine both for a full-funnel view.
    RD Station: lead_source maps to the contact's origin field.
    BigQuery:   NULLIF and COALESCE behave identically. No syntax changes needed.
*/
