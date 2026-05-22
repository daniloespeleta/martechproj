# SQL para CRM & Marketing Operations

![SQL](https://img.shields.io/badge/SQL-MySQL%20%2F%20BigQuery-4479A1?style=flat)
![Queries](https://img.shields.io/badge/Queries-30-brightgreen?style=flat)
![License](https://img.shields.io/badge/License-MIT-green?style=flat)

> A library of 30 documented SQL queries for marketing analytics — covering customer segmentation, engagement scoring, campaign reporting, and data hygiene. Written for MySQL with BigQuery equivalency comments throughout. Designed for marketing analysts, CRM managers, and marketing operations professionals who need production-ready queries they can adapt to their own stack.

---

## Schema

All queries reference a generic CRM/marketing schema. Column names follow common conventions used by platforms like HubSpot, RD Station, and Salesforce — adapt as needed for your environment.

```sql
-- contacts
-- One row per contact/lead in the CRM
contact_id          VARCHAR(64)   PRIMARY KEY
email               VARCHAR(255)
first_name          VARCHAR(100)
last_name           VARCHAR(100)
company             VARCHAR(255)
job_title           VARCHAR(255)
country             CHAR(2)
state               CHAR(2)
city                VARCHAR(100)
lead_source         VARCHAR(100)  -- e.g. 'organic', 'paid', 'referral'
lifecycle_stage     VARCHAR(50)   -- e.g. 'lead', 'mql', 'sql', 'customer'
created_at          DATETIME
updated_at          DATETIME

-- deals
-- One row per deal/opportunity in the pipeline
deal_id             VARCHAR(64)   PRIMARY KEY
contact_id          VARCHAR(64)   FK → contacts.contact_id
deal_name           VARCHAR(255)
stage               VARCHAR(100)  -- e.g. 'prospecting', 'qualified', 'closed_won'
amount              DECIMAL(12,2)
currency            CHAR(3)
close_date          DATE
created_at          DATETIME
owner_id            VARCHAR(64)

-- campaigns
-- One row per marketing campaign
campaign_id         VARCHAR(64)   PRIMARY KEY
campaign_name       VARCHAR(255)
channel             VARCHAR(100)  -- e.g. 'email', 'paid_search', 'social', 'organic'
status              VARCHAR(50)   -- e.g. 'draft', 'active', 'paused', 'completed'
budget              DECIMAL(12,2)
start_date          DATE
end_date            DATE
created_at          DATETIME

-- campaign_contacts
-- Junction: which contacts were targeted by which campaign
campaign_id         VARCHAR(64)   FK → campaigns.campaign_id
contact_id          VARCHAR(64)   FK → contacts.contact_id
assigned_at         DATETIME
PRIMARY KEY (campaign_id, contact_id)

-- events
-- Behavioral events: email opens, clicks, page views, form submissions, purchases
event_id            VARCHAR(64)   PRIMARY KEY
contact_id          VARCHAR(64)   FK → contacts.contact_id
campaign_id         VARCHAR(64)   FK → campaigns.campaign_id  -- nullable
event_type          VARCHAR(100)  -- e.g. 'email_open', 'email_click', 'page_view',
                                  --      'form_submit', 'purchase', 'unsubscribe'
event_value         DECIMAL(12,2) -- revenue for purchases, null for other events
channel             VARCHAR(100)
occurred_at         DATETIME

-- orders
-- Transactional purchases linked to contacts
order_id            VARCHAR(64)   PRIMARY KEY
contact_id          VARCHAR(64)   FK → contacts.contact_id
campaign_id         VARCHAR(64)   FK → campaigns.campaign_id  -- attribution
total_amount        DECIMAL(12,2)
currency            CHAR(3)
status              VARCHAR(50)   -- e.g. 'completed', 'refunded', 'cancelled'
ordered_at          DATETIME
```

---

## Query Index

### Segmentation — 8 queries

| File | Query | Description |
|---|---|---|
| [`segmentation/01-rfm-segments.sql`](segmentation/01-rfm-segments.sql) | RFM Segmentation | Classifies contacts by Recency, Frequency and Monetary value into actionable tiers |
| [`segmentation/02-lifecycle-stage-breakdown.sql`](segmentation/02-lifecycle-stage-breakdown.sql) | Lifecycle Stage Breakdown | Distribution of contacts across funnel stages with conversion rates between them |
| [`segmentation/03-high-value-customers.sql`](segmentation/03-high-value-customers.sql) | High-Value Customers | Identifies top-revenue contacts by total spend and order frequency |
| [`segmentation/04-at-risk-customers.sql`](segmentation/04-at-risk-customers.sql) | At-Risk Customers | Flags previously active contacts who have gone silent based on recency thresholds |
| [`segmentation/05-lead-source-performance.sql`](segmentation/05-lead-source-performance.sql) | Lead Source Performance | Conversion rates and revenue by acquisition channel |
| [`segmentation/06-geographic-segmentation.sql`](segmentation/06-geographic-segmentation.sql) | Geographic Segmentation | Contact and revenue distribution by country and state |
| [`segmentation/07-firmographic-segmentation.sql`](segmentation/07-firmographic-segmentation.sql) | Firmographic Segmentation | B2B segmentation by company and job title patterns |
| [`segmentation/08-purchase-frequency-bands.sql`](segmentation/08-purchase-frequency-bands.sql) | Purchase Frequency Bands | Groups contacts by number of orders into frequency tiers for targeting |

### Engagement — 6 queries

| File | Query | Description |
|---|---|---|
| [`engagement/01-engagement-score.sql`](engagement/01-engagement-score.sql) | Engagement Score | Composite score weighted across opens, clicks, purchases and recency |
| [`engagement/02-email-activity-summary.sql`](engagement/02-email-activity-summary.sql) | Email Activity Summary | Per-contact email engagement metrics: open rate, click rate, last activity |
| [`engagement/03-inactive-contacts.sql`](engagement/03-inactive-contacts.sql) | Inactive Contacts | Contacts with no recorded event in a configurable lookback window |
| [`engagement/04-most-engaged-by-segment.sql`](engagement/04-most-engaged-by-segment.sql) | Most Engaged by Segment | Top-engaged contacts within each lifecycle stage |
| [`engagement/05-event-frequency-trend.sql`](engagement/05-event-frequency-trend.sql) | Event Frequency Trend | Monthly event volume trend per contact to identify engagement patterns |
| [`engagement/06-channel-engagement-comparison.sql`](engagement/06-channel-engagement-comparison.sql) | Channel Engagement Comparison | Side-by-side engagement metrics across email, social, paid and organic |

### Campaigns — 8 queries

| File | Query | Description |
|---|---|---|
| [`campaigns/01-campaign-performance-summary.sql`](campaigns/01-campaign-performance-summary.sql) | Campaign Performance Summary | Impressions, clicks, conversions and revenue per campaign |
| [`campaigns/02-email-campaign-metrics.sql`](campaigns/02-email-campaign-metrics.sql) | Email Campaign Metrics | Open rate, click rate, unsubscribe rate and revenue per email campaign |
| [`campaigns/03-funnel-conversion-rates.sql`](campaigns/03-funnel-conversion-rates.sql) | Funnel Conversion Rates | Step-by-step conversion rates from lead to closed deal |
| [`campaigns/04-campaign-roi.sql`](campaigns/04-campaign-roi.sql) | Campaign ROI | Revenue attributed to each campaign vs budget spent |
| [`campaigns/05-attributed-revenue.sql`](campaigns/05-attributed-revenue.sql) | Attributed Revenue | First-touch and last-touch revenue attribution by campaign and channel |
| [`campaigns/06-cohort-campaign-response.sql`](campaigns/06-cohort-campaign-response.sql) | Cohort Campaign Response | Purchase rate by contact cohort (acquisition month) after campaign exposure |
| [`campaigns/07-ab-test-results.sql`](campaigns/07-ab-test-results.sql) | A/B Test Results | Conversion rates, statistical lift and significance per campaign variant |
| [`campaigns/08-best-send-time.sql`](campaigns/08-best-send-time.sql) | Best Send Time | Open and click rates by day of week and hour for send-time optimization |

### Hygiene — 8 queries

| File | Query | Description |
|---|---|---|
| [`hygiene/01-duplicate-contacts.sql`](hygiene/01-duplicate-contacts.sql) | Duplicate Contacts | Identifies contacts sharing the same email address |
| [`hygiene/02-missing-required-fields.sql`](hygiene/02-missing-required-fields.sql) | Missing Required Fields | Contacts with null or empty values in critical CRM fields |
| [`hygiene/03-invalid-email-format.sql`](hygiene/03-invalid-email-format.sql) | Invalid Email Format | Detects malformed email addresses using pattern matching |
| [`hygiene/04-stale-lifecycle-stages.sql`](hygiene/04-stale-lifecycle-stages.sql) | Stale Lifecycle Stages | Contacts whose lifecycle stage has not been updated in over 90 days |
| [`hygiene/05-unsubscribed-in-active-campaigns.sql`](hygiene/05-unsubscribed-in-active-campaigns.sql) | Unsubscribed in Active Campaigns | Flags unsubscribed contacts still assigned to active campaigns |
| [`hygiene/06-orphaned-deals.sql`](hygiene/06-orphaned-deals.sql) | Orphaned Deals | Deals with no associated contact or with a deleted contact reference |
| [`hygiene/07-contact-update-audit.sql`](hygiene/07-contact-update-audit.sql) | Contact Update Audit | Contacts that have never been updated since creation |
| [`hygiene/08-data-completeness-report.sql`](hygiene/08-data-completeness-report.sql) | Data Completeness Report | Field-level completeness percentage across the entire contacts table |

---

## Usage

These queries are written for **MySQL 8.0+**. Each file includes a `-- BigQuery:` comment block where syntax differs, covering the most common incompatibilities:

| MySQL | BigQuery |
|---|---|
| `DATEDIFF(end, start)` | `DATE_DIFF(end, start, DAY)` |
| `GROUP_CONCAT(col)` | `STRING_AGG(col, ',')` |
| `IFNULL(col, val)` | `IFNULL(col, val)` *(identical)* |
| `NOW()` | `CURRENT_DATETIME()` |
| `DATE_FORMAT(col, '%Y-%m')` | `FORMAT_DATE('%Y-%m', col)` |

All queries are parameterized with clearly labeled constants at the top of each file so thresholds and lookback windows are easy to adjust without editing the core logic.

---

## Adapting to Your Schema

Each query includes a `-- Schema note:` comment at the top mapping the generic column names to common alternatives found in HubSpot, Salesforce, RD Station, and Klaviyo. Swap the table and column names to match your environment — the logic stays the same.

---

## License

Distributed under the **MIT License**. See [`LICENSE`](LICENSE) for details.

**Developed by Danilo Campos Espeleta**
