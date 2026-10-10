USE RetailDB;
GO

WITH normalized AS (
    SELECT
        product_id,
        product_name,
        category,
        TRY_CAST(base_price AS DECIMAL(18,2)) AS base_price,
        supplier_code,
        ROW_NUMBER() OVER (
            PARTITION BY product_id
            ORDER BY (SELECT NULL)
        ) AS rn
    FROM retail.products_raw
    WHERE product_id IS NOT NULL
)
INSERT INTO retail.products_clean (product_id, product_name, category, base_price, supplier_code)
SELECT
    product_id,
    LTRIM(RTRIM(product_name)),
    LTRIM(RTRIM(category)),
    NULLIF(base_price, 0),   -- turn 0 into NULL for later imputation
    COALESCE(NULLIF(LTRIM(RTRIM(supplier_code)), ''), 'Unknown')
FROM normalized
WHERE rn = 1;
GO

SELECT 'products_clean populated' AS status, COUNT(*) AS total FROM retail.products_clean;
GO

USE RetailDB;
GO

WITH median_by_category AS (
    SELECT DISTINCT
        category,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY base_price)
            OVER (PARTITION BY category) AS median_price
    FROM retail.products_clean
    WHERE base_price IS NOT NULL AND base_price > 0
)
UPDATE pc
SET pc.base_price = mbc.median_price
FROM retail.products_clean AS pc
INNER JOIN median_by_category AS mbc
    ON pc.category = mbc.category
WHERE pc.base_price IS NULL;
GO

-- Verify no nulls remain
SELECT 
    COUNT(*) AS total_products,
    SUM(CASE WHEN base_price IS NULL THEN 1 ELSE 0 END) AS null_prices,
    SUM(CASE WHEN base_price <= 0 THEN 1 ELSE 0 END) AS non_positive_prices
FROM retail.products_clean;
GO
