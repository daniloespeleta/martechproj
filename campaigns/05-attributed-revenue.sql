/*
  Query Name: Attributed Revenue
  Category:   Campaigns

  Purpose:
    Calculate first-touch and last-touch revenue attribution for each
    campaign and channel. First-touch credits the campaign that acquired
    the contact; last-touch credits the campaign closest to the purchase.
    Comparing both models reveals where campaigns create demand versus
    where they close it.

  Use Case:
    Use when evaluating which campaigns to credit for revenue in budget
    planning. First-touch attribution favors top-of-funnel acquisition
    campaigns; last-touch favors bottom-of-funnel nurture and retargeting.
    A campaign that ranks high on first-touch but low on last-touch is an
    acquisition driver that needs better nurture handoff. Present both
    models side by side to avoid over-crediting any single campaign.

  Tables Used:
    contacts          — links contacts to their original acquisition source
    campaign_contacts — all campaign touchpoints per contact
    orders            — purchase revenue for attribution
    campaigns         — campaign metadata
*/

WITH contact_orders AS (

  -- One row per completed order with the purchasing contact.

  SELECT
    o.order_id,
    o.contact_id,
    o.total_amount,
    o.ordered_at
  FROM orders o
  WHERE o.status = 'completed'

),

first_touch AS (

  -- First-touch: the earliest campaign assigned to each contact.
  -- Represents the campaign that initially acquired or first engaged them.

  SELECT
    contact_id,
    campaign_id,
    ROW_NUMBER() OVER (
      PARTITION BY contact_id
      ORDER BY assigned_at ASC
    ) AS rn
  FROM campaign_contacts

),

last_touch AS (

  -- Last-touch: the most recent campaign assigned to each contact
  -- before their purchase. Represents the campaign closest to conversion.

  SELECT
    cc.contact_id,
    cc.campaign_id,
    ROW_NUMBER() OVER (
      PARTITION BY cc.contact_id
      ORDER BY cc.assigned_at DESC
    ) AS rn
  FROM campaign_contacts cc

),

first_touch_revenue AS (

  SELECT
    ft.campaign_id,
    COUNT(co.order_id)             AS ft_orders,
    ROUND(SUM(co.total_amount), 2)  AS ft_revenue
  FROM first_touch ft
  INNER JOIN contact_orders co ON co.contact_id = ft.contact_id
  WHERE ft.rn = 1
  GROUP BY ft.campaign_id

),

last_touch_revenue AS (

  SELECT
    lt.campaign_id,
    COUNT(co.order_id)             AS lt_orders,
    ROUND(SUM(co.total_amount), 2)  AS lt_revenue
  FROM last_touch lt
  INNER JOIN contact_orders co ON co.contact_id = lt.contact_id
  WHERE lt.rn = 1
  GROUP BY lt.campaign_id

)

SELECT
  c.campaign_id,
  c.campaign_name,
  c.channel,
  c.start_date,

  -- First-touch attribution
  COALESCE(ftr.ft_orders,  0)  AS first_touch_orders,
  COALESCE(ftr.ft_revenue, 0)  AS first_touch_revenue,

  -- Last-touch attribution
  COALESCE(ltr.lt_orders,  0)  AS last_touch_orders,
  COALESCE(ltr.lt_revenue, 0)  AS last_touch_revenue,

  -- Delta: positive means more credit on first-touch (acquisition driver)
  -- Negative means more credit on last-touch (conversion driver)
  ROUND(
    COALESCE(ftr.ft_revenue, 0) - COALESCE(ltr.lt_revenue, 0), 2
  )                            AS first_vs_last_touch_delta,

  CASE
    WHEN COALESCE(ftr.ft_revenue, 0) > COALESCE(ltr.lt_revenue, 0) THEN 'Acquisition Driver'
    WHEN COALESCE(ftr.ft_revenue, 0) < COALESCE(ltr.lt_revenue, 0) THEN 'Conversion Driver'
    ELSE 'Balanced'
  END                          AS campaign_role

FROM campaigns c
LEFT JOIN first_touch_revenue ftr ON ftr.campaign_id = c.campaign_id
LEFT JOIN last_touch_revenue  ltr ON ltr.campaign_id = c.campaign_id
ORDER BY last_touch_revenue DESC;

/*
  Sample Output:

  campaign_name      | channel | first_touch_revenue | last_touch_revenue | first_vs_last_touch_delta | campaign_role
  -------------------|---------|---------------------|--------------------|---------------------------|---------------------
  Welcome Series     | email   |          34,020.00  |         12,600.00  |                 21,420.00 | Acquisition Driver
  Q4 Retargeting     | paid    |           4,200.00  |         38,850.00  |                -34,650.00 | Conversion Driver
  Black Friday 2024  | email   |          18,720.00  |         19,500.00  |                   -780.00 | Balanced
  Referral Q3 2024   | referral|          67,200.00  |         48,300.00  |                 18,900.00 | Acquisition Driver

  Logic Notes:
    - This query implements single-touch models only (first and last touch).
      For linear or time-decay multi-touch attribution, each touchpoint in
      campaign_contacts must be weighted and the revenue split accordingly.
    - A campaign can appear in both first-touch and last-touch results for
      different contacts — a contact acquired by Campaign A who is also
      retargeted by Campaign A will credit the same campaign on both models.
    - Revenue totals across models will not match because each model
      attributes the full order value to a single campaign — the same
      order may be counted under different campaigns in each model.

  Adapting to Other Platforms:
    HubSpot:    Original Source contact property for first-touch;
                most recent conversion for last-touch.
    Salesforce: Use the CampaignInfluence object for multi-touch attribution.
                First and last touch are available as influence model types.
    Google Analytics 4: Use the Acquisition report for first-touch and the
                Conversion report for last-touch channel comparisons.
    BigQuery:   ROW_NUMBER() OVER (...) is supported with identical syntax.
*/
