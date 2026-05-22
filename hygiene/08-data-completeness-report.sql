/*
  Query Name: Data Completeness Report
  Category:   Hygiene

  Purpose:
    Calculate field-level completeness percentages across the entire
    contacts table. Provides a single-row-per-field summary showing how
    many contacts have each field populated, enabling data quality tracking
    over time and gap prioritization for enrichment efforts.

  Use Case:
    Run monthly and log the results to track data quality trends. A declining
    completeness rate on email indicates a data capture problem at the
    acquisition stage. A low completeness rate on lifecycle_stage indicates
    that contact scoring or manual stage assignment is not keeping up with
    volume. Share the output with marketing ops, sales ops, and data
    engineering teams as a shared quality benchmark.

  Tables Used:
    contacts  — all fields assessed for completeness
*/

WITH field_stats AS (

  -- Calculate completeness for each field in a single pass over contacts.
  -- A field is populated if it is non-NULL and not an empty/whitespace string.

  SELECT
    COUNT(*)                                                           AS total_contacts,

    -- Identity
    SUM(CASE WHEN email      IS NOT NULL AND TRIM(email)      != '' THEN 1 ELSE 0 END) AS has_email,
    SUM(CASE WHEN first_name IS NOT NULL AND TRIM(first_name) != '' THEN 1 ELSE 0 END) AS has_first_name,
    SUM(CASE WHEN last_name  IS NOT NULL AND TRIM(last_name)  != '' THEN 1 ELSE 0 END) AS has_last_name,

    -- Segmentation
    SUM(CASE WHEN lifecycle_stage IS NOT NULL AND TRIM(lifecycle_stage) != ''
             THEN 1 ELSE 0 END)                                        AS has_lifecycle_stage,
    SUM(CASE WHEN lead_source IS NOT NULL AND TRIM(lead_source) != ''
             THEN 1 ELSE 0 END)                                        AS has_lead_source,

    -- Geographic
    SUM(CASE WHEN country IS NOT NULL AND TRIM(country) != '' THEN 1 ELSE 0 END) AS has_country,
    SUM(CASE WHEN state   IS NOT NULL AND TRIM(state)   != '' THEN 1 ELSE 0 END) AS has_state,
    SUM(CASE WHEN city    IS NOT NULL AND TRIM(city)    != '' THEN 1 ELSE 0 END) AS has_city,

    -- B2B
    SUM(CASE WHEN company   IS NOT NULL AND TRIM(company)   != '' THEN 1 ELSE 0 END) AS has_company,
    SUM(CASE WHEN job_title IS NOT NULL AND TRIM(job_title) != '' THEN 1 ELSE 0 END) AS has_job_title

  FROM contacts

)

-- UNION ALL unpivots the aggregated counts into one row per field,
-- making it easy to sort, filter, and track over time.
SELECT 'email'           AS field_name, 'Identity'     AS category, has_email           AS populated, total_contacts, ROUND(has_email           * 100.0 / total_contacts, 1) AS completeness_pct FROM field_stats
UNION ALL
SELECT 'first_name',                    'Identity',                  has_first_name,      total_contacts, ROUND(has_first_name      * 100.0 / total_contacts, 1) FROM field_stats
UNION ALL
SELECT 'last_name',                     'Identity',                  has_last_name,       total_contacts, ROUND(has_last_name       * 100.0 / total_contacts, 1) FROM field_stats
UNION ALL
SELECT 'lifecycle_stage',               'Segmentation',              has_lifecycle_stage, total_contacts, ROUND(has_lifecycle_stage * 100.0 / total_contacts, 1) FROM field_stats
UNION ALL
SELECT 'lead_source',                   'Segmentation',              has_lead_source,     total_contacts, ROUND(has_lead_source     * 100.0 / total_contacts, 1) FROM field_stats
UNION ALL
SELECT 'country',                       'Geographic',                has_country,         total_contacts, ROUND(has_country         * 100.0 / total_contacts, 1) FROM field_stats
UNION ALL
SELECT 'state',                         'Geographic',                has_state,           total_contacts, ROUND(has_state           * 100.0 / total_contacts, 1) FROM field_stats
UNION ALL
SELECT 'city',                          'Geographic',                has_city,            total_contacts, ROUND(has_city            * 100.0 / total_contacts, 1) FROM field_stats
UNION ALL
SELECT 'company',                       'B2B',                       has_company,         total_contacts, ROUND(has_company         * 100.0 / total_contacts, 1) FROM field_stats
UNION ALL
SELECT 'job_title',                     'B2B',                       has_job_title,       total_contacts, ROUND(has_job_title       * 100.0 / total_contacts, 1) FROM field_stats
ORDER BY completeness_pct ASC;

/*
  Sample Output:

  field_name      | category     | populated | total_contacts | completeness_pct
  ----------------|--------------|-----------|----------------|------------------
  job_title       | B2B          |     3,210 |         13,510 |             23.8
  company         | B2B          |     4,052 |         13,510 |             30.0
  state           | Geographic   |     6,755 |         13,510 |             50.0
  lead_source     | Segmentation |     9,457 |         13,510 |             70.0
  lifecycle_stage | Segmentation |    10,138 |         13,510 |             75.0
  city            | Geographic   |    10,273 |         13,510 |             76.1
  country         | Geographic   |    11,083 |         13,510 |             82.0
  last_name       | Identity     |    12,159 |         13,510 |             90.0
  first_name      | Identity     |    12,835 |         13,510 |             95.0
  email           | Identity     |    13,375 |         13,510 |             98.9

  Logic Notes:
    - Sorting ASC by completeness_pct puts the most incomplete fields first —
      the top of the output is the prioritized remediation list.
    - Fields below 80% completeness in Identity or Segmentation categories
      represent significant gaps that directly impact campaign targeting accuracy.
    - Run this query on a monthly schedule and store results with a snapshot_date
      column to build a completeness trend over time:
        INSERT INTO data_quality_log (snapshot_date, field_name, completeness_pct)
        SELECT CURDATE(), field_name, completeness_pct FROM ( <this query> ) t;

  Adapting to Other Platforms:
    HubSpot:    Use the Property Completion report in the Contacts dashboard.
                For programmatic access, use the Properties API to retrieve
                field-level population rates.
    Salesforce: Use the Data Assessment tool or create a custom report with
                formula fields that flag NULL values on each Contact field.
    RD Station: No native completeness report exists. Use the Contacts API
                to export contacts and calculate completeness in Python or SQL.
    BigQuery:   TRIM() and IS NOT NULL behave identically.
                UNION ALL is fully supported. No syntax changes needed.
*/
