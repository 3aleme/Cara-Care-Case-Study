# Cara Care — Senior Data Architect Case Study
**Hassan Alame · July 2026**

---

## General Observations

The source data is a single flat table where every row represents a touchpoint event. Patient details, prescription details, doctor details, and touchpoint details all repeat on every row. There are 16 rows in total, covering 4 unique prescriptions across a small number of patients.

A few things stood out immediately:

- **The data is denormalised by design** — it reflects how an operations team collected data in a Google Sheet, not how a data platform would store it. The first task is therefore not optional groundwork; it is the foundation every subsequent question depends on.
- **The business question is underspecified** — "which touchpoint contributes most to re-prescription?" cannot be answered without first defining what re-prescription rate means (which date anchors it, at what granularity), and what kind of attribution model is appropriate given the data available.
- **The sample is very small** — 4 prescriptions and 16 touchpoint rows. Any statistical output from this data carries wide uncertainty. The analytical work is sound, but conclusions drawn from it should be treated as directional, not definitive.

---

## Task 1: Create Object Layer

### What Is Being Asked

Design a clean, normalised object layer in dbt derived from the flat source table. For each table: name, columns with data types, primary key, and foreign key relationships.

### How We Interpret the Question

The flat table conflates four distinct real-world entities — patients, doctors, prescriptions, and touchpoints — into a single row structure. Normalising this means extracting each entity into its own table, keeping only the attributes that belong to it, and expressing the relationships between entities as foreign keys.

This is not just an exercise in table design. A clean object layer is the prerequisite for every downstream query. Without it, any aggregation risks double-counting, any join risks fan-outs, and any data quality issue is invisible until it corrupts a KPI.

### Assumptions

**Doctor identity (no source ID exists)**
The source data has no unique identifier for doctors. It only contains `doctor_name`, `doctor_specialty`, and `doctor_city`. We generate a surrogate key from the combination of these three fields using an MD5 hash. This works as long as no two different doctors share the same name, specialty, and city simultaneously. In production, Cara Care's actual doctor ID should replace this surrogate entirely.

**Prescription ID as a natural key**
The source data includes a `prescription_id` field (e.g. RX-2001). We treat this as a globally unique, stable natural key issued by the backend system and do not generate a surrogate for prescriptions.

**Touchpoint ID (no source ID exists)**
Touchpoints have no unique identifier in the source data. We generate a surrogate key from `prescription_id + touchpoint_type + touchpoint_date`, on the assumption that a patient cannot receive two touchpoints of the same type on the same day within the same prescription period.

**Re-prescription belongs to the prescription, not the touchpoint**
In the source data, the `represcription` and `represcription_date` fields carry the same value across every touchpoint row belonging to the same prescription. We therefore treat re-prescription as an outcome of the prescription period and place `has_represcription` and `represcription_date` on the prescriptions table, not on touchpoints.

### Decisions

**Four tables, snowflake schema**
We normalised into `patients`, `doctors`, `prescriptions`, and `touchpoints`. The relationship chain is: touchpoints → prescriptions → patients and doctors. This is a snowflake schema rather than a star schema. It avoids redundancy, makes data corrections surgical, and creates clean model boundaries in dbt — each model has a single, well-defined responsibility.

**Layered dbt architecture**
Models are organised into three layers: staging (raw data cleaning, no business logic), intermediate (business logic, the object layer), and marts (analytics-ready outputs consumed by BI tools or analysts). Intermediate models are materialised as tables in BigQuery rather than views to avoid re-executing the same transformation multiple times when multiple downstream models reference them.

**Separate BigQuery datasets per layer**
Each layer is isolated in its own dataset (`staging`, `intermediate`, `marts`) rather than all landing in a single dataset. This prevents analysts from accidentally querying staging or intermediate tables and mirrors how production data platforms are typically organised.

### Results

