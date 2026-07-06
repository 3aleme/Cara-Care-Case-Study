WITH source AS (
    SELECT * FROM {{ ref('raw_patient_touchpoints') }}
),

staged AS (
    SELECT
        patient_id,
        patient_email                                               AS email,
        date_of_birth,
        insurance_name,
        insurance_type,

        prescription_id,
        prescription_start,
        prescription_end,
        prescription_status,

        prescribing_doctor                                          AS doctor_name,
        doctor_specialty,
        doctor_city,

        touchpoint_date,
        touchpoint_type,
        touchpoint_channel,
        touchpoint_outcome,

        CASE
            WHEN LOWER(represcription) = 'ja'   THEN TRUE
            WHEN LOWER(represcription) = 'nein' THEN FALSE
            ELSE NULL
        END                                                         AS has_represcription,
        represcription_date

    FROM source
)

SELECT * FROM staged
