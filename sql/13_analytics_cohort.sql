USE RetailDB;
GO

IF OBJECT_ID('retail.cohort_base', 'U') IS NOT NULL
    DROP TABLE retail.cohort_base;
GO

WITH customer_first_order AS (
    -- One row per customer: their earliest order date defines their cohort
    SELECT
        customer_id,
        MIN(order_date) AS first_order_date
    FROM retail.sales_enriched
    WHERE customer_known = 1
    GROUP BY customer_id
),

cohort_mapped AS (
    SELECT
        se.customer_id,
        se.order_id,
        se.order_date,
        -- Cohort label: the month of the customer's very first purchase
        FORMAT(cfo.first_order_date, 'yyyy-MM')         AS customer_first_order_month,
        -- Current order month label
        FORMAT(se.order_date, 'yyyy-MM')                AS order_month,
        -- Cohort index: integer months elapsed since first order
        -- Uses year and month arithmetic to avoid day-of-month edge cases
        (YEAR(se.order_date)  - YEAR(cfo.first_order_date))  * 12
        + (MONTH(se.order_date) - MONTH(cfo.first_order_date)) AS cohort_index
    FROM retail.sales_enriched se
    INNER JOIN customer_first_order cfo
        ON se.customer_id = cfo.customer_id
    WHERE se.customer_known = 1
)

SELECT
    customer_id,
    order_id,
    order_date,
    CAST(customer_first_order_month AS VARCHAR(10))  AS customer_first_order_month,
    CAST(order_month                AS VARCHAR(10))  AS order_month,
    cohort_index
INTO retail.cohort_base
FROM cohort_mapped;
GO

USE RetailDB;
GO

IF OBJECT_ID('retail.cohort_retention_rates', 'U') IS NOT NULL
    DROP TABLE retail.cohort_retention_rates;
GO

WITH cohort_sizes AS (
    -- Count of distinct customers who first purchased in each cohort month
    SELECT
        customer_first_order_month,
        COUNT(DISTINCT customer_id) AS cohort_size
    FROM retail.cohort_base
    WHERE cohort_index = 0          -- only acquisition month rows define cohort size
    GROUP BY customer_first_order_month
),

returning_customers AS (
    -- Count distinct customers active at each cohort_index
    SELECT
        cb.customer_first_order_month,
        cb.cohort_index,
        COUNT(DISTINCT cb.customer_id) AS active_customers
    FROM retail.cohort_base cb
    GROUP BY cb.customer_first_order_month, cb.cohort_index
)

SELECT
    rc.customer_first_order_month   AS cohort_month,
    cs.cohort_size,
    rc.cohort_index,
    rc.active_customers,
    -- Retention rate: what % of the original cohort is still purchasing at this index
    CAST(
        rc.active_customers * 100.0 / NULLIF(cs.cohort_size, 0)
    AS DECIMAL(5,2))                AS retention_rate_pct
INTO retail.cohort_retention_rates
FROM returning_customers rc
INNER JOIN cohort_sizes cs
    ON rc.customer_first_order_month = cs.customer_first_order_month
ORDER BY rc.customer_first_order_month, rc.cohort_index;
GO
