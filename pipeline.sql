/*
================================================================================
  VEHICLE INVENTORY HEALTH ANALYTICS PIPELINE
================================================================================
  Business Goal : Identify slow-moving inventory and track vehicle aging.
  Source        : VEHICLE_DB.PUBLIC.VEHICLE_INVENTORY
  Target        : VEHICLE_DB.VEHICLE_SCHEMA.INVENTORY_HEALTH (materialized)

  Pipeline Objects:
    1. VEHICLE_DB.PUBLIC.VEHICLE_INVENTORY          - Source table
    2. VEHICLE_DB.VEHICLE_SCHEMA.INVENTORY_HEALTH   - Materialized analytics table
    3. VEHICLE_DB.VEHICLE_SCHEMA.SP_REFRESH_INVENTORY_HEALTH - Refresh procedure
    4. VEHICLE_DB.VEHICLE_SCHEMA.VW_INVENTORY_HEALTH_METRICS - Aggregated KPIs
    5. VEHICLE_DB.VEHICLE_SCHEMA.VW_DATA_QUALITY_CHECKS      - Data quality checks
    6. VEHICLE_DB.VEHICLE_SCHEMA.VW_AGING_RISK_FORECAST      - 15-day aging forecast

  Aging Categories:
    GREEN  : < 50 days on lot (healthy turnover)
    YELLOW : 51-80 days on lot (monitor closely)
    RED    : > 80 days on lot (slow-moving, action needed)

  Refresh Strategy:
    Call SP_REFRESH_INVENTORY_HEALTH() to truncate and reload
    INVENTORY_HEALTH from the source table. Schedule via Snowflake Task
    or external orchestrator as needed.
================================================================================
*/

-- ============================================================================
-- STEP 1: Create Database and Schema
-- ============================================================================
CREATE DATABASE IF NOT EXISTS VEHICLE_DB;
CREATE SCHEMA IF NOT EXISTS VEHICLE_DB.VEHICLE_SCHEMA;

-- ============================================================================
-- STEP 2: Create Source Table
-- ============================================================================
CREATE TABLE IF NOT EXISTS VEHICLE_DB.PUBLIC.VEHICLE_INVENTORY (
    vehicle_id       INT NOT NULL,
    vin              VARCHAR(17) NOT NULL,
    make             VARCHAR(50) NOT NULL,
    model            VARCHAR(50) NOT NULL,
    dealer_id        INT NOT NULL,
    acquisition_date DATE NOT NULL,
    current_price    NUMBER(12,2) NOT NULL,
    status           VARCHAR(20) NOT NULL
);

-- ============================================================================
-- STEP 3: Create Target Table (INVENTORY_HEALTH)
-- ============================================================================
CREATE OR REPLACE TABLE VEHICLE_DB.VEHICLE_SCHEMA.INVENTORY_HEALTH AS
SELECT
    vehicle_id,
    vin,
    make,
    model,
    dealer_id,
    acquisition_date,
    current_price,
    status,
    DATEDIFF(day, acquisition_date, CURRENT_DATE()) AS days_on_lot,
    CASE
        WHEN DATEDIFF(day, acquisition_date, CURRENT_DATE()) < 50 THEN 'GREEN'
        WHEN DATEDIFF(day, acquisition_date, CURRENT_DATE()) BETWEEN 51 AND 80 THEN 'YELLOW'
        ELSE 'RED'
    END AS aging_category,
    CASE
        WHEN DATEDIFF(day, acquisition_date, CURRENT_DATE()) > 80 THEN TRUE
        ELSE FALSE
    END AS is_slow_moving,
    CURRENT_TIMESTAMP() AS last_refreshed_at
FROM VEHICLE_DB.PUBLIC.VEHICLE_INVENTORY;

-- ============================================================================
-- STEP 4: Create Refresh Stored Procedure
-- ============================================================================
CREATE OR REPLACE PROCEDURE VEHICLE_DB.VEHICLE_SCHEMA.SP_REFRESH_INVENTORY_HEALTH()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
BEGIN
    TRUNCATE TABLE VEHICLE_DB.VEHICLE_SCHEMA.INVENTORY_HEALTH;

    INSERT INTO VEHICLE_DB.VEHICLE_SCHEMA.INVENTORY_HEALTH
    SELECT
        vehicle_id,
        vin,
        make,
        model,
        dealer_id,
        acquisition_date,
        current_price,
        status,
        DATEDIFF(day, acquisition_date, CURRENT_DATE()) AS days_on_lot,
        CASE
            WHEN DATEDIFF(day, acquisition_date, CURRENT_DATE()) < 50 THEN 'GREEN'
            WHEN DATEDIFF(day, acquisition_date, CURRENT_DATE()) BETWEEN 51 AND 80 THEN 'YELLOW'
            ELSE 'RED'
        END AS aging_category,
        CASE
            WHEN DATEDIFF(day, acquisition_date, CURRENT_DATE()) > 80 THEN TRUE
            ELSE FALSE
        END AS is_slow_moving,
        CURRENT_TIMESTAMP() AS last_refreshed_at
    FROM VEHICLE_DB.PUBLIC.VEHICLE_INVENTORY;

    RETURN 'INVENTORY_HEALTH refreshed successfully at ' || CURRENT_TIMESTAMP()::VARCHAR;
