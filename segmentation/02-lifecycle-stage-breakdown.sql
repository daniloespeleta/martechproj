/*
  Query Name: Lifecycle Stage Breakdown
  Category:   Segmentation

  Purpose:
    Show the distribution of contacts across each funnel stage along with
    the conversion rate between consecutive stages. Provides a snapshot of
    pipeline health and identifies where the funnel is leaking.

  Use Case:
    Use this query in weekly ops reviews to monitor funnel balance.
    A shrinking MQL pool with a stable SQL count signals that lead quality
    is improving. A growing lead count with flat MQL conversion points to
    a qualification bottleneck. Export results to a BI dashboard or paste
    directly into a campaign planning doc.

  Tables Used:
    contacts  — lifecycle_stage field drives all segmentation here
*/

WITH stage_counts AS (

  -- Count contacts per lifecycle stage and compute the percentage of
  -- total contacts each stage represents.
  -- NULL lifecycle_stage values are grouped as 'unknown' to avoid
  -- silently dropping unclassified contacts from the report.

  SELECT
    COALESCE(lifecycle_stage, 'unknown')  AS stage,
    COUNT(contact_id)                     AS total_contacts,
    MIN(created_at)                       AS first_contact_date,
    MAX(created_at)                       AS latest_contact_date
  FROM contacts
  GROUP BY COALESCE(lifecycle_stage, 'unknown')

),

stage_ordered AS (

  -- Assign a display order to each stage so results sort top-to-bottom
  -- through the funnel rather than alphabetically.
  -- Adjust the order values if your funnel has different stage names.

  SELECT
    s.*,
    CASE s.stage
      WHEN 'lead'        THEN 1
      WHEN 'mql'         THEN 2
      WHEN 'sql'         THEN 3
      WHEN 'opportunity' THEN 4
      WHEN 'customer'    THEN 5
      WHEN 'churned'     THEN 6
      ELSE 99
    END AS stage_order,
    SUM(total_contacts) OVER ()           AS grand_total
  FROM stage_counts s

)

SELECT
  stage,
  total_contacts,
  ROUND(total_contacts * 100.0 / grand_total, 1)   AS pct_of_total,

  -- Stage-to-stage conversion rate using LAG to compare each stage
  -- to the one immediately above it in the funnel order.
  -- NULL for the first stage since there is no prior stage to compare.
  ROUND(
    total_contacts * 100.0 /
    NULLIF(LAG(total_contacts) OVER (ORDER BY stage_order), 0),
  1)                                               AS conversion_from_prev_stage_pct,
  -- BigQuery: same syntax — LAG is supported in both engines

  first_contact_date,
  latest_contact_date
FROM stage_ordered
ORDER BY stage_order;

/*
  Sample Output:

  stage       | total_contacts | pct_of_total | conversion_from_prev_stage_pct | first_contact_date
  ------------|----------------|--------------|-------------------------------|--------------------
  lead        |          8,420 |        62.3% |                          NULL | 2023-01-03
  mql         |          2,105 |        15.6% |                         25.0% | 2023-01-15
  sql         |            842 |         6.2% |                         40.0% | 2023-02-01
  opportunity |            421 |         3.1% |                         50.0% | 2023-02-10
  customer    |          1,684 |        12.5% |                           N/A | 2023-01-20
  churned     |             56 |         0.4% |                           N/A | 2023-06-01

  Logic Notes:
    - conversion_from_prev_stage_pct is only meaningful for sequential funnel stages
      (lead → mql → sql → opportunity). Customer and churned sit outside the linear
      progression and their conversion values should be interpreted separately.
    - NULLIF prevents division-by-zero errors when a stage has zero contacts.
    - Contacts with NULL lifecycle_stage appear as 'unknown' and are included in
      grand_total so percentages always sum to 100%.

  Adapting to Other Platforms:
    HubSpot:    lifecycle_stage maps to the lifecyclestage contact property.
                Standard values: subscriber, lead, marketingqualifiedlead,
                salesqualifiedlead, opportunity, customer, evangelist, other.
    Salesforce: Use the Lead.Status field for pre-opportunity stages and
                Opportunity.StageName for post-qualification stages.
    RD Station: lifecycle_stage maps to the contact's funnel stage field.
                Stage names vary by account configuration.
    BigQuery:   LAG() and OVER() are supported with identical syntax.
                Replace ROUND(..., 1) with ROUND(..., 1) — no change needed.
*/
