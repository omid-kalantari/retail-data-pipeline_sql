USE RetailDB;
GO

-- Idempotency guard
IF OBJECT_ID('retail.customer_metrics', 'U') IS NOT NULL
    DROP TABLE retail.customer_metrics;
GO

-- Step 1: compute the dataset-wide latest order date once
-- so recency_days is consistent across all customers.
WITH dataset_max AS (
    SELECT MAX(order_date) AS max_order_date
    FROM retail.sales_enriched
),

-- Step 2: pull stable customer attributes from customers_clean (single source of truth).
-- This avoids grouping on region/loyalty_tier/signup_date from sales_enriched,
-- which can differ across orders for the same customer and inflate row count.
customer_attrs AS (
    SELECT
        customer_id,
        -- Use MAX() as a tie-breaker in case of any residual duplicates in customers_clean
        MAX(loyalty_tier)  AS loyalty_tier,
        MAX(signup_date)   AS signup_date
    FROM retail.customers_clean
    GROUP BY customer_id
),

-- Step 3: aggregate sales to customer grain — only group by customer_id.
-- region is resolved as the customer's modal (most frequent) shipping region
-- using a ROW_NUMBER trick to avoid a multi-column GROUP BY explosion.
customer_region AS (
    SELECT
        customer_id,
        region,
        COUNT(*) AS region_count,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY COUNT(*) DESC, region ASC   -- DESC count, ASC region breaks ties deterministically
        ) AS rn
    FROM retail.sales_enriched
    WHERE customer_known = 1
    GROUP BY customer_id, region
),

customer_agg AS (
    SELECT
        se.customer_id,
        MIN(se.order_date)                                   AS first_purchase_date,
        MAX(se.order_date)                                   AS last_purchase_date,
        COUNT(DISTINCT se.order_id)                          AS total_orders,
        SUM(COALESCE(se.Sales, 0))                           AS total_revenue,
        SUM(COALESCE(se.quantity, 0))                        AS total_units
    FROM retail.sales_enriched se
    WHERE se.customer_known = 1
    GROUP BY se.customer_id   -- single column: guaranteed one row per customer_id
),

-- Step 4: join stable attributes back in (one row per customer_id guaranteed)
customer_joined AS (
    SELECT
        ca.customer_id,
        cr.region,                    -- modal shipping region
        attrs.loyalty_tier,           -- from customers_clean (stable)
        attrs.signup_date,            -- from customers_clean (stable)
        ca.first_purchase_date,
        ca.last_purchase_date,
        ca.total_orders,
        ca.total_revenue,
        ca.total_units
    FROM customer_agg ca
    INNER JOIN customer_attrs attrs ON ca.customer_id = attrs.customer_id
    LEFT  JOIN customer_region  cr  ON ca.customer_id = cr.customer_id AND cr.rn = 1
),

-- Step 5: derive recency and average order value
customer_rfm_base AS (
    SELECT
        cj.*,
        -- recency: days from last purchase to dataset ceiling
        DATEDIFF(DAY, cj.last_purchase_date, dm.max_order_date) AS recency_days,
        -- avg_order_value: NULL when total_orders = 0 (honest, not 0)
        CASE
            WHEN cj.total_orders > 0
            THEN cj.total_revenue / cj.total_orders
        END AS avg_order_value
    FROM customer_joined cj
    CROSS JOIN dataset_max dm
),

-- Step 6: apply NTILE quintiles over the true customer-grain dataset
-- r_score: ASC order → smallest recency_days (most recent) → highest bucket
-- f_score: ASC order → highest total_orders → highest bucket
-- m_score: ASC order → highest total_revenue → highest bucket
customer_scored AS (
    SELECT
        *,
        NTILE(5) OVER (ORDER BY recency_days DESC)  AS r_score,
        NTILE(5) OVER (ORDER BY total_orders ASC)  AS f_score,
        NTILE(5) OVER (ORDER BY total_revenue ASC) AS m_score
    FROM customer_rfm_base
)

