/*
  Query Name: Cohort Campaign Response
  Category:   Campaigns

  Purpose:
    Measure the purchase response rate of contact cohorts (grouped by the
    month they were acquired) after being exposed to a campaign. Reveals
    whether newer or older cohorts respond better to campaigns — a signal
    of list aging, onboarding effectiveness, or campaign relevance by
    customer tenure.

  Use Case:
    Use when investigating why campaign conversion rates are declining
    over time. If older cohorts convert at a higher rate than newer ones,
    the acquisition quality may be declining. If newer cohorts convert
    better, the campaign creative resonates more with recent buyers.
    Also useful for timing decisions: which acquisition month produces
    contacts most likely to convert in month 3 versus month 12.

  Tables Used:
    contacts          — contact creation date as cohort anchor
    campaign_contacts — campaign exposure per contact
    orders            — purchase events post-exposure
*/

-- ── Parameters ───────────────────────────────────────────────────────────────
SET @cohort_months  = 12;   -- how many acquisition months to show
SET @reference_date = CURDATE();

WITH cohort_base AS (

  -- Assign each contact to a cohort based on the month they were created.
  -- Only contacts acquired within the lookback window are included.

  SELECT
    c.contact_id,
    DATE_FORMAT(c.created_at, '%Y-%m')       AS acquisition_cohort
    -- BigQuery: FORMAT_DATE('%Y-%m', DATE(c.created_at))
  FROM contacts c
  WHERE c.created_at >= DATE_SUB(@reference_date, INTERVAL @cohort_months MONTH)
  -- BigQuery: DATE_SUB(CURRENT_DATE(), INTERVAL @cohort_months MONTH)

),

campaign_exposure AS (

  -- Contacts exposed to at least one campaign after acquisition.

  SELECT DISTINCT
    cc.contact_id,
    cc.campaign_id
  FROM campaign_contacts cc
  INNER JOIN cohort_base cb ON cb.contact_id = cc.contact_id

),

post_exposure_purchases AS (

  -- Contacts who placed a completed order after their first campaign exposure.

  SELECT DISTINCT
    ce.contact_id,
    ce.campaign_id
  FROM campaign_exposure ce
  INNER JOIN orders o
          ON o.contact_id = ce.contact_id
         AND o.status     = 'completed'

)

SELECT
  cb.acquisition_cohort,
  c_meta.campaign_name,
  c_meta.channel,
  COUNT(DISTINCT ce.contact_id)                                   AS contacts_exposed,
  COUNT(DISTINCT pep.contact_id)                                  AS contacts_purchased,
  ROUND(
    COUNT(DISTINCT pep.contact_id) * 100.0
    / NULLIF(COUNT(DISTINCT ce.contact_id), 0), 1)               AS purchase_rate_pct
FROM cohort_base cb
INNER JOIN campaign_exposure ce       ON ce.contact_id    = cb.contact_id
INNER JOIN campaigns c_meta           ON c_meta.campaign_id = ce.campaign_id
LEFT JOIN  post_exposure_purchases pep ON pep.contact_id   = ce.contact_id
                                      AND pep.campaign_id  = ce.campaign_id
GROUP BY
  cb.acquisition_cohort,
  c_meta.campaign_name,
  c_meta.channel
ORDER BY
  cb.acquisition_cohort  DESC,
  purchase_rate_pct      DESC;

/*
  Sample Output:

  acquisition_cohort | campaign_name      | contacts_exposed | contacts_purchased | purchase_rate_pct
  -------------------|--------------------|------------------|--------------------|-------------------
  2024-10            | Black Friday 2024  |              842 |                 95 |              11.3
  2024-09            | Black Friday 2024  |            1,204 |                180 |              15.0
  2024-06            | Black Friday 2024  |            2,100 |                378 |              18.0
  2024-03            | Black Friday 2024  |            1,850 |                370 |              20.0

  Logic Notes:
    - A declining purchase_rate_pct from older to newer cohorts (reading
      bottom to top in this output) indicates list aging is healthy — older
      contacts have had more time to build purchase history and brand trust.
    - If newer cohorts consistently outperform older ones, investigate
      whether the campaign message is better aligned to recent acquisition
      sources or whether older contacts have churned out of the active list.
    - The query counts a contact as purchased if they placed any completed
      order after campaign exposure — it does not require the order to be
      directly attributed to the campaign in the orders table.

  Adapting to Other Platforms:
    HubSpot:    Use Contact Create Date as the cohort dimension. Pull campaign
                enrollment and conversion data from the Campaigns tool.
    Salesforce: Use Contact.CreatedDate for cohort grouping. Link to Campaign
                via CampaignMember and Opportunity for purchase signals.
    BigQuery:   FORMAT_DATE('%Y-%m', DATE(created_at)) replaces DATE_FORMAT.
                DATE_SUB and INTERVAL syntax as noted above.
*/
