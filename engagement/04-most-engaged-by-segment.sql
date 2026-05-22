/*
  Query Name: Most Engaged by Segment
  Category:   Engagement

  Purpose:
    Rank contacts by engagement score within each lifecycle stage and
    return the top N per segment. Identifies the warmest contacts in
    each funnel stage for prioritized outreach — the leads most likely
    to convert, the MQLs most likely to become SQLs, and the customers
    most likely to expand.

  Use Case:
    Use this query to build daily or weekly sales prioritization lists.
    Top-ranked leads in the MQL stage should be fast-tracked to sales.
    Top customers by engagement are expansion candidates — forward their
    profiles to account managers before renewal or upsell conversations.
    The rank column lets you slice the output at any depth without rerunning.

  Tables Used:
    contacts  — identity and lifecycle_stage fields
    events    — behavioral interactions for engagement scoring
*/

-- ── Parameters ───────────────────────────────────────────────────────────────
SET @lookback_days       = 90;
SET @top_n_per_segment   = 10;   -- top contacts to return per lifecycle stage
SET @reference_date      = CURDATE();
SET @weight_purchase     = 10;
SET @weight_form_submit  =  8;
SET @weight_email_click  =  5;
SET @weight_email_open   =  2;
SET @weight_page_view    =  1;

WITH recent_events AS (

  SELECT
    contact_id,
    event_type,
    COUNT(event_id) AS event_count
  FROM events
  WHERE occurred_at >= DATE_SUB(@reference_date, INTERVAL @lookback_days DAY)
  -- BigQuery: DATE_SUB(CURRENT_DATE(), INTERVAL @lookback_days DAY)
  GROUP BY contact_id, event_type

),

engagement_scores AS (

  SELECT
    contact_id,
    SUM(
      CASE event_type
        WHEN 'purchase'     THEN event_count * @weight_purchase
        WHEN 'form_submit'  THEN event_count * @weight_form_submit
        WHEN 'email_click'  THEN event_count * @weight_email_click
        WHEN 'email_open'   THEN event_count * @weight_email_open
        WHEN 'page_view'    THEN event_count * @weight_page_view
        ELSE 0
      END
    ) AS engagement_score
  FROM recent_events
  GROUP BY contact_id

),

ranked AS (

  -- Rank contacts within each lifecycle stage by engagement score.
  -- DENSE_RANK is used instead of ROW_NUMBER so that contacts with
  -- identical scores share the same rank position.

  SELECT
    c.contact_id,
    c.email,
    c.first_name,
    c.last_name,
    COALESCE(c.lifecycle_stage, 'unknown')          AS lifecycle_stage,
    c.lead_source,
    COALESCE(es.engagement_score, 0)                AS engagement_score,
    DENSE_RANK() OVER (
      PARTITION BY COALESCE(c.lifecycle_stage, 'unknown')
      ORDER BY COALESCE(es.engagement_score, 0) DESC
    )                                               AS rank_in_segment
    -- BigQuery: DENSE_RANK() OVER (...) is supported with identical syntax

  FROM contacts c
  LEFT JOIN engagement_scores es ON es.contact_id = c.contact_id

)

SELECT *
FROM ranked
WHERE rank_in_segment <= @top_n_per_segment
ORDER BY lifecycle_stage, rank_in_segment;

/*
  Sample Output:

  lifecycle_stage | rank_in_segment | contact_id | email               | engagement_score
  ----------------|-----------------|------------|---------------------|------------------
  customer        |               1 | c_091      | ana@example.com     |               87
  customer        |               2 | c_204      | rui@example.com     |               74
  mql             |               1 | c_017      | sara@example.com    |               55
  mql             |               2 | c_338      | lucas@example.com   |               48
  lead            |               1 | c_421      | pedro@example.com   |               31
  lead            |               2 | c_512      | marta@example.com   |               28

  Logic Notes:
    - Contacts with no events receive engagement_score = 0 and are ranked
      last within their segment. They appear in the output only if the segment
      has fewer than @top_n_per_segment contacts with positive scores.
    - DENSE_RANK means two contacts with the same score share the same rank.
      If you need exactly N contacts per segment regardless of ties, replace
      DENSE_RANK with ROW_NUMBER.
    - The @top_n_per_segment filter in the WHERE clause is applied after
      ranking, so it always returns the correct top N even for segments
      with many tied scores.

  Adapting to Other Platforms:
    HubSpot:    Use HubSpot's Contact Score property if engagement scoring
                is configured. PARTITION BY maps to list segmentation.
    Salesforce: Use the Einstein Lead Score or a custom score field as
                the ranking dimension. DENSE_RANK window functions are
                supported in Salesforce SOQL via Analytics queries.
    BigQuery:   Identical syntax. Replace DATE_SUB and SET variables
                with a WITH params AS CTE as noted in other queries.
*/
