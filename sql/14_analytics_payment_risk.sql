USE RetailDB;
GO

IF OBJECT_ID('retail.payment_risk_profile', 'U') IS NOT NULL
    DROP TABLE retail.payment_risk_profile;
GO

WITH payment_agg AS (
    SELECT
        payment_method,
        COUNT(DISTINCT order_id)                                AS total_orders,
        SUM(COALESCE(Sales, 0))                                 AS total_revenue,
        -- Return rate by payment method
        CAST(
            SUM(CASE WHEN delivery_status = 'Returned' THEN 1 ELSE 0 END) * 100.0
            / NULLIF(COUNT(*), 0)
        AS DECIMAL(5,2))                                        AS return_rate_pct,
        -- Cancellation rate
        CAST(
            SUM(CASE WHEN delivery_status = 'Cancelled' THEN 1 ELSE 0 END) * 100.0
            / NULLIF(COUNT(*), 0)
        AS DECIMAL(5,2))                                        AS cancellation_rate_pct,
        -- Price anomaly rate — 'Unknown' payment methods may correlate with data issues
        CAST(
            SUM(CASE WHEN PriceAnomaly = 1 THEN 1 ELSE 0 END) * 100.0
            / NULLIF(COUNT(*), 0)
        AS DECIMAL(5,2))                                        AS price_anomaly_rate_pct,
        AVG(CAST(Sales AS FLOAT))                               AS avg_order_value
    FROM retail.sales_enriched
    GROUP BY payment_method
),

payment_ranked AS (
    SELECT
        *,
        -- Risk score: composite of return + cancellation + anomaly rates
        -- Simple additive; weights can be tuned per business rules
        CAST(
            return_rate_pct * 0.5
            + cancellation_rate_pct * 0.3
            + price_anomaly_rate_pct * 0.2
        AS DECIMAL(5,2))                                        AS composite_risk_score,
        RANK() OVER (ORDER BY total_revenue DESC)               AS revenue_rank
    FROM payment_agg
)

SELECT
    payment_method,
    total_orders,
    CAST(total_revenue      AS DECIMAL(18,2)) AS total_revenue,
    return_rate_pct,
    cancellation_rate_pct,
    price_anomaly_rate_pct,
    CAST(avg_order_value    AS DECIMAL(18,2)) AS avg_order_value,
    composite_risk_score,
    revenue_rank
INTO retail.payment_risk_profile
FROM payment_ranked;
GO
