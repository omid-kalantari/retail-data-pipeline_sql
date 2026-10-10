USE RetailDB;
GO

-- Customers clean table
IF OBJECT_ID('retail.customers_clean', 'U') IS NOT NULL
    DROP TABLE retail.customers_clean;

CREATE TABLE retail.customers_clean (
    customer_id   VARCHAR(20)   NOT NULL,
    signup_date   DATE          NULL,
    region        NVARCHAR(100) NULL,
    loyalty_tier  NVARCHAR(50)  NULL
);
GO

-- Products clean table
IF OBJECT_ID('retail.products_clean', 'U') IS NOT NULL
    DROP TABLE retail.products_clean;

CREATE TABLE retail.products_clean (
    product_id     VARCHAR(20)    NOT NULL,
    product_name   NVARCHAR(200)  NOT NULL,
    category       NVARCHAR(100)  NOT NULL,
    base_price     DECIMAL(18,2)  NULL,
    supplier_code  NVARCHAR(50)   NULL
);
GO

-- Sales clean table
IF OBJECT_ID('retail.sales_clean', 'U') IS NOT NULL
    DROP TABLE retail.sales_clean;

CREATE TABLE retail.sales_clean (
    order_id         VARCHAR(20)   NOT NULL,
    customer_id      VARCHAR(20)   NOT NULL,
    product_id       VARCHAR(20)   NOT NULL,
    quantity         INT           NOT NULL,
    unit_price       DECIMAL(18,2) NOT NULL,
    order_date       DATE          NULL,
    delivery_status  NVARCHAR(50)  NULL,
    payment_method   NVARCHAR(100) NULL,
    region           NVARCHAR(100) NULL,
    discount_pct     DECIMAL(5,2)  NULL
);
GO

SELECT 'Staging tables created.' AS status;
GO
