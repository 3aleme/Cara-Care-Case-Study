# Cara Care — Patient Touchpoints dbt Project

A dbt project built on **BigQuery** that transforms a flat patient-touchpoint export into a normalised object layer, calculates a monthly re-prescription rate KPI, and produces a touchpoint attribution model.

Built as part of the Cara Care Senior Data Architect case study.

---

## What This Project Does

Cara Care prescribes a digital health app to patients for 90-day periods. An operations team recorded all patient interactions (touchpoints) in a Google Sheet, which lives in BigQuery as a single flat table called `raw_patient_touchpoints`.

This project:

1. **Cleans and normalises** that flat table into four separate entities — patients, doctors, prescriptions, and touchpoints.
2. **Calculates the monthly re-prescription rate** — the fraction of prescriptions that led to a follow-up prescription, grouped by the month the prescription ended.
3. **Attributes re-prescription probability to touchpoint types** — for each touchpoint type, calculates `P(re-prescription | touchpoint_type)` as a conditional probability.

---

## Architecture

```
BigQuery (source)
    └── raw_patient_touchpoints          ← flat seed table (CSV → BigQuery via dbt seed)

dbt layers
    ├── staging/                         ← dataset: staging
    │   └── stg_raw_patient_touchpoints  ← view: rename columns, cast types, no logic
    │
    ├── intermediate/                    ← dataset: intermediate
    │   ├── int_patients                 ← one row per patient
    │   ├── int_doctors                  ← one row per doctor (surrogate key)
    │   ├── int_prescriptions            ← one row per prescription + re-prescription outcome
    │   └── int_touchpoints              ← one row per touchpoint event
    │
    └── marts/                           ← dataset: marts
        ├── monthly_represcription_rate  ← KPI: re-prescription rate by month
        └── mart_touchpoint_attribution  ← P(re-prescription | touchpoint_type)
```

Each layer lives in its own BigQuery dataset (`staging`, `intermediate`, `marts`) inside the `cara-care-case` GCP project. Staging models are views; intermediate and mart models are materialised as tables.

### Data model relationships

```
touchpoints → prescriptions → patients
                           → doctors
```

---

## Prerequisites

| Requirement | Detail |
|---|---|
| Python | 3.10+ |
| dbt-bigquery | 1.11+ |
| GCP project | `cara-care-case` |
| BigQuery datasets | `staging`, `intermediate`, `marts` |
| Service account keyfile | JSON with BigQuery Data Editor + Job User roles |

---

## Local Setup

### 1. Clone the repo

```bash
git clone <repo-url>
cd "Cara Care Case Study"
```

### 2. Create a Python virtual environment

```bash
python3 -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install dbt-bigquery
```

### 3. Configure dbt credentials

dbt reads credentials from `~/.dbt/profiles.yml` — this file lives outside the repo and must never be committed.

Create or update `~/.dbt/profiles.yml`:

```yaml
patient_touchpoints:
  target: dev
  outputs:
    dev:
      type: bigquery
      method: service-account
      project: cara-care-case
      dataset: patient_touchpoints
      keyfile: /path/to/your/keyfile.json
      location: EU
      threads: 4
      timeout_seconds: 300
```

Replace `/path/to/your/keyfile.json` with the path to a GCP service account key that has **BigQuery Data Editor** and **BigQuery Job User** roles on the `cara-care-case` project.

### 4. Verify the connection

```bash
.venv/bin/dbt debug --project-dir patient_touchpoints
```

### 5. Load the seed data

```bash
.venv/bin/dbt seed --project-dir patient_touchpoints
```

> If you need to regenerate the CSV from the original Excel file first:
> ```bash
> python3 Scripts/excel_to_csv.py
> ```

### 6. Build everything

```bash
.venv/bin/dbt build --project-dir patient_touchpoints
```

`dbt build` runs seed → models → tests in dependency order. 69 tests should pass.

---

## Project Structure

```
patient_touchpoints/
├── dbt_project.yml                   # project config and materialisation strategy
├── seeds/
│   └── raw_patient_touchpoints.csv   # source data loaded via dbt seed
├── models/
│   ├── staging/
│   │   ├── stg_raw_patient_touchpoints.sql
│   │   └── schema.yml
│   ├── intermediate/
│   │   ├── int_patients.sql
│   │   ├── int_doctors.sql
│   │   ├── int_prescriptions.sql
│   │   ├── int_touchpoints.sql
│   │   └── schema.yml
│   └── marts/
│       ├── monthly_represcription_rate.sql
│       ├── mart_touchpoint_attribution.sql
│       └── schema.yml
├── macros/
│   ├── generate_surrogate_key.sql    # MD5-based surrogate key macro
│   └── generate_schema_name.sql      # overrides dbt's default schema naming
├── tests/
│   └── assert_represcription_date_after_prescription_end.sql
└── analyses/                         # reserved for ad-hoc investigative queries
```

---

## Key Design Decisions

**Why four tables?**
The source table is fully denormalised — patient, doctor, prescription, and touchpoint data all repeat on every row. Normalising into four entities eliminates redundancy, makes each model independently testable, and follows 3NF.

**Why `prescription_end` as the KPI monthly anchor?**
Re-prescription is a sequel event that occurs after the prescription concludes. Grouping by `prescription_end` month means every prescription in a given cohort has already resolved — the rate is immediately meaningful with no lag adjustment required.

**Why conditional probability for attribution?**
`P(re-prescription | touchpoint_type)` is the most direct statistical summary of the attribution question given observational data. A ML model (logistic regression, feature importance) would be more rigorous but was out of scope. The SQL model is transparent and fully reproducible within dbt.

**Why separate BigQuery datasets per layer?**
Isolating `staging`, `intermediate`, and `marts` prevents analysts from accidentally querying half-built tables and makes the lineage immediately visible in the BigQuery console.

For the full rationale behind every decision, see [`MYNotes.txt`](../MYNotes.txt) and [`Solution.md`](../Solution.md) at the project root.

---

## Handing Over This Project

The three things a new engineer needs to understand before touching this repo:

1. **The data lives in BigQuery, not in this repo.** The CSV seed is the original source snapshot — in production it would be replaced by a live BigQuery source table. All models run against `cara-care-case` in GCP. You need a service account key and `~/.dbt/profiles.yml` configured to connect.

2. **The intermediate layer is the object layer.** The four `int_*` tables are the canonical, tested representation of patients, doctors, prescriptions, and touchpoints. Downstream models and any new analysis should build on these, not on staging or the raw seed.

3. **The mart models are the deliverables.** `monthly_represcription_rate` answers the KPI question; `mart_touchpoint_attribution` answers the attribution question. If the business question changes, these are the files to update — the object layer beneath them does not need to change.
