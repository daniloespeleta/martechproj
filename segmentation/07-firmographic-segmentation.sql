/*
  Query Name: Firmographic Segmentation
  Category:   Segmentation

  Purpose:
    Segment B2B contacts by company and job title patterns to identify
    which companies and roles generate the most revenue and conversion.
    Used to refine ICP (Ideal Customer Profile) definitions and build
    targeted ABM (Account-Based Marketing) audience lists.

  Use Case:
    Run this query quarterly to refresh ICP scoring. The company_tier
    column feeds an ABM prioritization list. Job title patterns surface
    which decision-maker roles drive the most revenue — use this to
    adjust LinkedIn and paid targeting filters. Requires that company
    and job_title fields are populated; run the Missing Required Fields
    hygiene query first to assess coverage.

  Tables Used:
    contacts  — company, job_title for firmographic attributes
    orders    — revenue and frequency per contact
*/

WITH firmographic_base AS (

  SELECT
    c.contact_id,
    COALESCE(NULLIF(TRIM(c.company),   ''), 'Unknown Company')    AS company,
    COALESCE(NULLIF(TRIM(c.job_title), ''), 'Unknown Title')       AS job_title,

    -- Normalize seniority from job title using keyword matching.
    -- Extend the CASE with terms relevant to your industry.
    CASE
      WHEN c.job_title REGEXP '(?i)(CEO|CTO|CMO|CFO|COO|Chief|Founder|Owner|President)' THEN 'C-Level'
      WHEN c.job_title REGEXP '(?i)(VP|Vice President|Director)'                         THEN 'Director'
      WHEN c.job_title REGEXP '(?i)(Manager|Lead|Head of)'                               THEN 'Manager'
      WHEN c.job_title REGEXP '(?i)(Analyst|Specialist|Coordinator|Executive)'           THEN 'Individual Contributor'
      ELSE 'Other'
    END AS seniority_tier,
    -- BigQuery: REGEXP_CONTAINS(c.job_title, r'(?i)(CEO|CTO|...)') in a CASE WHEN

    COUNT(o.order_id)                AS total_orders,
    COALESCE(SUM(o.total_amount), 0) AS total_spent
  FROM contacts c
  LEFT JOIN orders o
         ON o.contact_id = c.contact_id
        AND o.status = 'completed'
  GROUP BY
    c.contact_id,
    COALESCE(NULLIF(TRIM(c.company),   ''), 'Unknown Company'),
    COALESCE(NULLIF(TRIM(c.job_title), ''), 'Unknown Title'),
    CASE
      WHEN c.job_title REGEXP '(?i)(CEO|CTO|CMO|CFO|COO|Chief|Founder|Owner|President)' THEN 'C-Level'
      WHEN c.job_title REGEXP '(?i)(VP|Vice President|Director)'                         THEN 'Director'
      WHEN c.job_title REGEXP '(?i)(Manager|Lead|Head of)'                               THEN 'Manager'
      WHEN c.job_title REGEXP '(?i)(Analyst|Specialist|Coordinator|Executive)'           THEN 'Individual Contributor'
      ELSE 'Other'
    END

)

SELECT
  company,
  COUNT(DISTINCT contact_id)                         AS total_contacts,
  SUM(total_orders)                                  AS total_orders,
  ROUND(SUM(total_spent), 2)                         AS total_revenue,
  ROUND(AVG(NULLIF(total_spent, 0)), 2)              AS avg_revenue_per_buyer,
  SUM(CASE WHEN total_orders > 0 THEN 1 ELSE 0 END) AS buyers,

  -- Company tier based on revenue contribution
  CASE
    WHEN SUM(total_spent) >= 10000 THEN 'Enterprise'
    WHEN SUM(total_spent) >= 2000  THEN 'Mid-Market'
    WHEN SUM(total_spent) >  0     THEN 'SMB'
    ELSE 'No Revenue'
  END AS company_tier,

  -- Most common seniority tier within this company's contacts
  -- Uses a subquery to avoid complex aggregation in the outer GROUP BY
  (
    SELECT seniority_tier
    FROM firmographic_base fb2
    WHERE fb2.company = firmographic_base.company
    GROUP BY seniority_tier
    ORDER BY COUNT(*) DESC
    LIMIT 1
  ) AS dominant_seniority

FROM firmographic_base
GROUP BY company
ORDER BY total_revenue DESC;

/*
  Sample Output:

  company           | total_contacts | total_orders | total_revenue | company_tier | dominant_seniority
  ------------------|----------------|--------------|---------------|--------------|-------------------
  Acme Corp         |             12 |           34 |     18,400.00 | Enterprise   | Manager
  Global Media Ltd  |              8 |           21 |      9,200.00 | Mid-Market   | Director
  StartupXYZ        |              3 |            5 |      1,850.00 | SMB          | C-Level
  Unknown Company   |            420 |           84 |      6,300.00 | SMB          | Individual Contributor

  Logic Notes:
    - The REGEXP pattern matching for seniority_tier uses case-insensitive matching.
      In BigQuery replace REGEXP with REGEXP_CONTAINS using the r'...' raw string syntax.
    - Unknown Company and Unknown Title appear when company or job_title fields
      are empty or null. High counts here signal a data quality issue — run the
      Missing Required Fields hygiene query to quantify coverage.
    - The correlated subquery for dominant_seniority adds per-row cost.
      For large datasets, materialize firmographic_base as a temp table first.

  Adapting to Other Platforms:
    HubSpot:    company → Associated Company Name; job_title → Job Title.
    Salesforce: Contact.AccountId links to Account for company-level rollups.
                Use Account.Type or custom fields for company tier.
    RD Station: company and job_title are standard contact fields.
    BigQuery:   Replace REGEXP with REGEXP_CONTAINS(col, r'pattern').
                Correlated subqueries are supported but consider QUALIFY with
                ROW_NUMBER() for better performance at scale.
*/
