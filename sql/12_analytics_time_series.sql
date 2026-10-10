USE RetailDB;
GO

IF OBJECT_ID('retail.time_series_monthly', 'U') IS NOT NULL
    DROP TABLE retail.time_series_monthly;
GO

WITH monthly_agg AS (
    SELECT
        -- FORMAT produces 'yyyy-MM' string for grouping and charting labels
        FORMAT(order_date, 'yyyy-MM')           AS year_month,
        YEAR(order_date)                        AS order_year,
        MONTH(order_date)                       AS order_month,
        COUNT(DISTINCT order_id)                AS total_orders,
        SUM(COALESCE(Sales, 0))                 AS total_revenue,
        SUM(COALESCE(GrossSales, 0))            AS total_gross_sales,
        SUM(COALESCE(DiscountAmount, 0))        AS total_discount,
        COUNT(DISTINCT customer_id)             AS unique_customers,
        COUNT(DISTINCT product_id)              AS unique_products
    FROM retail.sales_enriched
    GROUP BY
        FORMAT(order_date, 'yyyy-MM'),
        YEAR(order_date),
        MONTH(order_date)
),

monthly_with_aov AS (
    SELECT
        *,
        -- avg_order_value: NULL when no orders in month (honest)
        CASE
            WHEN total_orders > 0
            THEN total_revenue / total_orders
        END AS avg_order_value
    FROM monthly_agg
),

monthly_with_lag AS (
    SELECT
        *,
        -- LAG over chronological order gives previous month's revenue
        -- Ordered by year then month (INT) to avoid string sort issues
        LAG(total_revenue, 1) OVER (
            ORDER BY order_year, order_month
        ) AS prev_month_revenue
    FROM monthly_with_aov
)

SELECT
    CAST(year_month      AS VARCHAR(10))        AS year_month,
    order_year,
    order_month,
    total_orders,
    CAST(total_revenue      AS DECIMAL(18,2))   AS total_revenue,
    CAST(total_gross_sales  AS DECIMAL(18,2))   AS total_gross_sales,
    CAST(total_discount     AS DECIMAL(18,2))   AS total_discount,
    CAST(avg_order_value    AS DECIMAL(18,2))   AS avg_order_value,
    unique_customers,
    unique_products,
    CAST(prev_month_revenue AS DECIMAL(18,2))   AS prev_month_revenue,
    -- mom_growth_pct: NULL for first month; NULLIF guards against zero denominator
    CAST(
        (total_revenue - prev_month_revenue)
        / NULLIF(prev_month_revenue, 0) * 100
    AS DECIMAL(5,2))                            AS mom_growth_pct
INTO retail.time_series_monthly
FROM monthly_with_lag
ORDER BY order_year, order_month;
GO

USE RetailDB;
GO

IF OBJECT_ID('retail.category_monthly_matrix', 'U') IS NOT NULL
    DROP TABLE retail.category_monthly_matrix;
GO

SELECT
    se.category,
    CAST(FORMAT(se.order_date, 'yyyy-MM') AS VARCHAR(10))  AS year_month,
    CAST(SUM(COALESCE(se.Sales, 0)) AS DECIMAL(18,2))      AS revenue,
    COUNT(DISTINCT se.order_id)                             AS orders
INTO retail.category_monthly_matrix
FROM retail.sales_enriched se
WHERE se.product_known = 1          -- excludes NULL category rows
GROUP BY
    se.category,
    FORMAT(se.order_date, 'yyyy-MM')
ORDER BY
    se.category,
    FORMAT(se.order_date, 'yyyy-MM');
GO
