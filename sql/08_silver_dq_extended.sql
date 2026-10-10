USE RetailDB;
GO

-- ============================================================
-- SILVER DQ EXTENSION — Advanced Validation Checks
-- Appends to the existing integrity check pattern.
-- All checks return (check_name, severity, count, detail).
-- severity: 'BLOCKING' = stop pipeline; 'WARNING' = log and continue
-- ============================================================

WITH

-- CHECK 1: Negative or zero quantity (data corruption / system error)
-- Blocking: a sale with qty ≤ 0 makes revenue math meaningless.
negative_qty AS (
    SELECT
        'Negative or zero quantity'      AS check_name,
        'BLOCKING'                       AS severity,
        COUNT(*)                         AS issue_count,
        'order_id sample: '
            + STRING_AGG(CAST(order_id AS NVARCHAR(20)), ', ')
              WITHIN GROUP (ORDER BY order_id)  AS detail
    FROM (
        SELECT TOP 5 order_id
        FROM retail.sales_enriched
        WHERE quantity <= 0
    ) sub
),

-- CHECK 2: Future-dated orders (order_date > today)
-- Blocking: future dates break LAG/cohort index calculations.
future_orders AS (
    SELECT
        'Future-dated orders'            AS check_name,
        'BLOCKING'                       AS severity,
        COUNT(*)                         AS issue_count,
        'Max order_date: ' + CAST(MAX(order_date) AS VARCHAR(20)) AS detail
    FROM retail.sales_enriched
    WHERE order_date > CAST(GETDATE() AS DATE)
),

-- CHECK 3: Order dates before plausible business start (2020-01-01)
-- Warning: might be a test record or bad ETL.
implausible_old_orders AS (
    SELECT
        'Order date before 2020-01-01'   AS check_name,
        'WARNING'                        AS severity,
        COUNT(*)                         AS issue_count,
        'Min order_date: ' + CAST(MIN(order_date) AS VARCHAR(20)) AS detail
    FROM retail.sales_enriched
    WHERE order_date < '2020-01-01'
),

-- CHECK 4: Sales consistency — Sales should equal quantity × unit_price
-- Tolerance: ±0.02 to allow for rounding in source system.
-- Warning (not blocking) because the column is already derived; flag for audit.
sales_consistency AS (
    SELECT
        'Sales ≠ quantity × unit_price (±0.02 tolerance)' AS check_name,
        'WARNING'                                          AS severity,
        COUNT(*)                                           AS issue_count,
        'Max abs diff: '
            + CAST(MAX(ABS(Sales - CAST(quantity AS DECIMAL(18,2)) * unit_price)) AS VARCHAR(20))
            AS detail
    FROM retail.sales_enriched
    WHERE ABS(Sales - CAST(quantity AS DECIMAL(18,2)) * unit_price) > 0.02
),

-- CHECK 5: GrossSales consistency — GrossSales = quantity × base_price
-- Only meaningful for known products (base_price is NULL otherwise).
gross_sales_consistency AS (
    SELECT
        'GrossSales ≠ quantity × base_price (known products, ±0.02)' AS check_name,
        'WARNING'                                                      AS severity,
        COUNT(*)                                                       AS issue_count,
        'Max abs diff: '
            + CAST(MAX(ABS(GrossSales - CAST(quantity AS DECIMAL(18,2)) * base_price)) AS VARCHAR(20))
            AS detail
    FROM retail.sales_enriched
    WHERE product_known = 1
      AND ABS(GrossSales - CAST(quantity AS DECIMAL(18,2)) * base_price) > 0.02
),

-- CHECK 6: Statistical volume anomaly — orders per day > mean + 3σ
-- Uses window functions to compute daily order counts, then flags outlier days.
-- Warning: spikes might be legitimate (promotions) but worth surfacing.
daily_order_counts AS (
    SELECT
        order_date,
        COUNT(DISTINCT order_id) AS daily_orders
    FROM retail.sales_enriched
    GROUP BY order_date
),
daily_stats AS (
    SELECT
        AVG(CAST(daily_orders AS FLOAT))  AS mean_orders,
        STDEV(CAST(daily_orders AS FLOAT)) AS stdev_orders
    FROM daily_order_counts
),
volume_anomaly AS (
    SELECT
        'Days with order volume > mean + 3σ' AS check_name,
        'WARNING'                             AS severity,
        COUNT(*)                              AS issue_count,
        'Threshold: '
            + CAST(CAST(ds.mean_orders + 3 * ds.stdev_orders AS DECIMAL(10,2)) AS VARCHAR(20))
            + ' orders/day'                   AS detail
    FROM daily_order_counts doc
    CROSS JOIN daily_stats ds
    WHERE doc.daily_orders > ds.mean_orders + 3 * ds.stdev_orders
),