SELECT
    customer_id,
    region,
    loyalty_tier,
    signup_date,
    first_purchase_date,
    last_purchase_date,
    total_orders,
    CAST(total_revenue   AS DECIMAL(18,2))  AS total_revenue,
    total_units,
    CAST(avg_order_value AS DECIMAL(18,2))  AS avg_order_value,
    recency_days,
    total_orders                            AS frequency,
    CAST(total_revenue   AS DECIMAL(18,2))  AS monetary,
    r_score,
    f_score,
    m_score,
    CAST(r_score AS VARCHAR(1))
        + CAST(f_score AS VARCHAR(1))
        + CAST(m_score AS VARCHAR(1))       AS rfm_segment
INTO retail.customer_metrics
FROM customer_scored;
GO

USE RetailDB;
GO

IF OBJECT_ID('retail.customer_clv', 'U') IS NOT NULL
    DROP TABLE retail.customer_clv;
GO

WITH dataset_bounds AS (
    SELECT
        MIN(order_date) AS dataset_start,
        MAX(order_date) AS dataset_end,
        -- Observation window in days (used to annualise)
        DATEDIFF(DAY, MIN(order_date), MAX(order_date)) AS observation_days
    FROM retail.sales_enriched
),

customer_base AS (
    SELECT
        cm.customer_id,
        cm.loyalty_tier,
        cm.region,
        cm.total_orders,
        cm.total_revenue,
        cm.recency_days,
        cm.avg_order_value,
        cm.first_purchase_date,
        cm.last_purchase_date,
        db.observation_days,
        -- Active tenure in days (time between first and last purchase)
        DATEDIFF(DAY, cm.first_purchase_date, cm.last_purchase_date) AS tenure_days
    FROM retail.customer_metrics cm
    CROSS JOIN dataset_bounds db
),

clv_calculated AS (
    SELECT
        customer_id,
        loyalty_tier,
        region,
        total_orders,
        total_revenue                                                       AS historical_revenue,
        avg_order_value,
        recency_days,
        tenure_days,
        observation_days,

        -- Purchase rate: orders per day over active tenure (NULL if tenure=0, i.e. single purchase)
        CASE
            WHEN tenure_days > 0
            THEN CAST(total_orders AS FLOAT) / tenure_days
        END                                                                  AS purchase_rate_per_day,

        -- Annualised purchase frequency (365-day projection)
        CASE
            WHEN tenure_days > 0
            THEN CAST(total_orders AS FLOAT) / tenure_days * 365
            ELSE total_orders   -- single-purchase customers: use 1 order/year as floor
        END                                                                  AS predicted_annual_orders,

        -- Simple CLV: annualised orders × average order value × assumed margin (30%)
        -- Margin assumption is explicit and can be parameterised.
        CASE
            WHEN tenure_days > 0
            THEN CAST(total_orders AS FLOAT) / tenure_days * 365
                     * avg_order_value * 0.30
            ELSE avg_order_value * 0.30
        END                                                                  AS clv_1yr_estimate,

        -- CLV tier based on historical revenue quartiles
        -- NTILE(4) over revenue: 4=highest value customer
        NTILE(4) OVER (ORDER BY total_revenue ASC)                          AS clv_quartile

    FROM customer_base
),

clv_labelled AS (
    SELECT
        *,
        CASE clv_quartile
            WHEN 4 THEN 'Champions'
            WHEN 3 THEN 'Loyal'
            WHEN 2 THEN 'Promising'
            WHEN 1 THEN 'At Risk'
        END AS clv_segment
    FROM clv_calculated
)

SELECT
    customer_id,
    loyalty_tier,
    region,
    total_orders,
    CAST(historical_revenue      AS DECIMAL(18,2)) AS historical_revenue,
    CAST(avg_order_value         AS DECIMAL(18,2)) AS avg_order_value,
    recency_days,
    tenure_days,
    CAST(purchase_rate_per_day   AS DECIMAL(10,6)) AS purchase_rate_per_day,
    CAST(predicted_annual_orders AS DECIMAL(10,2)) AS predicted_annual_orders,
    CAST(clv_1yr_estimate        AS DECIMAL(18,2)) AS clv_1yr_estimate,
    clv_quartile,
    clv_segment
INTO retail.customer_clv
FROM clv_labelled;
GO
