WITH staged AS (
    SELECT * FROM {{ ref('stg_raw_patient_touchpoints') }}
),

prescriptions AS (
    SELECT
        prescription_id,
        patient_id,
        {{ generate_surrogate_key(['doctor_name', 'doctor_specialty', 'doctor_city']) }} AS doctor_id,
        prescription_start,
        prescription_end,
        prescription_status,
        has_represcription,
        represcription_date
    FROM staged
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8
)

SELECT * FROM prescriptions