END;
$$;

-- ============================================================================
-- STEP 5: Create Inventory Health Metrics View
-- ============================================================================
CREATE OR REPLACE VIEW VEHICLE_DB.VEHICLE_SCHEMA.VW_INVENTORY_HEALTH_METRICS AS
WITH category_summary AS (
    SELECT
        aging_category,
        COUNT(*) AS vehicle_count,
        ROUND(AVG(days_on_lot), 1) AS avg_days_on_lot,
        SUM(current_price) AS total_value
    FROM VEHICLE_DB.VEHICLE_SCHEMA.INVENTORY_HEALTH
    WHERE status != 'SOLD'
    GROUP BY aging_category
),
dealer_summary AS (
    SELECT
        dealer_id,
        COUNT(*) AS total_vehicles,
        ROUND(AVG(days_on_lot), 1) AS avg_days_on_lot,
        SUM(CASE WHEN aging_category = 'RED' THEN 1 ELSE 0 END) AS red_count,
        SUM(CASE WHEN aging_category = 'RED' THEN current_price ELSE 0 END) AS value_at_risk
    FROM VEHICLE_DB.VEHICLE_SCHEMA.INVENTORY_HEALTH
    WHERE status != 'SOLD'
    GROUP BY dealer_id
),
overall AS (
    SELECT
        COUNT(*) AS total_active_vehicles,
        ROUND(AVG(days_on_lot), 1) AS overall_avg_days,
        SUM(CASE WHEN is_slow_moving THEN 1 ELSE 0 END) AS slow_moving_count,
        ROUND(SUM(CASE WHEN is_slow_moving THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0), 1) AS slow_moving_pct,
        SUM(CASE WHEN aging_category = 'RED' THEN current_price ELSE 0 END) AS total_value_at_risk,
        SUM(current_price) AS total_inventory_value
    FROM VEHICLE_DB.VEHICLE_SCHEMA.INVENTORY_HEALTH
    WHERE status != 'SOLD'
)
SELECT
    'OVERALL' AS metric_level,
    NULL AS dimension_value,
    total_active_vehicles AS vehicle_count,
    overall_avg_days AS avg_days_on_lot,
    slow_moving_count,
    slow_moving_pct,
    total_value_at_risk,
    total_inventory_value
FROM overall

UNION ALL

SELECT
    'AGING_CATEGORY' AS metric_level,
    aging_category AS dimension_value,
    vehicle_count,
    avg_days_on_lot,
    NULL AS slow_moving_count,
    ROUND(vehicle_count * 100.0 / NULLIF(SUM(vehicle_count) OVER (), 0), 1) AS slow_moving_pct,
    CASE WHEN aging_category = 'RED' THEN total_value ELSE 0 END AS total_value_at_risk,
    total_value AS total_inventory_value
FROM category_summary

UNION ALL

SELECT
    'DEALER' AS metric_level,
    dealer_id::VARCHAR AS dimension_value,
    total_vehicles AS vehicle_count,
    avg_days_on_lot,
    red_count AS slow_moving_count,
    ROUND(red_count * 100.0 / NULLIF(total_vehicles, 0), 1) AS slow_moving_pct,
    value_at_risk AS total_value_at_risk,
    NULL AS total_inventory_value
FROM dealer_summary;

