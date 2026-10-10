# Architecture

## Medallion layers

This pipeline follows a classic Bronze → Silver → Gold (medallion) pattern inside a single SQL Server database (`RetailDB`, schema `retail`).

```
┌─────────────────────────────────────────────────────────────┐
│  BRONZE                                                     │
│  customers_raw · products_raw · sales_raw                   │
│  (raw CSV load, minimal typing)                             │
└──────────────────────────┬──────────────────────────────────┘
                           │  cleaning, dedup, standardization
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  SILVER                                                     │
│  customers_clean · products_clean · sales_clean             │
│  sales_enriched · order_summary                             │
│  (+ integrity flags: customer_known, product_known)         │
└──────────────────────────┬──────────────────────────────────┘
                           │  aggregations, RFM, cohorts, risk
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  GOLD                                                       │
│  customer_metrics · customer_clv                            │
│  product_metrics · supplier_metrics                         │
│  time_series_monthly · category_monthly_matrix              │
│  cohort_base · cohort_retention_rates                       │
│  payment_risk_profile · mba_order_product_matrix            │
│  (+ nonclustered indexes for Power BI DirectQuery)          │
└──────────────────────────┬──────────────────────────────────┘
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
         Power BI                    Python EDA
      (DirectQuery)              (pandas / mlxtend)
```

## Design principles

1. **Preserve grain.** Silver line-item fact (`sales_enriched`) stays at order-line grain. Gold tables declare their grain explicitly (one row per customer, product, month, etc.).
2. **Flag, don’t invent.** Referential misses and missing payment methods are retained with flags or `'Unknown'` rather than dropped or imputed arbitrarily.
3. **Idempotent scripts.** Each module drops/recreates its target table (or uses guarded `IF OBJECT_ID`) so re-runs are safe.
4. **Severity-graded DQ.** BLOCKING checks stop or mark the run; WARNING checks log and continue. Results are written to `retail.gold_validation_log`.
5. **Git-friendly source.** Production logic lives in numbered `.sql` files; the notebook is the narrative walkthrough.

## Key transforms

| Step | Module | What it does |
| ---- | ------ | ------------ |
| Setup | `01_setup.sql` | Empty Silver staging tables |
| Customers | `02_clean_customers.sql` | Dedup, safe date parse, region/tier canonicalization |
| Products | `03_clean_products.sql` | Dedup, null zero prices, category-median imputation |
| Sales | `04_clean_sales.sql` | Dedup, type casts, status/payment/region maps, filter bad qty/price/discount |
| Enrich | `05_enrich.sql` | LEFT JOIN products + customers; fill region; compute GrossSales / Sales / DiscountAmount |
| Order rollup | `06_compute_metrics.sql` | `order_summary` at order grain |
| Validation | `07_validation.sql`, `08_silver_dq_extended.sql` | Count checks + extended BLOCKING/WARNING suite + audit log |
| Customer Gold | `09_analytics_customer_metrics.sql` | RFM (`NTILE`) + CLV |
| Product / supplier | `10_…`, `11_…` | Rank, return rates, supplier scorecard |
| Time / cohort | `12_…`, `13_…` | Monthly series, cohort base + retention % |
| Risk / MBA | `14_…`, `15_…` | Payment risk profile, order–product matrix for Apriori |
| Indexes | `16_indexes.sql` | Nonclustered indexes on common filter/sort columns |

## Customer metrics grain (important)

`retail.customer_metrics` is **one row per known `customer_id`**.

- Sales are aggregated with `GROUP BY customer_id` only.
- Region is the **modal** shipping region (most frequent), resolved with `ROW_NUMBER()`.
- Loyalty tier and signup date come from `customers_clean` (stable attributes), not from the fact table.
- RFM scores use `NTILE(5)` over that customer-grain set.

After a full re-run, `COUNT(*)` on `customer_metrics` should equal distinct `customer_id` values in `sales_enriched` where `customer_known = 1`.

## Downstream consumers

- **Power BI:** DirectQuery against Gold tables; indexes in `16_indexes.sql` target common filters (`loyalty_tier`, `region`, `category`, year-month, cohort keys).
- **Python:** Load the ten Gold tables listed in the notebook handoff section; no extra SQL required for EDA or Apriori on `mba_order_product_matrix`.
