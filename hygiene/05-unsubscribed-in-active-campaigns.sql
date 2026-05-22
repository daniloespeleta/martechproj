/*
  Query Name: Unsubscribed in Active Campaigns
  Category:   Hygiene

  Purpose:
    Identify contacts who have unsubscribed but are still assigned to
    active campaigns in the campaign_contacts table. Sending to unsubscribed
    contacts violates CAN-SPAM, GDPR, and LGPD regulations and damages
    sender reputation. This query surfaces compliance risks before they
    become legal or deliverability issues.

  Use Case:
    Run before every campaign send as a pre-flight compliance check.
    Any contacts returned by this query must be removed from the campaign
    audience immediately. If your ESP enforces suppression lists automatically,
    use this query to verify that the suppression list is being correctly
    applied — contacts appearing here indicate a synchronization gap between
    your CRM and ESP.

  Tables Used:
    contacts          — lifecycle or custom unsubscribe status field
    events            — unsubscribe events as an alternative signal
    campaign_contacts — active campaign assignments
    campaigns         — campaign status to filter active campaigns
*/

WITH unsubscribed_contacts AS (

  -- Identify unsubscribed contacts via the events table.
  -- Using events rather than a flag field captures unsubscribes from
  -- ESP webhooks that may not have updated the contact record yet.

  SELECT DISTINCT contact_id
  FROM events
  WHERE event_type = 'unsubscribe'

),

active_campaign_contacts AS (

  -- Contacts currently assigned to campaigns that are in 'active' status.

  SELECT
    cc.contact_id,
    cc.campaign_id,
    cc.assigned_at,
    c_meta.campaign_name,
    c_meta.channel,
    c_meta.start_date,
    c_meta.end_date
  FROM campaign_contacts cc
  INNER JOIN campaigns c_meta
          ON c_meta.campaign_id = cc.campaign_id
         AND c_meta.status      = 'active'

)

SELECT
  c.contact_id,
  c.email,
  c.first_name,
  c.last_name,
  c.lifecycle_stage,
  acc.campaign_id,
  acc.campaign_name,
  acc.channel,
  acc.assigned_at,
  acc.start_date   AS campaign_start_date,
  acc.end_date     AS campaign_end_date,

  -- When did this contact unsubscribe?
  MAX(e.occurred_at)  AS unsubscribe_date,

  -- Is the unsubscribe more recent than the campaign assignment?
  -- If yes, the contact unsubscribed after being enrolled — critical to remove.
  CASE
    WHEN MAX(e.occurred_at) > acc.assigned_at THEN 'Unsubscribed after enrollment — remove immediately'
    ELSE                                            'Unsubscribed before enrollment — enrollment error'
  END AS risk_note

FROM unsubscribed_contacts uc
INNER JOIN contacts c              ON c.contact_id   = uc.contact_id
INNER JOIN active_campaign_contacts acc ON acc.contact_id = uc.contact_id
INNER JOIN events e                ON e.contact_id   = uc.contact_id
                                   AND e.event_type  = 'unsubscribe'
GROUP BY
  c.contact_id, c.email, c.first_name, c.last_name, c.lifecycle_stage,
  acc.campaign_id, acc.campaign_name, acc.channel,
  acc.assigned_at, acc.start_date, acc.end_date
ORDER BY unsubscribe_date DESC;

/*
  Sample Output:

  contact_id | email              | campaign_name      | unsubscribe_date    | risk_note
  -----------|--------------------|--------------------|--------------------|--------------------------------------------
  c_512      | marta@example.com  | Black Friday 2024  | 2024-11-01 09:12:00 | Unsubscribed after enrollment — remove immediately
  c_338      | lucas@example.com  | Welcome Series     | 2024-09-15 14:00:00 | Unsubscribed before enrollment — enrollment error

  Logic Notes:
    - This query surfaces the compliance risk but does not remove contacts
      from campaigns automatically. Removal must be done in your CRM or ESP.
    - 'Enrollment error' contacts (unsubscribed before being assigned) indicate
      a gap in your audience-building process — the unsubscribe suppression
      list was not applied at the time of campaign audience creation.
    - If your ESP enforces suppression lists server-side, this query will
      still return these contacts because the campaign_contacts table reflects
      CRM assignments, not ESP-level send eligibility. Reconcile both sources.

  Adapting to Other Platforms:
    HubSpot:    Use the Email Subscription Status contact property.
                HubSpot automatically suppresses unsubscribed contacts from
                marketing emails — use this query to verify CRM data consistency.
    Salesforce Marketing Cloud: Use the All Subscribers list and Data Extensions
                to cross-reference active campaign targets against the
                unsubscribed status in the All Subscribers list.
    Klaviyo:    Suppressed profiles are stored in the Suppressions list.
                Use the Suppressions API to check suppression status per profile.
    GDPR note:  For EU contacts, unsubscribe from a single campaign type
                (e.g. promotional) may not apply to transactional emails.
                Ensure your unsubscribe categorization reflects consent granularity.
    BigQuery:   No syntax changes required. DISTINCT and INNER JOIN are identical.
*/
