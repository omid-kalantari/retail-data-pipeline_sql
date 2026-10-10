USE RetailDB;
GO

IF OBJECT_ID('retail.supplier_metrics', 'U') IS NOT NULL
    DROP TABLE retail.supplier_metrics;
GO

WITH supplier_agg AS (
    SELECT
        se.supplier_code,
        COUNT(DISTINCT se.product_id)                           AS distinct_products,
        COUNT(DISTINCT se.order_id)                             AS total_orders,
        SUM(COALESCE(se.quantity, 0))                           AS total_units_sold,
        SUM(COALESCE(se.Sales, 0))                              AS total_revenue,
        SUM(COALESCE(se.DiscountAmount, 0))                     AS total_discount_given,
        AVG(se.discount_pct)                                    AS avg_discount_pct,
        -- Return rate at supplier level
        CAST(
            SUM(CASE WHEN se.delivery_status = 'Returned' THEN 1 ELSE 0 END) * 100.0
            / NULLIF(COUNT(*), 0)
        AS DECIMAL(5,2))                                        AS return_rate_pct,
        -- Price anomaly rate: what % of this supplier's line items have a price anomaly
        CAST(
            SUM(CASE WHEN se.PriceAnomaly = 1 THEN 1 ELSE 0 END) * 100.0
            / NULLIF(COUNT(*), 0)
        AS DECIMAL(5,2))                                        AS price_anomaly_rate_pct
    FROM retail.sales_enriched se
    WHERE se.product_known = 1      -- supplier is only meaningful for known products
    GROUP BY se.supplier_code
),

supplier_ranked AS (
    SELECT
        *,
        -- Revenue rank across all suppliers
        RANK() OVER (ORDER BY total_revenue DESC)               AS revenue_rank,
        -- Flag suppliers whose return rate is more than 2× the average
        AVG(return_rate_pct) OVER ()                            AS avg_return_rate_all,
        CASE
            WHEN return_rate_pct > 2 * AVG(return_rate_pct) OVER ()
            THEN 1 ELSE 0
        END                                                     AS high_return_flag
    FROM supplier_agg
)

SELECT
    supplier_code,
    distinct_products,
    total_orders,
    total_units_sold,
    CAST(total_revenue          AS DECIMAL(18,2)) AS total_revenue,
    CAST(total_discount_given   AS DECIMAL(18,2)) AS total_discount_given,
    avg_discount_pct,
    return_rate_pct,
    price_anomaly_rate_pct,
    revenue_rank,
    CAST(avg_return_rate_all    AS DECIMAL(5,2))  AS avg_return_rate_benchmark,
    high_return_flag
INTO retail.supplier_metrics
FROM supplier_ranked;
GO
