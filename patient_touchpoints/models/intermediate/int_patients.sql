WITH staged AS (
    SELECT * FROM {{ ref('stg_raw_patient_touchpoints') }}
),

patients AS (
    SELECT
        patient_id,
        email,
        date_of_birth,
        insurance_name,
        insurance_type
    FROM staged
    GROUP BY 1, 2, 3, 4, 5
)

SELECT * FROM patients
