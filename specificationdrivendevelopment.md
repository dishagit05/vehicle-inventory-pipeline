# Specification-Driven Development: Vehicle Inventory Health Analytics

## 1. Project Overview

| Field | Value |
|-------|-------|
| **Project Name** | Vehicle Inventory Health Analytics Pipeline |
| **Business Goal** | Identify slow-moving inventory and track vehicle aging across dealerships |
| **Owner** | Data Analytics Team |
| **Platform** | Snowflake + Streamlit |
| **Repository** | https://github.com/dishagit05/vehicle-inventory-pipeline |

## 2. Business Requirements

### 2.1 Problem Statement
Dealerships lack visibility into aging inventory, resulting in capital tied up in slow-moving vehicles. There is no automated system to flag vehicles approaching critical aging thresholds or to provide actionable metrics for inventory management decisions.

### 2.2 Success Criteria
- Real-time categorization of all vehicles by aging status (GREEN/YELLOW/RED)
- Proactive identification of vehicles at risk of aging within 15 days
- Dealer-level and make-level inventory health metrics
- Data quality monitoring with automated checks
- Interactive dashboard for stakeholders

## 3. Functional Specifications

### 3.1 Data Model

#### Source Table: `VEHICLE_DB.PUBLIC.VEHICLE_INVENTORY`

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| vehicle_id | INT | NO | Unique vehicle identifier |
| vin | VARCHAR(17) | NO | Vehicle Identification Number |
| make | VARCHAR(50) | NO | Vehicle manufacturer |
| model | VARCHAR(50) | NO | Vehicle model |
| dealer_id | INT | NO | Dealer identifier |
| acquisition_date | DATE | NO | Date vehicle was acquired |
| current_price | NUMBER(12,2) | NO | Current listing price |
| status | VARCHAR(20) | NO | AVAILABLE, RESERVED, or SOLD |

#### Target Table: `VEHICLE_DB.VEHICLE_SCHEMA.INVENTORY_HEALTH`

| Column | Type | Derivation |
|--------|------|------------|
| vehicle_id | INT | Pass-through |
| vin | VARCHAR(17) | Pass-through |
| make | VARCHAR(50) | Pass-through |
| model | VARCHAR(50) | Pass-through |
| dealer_id | INT | Pass-through |
| acquisition_date | DATE | Pass-through |
| current_price | NUMBER(12,2) | Pass-through |
| status | VARCHAR(20) | Pass-through |
| days_on_lot | INT | `DATEDIFF(day, acquisition_date, CURRENT_DATE())` |
| aging_category | VARCHAR(6) | GREEN (<50), YELLOW (51-80), RED (>80) |
| is_slow_moving | BOOLEAN | TRUE if days_on_lot > 80 |
| last_refreshed_at | TIMESTAMP | `CURRENT_TIMESTAMP()` at refresh time |

### 3.2 Aging Category Rules

| Category | Condition | Business Meaning |
|----------|-----------|------------------|
| GREEN | days_on_lot < 50 | Healthy turnover, no action needed |
| YELLOW | 51 <= days_on_lot <= 80 | Monitor closely, consider pricing adjustments |
| RED | days_on_lot > 80 | Slow-moving, immediate action required |

### 3.3 Predictive Aging (15-Day Forecast)

**View**: `VEHICLE_DB.VEHICLE_SCHEMA.VW_AGING_RISK_FORECAST`

| Rule | Condition | Output |
|------|-----------|--------|
| At-risk GREEN | days_on_lot + 15 >= 50 | Flagged as GREEN -> YELLOW |
| At-risk YELLOW | days_on_lot + 15 > 80 | Flagged as YELLOW -> RED |
| Already RED | N/A | Not flagged (already worst category) |
| SOLD vehicles | status = 'SOLD' | Excluded from forecast |

### 3.4 Inventory Health Metrics

**View**: `VEHICLE_DB.VEHICLE_SCHEMA.VW_INVENTORY_HEALTH_METRICS`

