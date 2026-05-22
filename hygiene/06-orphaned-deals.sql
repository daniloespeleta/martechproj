/*
  Query Name: Orphaned Deals
  Category:   Hygiene

  Purpose:
    Identify deals with no associated contact, or deals linked to a
    contact that no longer exists in the contacts table. Orphaned deals
    corrupt pipeline reporting, inflate deal counts, and cause workflow
    errors when automation attempts to access the associated contact record.

  Use Case:
    Run monthly as part of CRM maintenance. Orphaned deals should be
    investigated and either re-linked to the correct contact or archived.
    High orphan counts after a data migration or import indicate that the
    contact matching step during the import failed and needs to be rerun.

  Tables Used:
    deals    — deal records with contact_id foreign key
    contacts — to validate that associated contacts exist
*/

WITH deal_contact_status AS (

  SELECT
    d.deal_id,
    d.deal_name,
    d.contact_id,
    d.stage,
    d.amount,
    d.close_date,
    d.created_at,
    d.owner_id,

    -- Is the contact_id NULL? (deal was created without a contact)
    CASE WHEN d.contact_id IS NULL THEN 1 ELSE 0 END  AS has_null_contact,

    -- Does the referenced contact still exist?
    CASE WHEN c.contact_id IS NULL
          AND d.contact_id IS NOT NULL
         THEN 1 ELSE 0 END                            AS contact_deleted,

    c.email        AS contact_email,
    c.first_name   AS contact_first_name,
    c.last_name    AS contact_last_name,
    c.lifecycle_stage AS contact_lifecycle_stage

  FROM deals d
  LEFT JOIN contacts c ON c.contact_id = d.contact_id

)

SELECT
  deal_id,
  deal_name,
  contact_id,
  stage,
  ROUND(amount, 2)   AS amount,
  close_date,
  created_at,
  owner_id,
  contact_email,
  contact_first_name,
  contact_last_name,
  contact_lifecycle_stage,

  CASE
    WHEN has_null_contact = 1  THEN 'No contact assigned'
    WHEN contact_deleted  = 1  THEN 'Contact record deleted'
  END AS orphan_type,

  CASE
    WHEN has_null_contact = 1  THEN 'Assign to correct contact or archive deal'
    WHEN contact_deleted  = 1  THEN 'Restore contact or re-link deal to existing contact'
  END AS recommended_action

FROM deal_contact_status
WHERE has_null_contact = 1
   OR contact_deleted  = 1
ORDER BY created_at DESC;

/*
  Sample Output:

  deal_id  | deal_name           | contact_id | stage       | amount   | orphan_type               | recommended_action
  ---------|---------------------|------------|-------------|----------|---------------------------|------------------------------------
  d_1042   | Enterprise Q4 Deal  | NULL       | prospecting | 12,000   | No contact assigned       | Assign to correct contact or archive deal
  d_0871   | SMB Renewal         | c_deleted  | qualified   |  2,400   | Contact record deleted    | Restore contact or re-link deal to existing contact

  Summary Query:
    SELECT orphan_type, COUNT(*) AS deal_count, ROUND(SUM(amount), 2) AS at_risk_revenue
    FROM ( <this query> ) t
    GROUP BY orphan_type;

  Logic Notes:
    - Deals in closed stages (closed_won, closed_lost) with orphaned contacts
      are lower priority than open pipeline deals since they do not affect
      active workflows. Filter by stage to triage by business impact.
    - A sudden spike in orphaned deals often indicates a batch delete of
      contacts without first reassigning their associated deals. Add a
      pre-delete check to your data governance process.
    - owner_id is included to route remediation tasks to the responsible
      sales rep or operations owner.

  Adapting to Other Platforms:
    HubSpot:    Deals without associated contacts are visible in the
                Deals view filtered by 'Associated Contact is unknown'.
                Use the Associations API to check and repair links.
    Salesforce: Query Opportunity where ContactId IS NULL or where
                the related Contact.IsDeleted = true.
    RD Station: Deals without a linked contact appear in the deals list
                with no contact association. Use the Deals API to identify
                and repair orphaned records.
    BigQuery:   LEFT JOIN and IS NULL logic is identical. No changes needed.
*/
