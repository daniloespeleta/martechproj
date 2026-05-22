/*
  Query Name: Best Send Time
  Category:   Campaigns

  Purpose:
    Identify the days of the week and hours of the day that generate the
    highest email open and click rates based on historical event data.
    Used to optimize send time scheduling for future campaigns.

  Use Case:
    Run monthly to refresh send-time recommendations as audience behavior
    evolves seasonally. The output feeds directly into ESP scheduling
    settings or an automated send-time optimization workflow. Segment
    the analysis by lifecycle_stage or lead_source to discover whether
    different audience segments have different peak engagement windows —
    customers may engage differently from leads.

  Tables Used:
    events    — email open and click events with timestamps
    contacts  — optional join for segment-level analysis
*/

-- ── Parameters ───────────────────────────────────────────────────────────────
SET @lookback_days  = 180;   -- analyze the past N days of send history
SET @reference_date = CURDATE();
SET @min_sends      = 50;    -- minimum sends per hour slot to include in results

WITH email_sends AS (

  -- Isolate email send events within the lookback window.
  -- Each send event is one contact receiving one email in one hour slot.

  SELECT
    contact_id,
    campaign_id,
    occurred_at,
    DAYOFWEEK(occurred_at)              AS day_of_week_num,
    -- 1=Sunday, 2=Monday, ..., 7=Saturday in MySQL
    -- BigQuery: EXTRACT(DAYOFWEEK FROM occurred_at)
    DAYNAME(occurred_at)                AS day_of_week_name,
    -- BigQuery: FORMAT_DATE('%A', DATE(occurred_at))
    HOUR(occurred_at)                   AS send_hour
    -- BigQuery: EXTRACT(HOUR FROM occurred_at)
  FROM events
  WHERE event_type  = 'email_send'
    AND occurred_at >= DATE_SUB(@reference_date, INTERVAL @lookback_days DAY)

),

email_responses AS (

  -- For each send event, check if the same contact opened or clicked
  -- within 48 hours — a reasonable attribution window for email responses.

  SELECT DISTINCT
    s.contact_id,
    s.campaign_id,
    s.day_of_week_num,
    s.day_of_week_name,
    s.send_hour,
    MAX(CASE WHEN r.event_type = 'email_open'  THEN 1 ELSE 0 END) AS opened,
    MAX(CASE WHEN r.event_type = 'email_click' THEN 1 ELSE 0 END) AS clicked
  FROM email_sends s
  LEFT JOIN events r
         ON r.contact_id  = s.contact_id
        AND r.campaign_id = s.campaign_id
        AND r.event_type  IN ('email_open', 'email_click')
        AND r.occurred_at BETWEEN s.occurred_at
                              AND DATE_ADD(s.occurred_at, INTERVAL 48 HOUR)
        -- BigQuery: r.occurred_at BETWEEN s.occurred_at
        --           AND DATETIME_ADD(s.occurred_at, INTERVAL 48 HOUR)
  GROUP BY
    s.contact_id, s.campaign_id,
    s.day_of_week_num, s.day_of_week_name, s.send_hour

)

SELECT
  day_of_week_num,
  day_of_week_name,
  send_hour,
  COUNT(*)                                              AS total_sends,
  SUM(opened)                                          AS total_opens,
  SUM(clicked)                                         AS total_clicks,
  ROUND(SUM(opened)  * 100.0 / NULLIF(COUNT(*), 0), 1) AS open_rate_pct,
  ROUND(SUM(clicked) * 100.0 / NULLIF(COUNT(*), 0), 1) AS click_rate_pct,

  -- Composite engagement score: weighted combination of open and click rates
  -- Click rate weighted higher because it signals stronger intent
  ROUND(
    (SUM(opened) * 1.0 + SUM(clicked) * 2.0)
    / NULLIF(COUNT(*), 0) * 100, 2)                    AS engagement_score

FROM email_responses
GROUP BY day_of_week_num, day_of_week_name, send_hour
HAVING COUNT(*) >= @min_sends
ORDER BY engagement_score DESC
LIMIT 20;

/*
  Sample Output:

  day_of_week_name | send_hour | total_sends | open_rate_pct | click_rate_pct | engagement_score
  -----------------|-----------|-------------|---------------|----------------|------------------
  Tuesday          |        10 |       4,820 |          38.2 |           14.1 |            66.4
  Wednesday        |         9 |       4,105 |          36.8 |           13.5 |            63.8
  Thursday         |        11 |       3,840 |          35.4 |           12.9 |            61.2
  Tuesday          |        14 |       2,960 |          33.1 |           11.8 |            56.7
  Sunday           |        20 |         890 |          28.4 |            8.2 |            44.8

  Logic Notes:
    - The 48-hour attribution window captures delayed opens common on mobile
      email clients. Adjust to 24 hours for lists with high mobile readership
      and faster open patterns.
    - The HAVING clause removes hour slots with fewer than @min_sends sends.
      Low-volume slots produce statistically unstable rates — lower the
      threshold to 10 to see more data at the cost of reliability.
    - The engagement_score weights clicks twice as heavily as opens because
      a click signals active intent rather than passive inbox preview.
      Adjust weights to match your definition of a meaningful interaction.

  Adapting to Other Platforms:
    HubSpot:    Use the Email Health report or the Send Time Intelligence
                feature (available on Marketing Hub Professional and above).
    Klaviyo:    Smart Send Time is a built-in feature. For manual analysis,
                pull send and open events from the Metrics API.
    Salesforce Marketing Cloud: Use Einstein Send Time Optimization or
                query _Sent and _Open data views filtered by EventDate hour.
    BigQuery:   Replace DAYOFWEEK with EXTRACT(DAYOFWEEK FROM occurred_at),
                DAYNAME with FORMAT_DATE('%A', DATE(occurred_at)),
                HOUR with EXTRACT(HOUR FROM occurred_at),
                and DATE_ADD with DATETIME_ADD as noted.
*/