-- ============================================================================
-- STEP 6: Create Data Quality Checks View
-- ============================================================================
CREATE OR REPLACE VIEW VEHICLE_DB.VEHICLE_SCHEMA.VW_DATA_QUALITY_CHECKS AS
WITH null_checks AS (
    SELECT
        'NULL_CHECK' AS check_type,
        'vehicle_id is NULL' AS check_description,
        COUNT(*) AS records_failed
    FROM VEHICLE_DB.PUBLIC.VEHICLE_INVENTORY
    WHERE vehicle_id IS NULL

    UNION ALL

    SELECT 'NULL_CHECK', 'vin is NULL', COUNT(*)
    FROM VEHICLE_DB.PUBLIC.VEHICLE_INVENTORY
    WHERE vin IS NULL

    UNION ALL

    SELECT 'NULL_CHECK', 'acquisition_date is NULL', COUNT(*)
    FROM VEHICLE_DB.PUBLIC.VEHICLE_INVENTORY
    WHERE acquisition_date IS NULL

    UNION ALL

    SELECT 'NULL_CHECK', 'current_price is NULL', COUNT(*)
    FROM VEHICLE_DB.PUBLIC.VEHICLE_INVENTORY
    WHERE current_price IS NULL
),
duplicate_checks AS (
    SELECT
        'DUPLICATE_CHECK' AS check_type,
        'Duplicate VINs detected' AS check_description,
        COUNT(*) - COUNT(DISTINCT vin) AS records_failed
    FROM VEHICLE_DB.PUBLIC.VEHICLE_INVENTORY
),
validity_checks AS (
    SELECT
        'VALIDITY_CHECK' AS check_type,
        'acquisition_date in the future' AS check_description,
        COUNT(*) AS records_failed
    FROM VEHICLE_DB.PUBLIC.VEHICLE_INVENTORY
    WHERE acquisition_date > CURRENT_DATE()

    UNION ALL

    SELECT 'VALIDITY_CHECK', 'current_price <= 0', COUNT(*)
    FROM VEHICLE_DB.PUBLIC.VEHICLE_INVENTORY
    WHERE current_price <= 0

    UNION ALL

    SELECT
        'VALIDITY_CHECK',
        'status not in expected values (AVAILABLE, RESERVED, SOLD)',
        COUNT(*)
    FROM VEHICLE_DB.PUBLIC.VEHICLE_INVENTORY
    WHERE status NOT IN ('AVAILABLE', 'RESERVED', 'SOLD')
)
SELECT
    check_type,
    check_description,
    records_failed,
    CASE WHEN records_failed = 0 THEN 'PASS' ELSE 'FAIL' END AS check_result,
    CURRENT_TIMESTAMP() AS checked_at
FROM null_checks
UNION ALL
SELECT check_type, check_description, records_failed,
    CASE WHEN records_failed = 0 THEN 'PASS' ELSE 'FAIL' END, CURRENT_TIMESTAMP()
FROM duplicate_checks
UNION ALL
SELECT check_type, check_description, records_failed,
    CASE WHEN records_failed = 0 THEN 'PASS' ELSE 'FAIL' END, CURRENT_TIMESTAMP()
FROM validity_checks;

-- ============================================================================
-- STEP 7: Create Aging Risk Forecast View (15-day lookahead)
-- ============================================================================
CREATE OR REPLACE VIEW VEHICLE_DB.VEHICLE_SCHEMA.VW_AGING_RISK_FORECAST AS
SELECT
    vehicle_id,
    vin,
    make,
    model,
    dealer_id,
    acquisition_date,
    current_price,
    status,
    days_on_lot,
    aging_category AS current_category,
    days_on_lot + 15 AS projected_days_on_lot,
    CASE
        WHEN days_on_lot + 15 < 50 THEN 'GREEN'
        WHEN days_on_lot + 15 BETWEEN 51 AND 80 THEN 'YELLOW'
        ELSE 'RED'
    END AS projected_category,
    CASE
        WHEN aging_category = 'GREEN' AND days_on_lot + 15 >= 50 THEN TRUE
        WHEN aging_category = 'YELLOW' AND days_on_lot + 15 > 80 THEN TRUE
        ELSE FALSE
    END AS at_risk,
    CASE
        WHEN aging_category = 'GREEN' THEN 50 - days_on_lot
        WHEN aging_category = 'YELLOW' THEN 81 - days_on_lot
        ELSE NULL
    END AS days_until_transition,
    CASE
        WHEN aging_category = 'GREEN' AND days_on_lot + 15 >= 50 THEN 'GREEN -> YELLOW'
        WHEN aging_category = 'YELLOW' AND days_on_lot + 15 > 80 THEN 'YELLOW -> RED'
        ELSE NULL
    END AS risk_transition
FROM VEHICLE_DB.VEHICLE_SCHEMA.INVENTORY_HEALTH
WHERE status != 'SOLD';

-- ============================================================================
-- USAGE EXAMPLES
-- ============================================================================

-- Refresh the INVENTORY_HEALTH table:
-- CALL VEHICLE_DB.VEHICLE_SCHEMA.SP_REFRESH_INVENTORY_HEALTH();

-- View overall and per-category metrics:
-- SELECT * FROM VEHICLE_DB.VEHICLE_SCHEMA.VW_INVENTORY_HEALTH_METRICS;

-- Run data quality checks:
-- SELECT * FROM VEHICLE_DB.VEHICLE_SCHEMA.VW_DATA_QUALITY_CHECKS;

-- Find all RED (slow-moving) vehicles:
-- SELECT * FROM VEHICLE_DB.VEHICLE_SCHEMA.INVENTORY_HEALTH
-- WHERE aging_category = 'RED' AND status = 'AVAILABLE'
-- ORDER BY days_on_lot DESC;

-- View vehicles at risk of aging within 15 days:
-- SELECT * FROM VEHICLE_DB.VEHICLE_SCHEMA.VW_AGING_RISK_FORECAST
-- WHERE at_risk = TRUE
-- ORDER BY days_until_transition ASC;