| Table | Description | Link |
|---|---|---|
| `int_patients` | One row per unique patient | [Open in BigQuery](https://console.cloud.google.com/bigquery?project=cara-care-case&p=cara-care-case&d=intermediate&t=int_patients&page=table) |
| `int_doctors` | One row per unique doctor (surrogate key) | [Open in BigQuery](https://console.cloud.google.com/bigquery?project=cara-care-case&p=cara-care-case&d=intermediate&t=int_doctors&page=table) |
| `int_prescriptions` | One row per prescription with re-prescription outcome | [Open in BigQuery](https://console.cloud.google.com/bigquery?project=cara-care-case&p=cara-care-case&d=intermediate&t=int_prescriptions&page=table) |
| `int_touchpoints` | One row per touchpoint event | [Open in BigQuery](https://console.cloud.google.com/bigquery?project=cara-care-case&p=cara-care-case&d=intermediate&t=int_touchpoints&page=table) |

---

## Task 2: Calculate Monthly Re-prescription Rate

### What Is Being Asked

Write a SQL query in BigQuery syntax that calculates the monthly re-prescription rate, using the object layer from Task 1 as the basis.

### How We Interpret the Question

"Monthly re-prescription rate" is not uniquely defined by the question. Before writing any SQL, three dimensions needed to be resolved:

1. **Which date defines "monthly"?** Three candidates exist: `prescription_start`, `prescription_end`, and `represcription_date`. Each produces a different metric.
2. **What is the base unit?** Is the rate per touchpoint, per prescription, or per patient?
3. **What is the aggregation granularity?** One rate for the whole dataset, or one rate per month?

### Assumptions

**prescription_end as the monthly anchor**
We chose `prescription_end` rather than `prescription_start` or `represcription_date`. Since re-prescription is a sequel event that occurs after the prescription concludes, grouping by the month the prescription ended groups prescriptions by when their outcome became known. Every prescription in a given month's cohort has already resolved by definition — the rate is immediately meaningful with no lag adjustment required.

**Prescription granularity, not patient or touchpoint**
The naming "re-prescription rate" implies prescription granularity. Re-prescription is confirmed by the data to be a sequel event occurring after `prescription_end`, making it an attribute of the prescription period rather than a behaviour of individual patients or touchpoints.

**COUNT(\*) is safe here**
A prescription is valid for 90 days. It is therefore impossible for a patient to have two prescriptions starting within the same calendar month — the first would still be active for the entirety of that month. This guarantees one row per prescription within any monthly cohort, making `COUNT(*)` and `COUNT(DISTINCT prescription_id)` equivalent. We use `COUNT(*)` to avoid the additional cost of a distinct aggregation in BigQuery.

### Decisions

**DATE_TRUNC on prescription_end**
Returns the first day of the month as a native `DATE` type, which BI tools order and filter correctly without casting.

**CASE WHEN for the numerator**
`COUNT(CASE WHEN has_represcription THEN 1 END)` returns `NULL` for non-represcribers, which `COUNT` ignores. This avoids a subquery.

**Float division via 1.0 multiplier**
Without `1.0 *`, BigQuery integer division returns 0 for any rate between 0 and 1.

### Results

| Model | Description | Link |
|---|---|---|
| `monthly_represcription_rate` | One row per month: represcribed count, total count, and rate | [Open in BigQuery](https://console.cloud.google.com/bigquery?project=cara-care-case&p=cara-care-case&d=marts&t=monthly_represcription_rate&page=table) |

---

## Task 3: Touchpoint Attribution

### What Is Being Asked

Propose an analytical approach to answer: "Which touchpoint contributes the most to re-prescription?" Describe the limitations of the approach.

### How We Interpret the Question

This is a statistical attribution question: given what happened to a patient during their 90-day prescription period, which touchpoint type is most associated with the outcome of re-prescribing?

Before settling on an approach, we considered the right analytical framing. The gold standard would be a randomised controlled trial — a holdout group that received no touchpoints, allowing us to isolate the causal effect of each one. That data does not exist. What we have is observational data: patients received touchpoints as part of normal operations, and some re-prescribed and some did not. In this setting, the honest approach is to measure association rather than claim causation.

### Assumptions

**Conditional probability as the metric**
We frame the question as: given that a patient received a particular type of touchpoint, what is the probability their prescription ended in a re-prescription? This is `P(re-prescription | touchpoint_type)`. It is the most direct statistical summary of the attribution question given observational data.

**One row per prescription per touchpoint type**
A prescription may contain multiple touchpoints of the same type on different dates. We deduplicate to one row per `(prescription_id, touchpoint_type)` pair before counting, so a prescription is counted at most once per type regardless of how many times that touchpoint was delivered.

### Decisions

**Conditional probability, implemented in SQL within dbt**
For each touchpoint type: count the prescriptions that included it, count how many of those re-prescribed, divide. The result is a ranked table of touchpoint types ordered by their conditional probability of leading to a re-prescription.

**Why not a Python ML model?**
A logistic regression or gradient boosting model trained on features such as touchpoint type, channel, sequence position, and timing relative to prescription end would capture interaction effects and the time dimension that a simple conditional probability cannot. A feature importance plot from such a model would give a more complete and statistically robust answer.

We opted for the SQL conditional probability approach for two reasons: simplicity and time. The model is transparent, reproducible entirely within dbt, and demonstrates a statistically grounded interpretation of the attribution question without requiring a separate Python pipeline. The ML route is the documented next step.

**Where this model lives in dbt**
Technically, this query belongs in the `analyses/` folder rather than `models/marts/`. The `analyses/` folder is for investigative queries that dbt compiles but does not materialise — exactly what this is. `monthly_represcription_rate` is an operational KPI that runs on a schedule; touchpoint attribution is a one-off analytical deep-dive. We placed it in `models/marts/` for this case study to allow dbt schema tests to validate the output, but note that `analyses/` would be the correct home in a production project.

### Limitations

**No time dimension**
The model treats a touchpoint on day 2 and one on day 88 as equivalent. Temporal proximity to the re-prescription decision is entirely ignored. A richer model would weight touchpoints by recency or explicitly model the number of days between each touchpoint and the re-prescription date.

**No causality**
The data is observational. Patients who received more touchpoints may already differ from those who received fewer in ways we cannot measure — disease severity, motivation, engagement level. The conditional probability captures association, not causal effect.

**No control group**
Without a randomised holdout of patients who received zero touchpoints, it is impossible to isolate the marginal effect of any individual touchpoint type.

**Small sample**
The dataset contains 4 unique prescriptions. Any probability calculated from a denominator this small carries enormous uncertainty. No statistical significance can be claimed.

**We omitted counting out unsuccessful touchpoints**
We counted touchpoints which might have "Incomplete", "Failed", "Dismissed", but we should not have.

### Results

| Model | Description | Link |
|---|---|---|
| `mart_touchpoint_attribution` | One row per touchpoint type, ordered by P(re-prescription \| touchpoint_type) descending | [Open in BigQuery](https://console.cloud.google.com/bigquery?project=cara-care-case&p=cara-care-case&d=marts&t=mart_touchpoint_attribution&page=table) |
