/*
  Query Name: Engagement Score
  Category:   Engagement

  Purpose:
    Calculate a composite engagement score for each contact by weighting
    behavioral events across multiple interaction types. Higher scores
    indicate contacts who are actively engaging with marketing content
    and are more likely to convert or respond to outreach.

  Use Case:
    Use this score to prioritize contacts for sales follow-up, suppress
    low-scoring contacts from broad campaigns to protect deliverability,
    and trigger re-engagement flows when a previously high-scoring contact
    drops below a threshold. Refresh weekly and sync the score to a custom
    CRM field for use in segmentation rules and workflow triggers.

  Tables Used:
    contacts  — identity fields
    events    — behavioral interactions (opens, clicks, purchases, etc.)
*/

-- ── Parameters ───────────────────────────────────────────────────────────────
-- Adjust weights to reflect the relative value of each interaction type
-- in your funnel. Purchase events typically warrant the highest weight.
SET @weight_purchase     = 10;
SET @weight_form_submit  =  8;
SET @weight_email_click  =  5;
SET @weight_email_open   =  2;
SET @weight_page_view    =  1;
SET @lookback_days       = 90;  -- only count events within this window
SET @reference_date      = CURDATE();

WITH recent_events AS (

  -- Filter to behavioral events within the lookback window.
  -- Events older than @lookback_days decay naturally out of the score
  -- so that inactive contacts lose score over time without manual resets.

  SELECT
    contact_id,
    event_type,
    COUNT(event_id) AS event_count
  FROM events
  WHERE occurred_at >= DATE_SUB(@reference_date, INTERVAL @lookback_days DAY)
  -- BigQuery: WHERE occurred_at >= DATE_SUB(CURRENT_DATE(), INTERVAL @lookback_days DAY)
  GROUP BY contact_id, event_type

),

weighted_scores AS (

  -- Apply per-event-type weights and sum to a raw score per contact.
  -- Event types not listed in the CASE receive zero weight and do not
  -- contribute to the score — add new types here as your tracking expands.

  SELECT
    contact_id,
    SUM(
      CASE event_type
        WHEN 'purchase'      THEN event_count * @weight_purchase
        WHEN 'form_submit'   THEN event_count * @weight_form_submit
        WHEN 'email_click'   THEN event_count * @weight_email_click
        WHEN 'email_open'    THEN event_count * @weight_email_open
        WHEN 'page_view'     THEN event_count * @weight_page_view
        ELSE 0
      END
    ) AS raw_score,
    SUM(event_count) AS total_events
  FROM recent_events
  GROUP BY contact_id

)

SELECT
  c.contact_id,
  c.email,
  c.first_name,
  c.last_name,
  c.lifecycle_stage,
  c.lead_source,
  COALESCE(ws.raw_score, 0)     AS engagement_score,
  COALESCE(ws.total_events, 0)  AS total_events_90d,

  -- Tier label for CRM tagging and workflow routing
  CASE
    WHEN COALESCE(ws.raw_score, 0) >= 50  THEN 'Hot'
    WHEN COALESCE(ws.raw_score, 0) >= 20  THEN 'Warm'
    WHEN COALESCE(ws.raw_score, 0) >= 5   THEN 'Cool'
    ELSE                                       'Cold'
  END AS engagement_tier

FROM contacts c
LEFT JOIN weighted_scores ws ON ws.contact_id = c.contact_id
ORDER BY engagement_score DESC;

/*
  Sample Output:

  contact_id | email               | lifecycle_stage | engagement_score | total_events_90d | engagement_tier
  -----------|---------------------|-----------------|------------------|------------------|----------------
  c_091      | ana@example.com     | customer        |               87 |               24 | Hot
  c_204      | rui@example.com     | sql             |               42 |               15 | Warm
  c_017      | sara@example.com    | mql             |               18 |               11 | Cool
  c_338      | lucas@example.com   | lead            |                3 |                4 | Cool
  c_512      | marta@example.com   | lead            |                0 |                0 | Cold

  Logic Notes:
    - Contacts with no events in the lookback window receive a score of 0
      via COALESCE and land in the Cold tier. They are still included in
      the output so the full contact list is available for suppression use.
    - The lookback window creates implicit score decay: a contact who was
      Hot three months ago and has since gone silent will drop to Cold
      without any manual intervention.
    - Tier thresholds (5 / 20 / 50) should be calibrated to your event
      volume. Run a histogram of raw_score values first and set thresholds
      at natural breakpoints in your distribution.

  Adapting to Other Platforms:
    HubSpot:    events maps to the HubSpot Engagements object (emails, calls,
                meetings). Use the Analytics API for page_view data.
                Write the score back to a custom contact property via workflow.
    Salesforce: Use Activity (Task/Event) records for interaction history.
                Map event_type to TaskSubtype or Subject patterns.
    RD Station: events maps to contact activities. Use the RD Station API
                to pull activity history and load it into the events table.
    Klaviyo:    Use Klaviyo's built-in Predictive Analytics score as an
                alternative, or replicate this logic in the SQL editor
                against the Profiles and Events data models.
    BigQuery:   Replace DATE_SUB with DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY).
                SET variables are not supported — use a WITH params AS CTE.
*/
