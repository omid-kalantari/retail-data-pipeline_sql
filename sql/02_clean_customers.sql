USE RetailDB;
GO

WITH normalized AS (
    SELECT
        customer_id,
        TRY_CAST(signup_date AS DATE) AS signup_date,
        region,
        loyalty_tier,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY (SELECT NULL)
        ) AS rn
    FROM retail.customers_raw
    WHERE customer_id IS NOT NULL
)
INSERT INTO retail.customers_clean (customer_id, signup_date, region, loyalty_tier)
SELECT
    customer_id,
    signup_date,
    CASE LOWER(LTRIM(RTRIM(region)))
        WHEN 'tehran'           THEN 'Tehran'
        WHEN 'tehran province'  THEN 'Tehran'
        WHEN 'mashad'           THEN 'Mashhad'
        WHEN 'mashhad'          THEN 'Mashhad'
        WHEN 'isfahan'          THEN 'Isfahan'
        WHEN 'esfahan'          THEN 'Isfahan'
        WHEN 'khorasan razavi'  THEN 'Khorasan Razavi'
        WHEN 'east azerbaijan'  THEN 'East Azerbaijan'
        WHEN 'alborz'           THEN 'Alborz'
        WHEN 'gilan'            THEN 'Gilan'
        WHEN 'mazandaran'       THEN 'Mazandaran'
        WHEN 'yazd'             THEN 'Yazd'
        WHEN 'kerman'           THEN 'Kerman'
        WHEN 'qom'              THEN 'Qom'
        WHEN 'semnan'           THEN 'Semnan'
        WHEN 'hamedan'          THEN 'Hamedan'
        WHEN 'lorestan'         THEN 'Lorestan'
        WHEN 'ardabil'          THEN 'Ardabil'
        WHEN 'ahvaz'            THEN 'Ahvaz'
        WHEN 'shiraz'           THEN 'Shiraz'
        WHEN 'tabriz'           THEN 'Tabriz'
        ELSE NULL
    END,
    CASE LOWER(LTRIM(RTRIM(loyalty_tier)))
        WHEN 'bronze'   THEN 'Bronze'
        WHEN 'silver'   THEN 'Silver'
        WHEN 'gold'     THEN 'Gold'
        WHEN 'platinum' THEN 'Platinum'
        ELSE NULL
    END
FROM normalized
WHERE rn = 1;
GO

-- Verify
SELECT 
    COUNT(*) AS total_clean_customers,
    SUM(CASE WHEN signup_date IS NULL THEN 1 ELSE 0 END) AS null_dates,
    SUM(CASE WHEN region IS NULL THEN 1 ELSE 0 END) AS null_regions,
    SUM(CASE WHEN loyalty_tier IS NULL THEN 1 ELSE 0 END) AS null_tiers
FROM retail.customers_clean;
GO
