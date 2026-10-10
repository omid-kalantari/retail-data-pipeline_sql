USE RetailDB;
GO

SELECT 'Negative quantity'          AS check_name, COUNT(*) AS failures FROM retail.sales_enriched WHERE quantity <= 0
UNION ALL
SELECT 'unit_price < 1000',         COUNT(*) FROM retail.sales_enriched WHERE unit_price < 1000
UNION ALL
SELECT 'base_price <= 0',           COUNT(*) FROM retail.sales_enriched WHERE base_price <= 0
UNION ALL
SELECT 'Negative DiscountAmount',   COUNT(*) FROM retail.sales_enriched WHERE DiscountAmount < 0
UNION ALL
SELECT 'Missing region',            COUNT(*) FROM retail.sales_enriched WHERE region IS NULL OR region = ''
UNION ALL
SELECT 'Missing payment_method',    COUNT(*) FROM retail.sales_enriched WHERE payment_method IS NULL
UNION ALL
SELECT 'Missing loyalty_tier',      COUNT(*) FROM retail.sales_enriched WHERE loyalty_tier IS NULL
UNION ALL
SELECT 'Unknown product IDs',       COUNT(*) FROM retail.sales_enriched WHERE product_known = 0
UNION ALL
SELECT 'Unknown customer IDs',      COUNT(*) FROM retail.sales_enriched WHERE customer_known = 0;
GO

USE RetailDB;
GO

-- =====================================================
-- Validation Details — every row that failed a check
-- =====================================================
SELECT 
    'Negative quantity' AS check_name,
    order_id, customer_id, product_id,
    CONCAT('quantity = ', quantity) AS issue_detail
FROM retail.sales_enriched
WHERE quantity <= 0

UNION ALL

SELECT 
    'unit_price < 1000',
    order_id, customer_id, product_id,
    CONCAT('unit_price = ', unit_price)
FROM retail.sales_enriched
WHERE unit_price < 1000

UNION ALL

SELECT 
    'base_price <= 0',
    order_id, customer_id, product_id,
    CONCAT('base_price = ', base_price)
FROM retail.sales_enriched
WHERE base_price <= 0

UNION ALL

SELECT 
    'Negative DiscountAmount',
    order_id, customer_id, product_id,
    CONCAT('DiscountAmount = ', DiscountAmount)
FROM retail.sales_enriched
WHERE DiscountAmount < 0

UNION ALL

SELECT 
    'Missing region',
    order_id, customer_id, product_id,
    'region is NULL or empty'
FROM retail.sales_enriched
WHERE region IS NULL OR region = ''

UNION ALL

SELECT 
    'Missing payment_method',
    order_id, customer_id, product_id,
    'payment_method is NULL'
FROM retail.sales_enriched
WHERE payment_method IS NULL

UNION ALL

SELECT 
    'Missing loyalty_tier',
    order_id, customer_id, product_id,
    'loyalty_tier is NULL'
FROM retail.sales_enriched
WHERE loyalty_tier IS NULL

UNION ALL

SELECT 
    'Unknown product ID',
    order_id, customer_id, product_id,
    'product_id not found in products table'
FROM retail.sales_enriched
WHERE product_known = 0

UNION ALL

SELECT 
    'Unknown customer ID',
    order_id, customer_id, product_id,
    'customer_id not found in customers table'
FROM retail.sales_enriched
WHERE customer_known = 0

ORDER BY check_name, order_id;
GO
