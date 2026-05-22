/*
  Query Name: Event Frequency Trend
  Category:   Engagement

  Purpose:
    Show monthly event volume per contact over a rolling time window to
    identify engagement acceleration, deceleration, and churn signals.
    A contact whose event count is declining month over month is showing
    early signs of disengagement before they become inactive.

  Use Case:
    Feed this data into a BI dashboard to monitor engagement health trends
    at the portfolio level. For individual contacts, use the month-over-month
    change to trigger proactive outreach: a contact who drops from 10 events
    per month to 2 is a higher priority for re-engagement than one who has
    been consistently low. Combine with the Engagement Score query to build
    a leading indicator of churn risk.

  Tables Used:
    events    — all behavioral event types with timestamps
    contacts  — identity fields for context
*/

-- ── Parameters ───────────────────────────────────────────────────────────────
SET @lookback_months = 6;   -- number of months of trend data to return
SET @reference_date  = CURDATE();

WITH monthly_events AS (

  -- Aggregate event counts per contact per calendar month.
  -- DATE_FORMAT truncates timestamps to year-month for grouping.

  SELECT
    contact_id,
    DATE_FORMAT(occurred_at, '%Y-%m')    AS event_month,
    -- BigQuery: FORMAT_DATE('%Y-%m', DATE(occurred_at))
    COUNT(event_id)                      AS event_count,
    COUNT(DISTINCT event_type)           AS distinct_event_types
  FROM events
  WHERE occurred_at >= DATE_SUB(@reference_date, INTERVAL @lookback_months MONTH)
  -- BigQuery: DATE_SUB(CURRENT_DATE(), INTERVAL @lookback_months MONTH)
  GROUP BY contact_id, DATE_FORMAT(occurred_at, '%Y-%m')

),

with_trend AS (

  -- Calculate month-over-month change using LAG to compare each month
  -- to the previous one for the same contact.

  SELECT
    contact_id,
    event_month,
    event_count,
    distinct_event_types,
    LAG(event_count) OVER (
      PARTITION BY contact_id
      ORDER BY event_month
    )                                    AS prev_month_count,
    -- BigQuery: LAG() OVER (...) is supported with identical syntax

    event_count - LAG(event_count) OVER (
      PARTITION BY contact_id
      ORDER BY event_month
    )                                    AS mom_change

  FROM monthly_events

)

SELECT
  c.contact_id,
  c.email,
  c.first_name,
  c.last_name,
  c.lifecycle_stage,
  wt.event_month,
  wt.event_count,
  wt.distinct_event_types,
  wt.prev_month_count,
  wt.mom_change,

  -- Trend signal for routing and alerting
  CASE
    WHEN wt.prev_month_count IS NULL                    THEN 'First Month'
    WHEN wt.mom_change > 0                              THEN 'Accelerating'
    WHEN wt.mom_change = 0                              THEN 'Stable'
    WHEN wt.mom_change < 0 AND wt.event_count > 0      THEN 'Decelerating'
    WHEN wt.mom_change < 0 AND wt.event_count = 0      THEN 'Dropped Off'
  END AS trend_signal

FROM with_trend wt
INNER JOIN contacts c ON c.contact_id = wt.contact_id
ORDER BY c.contact_id, wt.event_month;

/*
  Sample Output:

  contact_id | email            | event_month | event_count | prev_month_count | mom_change | trend_signal
  -----------|------------------|-------------|-------------|------------------|------------|-------------
  c_091      | ana@example.com  | 2024-10     |          12 |             NULL |       NULL | First Month
  c_091      | ana@example.com  | 2024-11     |          18 |               12 |          6 | Accelerating
  c_091      | ana@example.com  | 2024-12     |          15 |               18 |         -3 | Decelerating
  c_091      | ana@example.com  | 2025-01     |           4 |               15 |        -11 | Decelerating
  c_091      | ana@example.com  | 2025-02     |           0 |                4 |         -4 | Dropped Off

  Logic Notes:
    - Months with zero events are absent from the output because there are
      no rows in the events table for that period. To show zero-count months
      explicitly, generate a date spine and LEFT JOIN this result against it.
    - mom_change is NULL for the first recorded month per contact since there
      is no prior month to compare — handled as 'First Month' in the trend signal.
    - INNER JOIN with contacts excludes events from deleted contacts. Use LEFT
      JOIN if you want to retain orphaned event records for audit purposes.

  Adapting to Other Platforms:
    HubSpot:    Pull engagement activity from the HubSpot Engagements API
                grouped by month. The Contact Timeline API provides the
                raw event stream.
    Salesforce: Use Activity records (Task/Event) grouped by CALENDAR_MONTH
                in SOQL to replicate monthly aggregation.
    BigQuery:   FORMAT_DATE('%Y-%m', DATE(occurred_at)) replaces DATE_FORMAT.
                DATE_SUB syntax changes as noted. LAG is identical.
*/
