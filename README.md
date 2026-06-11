# Vehicle Inventory Health Analytics Pipeline

## Business Goal
Identify slow-moving inventory and track vehicle aging across dealerships.

## Pipeline Objects

| Object | Type | Location |
|--------|------|----------|
| `VEHICLE_INVENTORY` | Source Table | `VEHICLE_DB.PUBLIC` |
| `INVENTORY_HEALTH` | Target Table | `VEHICLE_DB.VEHICLE_SCHEMA` |
| `SP_REFRESH_INVENTORY_HEALTH` | Stored Procedure | `VEHICLE_DB.VEHICLE_SCHEMA` |
| `VW_INVENTORY_HEALTH_METRICS` | View | `VEHICLE_DB.VEHICLE_SCHEMA` |
| `VW_DATA_QUALITY_CHECKS` | View | `VEHICLE_DB.VEHICLE_SCHEMA` |
| `VW_AGING_RISK_FORECAST` | View | `VEHICLE_DB.VEHICLE_SCHEMA` |

## Aging Categories

| Category | Days on Lot | Action |
|----------|-------------|--------|
| GREEN | < 50 days | Healthy turnover |
| YELLOW | 51-80 days | Monitor closely |
| RED | > 80 days | Slow-moving, action needed |

## INVENTORY_HEALTH Columns

| Column | Description |
|--------|-------------|
| `vehicle_id` | Unique vehicle identifier |
| `vin` | Vehicle Identification Number |
| `make` | Vehicle manufacturer |
| `model` | Vehicle model |
| `dealer_id` | Dealer identifier |
| `acquisition_date` | Date vehicle was acquired |
| `current_price` | Current listing price |
| `status` | AVAILABLE, RESERVED, or SOLD |
| `days_on_lot` | Calculated days since acquisition |
| `aging_category` | GREEN, YELLOW, or RED |
| `is_slow_moving` | TRUE if > 60 days on lot |
| `last_refreshed_at` | Timestamp of last data refresh |

## Usage

### Refresh the table
```sql
CALL VEHICLE_DB.VEHICLE_SCHEMA.SP_REFRESH_INVENTORY_HEALTH();
```

### View metrics
```sql
SELECT * FROM VEHICLE_DB.VEHICLE_SCHEMA.VW_INVENTORY_HEALTH_METRICS;
```

### Run data quality checks
```sql
SELECT * FROM VEHICLE_DB.VEHICLE_SCHEMA.VW_DATA_QUALITY_CHECKS;
```

### Find slow-moving vehicles
```sql
SELECT * FROM VEHICLE_DB.VEHICLE_SCHEMA.INVENTORY_HEALTH
WHERE aging_category = 'RED' AND status = 'AVAILABLE'
ORDER BY days_on_lot DESC;
```

### View vehicles at risk of aging (15-day forecast)
```sql
SELECT * FROM VEHICLE_DB.VEHICLE_SCHEMA.VW_AGING_RISK_FORECAST
WHERE at_risk = TRUE
ORDER BY days_until_transition ASC;
```

## Data Quality Checks

| Check Type | Description |
|-----------|-------------|
| NULL_CHECK | Validates required fields are not NULL |
| DUPLICATE_CHECK | Detects duplicate VINs |
| VALIDITY_CHECK | Future dates, invalid prices, unexpected status values |

## Refresh Strategy

Call `SP_REFRESH_INVENTORY_HEALTH()` to truncate and reload the target table. Schedule via Snowflake Task or external orchestrator as needed.

## Streamlit Dashboard

### Setup

1. Install dependencies:
```bash
pip install -r requirements.txt
```

2. Create `.streamlit/secrets.toml` in the project root:
```toml
[snowflake]
account = "your_account_locator"
user = "your_username"
password = "your_password"
warehouse = "your_warehouse"
```

3. Run the app:
```bash
streamlit run app.py
```

### Features

- **KPI Cards**: Total Vehicles, Avg Days on Lot, Red Category Count, Inventory Value
- **Charts**: Aging Bucket distribution, Inventory by Make, Inventory by Dealer, Top 10 Oldest Vehicles
- **Filters**: Dealer, Make, Model, Aging Bucket (sidebar multiselect)
- **Data Table**: Filterable raw data view
