/*
  Query Name: Inactive Contacts
  Category:   Engagement

  Purpose:
    Identify contacts with no recorded behavioral event in a configurable
    lookback window. Used to build suppression lists, trigger re-permission
    campaigns, and remove cold contacts from active sending to protect
    deliverability.

  Use Case:
    Run monthly as part of list hygiene. Contacts inactive for 180+ days
    should be moved to a re-permission flow before any further sends.
    Contacts inactive for 365+ days are candidates for permanent suppression
    or CRM archiving. Suppressing cold contacts from regular campaigns
    improves open rates, reduces spam complaints, and lowers ESP costs.

  Tables Used:
    contacts  — identity and lifecycle fields
    events    — any behavioral event type as a proxy for activity
*/

-- ── Parameters ───────────────────────────────────────────────────────────────
SET @medium_inactive_days = 90;   -- no activity in 90–179 days = moderately inactive
SET @high_inactive_days   = 180;  -- no activity in 180–364 days = highly inactive
SET @dormant_days         = 365;  -- no activity in 365+ days = dormant
SET @reference_date       = CURDATE();

WITH last_activity AS (

  -- Find the most recent event date per contact across all event types.
  -- A contact is considered active if any event occurred within the window,
  -- regardless of event type.

  SELECT
    contact_id,
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
  c.created_at                                              AS contact_created_at,
  la.last_event_date,
  DATEDIFF(@reference_date, la.last_event_date)             AS days_inactive,
  -- BigQuery: DATE_DIFF(CURRENT_DATE(), DATE(la.last_event_date), DAY)

  CASE
    WHEN la.last_event_date IS NULL                               THEN 'Never Active'
    WHEN DATEDIFF(@reference_date, la.last_event_date)
         >= @dormant_days                                         THEN 'Dormant'
    WHEN DATEDIFF(@reference_date, la.last_event_date)
         >= @high_inactive_days                                   THEN 'Highly Inactive'
    WHEN DATEDIFF(@reference_date, la.last_event_date)
         >= @medium_inactive_days                                 THEN 'Moderately Inactive'
  END AS inactivity_tier,

  CASE
    WHEN la.last_event_date IS NULL                               THEN 'Add to re-permission flow immediately'
    WHEN DATEDIFF(@reference_date, la.last_event_date)
         >= @dormant_days                                         THEN 'Suppress or archive'
    WHEN DATEDIFF(@reference_date, la.last_event_date)
         >= @high_inactive_days                                   THEN 'Re-permission campaign'
    WHEN DATEDIFF(@reference_date, la.last_event_date)
         >= @medium_inactive_days                                 THEN 'Reduce send frequency'
  END AS recommended_action

FROM contacts c
LEFT JOIN last_activity la ON la.contact_id = c.contact_id
WHERE
  la.last_event_date IS NULL
  OR DATEDIFF(@reference_date, la.last_event_date) >= @medium_inactive_days
ORDER BY days_inactive DESC NULLS LAST;
-- BigQuery: ORDER BY days_inactive DESC NULLS LAST  (supported natively)

/*
  Sample Output:

  contact_id | email                | days_inactive | inactivity_tier     | recommended_action
  -----------|----------------------|---------------|---------------------|-----------------------------
  c_512      | marta@example.com    |          NULL | Never Active        | Add to re-permission flow immediately
  c_009      | jose@example.com     |           420 | Dormant             | Suppress or archive
  c_118      | ines@example.com     |           210 | Highly Inactive     | Re-permission campaign
  c_307      | tiago@example.com    |            95 | Moderately Inactive | Reduce send frequency

  Logic Notes:
    - Never Active contacts have no events at all — they joined the list
      but never interacted. They are included via LEFT JOIN with NULL last_event_date.
    - NULLS LAST in ORDER BY ensures Never Active contacts appear at the top
      of the result rather than being sorted unpredictably.
    - This query returns only inactive contacts. Remove the WHERE clause
      to get the full contact list with inactivity status for all contacts.
    - Consider combining this output with the Email Activity Summary to confirm
      that inactive contacts also have low email engagement metrics before suppressing.

  Adapting to Other Platforms:
    HubSpot:    Use the Last Activity Date contact property as a proxy for
                last_event_date. Filter contacts where this property is
                more than N days ago using a HubSpot list filter.
    Salesforce: Last activity is available on the Contact object via
                LastActivityDate (populated from related Task/Event records).
    RD Station: Use the last_conversion_at or last_marked_opportunity_date
                fields as proxies for last activity.
    BigQuery:   NULLS LAST is supported. Replace DATEDIFF as noted above.
                Use IFNULL(DATE_DIFF(...), 9999) as an alternative sort approach.
*/
