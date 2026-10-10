USE RetailDB;
GO

WITH normalized AS (
    SELECT
        order_id,
        customer_id,
        product_id,
        TRY_CAST(quantity     AS INT)           AS quantity,
        TRY_CAST(unit_price   AS DECIMAL(18,2)) AS unit_price,
        TRY_CAST(order_date   AS DATE)          AS order_date,
        delivery_status,
        payment_method,
        region,
        TRY_CAST(discount_pct AS DECIMAL(5,2))  AS discount_pct,
        ROW_NUMBER() OVER (
            PARTITION BY order_id, product_id, TRY_CAST(order_date AS DATE)
            ORDER BY (SELECT NULL)
        ) AS rn
    FROM retail.sales_raw
    WHERE order_id    IS NOT NULL
      AND customer_id IS NOT NULL
      AND product_id  IS NOT NULL
)
INSERT INTO retail.sales_clean (
    order_id, customer_id, product_id, quantity, unit_price, order_date,
    delivery_status, payment_method, region, discount_pct
)
SELECT
    order_id,
    LTRIM(RTRIM(customer_id)),
    LTRIM(RTRIM(product_id)),
    quantity,
    unit_price,
    order_date,
    CASE LOWER(LTRIM(RTRIM(delivery_status)))
        WHEN 'delivered' THEN 'Delivered'
        WHEN 'deliverd'  THEN 'Delivered'
        WHEN 'returned'  THEN 'Returned'
        WHEN 'cancelled' THEN 'Cancelled'
        WHEN 'canceled'  THEN 'Cancelled'
        WHEN 'pending'   THEN 'Pending'
        WHEN 'shipped'   THEN 'Shipped'
        ELSE NULL
    END,
    CASE LOWER(REPLACE(REPLACE(LTRIM(RTRIM(payment_method)), '  ', ' '), '  ', ' '))
        WHEN 'card on delivery' THEN 'Card on Delivery'
        WHEN 'online payment'   THEN 'Online Payment'
        WHEN 'onlinepayment'    THEN 'Online Payment'
        WHEN 'bank transfer'    THEN 'Bank Transfer'
        WHEN 'banktransfer'     THEN 'Bank Transfer'
        WHEN 'digipay'          THEN 'DigiPay'
        ELSE NULL
    END,
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
    discount_pct
FROM normalized
WHERE rn = 1
  AND quantity     > 0
  AND unit_price   >= 1000
  AND discount_pct BETWEEN 0 AND 100;
GO

SELECT 
    COUNT(*) AS total_clean_sales,
    SUM(CASE WHEN quantity <= 0 THEN 1 ELSE 0 END) AS bad_quantity,
    SUM(CASE WHEN unit_price < 1000 THEN 1 ELSE 0 END) AS bad_price
FROM retail.sales_clean;
GO
