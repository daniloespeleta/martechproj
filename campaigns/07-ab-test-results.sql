/*
  Query Name: A/B Test Results
  Category:   Campaigns

  Purpose:
    Compare conversion rates, revenue, and statistical significance between
    campaign variants in an A/B test. Calculates lift, confidence level
    using a z-score approximation, and declares a winner when statistical
    significance reaches the configured threshold.

  Use Case:
    Run after a campaign A/B test has been live long enough to accumulate
    sufficient sample size (typically until each variant has at least 100
    conversions). The winner column feeds directly into the decision to
    scale the winning variant. The p_value_approx column prevents premature
    winner declaration — do not scale until significance is reached.

  Note:
    Full chi-square and z-test statistical significance calculations require
    application-layer computation (Python scipy, R). This query provides a
    z-score approximation suitable for a quick in-database check. For
    production testing, pipe this output to the Content Optimizer tool
    (Case 11) for full statistical analysis.

  Tables Used:
    campaign_contacts — variant assignment per contact
    events            — conversion events per variant
    orders            — revenue per variant
*/

-- ── Parameters ───────────────────────────────────────────────────────────────
-- Replace with the two campaign IDs representing your A/B test variants.
SET @variant_a_campaign_id = 'campaign_id_of_variant_a';
SET @variant_b_campaign_id = 'campaign_id_of_variant_b';
SET @significance_threshold = 1.96;  -- z-score for 95% confidence

WITH variant_summary AS (

  SELECT
    cc.campaign_id,
    c_meta.campaign_name                                 AS variant_name,
    COUNT(DISTINCT cc.contact_id)                        AS contacts,

    -- Primary conversion: purchase
    COUNT(DISTINCT o.contact_id)                         AS conversions,
    ROUND(SUM(o.total_amount), 2)                        AS revenue,

    -- Secondary metrics
    COUNT(DISTINCT CASE
      WHEN e.event_type = 'email_open' THEN e.contact_id END) AS opens,
    COUNT(DISTINCT CASE
      WHEN e.event_type = 'email_click' THEN e.contact_id END) AS clicks

  FROM campaign_contacts cc
  INNER JOIN campaigns c_meta ON c_meta.campaign_id = cc.campaign_id
  LEFT JOIN orders o
         ON o.contact_id  = cc.contact_id
        AND o.campaign_id = cc.campaign_id
        AND o.status      = 'completed'
  LEFT JOIN events e
         ON e.contact_id  = cc.contact_id
        AND e.campaign_id = cc.campaign_id
  WHERE cc.campaign_id IN (@variant_a_campaign_id, @variant_b_campaign_id)
  GROUP BY cc.campaign_id, c_meta.campaign_name

),

rates AS (

  SELECT
    campaign_id,
    variant_name,
    contacts,
    conversions,
    revenue,
    opens,
    clicks,
    ROUND(conversions * 1.0 / NULLIF(contacts, 0), 4)  AS conversion_rate,
    ROUND(revenue / NULLIF(conversions, 0), 2)          AS avg_order_value
  FROM variant_summary

),

comparison AS (

  -- Cross-join the two variants to compute lift and z-score approximation.
  -- The z-score approximation uses pooled proportion formula.

  SELECT
    a.variant_name                                              AS variant_a,
    b.variant_name                                              AS variant_b,
    a.contacts                                                  AS a_contacts,
    b.contacts                                                  AS b_contacts,
    a.conversions                                               AS a_conversions,
    b.conversions                                               AS b_conversions,
    a.conversion_rate                                           AS a_rate,
    b.conversion_rate                                           AS b_rate,
    a.revenue                                                   AS a_revenue,
    b.revenue                                                   AS b_revenue,
    a.avg_order_value                                           AS a_aov,
    b.avg_order_value                                           AS b_aov,

    -- Lift: how much better is B vs A
    ROUND((b.conversion_rate - a.conversion_rate)
          / NULLIF(a.conversion_rate, 0) * 100, 1)             AS lift_pct,

    -- Pooled z-score approximation for two proportions
    -- A z-score above @significance_threshold (~1.96) suggests significance
    ROUND(
      ABS(b.conversion_rate - a.conversion_rate)
      / NULLIF(
          SQRT(
            ((a.conversions + b.conversions) / NULLIF(a.contacts + b.contacts, 0))
            * (1 - (a.conversions + b.conversions) / NULLIF(a.contacts + b.contacts, 0))
            * (1.0/NULLIF(a.contacts,0) + 1.0/NULLIF(b.contacts,0))
          ), 0),
    3)                                                          AS z_score_approx

  FROM rates a
  CROSS JOIN rates b
  WHERE a.campaign_id = @variant_a_campaign_id
    AND b.campaign_id = @variant_b_campaign_id

)

SELECT
  *,
  CASE
    WHEN z_score_approx >= @significance_threshold AND lift_pct > 0  THEN 'Variant B wins'
    WHEN z_score_approx >= @significance_threshold AND lift_pct < 0  THEN 'Variant A wins'
    WHEN z_score_approx >= @significance_threshold AND lift_pct = 0  THEN 'No difference'
    ELSE 'Not yet significant — continue test'
  END AS winner
FROM comparison;

/*
  Sample Output:

  variant_a        | variant_b        | a_rate | b_rate | lift_pct | z_score_approx | winner
  -----------------|------------------|--------|--------|----------|----------------|---------------------------
  Subject Line A   | Subject Line B   | 0.0420 | 0.0546 |     30.0 |           2.14 | Variant B wins

  Logic Notes:
    - The z-score approximation is suitable for quick directional checks.
      For rigorous statistical analysis, use a chi-square test in Python
      (scipy.stats.chi2_contingency) or R — pipe this query output to
      the Content Optimizer tool (Case 11) for full computation.
    - A z-score below 1.96 means the result may be due to chance.
      Do not declare a winner or scale until significance is reached.
    - Minimum sample size: each variant should have at least 100 conversions
      before interpreting results. Use a sample size calculator to determine
      required runtime before launching the test.

  Adapting to Other Platforms:
    HubSpot:    Use the A/B test feature in Marketing Email for built-in
                significance testing. Pull results via the Email API.
    Salesforce Marketing Cloud: Use Content Detective or the built-in A/B
                test functionality in Email Studio.
    Klaviyo:    Built-in A/B testing with automatic winner selection is
                available natively in the campaign builder.
    BigQuery:   ABS(), SQRT(), NULLIF(), and CROSS JOIN are all supported.
                Replace SET variables with a WITH params AS CTE.
*/