| Metric Level | Dimensions | KPIs |
|-------------|-----------|------|
| OVERALL | None | total_active_vehicles, avg_days, slow_moving_count, slow_moving_pct, value_at_risk, total_value |
| AGING_CATEGORY | GREEN, YELLOW, RED | vehicle_count, avg_days_on_lot, total_value, pct_of_total |
| DEALER | dealer_id | total_vehicles, avg_days_on_lot, red_count, value_at_risk |

**Exclusion rule**: Vehicles with status = 'SOLD' are excluded from all metrics.

### 3.5 Data Quality Checks

**View**: `VEHICLE_DB.VEHICLE_SCHEMA.VW_DATA_QUALITY_CHECKS`

| Check Type | Check Description | Logic |
|-----------|-------------------|-------|
| NULL_CHECK | vehicle_id is NULL | COUNT WHERE vehicle_id IS NULL |
| NULL_CHECK | vin is NULL | COUNT WHERE vin IS NULL |
| NULL_CHECK | acquisition_date is NULL | COUNT WHERE acquisition_date IS NULL |
| NULL_CHECK | current_price is NULL | COUNT WHERE current_price IS NULL |
| DUPLICATE_CHECK | Duplicate VINs detected | COUNT(*) - COUNT(DISTINCT vin) |
| VALIDITY_CHECK | acquisition_date in the future | COUNT WHERE acquisition_date > CURRENT_DATE() |
| VALIDITY_CHECK | current_price <= 0 | COUNT WHERE current_price <= 0 |
| VALIDITY_CHECK | status not in expected values | COUNT WHERE status NOT IN ('AVAILABLE','RESERVED','SOLD') |

**Result**: PASS (0 failures) or FAIL (>0 failures)

## 4. Technical Specifications

### 4.1 Architecture

```
VEHICLE_DB.PUBLIC.VEHICLE_INVENTORY (source)
        │
        ▼
SP_REFRESH_INVENTORY_HEALTH() [stored procedure]
        │
        ▼
VEHICLE_DB.VEHICLE_SCHEMA.INVENTORY_HEALTH (target table)
        │
        ├──▶ VW_INVENTORY_HEALTH_METRICS (aggregated KPIs)
        ├──▶ VW_AGING_RISK_FORECAST (15-day lookahead)
        └──▶ VW_DATA_QUALITY_CHECKS (quality monitoring)
                    │
                    ▼
            Streamlit Dashboard (app.py)
```

### 4.2 Refresh Strategy

| Aspect | Specification |
|--------|--------------|
| Method | TRUNCATE + INSERT (full reload) |
| Procedure | `CALL VEHICLE_DB.VEHICLE_SCHEMA.SP_REFRESH_INVENTORY_HEALTH()` |
| Execution | CALLER rights |
| Frequency | On-demand or scheduled via Snowflake Task |
| Views | Auto-refresh (computed at query time) |

### 4.3 Authentication

| Method | Details |
|--------|---------|
| Type | RSA Key Pair (PKCS8) |
| Key Size | 2048-bit |
| Private Key Location | `.keys/rsa_key.p8` (unencrypted, local only) |
| Public Key | Registered on Snowflake user via ALTER USER |
| No MFA Required | Key pair bypasses TOTP requirement |

### 4.4 Streamlit Dashboard

| Component | Specification |
|-----------|--------------|
| Framework | Streamlit (local) |
| Charts | Plotly |
| Data Caching | 300-second TTL |
| Layout | Wide mode, sidebar filters |

#### KPI Cards (top row)

| KPI | Calculation |
|-----|-------------|
| Total Vehicles | COUNT of filtered records |
| Avg Days on Lot | MEAN of days_on_lot |
| Vehicles in Red | COUNT WHERE aging_category = 'RED' |
| Inventory Value | SUM of current_price |

#### Visualizations (2x2 grid)

