/*
  Query Name: Email Activity Summary
  Category:   Engagement

  Purpose:
    Summarize per-contact email engagement metrics — open rate, click rate,
    click-to-open rate, and last activity date. Provides the input data for
    deliverability audits, list hygiene decisions, and send-time optimization.

  Use Case:
    Run before any large email send to identify contacts who have not opened
    or clicked in the past 90 days — these are candidates for a re-permission
    flow or suppression to protect sender reputation. The click_to_open_rate
    column isolates content performance from deliverability performance:
    a high open rate with a low CTOR indicates the subject line is strong
    but the email body is not compelling.

  Tables Used:
    contacts  — identity fields
    events    — email-specific event types (email_open, email_click,
                email_send, unsubscribe)
*/

-- ── Parameters ───────────────────────────────────────────────────────────────
SET @lookback_days  = 180;
SET @reference_date = CURDATE();

WITH email_events AS (

  -- Isolate email-related events within the lookback window.
  -- Filtering by event_type here keeps the aggregation clean and avoids
  -- accidentally counting non-email events in email-specific rate calculations.

  SELECT
    contact_id,
    event_type,
    occurred_at
  FROM events
  WHERE event_type  IN ('email_send', 'email_open', 'email_click', 'unsubscribe')
    AND occurred_at >= DATE_SUB(@reference_date, INTERVAL @lookback_days DAY)
  -- BigQuery: DATE_SUB(CURRENT_DATE(), INTERVAL @lookback_days DAY)

),

email_summary AS (

  SELECT
    contact_id,
    COUNT(CASE WHEN event_type = 'email_send'   THEN 1 END) AS emails_sent,
    COUNT(CASE WHEN event_type = 'email_open'   THEN 1 END) AS emails_opened,
    COUNT(CASE WHEN event_type = 'email_click'  THEN 1 END) AS emails_clicked,
    COUNT(CASE WHEN event_type = 'unsubscribe'  THEN 1 END) AS unsubscribes,
    MAX(CASE WHEN event_type IN ('email_open','email_click')
             THEN occurred_at END)                          AS last_email_activity_date,
    MAX(occurred_at)                                        AS last_event_date
  FROM email_events
  GROUP BY contact_id

)

SELECT
  c.contact_id,
  c.email,
  c.first_name,
  c.last_name,
  c.lifecycle_stage,
  COALESCE(es.emails_sent,    0)                          AS emails_sent,
  COALESCE(es.emails_opened,  0)                          AS emails_opened,
  COALESCE(es.emails_clicked, 0)                          AS emails_clicked,
  COALESCE(es.unsubscribes,   0)                          AS unsubscribes,

  -- Open rate: share of sent emails that were opened
  ROUND(
    COALESCE(es.emails_opened, 0) * 100.0
    / NULLIF(es.emails_sent, 0), 1)                       AS open_rate_pct,

  -- Click rate: share of sent emails that received a click
  ROUND(
    COALESCE(es.emails_clicked, 0) * 100.0
    / NULLIF(es.emails_sent, 0), 1)                       AS click_rate_pct,

  -- Click-to-open rate: share of opened emails that received a click
  -- Isolates body/CTA performance from subject line performance
  ROUND(
    COALESCE(es.emails_clicked, 0) * 100.0
    / NULLIF(es.emails_opened, 0), 1)                     AS click_to_open_rate_pct,

  es.last_email_activity_date,
  DATEDIFF(@reference_date, es.last_email_activity_date)  AS days_since_last_activity
  -- BigQuery: DATE_DIFF(CURRENT_DATE(), DATE(es.last_email_activity_date), DAY)

FROM contacts c
LEFT JOIN email_summary es ON es.contact_id = c.contact_id
ORDER BY days_since_last_activity ASC;

/*
  Sample Output:

  contact_id | email              | emails_sent | emails_opened | open_rate_pct | click_rate_pct | click_to_open_rate_pct | days_since_last_activity
  -----------|--------------------|-------------|---------------|---------------|----------------|------------------------|-------------------------
  c_091      | ana@example.com    |          18 |            14 |          77.8 |           33.3 |                   42.9 |                        3
  c_204      | rui@example.com    |          12 |             6 |          50.0 |           16.7 |                   33.3 |                       21
  c_338      | lucas@example.com  |           8 |             1 |          12.5 |            0.0 |                    0.0 |                       95
  c_512      | marta@example.com  |           6 |             0 |           0.0 |            0.0 |                    0.0 |                     NULL

  Logic Notes:
    - days_since_last_activity is NULL for contacts who have never opened or
      clicked. In downstream tooling treat NULL as the maximum possible recency.
    - CTOR (click_to_open_rate_pct) is undefined when emails_opened = 0 —
      NULLIF prevents division-by-zero and returns NULL instead.
    - Contacts with unsubscribes > 0 should be cross-referenced with your
      suppression list to confirm they are excluded from active sends.

  Adapting to Other Platforms:
    HubSpot:    Email events are tracked natively. Use the Email Health report
                or pull from the HubSpot Engagements API.
    Salesforce: Use ExactTarget/Marketing Cloud Send, Open, Click data extensions
                or query the EmailMessage object in Service Cloud.
    Klaviyo:    Use Klaviyo's built-in per-profile engagement metrics or query
                the Metrics API for Opens, Clicks, and Unsubscribes.
    BigQuery:   Replace DATE_SUB and DATEDIFF as noted. NULLIF is identical.
*/
