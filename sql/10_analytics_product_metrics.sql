USE RetailDB;
GO

IF OBJECT_ID('retail.product_metrics', 'U') IS NOT NULL
    DROP TABLE retail.product_metrics;
GO

WITH product_agg AS (
    SELECT
        se.product_id,
        -- Take any non-NULL value — these are stable per product_id
        MAX(se.product_name)                                          AS product_name,
        MAX(se.category)                                              AS category,
        MAX(se.supplier_code)                                         AS supplier_code,
        MAX(se.base_price)                                            AS base_price,
        COUNT(DISTINCT se.order_id)                                   AS total_orders,
        SUM(COALESCE(se.quantity, 0))                                 AS total_units,
        SUM(COALESCE(se.Sales, 0))                                    AS total_revenue,
        SUM(COALESCE(se.GrossSales, 0))                              AS total_gross_sales,
        SUM(COALESCE(se.DiscountAmount, 0))                          AS total_discount,
        -- avg_discount_pct: NULL is honest when no rows exist
        AVG(se.discount_pct)                                          AS avg_discount_pct,
        -- return_rate: proportion of line items that were returned
        -- NULL guard: NULLIF prevents division by zero
        CAST(
            SUM(CASE WHEN se.delivery_status = 'Returned' THEN 1 ELSE 0 END) * 100.0
            / NULLIF(COUNT(*), 0)
        AS DECIMAL(5,2))                                              AS return_rate
    FROM retail.sales_enriched se
    WHERE se.product_known = 1
    GROUP BY se.product_id
),

product_ranked AS (
    SELECT
        *,
        -- Global revenue rank: ties share the same rank (gaps left intentionally by RANK)
        RANK() OVER (ORDER BY total_revenue DESC)                             AS revenue_rank_overall,
        -- Category-scoped rank: partitioned by category, same ordering
        RANK() OVER (PARTITION BY category ORDER BY total_revenue DESC)       AS revenue_rank_in_category
    FROM product_agg
)

SELECT
    product_id,
    product_name,
    category,
    supplier_code,
    CAST(base_price         AS DECIMAL(18,2)) AS base_price,
    total_orders,
    total_units,
    CAST(total_revenue      AS DECIMAL(18,2)) AS total_revenue,
    CAST(total_gross_sales  AS DECIMAL(18,2)) AS total_gross_sales,
    CAST(total_discount     AS DECIMAL(18,2)) AS total_discount,
    avg_discount_pct,
    return_rate,
    revenue_rank_overall,
    revenue_rank_in_category
INTO retail.product_metrics
FROM product_ranked;
GO
