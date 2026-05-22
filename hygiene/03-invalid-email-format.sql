/*
  Query Name: Invalid Email Format
  Category:   Hygiene

  Purpose:
    Detect contacts with malformed email addresses using pattern matching.
    Invalid emails cause hard bounces, damage sender reputation, and
    inflate list size with untargetable contacts.

  Use Case:
    Run before any email send or list export. Invalid emails should be
    suppressed immediately to avoid hard bounces. The invalid_reason
    column categorizes the specific format issue so remediation can be
    prioritized — missing domain is more likely a typo than a fake email,
    while entries with no @ symbol are almost certainly data entry errors.

  Tables Used:
    contacts  — email field
*/

SELECT
  contact_id,
  email,
  first_name,
  last_name,
  lifecycle_stage,
  created_at,

  -- Classify the specific format issue for targeted remediation
  CASE
    WHEN email IS NULL
      OR TRIM(email) = ''                                       THEN 'Missing email'
    WHEN email NOT LIKE '%@%'                                   THEN 'No @ symbol'
    WHEN email NOT LIKE '%@%.%'                                 THEN 'No domain extension'
    WHEN email LIKE '@%'                                        THEN 'Starts with @'
    WHEN email LIKE '%@'                                        THEN 'Nothing after @'
    WHEN email LIKE '% %'                                       THEN 'Contains spaces'
    WHEN LENGTH(email) - LENGTH(REPLACE(email, '@', '')) > 1   THEN 'Multiple @ symbols'
    -- BigQuery: ARRAY_LENGTH(SPLIT(email, '@')) - 1 > 1
    WHEN email NOT REGEXP '^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$'
                                                                THEN 'Invalid format'
    -- BigQuery: NOT REGEXP_CONTAINS(email, r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$')
  END AS invalid_reason,

  -- Remediation suggestion based on issue type
  CASE
    WHEN email IS NULL OR TRIM(email) = ''    THEN 'Collect email via re-engagement or remove'
    WHEN email NOT LIKE '%@%'                 THEN 'Likely typo — attempt correction or remove'
    WHEN email NOT LIKE '%@%.%'               THEN 'Missing TLD — attempt correction'
    WHEN email LIKE '% %'                     THEN 'Remove whitespace and revalidate'
    ELSE                                           'Suppress and flag for review'
  END AS remediation

FROM contacts
WHERE
  email IS NULL
  OR TRIM(email) = ''
  OR email NOT LIKE '%@%'
  OR email NOT LIKE '%@%.%'
  OR email LIKE '@%'
  OR email LIKE '%@'
  OR email LIKE '% %'
  OR LENGTH(email) - LENGTH(REPLACE(email, '@', '')) > 1
  OR email NOT REGEXP '^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$'
ORDER BY invalid_reason, created_at DESC;

/*
  Sample Output:

  contact_id | email                | invalid_reason        | remediation
  -----------|----------------------|-----------------------|-----------------------------------
  c_512      | NULL                 | Missing email         | Collect email via re-engagement or remove
  c_338      | bobexample.com       | No @ symbol           | Likely typo — attempt correction or remove
  c_721      | sara@@example.com    | Multiple @ symbols    | Suppress and flag for review
  c_094      | luis @example.com    | Contains spaces       | Remove whitespace and revalidate
  c_203      | maria@example        | No domain extension   | Missing TLD — attempt correction

  Summary Query:
    SELECT invalid_reason, COUNT(*) AS contact_count
    FROM ( <this query> ) t
    GROUP BY invalid_reason ORDER BY contact_count DESC;

  Logic Notes:
    - The REGEXP pattern catches most common invalid formats but is not a
      substitute for real-time email validation at the point of capture.
      Consider adding email verification to your forms and import processes.
    - This query does not verify whether an email address actually exists
      (deliverability check). For that, use an email validation service
      such as ZeroBounce, NeverBounce, or Kickbox before bulk sends.
    - The pattern allows + in the local part (user+tag@domain.com) which
      is valid RFC 5321 syntax and commonly used for email filtering.

  Adapting to Other Platforms:
    HubSpot:    Use the Email Validation feature in Forms to prevent invalid
                addresses at capture. Bulk validate via the Contacts API.
    Salesforce: Use the standard Email field validation rule. For existing
                data, run a report filtered by Email "does not contain" '@'.
    Klaviyo:    Klaviyo automatically suppresses hard bounces. Use the
                Suppressions API to identify and clean invalid addresses.
    BigQuery:   Replace REGEXP with REGEXP_CONTAINS(email, r'pattern').
                Replace LENGTH(REPLACE()) logic with
                ARRAY_LENGTH(SPLIT(email, '@')) - 1 > 1.
*/
