/*
  Query Name: Stale Lifecycle Stages
  Category:   Hygiene

  Purpose:
    Identify contacts whose lifecycle_stage has not been updated in a
    configurable number of days. Stale stages cause incorrect routing
    in automation workflows, inaccurate funnel reporting, and mis-targeted
    campaigns — a lead who has been a customer for six months but still
    shows as 'lead' in the CRM is a data quality failure.

  Use Case:
    Run monthly as part of CRM maintenance. The output feeds a review
    queue for the operations team: contacts with stale stages should be
    re-evaluated against their purchase history and recent behavior to
    determine the correct current stage. Combine with the Engagement Score
    query — a contact with a stale MQL stage and a high engagement score
    is almost certainly already in SQL territory.

  Tables Used:
    contacts  — lifecycle_stage and updated_at fields
    orders    — purchase history to cross-check stage accuracy
*/

-- ── Parameters ───────────────────────────────────────────────────────────────
SET @stale_threshold_days = 90;   -- contacts not updated in this many days
SET @reference_date       = CURDATE();

WITH contact_purchase_history AS (

  SELECT
    contact_id,
    COUNT(order_id)              AS total_orders,
    MAX(ordered_at)              AS last_purchase_date
  FROM orders
  WHERE status = 'completed'
  GROUP BY contact_id

)

SELECT
  c.contact_id,
  c.email,
  c.first_name,
  c.last_name,
  c.lifecycle_stage,
  c.updated_at,
  DATEDIFF(@reference_date, c.updated_at)         AS days_since_update,
  -- BigQuery: DATE_DIFF(CURRENT_DATE(), DATE(c.updated_at), DAY)

  -- Purchase context helps determine the correct stage
  COALESCE(cph.total_orders, 0)                   AS total_orders,
  cph.last_purchase_date,

  -- Stage accuracy flag: highlights likely misclassifications
  CASE
    WHEN c.lifecycle_stage IN ('lead', 'mql', 'sql')
     AND COALESCE(cph.total_orders, 0) > 0        THEN 'Likely customer — stage not updated'
    WHEN c.lifecycle_stage = 'lead'
     AND DATEDIFF(@reference_date, c.updated_at) >= @stale_threshold_days * 3
                                                   THEN 'Long-stale lead — archive or re-engage'
    ELSE                                               'Stage may need review'
  END AS stage_flag,

  CASE
    WHEN c.lifecycle_stage IN ('lead', 'mql', 'sql')
     AND COALESCE(cph.total_orders, 0) > 0        THEN 'Update to customer'
    WHEN DATEDIFF(@reference_date, c.updated_at) >= @stale_threshold_days * 3
                                                   THEN 'Archive or re-engagement campaign'
    ELSE                                               'Manual review recommended'
  END AS recommended_action

FROM contacts c
LEFT JOIN contact_purchase_history cph ON cph.contact_id = c.contact_id
WHERE
  c.updated_at IS NOT NULL
  AND DATEDIFF(@reference_date, c.updated_at) >= @stale_threshold_days
ORDER BY days_since_update DESC;

/*
  Sample Output:

  contact_id | email               | lifecycle_stage | days_since_update | total_orders | stage_flag
  -----------|---------------------|-----------------|-------------------|--------------|-----------------------------
  c_204      | rui@example.com     | lead            |               412 |            3 | Likely customer — stage not updated
  c_512      | marta@example.com   | mql             |               280 |            0 | Long-stale lead — archive or re-engage
  c_338      | lucas@example.com   | sql             |                95 |            1 | Likely customer — stage not updated

  Logic Notes:
    - updated_at reflects the last CRM record update, which may not correspond
      to a meaningful lifecycle stage change. If your CRM updates updated_at
      on any field change, add a dedicated stage_updated_at field for more
      precise tracking.
    - Contacts with total_orders > 0 but a pre-customer stage are the highest
      priority — they represent customers being treated as leads in all
      automation and reporting.
    - The 3x threshold for 'Long-stale lead' is a multiple of @stale_threshold_days
      so a single parameter change adjusts both thresholds proportionally.

  Adapting to Other Platforms:
    HubSpot:    Use the lifecyclestage history property to see when the stage
                was last changed (not just when the contact was updated).
    Salesforce: Query Lead.LastModifiedDate and filter by status. Use a Process
                Builder or Flow to auto-update status based on Opportunity stage.
    RD Station: The contact's funnel stage is updated via API or manually.
                Check the stage_updated_at timestamp if available.
    BigQuery:   DATE_DIFF(CURRENT_DATE(), DATE(c.updated_at), DAY) replaces DATEDIFF.
*/
