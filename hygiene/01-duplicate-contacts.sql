/*
  Query Name: Duplicate Contacts
  Category:   Hygiene

  Purpose:
    Identify contacts sharing the same email address. Duplicates inflate
    list size metrics, cause contacts to receive the same message multiple
    times, and corrupt engagement scoring by splitting a single person's
    event history across multiple records.

  Use Case:
    Run before any large import or campaign send. The output provides the
    full set of duplicate groups with each contact's creation date so you
    can determine which record to keep (typically the oldest, or the one
    with the most complete data). Export to a spreadsheet for manual review
    or pipe into a deduplication script that merges activity history before
    deleting the duplicate.

  Tables Used:
    contacts  — email field as the deduplication key
*/

WITH duplicate_emails AS (

  -- Identify email addresses that appear more than once.
  -- NULL emails are excluded — they represent a separate data quality
  -- issue covered by the Missing Required Fields query.

  SELECT
    LOWER(TRIM(email))  AS normalized_email,
    COUNT(contact_id)   AS duplicate_count
  FROM contacts
  WHERE email IS NOT NULL
    AND TRIM(email) != ''
  GROUP BY LOWER(TRIM(email))
  HAVING COUNT(contact_id) > 1

),

duplicate_contacts AS (

  -- Return all contacts belonging to a duplicate email group.
  -- Ordered by email then created_at so the oldest record appears first
  -- within each group — a common heuristic for which record to retain.

  SELECT
    c.contact_id,
    c.email,
    LOWER(TRIM(c.email))              AS normalized_email,
    c.first_name,
    c.last_name,
    c.lifecycle_stage,
    c.lead_source,
    c.created_at,
    c.updated_at,
    de.duplicate_count,

    -- Rank within duplicate group: rank 1 = oldest record (retain candidate)
    ROW_NUMBER() OVER (
      PARTITION BY LOWER(TRIM(c.email))
      ORDER BY c.created_at ASC
    )                                 AS rank_in_group
    -- BigQuery: ROW_NUMBER() OVER (...) is supported with identical syntax

  FROM contacts c
  INNER JOIN duplicate_emails de
          ON LOWER(TRIM(c.email)) = de.normalized_email

)

SELECT
  contact_id,
  email,
  first_name,
  last_name,
  lifecycle_stage,
  lead_source,
  created_at,
  updated_at,
  duplicate_count,
  rank_in_group,
  CASE
    WHEN rank_in_group = 1 THEN 'Keep — oldest record'
    ELSE                        'Review — potential duplicate'
  END AS recommendation
FROM duplicate_contacts
ORDER BY normalized_email, rank_in_group;

/*
  Sample Output:

  contact_id | email              | created_at          | duplicate_count | rank_in_group | recommendation
  -----------|--------------------|---------------------|-----------------|---------------|-------------------------
  c_012      | ana@example.com    | 2023-01-15 09:00:00 |               2 |             1 | Keep — oldest record
  c_847      | ana@example.com    | 2024-03-22 14:30:00 |               2 |             2 | Review — potential duplicate
  c_204      | rui@example.com    | 2023-04-10 11:00:00 |               3 |             1 | Keep — oldest record
  c_521      | rui@example.com    | 2023-09-01 08:15:00 |               3 |             2 | Review — potential duplicate
  c_903      | rui@example.com    | 2024-01-05 16:45:00 |               3 |             3 | Review — potential duplicate

  Summary Query (run separately):
    SELECT duplicate_count, COUNT(DISTINCT normalized_email) AS email_groups,
           COUNT(contact_id) AS total_contacts
    FROM duplicate_contacts
    GROUP BY duplicate_count ORDER BY duplicate_count;

  Logic Notes:
    - LOWER(TRIM(email)) normalizes casing and whitespace before comparison.
      'Ana@Example.com' and 'ana@example.com' will be treated as duplicates.
    - rank_in_group = 1 is a starting heuristic only. Before deleting, verify
      that the oldest record has the most complete event history. If a newer
      record has more purchases or engagements, it may be the better primary.
    - Do not delete duplicates directly from this query output without first
      merging the event, order, and campaign history from all duplicate records
      onto the record you are retaining.

  Adapting to Other Platforms:
    HubSpot:    Use the Duplicates Management tool (Contacts > Actions > Manage
                Duplicates) for UI-based merging. For bulk deduplication, use
                the Contacts API filtered by email to find and merge duplicates.
    Salesforce: Use the Duplicate Management rules and Matching Rules on the
                Contact object. The DataLoader can be used for bulk merges.
    RD Station: Duplicates are surfaced in the contact list view. Use the
                RD Station API to merge contacts programmatically.
    BigQuery:   ROW_NUMBER() OVER (...) is supported with identical syntax.
                LOWER() and TRIM() are both available.
*/
