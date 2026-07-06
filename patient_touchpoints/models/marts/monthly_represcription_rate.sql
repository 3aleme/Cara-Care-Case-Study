WITH prescriptions AS (
    SELECT * FROM {{ ref('int_prescriptions') }}
)

SELECT
    DATE_TRUNC(prescription_end, MONTH)                                                 AS month,
    COUNT(CASE WHEN has_represcription THEN prescription_id ELSE NULL END)              AS represcribed_prescriptions,
    COUNT(*)                                                                             AS total_prescriptions,
    1.0 * COUNT(CASE WHEN has_represcription THEN prescription_id ELSE NULL END)
        / COUNT(*)                                                                       AS represcription_rate
FROM prescriptions
GROUP BY 1
ORDER BY 1
