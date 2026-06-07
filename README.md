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

## Aging Categories

| Category | Days on Lot | Action |
|----------|-------------|--------|
| GREEN | < 30 days | Healthy turnover |
| YELLOW | 30-60 days | Monitor closely |
| RED | > 60 days | Slow-moving, action needed |

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

## Data Quality Checks

| Check Type | Description |
|-----------|-------------|
| NULL_CHECK | Validates required fields are not NULL |
| DUPLICATE_CHECK | Detects duplicate VINs |
| VALIDITY_CHECK | Future dates, invalid prices, unexpected status values |

## Refresh Strategy

Call `SP_REFRESH_INVENTORY_HEALTH()` to truncate and reload the target table. Schedule via Snowflake Task or external orchestrator as needed.