| Position | Chart | Type |
|----------|-------|------|
| Top-left | Inventory by Aging Bucket | Bar chart (color-coded GREEN/YELLOW/RED) |
| Top-right | Inventory by Make | Horizontal bar chart |
| Bottom-left | Inventory by Dealer | Donut chart |
| Bottom-right | Top 10 Oldest Vehicles | Horizontal bar chart (color by category) |

#### Filters (sidebar)

| Filter | Type | Default |
|--------|------|---------|
| Dealer | Multiselect | All selected |
| Make | Multiselect | All selected |
| Model | Multiselect | All selected |
| Aging Bucket | Multiselect | All selected |

## 5. Non-Functional Requirements

| Requirement | Specification |
|-------------|--------------|
| Performance | Dashboard loads in < 5 seconds with cached data |
| Scalability | Supports up to 100K vehicles without architecture change |
| Security | No credentials in code; key pair auth; secrets.toml gitignored |
| Data Freshness | Depends on refresh frequency; views always current post-refresh |
| Availability | Dependent on Snowflake uptime (99.9% SLA) |

## 6. File Structure

```
vehicle-inventory-pipeline/
├── app.py                  # Streamlit dashboard application
├── pipeline.sql            # Complete pipeline DDL/DML
├── requirements.txt        # Python dependencies
├── README.md               # Project documentation
├── specificationdrivendevelopment.md  # This file
├── .streamlit/
│   └── secrets.toml        # Snowflake connection config (gitignored)
└── .keys/
    ├── rsa_key.p8          # RSA private key (gitignored)
    └── rsa_key.pub         # RSA public key
```

## 7. Testing & Validation

| Test | Method | Expected Result |
|------|--------|-----------------|
| Aging calculation | Query INVENTORY_HEALTH | days_on_lot matches DATEDIFF from acquisition_date |
| Category assignment | Query WHERE days_on_lot = 51 | Should be YELLOW |
| Category boundary | Query WHERE days_on_lot = 80 | Should be YELLOW (BETWEEN is inclusive) |
| Category boundary | Query WHERE days_on_lot = 81 | Should be RED |
| Forecast accuracy | Query VW_AGING_RISK_FORECAST | at_risk = TRUE only for threshold-crossing vehicles |
| Data quality | Query VW_DATA_QUALITY_CHECKS | All checks PASS on clean data |
| Refresh procedure | CALL SP_REFRESH_INVENTORY_HEALTH() | Returns success message, table updated |
| Dashboard filters | Apply single filter | KPIs and charts update to filtered subset |
| Dashboard empty state | Filter to no results | KPIs show 0, charts empty gracefully |

## 8. Deployment Checklist

- [x] Create VEHICLE_DB database and VEHICLE_SCHEMA
- [x] Create source table VEHICLE_INVENTORY
- [x] Load sample data (15 vehicles across all categories)
- [x] Create INVENTORY_HEALTH target table
- [x] Create SP_REFRESH_INVENTORY_HEALTH stored procedure
- [x] Create VW_INVENTORY_HEALTH_METRICS view
- [x] Create VW_DATA_QUALITY_CHECKS view
- [x] Create VW_AGING_RISK_FORECAST view
- [x] Generate RSA key pair and register with Snowflake user
- [x] Build Streamlit dashboard with Plotly charts
- [x] Push to GitHub repository
- [ ] Schedule automated refresh (Snowflake Task)
- [ ] Add .gitignore for secrets and keys
- [ ] Production data load

## 9. Change Log

| Date | Change | Author |
|------|--------|--------|
| 2026-06-07 | Initial pipeline deployment (source, target, procedure, metrics, quality checks) | Cortex Code |
| 2026-06-07 | Added 15-day aging risk forecast view | Cortex Code |
| 2026-06-08 | Added Streamlit dashboard with Plotly visualizations | Cortex Code |
| 2026-06-08 | Switched to key pair authentication for MFA bypass | Cortex Code |
