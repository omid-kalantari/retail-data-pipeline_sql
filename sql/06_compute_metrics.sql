USE RetailDB;
GO

IF OBJECT_ID('retail.order_summary', 'U') IS NOT NULL
    DROP TABLE retail.order_summary;
GO

SELECT
    order_id,
    SUM(Sales)                    AS Sales,
    SUM(GrossSales)               AS GrossSales,
    SUM(DiscountAmount)           AS DiscountAmount,
    MIN(order_date)               AS order_date,
    MAX(delivery_status)          AS delivery_status,
    COUNT(DISTINCT product_id)    AS distinct_products,
    COUNT(*)                      AS line_items
INTO retail.order_summary
FROM retail.sales_enriched
GROUP BY order_id;
GO

SELECT TOP 10 * FROM retail.order_summary ORDER BY Sales DESC;
GO