-- CHECK 7: Discount outside declared range (should be 0.0–15.0 after Silver cleaning)
-- Blocking: out-of-range discounts corrupt DiscountAmount in Gold.
discount_range AS (
    SELECT
        'discount_pct outside [0, 15]'   AS check_name,
        'BLOCKING'                        AS severity,
        COUNT(*)                          AS issue_count,
        'Range seen: ['
            + CAST(MIN(discount_pct) AS VARCHAR(10)) + ', '
            + CAST(MAX(discount_pct) AS VARCHAR(10)) + ']' AS detail
    FROM retail.sales_enriched
    WHERE discount_pct < 0 OR discount_pct > 15
),

-- CHECK 8: Orphaned sales — customer_known=0 AND product_known=0
-- Both foreign keys missing: line item has no analytical value.
double_orphan AS (
    SELECT
        'Rows with both customer_known=0 and product_known=0' AS check_name,
        'WARNING'                                              AS severity,
        COUNT(*)                                               AS issue_count,
        CAST(ROUND(COUNT(*) * 100.0
            / NULLIF((SELECT COUNT(*) FROM retail.sales_enriched), 0), 2) AS VARCHAR(10))
            + '% of total rows'                                AS detail
    FROM retail.sales_enriched
    WHERE customer_known = 0 AND product_known = 0
)

SELECT check_name, severity, issue_count, detail FROM negative_qty
UNION ALL SELECT check_name, severity, issue_count, detail FROM future_orders
UNION ALL SELECT check_name, severity, issue_count, detail FROM implausible_old_orders
UNION ALL SELECT check_name, severity, issue_count, detail FROM sales_consistency
UNION ALL SELECT check_name, severity, issue_count, detail FROM gross_sales_consistency
UNION ALL SELECT check_name, severity, issue_count, detail FROM volume_anomaly
UNION ALL SELECT check_name, severity, issue_count, detail FROM discount_range
UNION ALL SELECT check_name, severity, issue_count, detail FROM double_orphan
ORDER BY
    CASE severity WHEN 'BLOCKING' THEN 0 ELSE 1 END,
    issue_count DESC;
GO

USE RetailDB;
GO

IF OBJECT_ID('retail.gold_validation_log', 'U') IS NULL
BEGIN
    CREATE TABLE retail.gold_validation_log (
        log_id          INT IDENTITY(1,1) PRIMARY KEY,
        run_timestamp   DATETIME2         DEFAULT SYSDATETIME(),
        run_id          VARCHAR(50)       NOT NULL,   -- passed from pipeline orchestrator
        check_name      NVARCHAR(200)     NOT NULL,
        severity        VARCHAR(20)       NOT NULL,
        issue_count     INT               NOT NULL,
        detail          NVARCHAR(500)     NULL,
        pipeline_action VARCHAR(50)       NOT NULL    -- 'BLOCKED' | 'WARNED' | 'PASSED'
    );
END
GO

USE RetailDB;
GO

-- Insert current Silver DQ results into the audit log.
-- pipeline_action is derived from severity:
--   BLOCKING checks with issue_count > 0 → 'BLOCKED'
--   WARNING  checks with issue_count > 0 → 'WARNED'
--   Any check with issue_count = 0       → 'PASSED'
--
-- Replace 'notebook-run-001' with a dynamic run_id in a scheduled pipeline
-- (e.g. CONVERT(VARCHAR, SYSDATETIME(), 120) for a timestamp-based id).

DECLARE @run_id VARCHAR(50) = 'notebook-run-001';

INSERT INTO retail.gold_validation_log (run_id, check_name, severity, issue_count, detail, pipeline_action)

WITH

