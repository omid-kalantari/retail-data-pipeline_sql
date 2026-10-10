USE RetailDB;
GO

-- customer_metrics: Power BI filters most often by loyalty_tier and region
CREATE NONCLUSTERED INDEX IX_customer_metrics_tier_region
    ON retail.customer_metrics (loyalty_tier, region)
    INCLUDE (total_revenue, rfm_segment, r_score, f_score, m_score);

-- product_metrics: filtered by category and ranked by revenue
CREATE NONCLUSTERED INDEX IX_product_metrics_category_revenue
    ON retail.product_metrics (category, revenue_rank_in_category)
    INCLUDE (total_revenue, return_rate, product_name);

-- time_series_monthly: always filtered/sorted by date
CREATE NONCLUSTERED INDEX IX_tsm_year_month
    ON retail.time_series_monthly (order_year, order_month)
    INCLUDE (total_revenue, mom_growth_pct, unique_customers);

-- cohort_retention_rates: heatmap queries by cohort_month and cohort_index
CREATE NONCLUSTERED INDEX IX_cohort_month_index
    ON retail.cohort_retention_rates (cohort_month, cohort_index)
    INCLUDE (retention_rate_pct, cohort_size);
GO
