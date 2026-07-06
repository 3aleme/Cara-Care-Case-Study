WITH staged AS (
    SELECT * FROM {{ ref('stg_raw_patient_touchpoints') }}
),

doctors AS (
    SELECT
        {{ generate_surrogate_key(['doctor_name', 'doctor_specialty', 'doctor_city']) }} AS doctor_id,
        doctor_name,
        doctor_specialty,
        doctor_city
    FROM staged
    GROUP BY 2, 3, 4
)

SELECT * FROM doctors
