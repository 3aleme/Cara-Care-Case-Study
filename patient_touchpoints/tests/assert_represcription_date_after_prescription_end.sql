SELECT
    prescription_id,
    prescription_end,
    represcription_date
FROM {{ ref('int_prescriptions') }}
WHERE
    represcription_date IS NOT NULL
    AND represcription_date < prescription_end
