/*
  Query Name: Contact Update Audit
  Category:   Hygiene

  Purpose:
    Identify contacts that have never been updated since their creation,
    or that have not been updated within a configurable lookback window.
    Stale contact records accumulate incorrect data, miss enrichment updates,
    and indicate gaps in CRM maintenance processes.

  Use Case:
    Use in quarterly CRM audits to identify records that may need enrichment
    or removal. Contacts created more than a year ago with zero updates are
    strong candidates for a data enrichment pass or re-permission campaign
    before the next major send. Export to a spreadsheet and route to the
    team responsible for CRM data quality.

  Tables Used:
    contacts  — created_at and updated_at fields for audit comparison
    events    — activity signals to cross-reference record staleness
*/

-- ── Parameters ───────────────────────────────────────────────────────────────
SET @never_updated_threshold_days = 30;   -- contacts updated within N days of creation
                                          -- are considered 'never meaningfully updated'
SET @stale_update_days            = 180;  -- contacts not updated in N days = stale
SET @reference_date               = CURDATE();

WITH contact_event_summary AS (

  SELECT
    contact_id,
    COUNT(event_id)  AS total_events,
    MAX(occurred_at) AS last_event_date
  FROM events
  GROUP BY contact_id

)

SELECT
  c.contact_id,
  c.email,
  c.first_name,
  c.last_name,
  c.lifecycle_stage,
  c.lead_source,
  c.created_at,
  c.updated_at,

  DATEDIFF(@reference_date, c.created_at)     AS age_days,
  -- BigQuery: DATE_DIFF(CURRENT_DATE(), DATE(c.created_at), DAY)
  DATEDIFF(@reference_date, c.updated_at)     AS days_since_update,
  -- BigQuery: DATE_DIFF(CURRENT_DATE(), DATE(c.updated_at), DAY)
  DATEDIFF(c.updated_at, c.created_at)        AS days_to_first_update,

  COALESCE(ces.total_events, 0)               AS total_events,
  ces.last_event_date,

  CASE
    WHEN DATEDIFF(c.updated_at, c.created_at) <= @never_updated_threshold_days
         AND DATEDIFF(@reference_date, c.created_at) > @never_updated_threshold_days
         THEN 'Never meaningfully updated'
    WHEN DATEDIFF(@reference_date, c.updated_at) >= @stale_update_days
         THEN 'Stale record'
    ELSE      'Recently updated'
  END AS update_status,

  CASE
    WHEN DATEDIFF(c.updated_at, c.created_at) <= @never_updated_threshold_days
         AND COALESCE(ces.total_events, 0) = 0
         THEN 'No activity — archive candidate'
    WHEN DATEDIFF(c.updated_at, c.created_at) <= @never_updated_threshold_days
         AND COALESCE(ces.total_events, 0) > 0
         THEN 'Has activity but record never enriched — data enrichment needed'
    WHEN DATEDIFF(@reference_date, c.updated_at) >= @stale_update_days
         THEN 'Schedule enrichment refresh'
    ELSE      'No action needed'
  END AS recommended_action

FROM contacts c
LEFT JOIN contact_event_summary ces ON ces.contact_id = c.contact_id
WHERE
  DATEDIFF(c.updated_at, c.created_at) <= @never_updated_threshold_days
  OR DATEDIFF(@reference_date, c.updated_at) >= @stale_update_days
ORDER BY age_days DESC;

/*
  Sample Output:

  contact_id | email               | age_days | days_since_update | total_events | update_status                 | recommended_action
  -----------|---------------------|----------|-------------------|--------------|-------------------------------|---------------------------------------------
  c_009      | jose@example.com    |      580 |               580 |            0 | Never meaningfully updated    | No activity — archive candidate
  c_204      | rui@example.com     |      420 |               195 |           12 | Stale record                  | Schedule enrichment refresh
  c_338      | lucas@example.com   |      310 |                 2 |            4 | Never meaningfully updated    | Has activity but record never enriched — data enrichment needed

  Logic Notes:
    - days_to_first_update <= @never_updated_threshold_days catches contacts
      where the CRM auto-populated the updated_at field at creation or within
      the first few days, which does not represent a real data update.
    - A contact with zero events AND no meaningful updates is the strongest
      archive candidate — there is no signal of engagement justifying
      continued storage and sending costs.
    - updated_at accuracy depends on your CRM updating this field on every
      meaningful record change. If your CRM does not maintain updated_at
      reliably, use last_event_date from the events table as a proxy.

  Adapting to Other Platforms:
    HubSpot:    Use the Last Modified Date contact property. HubSpot maintains
                this automatically on any property change.
    Salesforce: Contact.LastModifiedDate is maintained automatically.
                Use Contact.LastActivityDate for event-based recency.
    RD Station: updated_at is maintained automatically on the contact record.
    BigQuery:   DATE_DIFF syntax as noted above. No other changes required.
*/