negative_qty AS (
    SELECT
        'Negative or zero quantity'      AS check_name,
        'BLOCKING'                       AS severity,
        COUNT(*)                         AS issue_count,
        'order_id sample: '
            + ISNULL(STRING_AGG(CAST(order_id AS NVARCHAR(20)), ', ')
              WITHIN GROUP (ORDER BY order_id), 'none')  AS detail
    FROM (
        SELECT TOP 5 order_id
        FROM retail.sales_enriched
        WHERE quantity <= 0
    ) sub
),
future_orders AS (
    SELECT
        'Future-dated orders'            AS check_name,
        'BLOCKING'                       AS severity,
        COUNT(*)                         AS issue_count,
        'Max order_date: ' + ISNULL(CAST(MAX(order_date) AS VARCHAR(20)), 'n/a') AS detail
    FROM retail.sales_enriched
    WHERE order_date > CAST(GETDATE() AS DATE)
),
implausible_old_orders AS (
    SELECT
        'Order date before 2020-01-01'   AS check_name,
        'WARNING'                        AS severity,
        COUNT(*)                         AS issue_count,
        'Min order_date: ' + ISNULL(CAST(MIN(order_date) AS VARCHAR(20)), 'n/a') AS detail
    FROM retail.sales_enriched
    WHERE order_date < '2020-01-01'
),
sales_consistency AS (
    SELECT
        'Sales ≠ quantity × unit_price (±0.02 tolerance)' AS check_name,
        'WARNING'                                          AS severity,
        COUNT(*)                                           AS issue_count,
        'Max abs diff: '
            + ISNULL(CAST(MAX(ABS(Sales - CAST(quantity AS DECIMAL(18,2)) * unit_price)) AS VARCHAR(20)), '0')
            AS detail
    FROM retail.sales_enriched
    WHERE ABS(Sales - CAST(quantity AS DECIMAL(18,2)) * unit_price) > 0.02
),
gross_sales_consistency AS (
    SELECT
        'GrossSales ≠ quantity × base_price (known products, ±0.02)' AS check_name,
        'WARNING'                                                      AS severity,
        COUNT(*)                                                       AS issue_count,
        'Max abs diff: '
            + ISNULL(CAST(MAX(ABS(GrossSales - CAST(quantity AS DECIMAL(18,2)) * base_price)) AS VARCHAR(20)), '0')
            AS detail
    FROM retail.sales_enriched
    WHERE product_known = 1
      AND ABS(GrossSales - CAST(quantity AS DECIMAL(18,2)) * base_price) > 0.02
),
daily_order_counts AS (
    SELECT order_date, COUNT(DISTINCT order_id) AS daily_orders
    FROM retail.sales_enriched
    GROUP BY order_date
),
daily_stats AS (
    SELECT AVG(CAST(daily_orders AS FLOAT)) AS mean_orders,
           STDEV(CAST(daily_orders AS FLOAT)) AS stdev_orders
    FROM daily_order_counts
),
volume_anomaly AS (
    SELECT
        'Days with order volume > mean + 3σ' AS check_name,
        'WARNING'                             AS severity,
        COUNT(*)                              AS issue_count,
        'Threshold: '
            + CAST(CAST(ds.mean_orders + 3 * ds.stdev_orders AS DECIMAL(10,2)) AS VARCHAR(20))
            + ' orders/day'                   AS detail
    FROM daily_order_counts doc
    CROSS JOIN daily_stats ds
    WHERE doc.daily_orders > ds.mean_orders + 3 * ds.stdev_orders
),
discount_range AS (
    SELECT
        'discount_pct outside [0, 15]'   AS check_name,
        'BLOCKING'                        AS severity,
        COUNT(*)                          AS issue_count,
        'Range seen: ['
            + CAST(MIN(discount_pct) AS VARCHAR(10)) + ', '
            + CAST(MAX(discount_pct) AS VARCHAR(10)) + ']' AS detail
    FROM retail.sales_enriched
    WHERE discount_pct < 0 OR discount_pct > 15
),
double_orphan AS (
    SELECT
        'Rows with both customer_known=0 and product_known=0' AS check_name,
        'WARNING'                                              AS severity,
        COUNT(*)                                               AS issue_count,
        CAST(ROUND(COUNT(*) * 100.0
            / NULLIF((SELECT COUNT(*) FROM retail.sales_enriched), 0), 2) AS VARCHAR(10))
            + '% of total rows'                                AS detail
    FROM retail.sales_enriched
    WHERE customer_known = 0 AND product_known = 0
),

all_checks AS (
    SELECT check_name, severity, issue_count, detail FROM negative_qty
    UNION ALL SELECT check_name, severity, issue_count, detail FROM future_orders
    UNION ALL SELECT check_name, severity, issue_count, detail FROM implausible_old_orders
    UNION ALL SELECT check_name, severity, issue_count, detail FROM sales_consistency
    UNION ALL SELECT check_name, severity, issue_count, detail FROM gross_sales_consistency
    UNION ALL SELECT check_name, severity, issue_count, detail FROM volume_anomaly
    UNION ALL SELECT check_name, severity, issue_count, detail FROM discount_range
    UNION ALL SELECT check_name, severity, issue_count, detail FROM double_orphan
)

SELECT
    @run_id,
    check_name,
    severity,
    issue_count,
    detail,
    CASE
        WHEN severity = 'BLOCKING' AND issue_count > 0 THEN 'BLOCKED'
        WHEN severity = 'WARNING'  AND issue_count > 0 THEN 'WARNED'
        ELSE 'PASSED'
    END AS pipeline_action
FROM all_checks;

-- Confirm rows written
SELECT run_id, check_name, severity, issue_count, pipeline_action
FROM retail.gold_validation_log
WHERE run_id = @run_id
ORDER BY CASE pipeline_action WHEN 'BLOCKED' THEN 0 WHEN 'WARNED' THEN 1 ELSE 2 END;
GO
