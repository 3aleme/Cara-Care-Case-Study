WITH staged AS (
    SELECT * FROM {{ ref('stg_raw_patient_touchpoints') }}
),

touchpoints AS (
    SELECT
        {{ generate_surrogate_key(['prescription_id', 'touchpoint_type', 'touchpoint_date']) }} AS touchpoint_id,
        prescription_id,
        touchpoint_date,
        touchpoint_type,
        touchpoint_channel,
        touchpoint_outcome
    FROM staged
    GROUP BY 2, 3, 4, 5, 6
)

SELECT * FROM touchpoints
