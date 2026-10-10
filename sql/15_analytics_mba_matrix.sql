USE RetailDB;
GO

IF OBJECT_ID('retail.mba_order_product_matrix', 'U') IS NOT NULL
    DROP TABLE retail.mba_order_product_matrix;
GO

SELECT
    order_id,
    product_id,
    product_name,
    category,
    SUM(quantity) AS total_quantity    -- aggregate if same product appears on multiple lines
INTO retail.mba_order_product_matrix
FROM retail.sales_enriched
WHERE product_known = 1
  AND delivery_status NOT IN ('Returned', 'Cancelled')   -- only fulfilled orders
GROUP BY order_id, product_id, product_name, category;
GO
