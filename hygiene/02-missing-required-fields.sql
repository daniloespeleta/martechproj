/*
  Query Name: Missing Required Fields
  Category:   Hygiene

  Purpose:
    Identify contacts with null or empty values in fields that are required
    for campaign targeting, personalization, and reporting. Quantifies
    data completeness gaps that reduce segmentation accuracy and block
    workflow automation triggers.

  Use Case:
    Run weekly as a data quality health check. The output feeds a remediation
    backlog: contacts missing email are untargetable and should be archived
    or re-engaged through other channels. Contacts missing lifecycle_stage
    cannot be routed through funnel automation. Share the summary output
    with the team responsible for data enrichment to prioritize gap closure.

  Tables Used:
    contacts  — all key contact fields assessed for completeness
*/

WITH field_completeness AS (

  -- Assess each required field per contact.
  -- A field is considered missing if it is NULL or an empty/whitespace string.

  SELECT
    contact_id,

    -- Identity fields
    CASE WHEN email      IS NULL OR TRIM(email)      = '' THEN 1 ELSE 0 END AS missing_email,
    CASE WHEN first_name IS NULL OR TRIM(first_name) = '' THEN 1 ELSE 0 END AS missing_first_name,
    CASE WHEN last_name  IS NULL OR TRIM(last_name)  = '' THEN 1 ELSE 0 END AS missing_last_name,

    -- Segmentation fields
    CASE WHEN lifecycle_stage IS NULL OR TRIM(lifecycle_stage) = ''
         THEN 1 ELSE 0 END                                                  AS missing_lifecycle_stage,
    CASE WHEN lead_source IS NULL OR TRIM(lead_source) = ''
         THEN 1 ELSE 0 END                                                  AS missing_lead_source,

    -- Geographic fields
    CASE WHEN country IS NULL OR TRIM(country) = '' THEN 1 ELSE 0 END      AS missing_country,
    CASE WHEN state   IS NULL OR TRIM(state)   = '' THEN 1 ELSE 0 END      AS missing_state,

    -- B2B fields
    CASE WHEN company   IS NULL OR TRIM(company)   = '' THEN 1 ELSE 0 END  AS missing_company,
    CASE WHEN job_title IS NULL OR TRIM(job_title) = '' THEN 1 ELSE 0 END  AS missing_job_title

  FROM contacts

)

-- Part 1: Contact-level detail — which specific contacts are missing which fields
SELECT
  c.contact_id,
  c.email,
  c.first_name,
  c.last_name,
  c.created_at,

  -- Total missing fields per contact
  (
    fc.missing_email + fc.missing_first_name + fc.missing_last_name +
    fc.missing_lifecycle_stage + fc.missing_lead_source +
    fc.missing_country + fc.missing_state +
    fc.missing_company + fc.missing_job_title
  )                                           AS total_missing_fields,

  -- Individual flags for targeted remediation
  fc.missing_email,
  fc.missing_first_name,
  fc.missing_last_name,
  fc.missing_lifecycle_stage,
  fc.missing_lead_source,
  fc.missing_country,
  fc.missing_state,
  fc.missing_company,
  fc.missing_job_title,

  -- Completeness tier for prioritization
  CASE
    WHEN (fc.missing_email + fc.missing_first_name + fc.missing_last_name +
          fc.missing_lifecycle_stage + fc.missing_lead_source) >= 3
         THEN 'Critical — 3+ core fields missing'
    WHEN fc.missing_email = 1
         THEN 'Critical — no email address'
    WHEN (fc.missing_lifecycle_stage + fc.missing_lead_source) >= 2
         THEN 'High — segmentation fields missing'
    ELSE      'Low — optional fields only'
  END AS completeness_tier

FROM contacts c
INNER JOIN field_completeness fc ON fc.contact_id = c.contact_id
WHERE (
  fc.missing_email + fc.missing_first_name + fc.missing_last_name +
  fc.missing_lifecycle_stage + fc.missing_lead_source +
  fc.missing_country + fc.missing_state +
  fc.missing_company + fc.missing_job_title
) > 0
ORDER BY total_missing_fields DESC, c.created_at DESC;

/*
  Sample Output:

  contact_id | email            | total_missing_fields | missing_email | missing_lifecycle_stage | completeness_tier
  -----------|------------------|----------------------|---------------|-------------------------|-----------------------------
  c_512      | NULL             |                    5 |             1 |                       1 | Critical — no email address
  c_338      | bob@example.com  |                    3 |             0 |                       1 | High — segmentation fields missing
  c_091      | ana@example.com  |                    1 |             0 |                       0 | Low — optional fields only

  Field-Level Summary (run separately for an aggregate view):

    SELECT
      'email'           AS field_name, SUM(missing_email)           AS missing_count FROM field_completeness
    UNION ALL
    SELECT 'lifecycle_stage',          SUM(missing_lifecycle_stage)               FROM field_completeness
    UNION ALL
    SELECT 'lead_source',              SUM(missing_lead_source)                   FROM field_completeness
    ORDER BY missing_count DESC;

  Logic Notes:
    - The contact-level query returns only contacts with at least one missing
      field. Remove the WHERE clause to get completeness status for all contacts.
    - TRIM() handles fields that contain only whitespace — these are not
      technically NULL but are functionally empty and should be treated as missing.
    - Missing company and job_title are flagged but may be acceptable for B2C
      contacts. Adjust the completeness_tier CASE to reflect your data model.

  Adapting to Other Platforms:
    HubSpot:    Use the Property Completion report in Contacts to identify
                contacts missing specific properties.
    Salesforce: Use reports with "is null" field filters on Contact fields.
                The Data Assessment tool provides field completeness metrics.
    RD Station: Filter contacts in the contact list by missing field values
                using the advanced filter in the contact list view.
    BigQuery:   TRIM() and IS NULL behave identically. No syntax changes needed.
*/
