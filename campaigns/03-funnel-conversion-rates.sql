/*
  Query Name: Funnel Conversion Rates
  Category:   Campaigns

  Purpose:
    Calculate step-by-step conversion rates through the marketing and sales
    funnel for contacts acquired through campaigns — from initial contact
    through to closed deal. Identifies which funnel stage has the highest
    drop-off rate for prioritization of optimization efforts.

  Use Case:
    Run quarterly to assess funnel health by campaign cohort. A low lead-to-MQL
    rate indicates qualification criteria may be too loose or lead quality is
    declining. A high MQL-to-SQL rate with low SQL-to-opportunity conversion
    points to a sales follow-up problem, not a marketing problem. Use the
    campaign_name filter to compare funnel performance across specific campaigns.

  Tables Used:
    contacts          — lifecycle_stage tracks funnel position
    campaign_contacts — links contacts to the campaign that acquired them
    campaigns         — campaign metadata for filtering and grouping
    orders            — closed revenue as the bottom-of-funnel conversion
*/

WITH campaign_funnel AS (

  -- Build one row per contact with their current funnel stage and
  -- whether they have a completed order (bottom-of-funnel conversion).

  SELECT
    cc.campaign_id,
    c.contact_id,
    c.lifecycle_stage,
    CASE WHEN o.order_id IS NOT NULL THEN 1 ELSE 0 END AS has_purchase
  FROM campaign_contacts cc
  INNER JOIN contacts c ON c.contact_id = cc.contact_id
  LEFT JOIN (
    SELECT DISTINCT contact_id, order_id
    FROM orders
    WHERE status = 'completed'
  ) o ON o.contact_id = c.contact_id

),

funnel_counts AS (

  SELECT
    campaign_id,
    COUNT(DISTINCT contact_id)                                        AS total_contacts,

    -- Each stage count includes all contacts at or past that stage.
    -- A customer is also counted as a lead, MQL, SQL, and opportunity.
    COUNT(DISTINCT CASE
      WHEN lifecycle_stage IN ('mql','sql','opportunity','customer') OR has_purchase = 1
      THEN contact_id END)                                            AS reached_mql,

    COUNT(DISTINCT CASE
      WHEN lifecycle_stage IN ('sql','opportunity','customer') OR has_purchase = 1
      THEN contact_id END)                                            AS reached_sql,

    COUNT(DISTINCT CASE
      WHEN lifecycle_stage IN ('opportunity','customer') OR has_purchase = 1
      THEN contact_id END)                                            AS reached_opportunity,

    COUNT(DISTINCT CASE
      WHEN has_purchase = 1
      THEN contact_id END)                                            AS converted_to_customer

  FROM campaign_funnel
  GROUP BY campaign_id

)

SELECT
  c.campaign_id,
  c.campaign_name,
  c.channel,
  c.start_date,

  fc.total_contacts                                                   AS leads,
  fc.reached_mql,
  fc.reached_sql,
  fc.reached_opportunity,
  fc.converted_to_customer,

  -- Stage-to-stage conversion rates
  ROUND(fc.reached_mql         * 100.0 / NULLIF(fc.total_contacts,        0), 1) AS lead_to_mql_pct,
  ROUND(fc.reached_sql         * 100.0 / NULLIF(fc.reached_mql,           0), 1) AS mql_to_sql_pct,
  ROUND(fc.reached_opportunity * 100.0 / NULLIF(fc.reached_sql,           0), 1) AS sql_to_opp_pct,
  ROUND(fc.converted_to_customer*100.0 / NULLIF(fc.reached_opportunity,   0), 1) AS opp_to_customer_pct,

  -- End-to-end conversion: leads who became customers
  ROUND(fc.converted_to_customer*100.0 / NULLIF(fc.total_contacts,        0), 2) AS overall_conversion_pct

FROM funnel_counts fc
INNER JOIN campaigns c ON c.campaign_id = fc.campaign_id
ORDER BY overall_conversion_pct DESC;

/*
  Sample Output:

  campaign_name     | leads  | reached_mql | reached_sql | converted_to_customer | lead_to_mql_pct | overall_conversion_pct
  ------------------|--------|-------------|-------------|----------------------|-----------------|------------------------
  Referral Q3 2024  |    420 |         168 |          84 |                    67 |            40.0 |                   16.0
  Welcome Series    |  8,100 |       1,620 |         648 |                   227 |            20.0 |                    2.8
  Paid Search Q4    |  5,200 |         936 |         374 |                   104 |            18.0 |                    2.0
  Social Oct 2024   |  2,100 |         252 |          63 |                    11 |            12.0 |                    0.5

  Logic Notes:
    - Stage counts are cumulative: a contact counted at sql is also counted
      at mql and lead. This ensures conversion rates always divide smaller
      numbers into larger ones and results stay between 0–100%.
    - has_purchase = 1 is used as the bottom-of-funnel signal instead of
      lifecycle_stage = 'customer' to capture revenue events regardless of
      whether the CRM lifecycle stage was updated correctly.
    - Contacts who skipped stages (e.g. went directly from lead to customer)
      are counted at all intermediate stages to avoid understating conversion.

  Adapting to Other Platforms:
    HubSpot:    lifecycle_stage maps to the lifecyclestage contact property.
                Use Deal Stage as an alternative bottom-of-funnel signal.
    Salesforce: Use Lead.Status for top-of-funnel stages and Opportunity
                StageName for bottom-of-funnel. Join via ConvertedContactId.
    RD Station: lifecycle_stage maps to the contact's funnel stage.
                Bottom-of-funnel is a won deal in the deals object.
    BigQuery:   No syntax changes required. NULLIF is supported identically.
*/
