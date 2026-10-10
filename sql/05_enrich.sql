USE RetailDB;
GO

IF OBJECT_ID('retail.sales_enriched', 'U') IS NOT NULL
    DROP TABLE retail.sales_enriched;
GO

SELECT
    s.order_id,
    s.customer_id,
    s.product_id,
    s.quantity,
    s.unit_price,
    s.order_date,
    s.delivery_status,
    s.payment_method,
    COALESCE(s.region, c.region, 'Unknown') AS region,
    s.discount_pct,

    p.product_name,
    p.category,
    p.base_price,
    p.supplier_code,

    c.signup_date,
    COALESCE(c.loyalty_tier, 'Unknown') AS loyalty_tier,

    CASE WHEN p.product_id  IS NULL THEN 0 ELSE 1 END AS product_known,
    CASE WHEN c.customer_id IS NULL THEN 0 ELSE 1 END AS customer_known
INTO retail.sales_enriched
FROM retail.sales_clean      AS s
LEFT JOIN retail.products_clean  AS p ON s.product_id  = p.product_id
LEFT JOIN retail.customers_clean AS c ON s.customer_id = c.customer_id;
GO

SELECT 
    COUNT(*) AS total_rows,
    SUM(product_known)  AS known_products,
    SUM(customer_known) AS known_customers
FROM retail.sales_enriched;
GO

USE RetailDB;
GO

ALTER TABLE retail.sales_enriched
    ADD GrossSales      DECIMAL(18,2) NULL,
        Sales           DECIMAL(18,2) NULL,
        DiscountAmount  DECIMAL(18,2) NULL,
        ExpectedUnitPrice DECIMAL(18,2) NULL,
        PriceDiffPct    DECIMAL(10,2) NULL,
        PriceAnomaly    BIT           NULL;
GO

UPDATE retail.sales_enriched
SET
    GrossSales        = quantity * base_price,
    Sales             = quantity * unit_price,
    DiscountAmount    = quantity * base_price * discount_pct / 100.0,
    ExpectedUnitPrice = base_price * (1 - discount_pct / 100.0);
GO

UPDATE retail.sales_enriched
SET PriceDiffPct = 
        CASE 
            WHEN ExpectedUnitPrice = 0 THEN NULL
            ELSE ((unit_price - ExpectedUnitPrice) / ExpectedUnitPrice) * 100
        END;
GO

UPDATE retail.sales_enriched
SET PriceAnomaly = CASE WHEN ABS(PriceDiffPct) > 5 THEN 1 ELSE 0 END;
GO

SELECT TOP 5 order_id, GrossSales, Sales, DiscountAmount, PriceDiffPct, PriceAnomaly
FROM retail.sales_enriched
ORDER BY order_id;
GO
