WITH prescriptions AS (
    SELECT
        prescription_id,
        has_represcription
    FROM {{ ref('int_prescriptions') }}
),

-- One row per prescription × touchpoint_type (deduplicates same-type touchpoints
-- within a prescription so each prescription is counted at most once per type)
prescription_touchpoints AS (
    SELECT DISTINCT
        prescription_id,
        touchpoint_type
    FROM {{ ref('int_touchpoints') }}
),

attribution AS (
    SELECT
        pt.touchpoint_type,
        COUNT(*)                                                    AS prescriptions_with_touchpoint,
        COUNTIF(p.has_represcription)                               AS represcribed_prescriptions,
        ROUND(
            1.0 * COUNTIF(p.has_represcription) / COUNT(*),
            4
        )                                                           AS p_represcription_given_touchpoint
    FROM prescription_touchpoints pt
    INNER JOIN prescriptions p USING (prescription_id)
    GROUP BY pt.touchpoint_type
)

SELECT
    touchpoint_type,
    prescriptions_with_touchpoint,
    represcribed_prescriptions,
    p_represcription_given_touchpoint
FROM attribution
ORDER BY p_represcription_given_touchpoint DESC
