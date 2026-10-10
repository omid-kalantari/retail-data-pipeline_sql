# Data Quality Findings

This document records anomalies discovered during Bronze → Silver cleaning and the deliberate treatment applied. The pipeline prefers **visibility over silent correction**.

## Resolved during cleaning

### Customers (`retail.customers_clean`)

| Issue | Treatment |
| ----- | --------- |
| Duplicate `customer_id` | Keep one row via `ROW_NUMBER() … PARTITION BY customer_id` |
| Invalid signup dates (e.g. month 13, day 45) | `TRY_CAST(signup_date AS DATE)` → NULL when invalid |
| Region casing / spelling variants (`tehran`, `TEHRAN`, `Tehran Province`, `mashad`, `esfahan`, …) | `LOWER(LTRIM(RTRIM(...)))` + `CASE` map to canonical province/city names |
| Loyalty tier casing (`bronze`, `SILVER`, …) | Map to `Bronze` / `Silver` / `Gold` / `Platinum`; unmapped → NULL |

### Products (`retail.products_clean`)

| Issue | Treatment |
| ----- | --------- |
| Duplicate `product_id` | Deduplicate with `ROW_NUMBER()` |
| `base_price = 0` (e.g. product P080) | Converted to NULL, then imputed with category median using `PERCENTILE_CONT(0.5)` |
| Blank / missing `supplier_code` | `COALESCE` to `'Unknown'` |
| Whitespace in names/categories | `LTRIM(RTRIM(...))` |

### Sales (`retail.sales_clean` → `sales_enriched`)

| Issue | Treatment |
| ----- | --------- |
| Duplicate lines | Deduplicate on `(order_id, product_id, order_date)` |
| Negative or zero quantity | **Removed** (BLOCKING) |
| Placeholder / corrupt `unit_price` (&lt; 1000) | **Removed** (BLOCKING) |
| `discount_pct` outside [0, 100] | **Removed** (BLOCKING) |
| Delivery status typos (`deliverd`, `canceled`, …) | Canonical map → Delivered / Returned / Cancelled / Pending / Shipped |
| Payment method variants (`onlinepayment`, `banktransfer`, …) | Canonical map → Card on Delivery / Online Payment / Bank Transfer / DigiPay |
| Region variants on the transaction | Same canonical map as customers; remaining gaps filled from customer master, else `'Unknown'` |

## Open questions (retained, not silently fixed)

These rows stay in Silver/Gold so revenue is not understated and so analysts can see the gaps.

### 1. Missing `payment_method` (~23 rows, ~0.5%)

Valid amounts, customers, and dates, but no payment method.

**Possible causes:** alternate channels (phone / B2B), processor failures, manual entry gaps, promotional/free orders.

**Treatment:** retained; method left unknown / standardized to a visible unknown bucket where applicable. Dropping would understate revenue; inventing a method would fabricate data.

### 2. Unknown `customer_id` (~11 rows, ~0.2%)

`customer_id` present on sales but no match in `customers_clean`.

**Possible causes:** post-sale deletion (e.g. account closure), sync lag, typo, test data.

**Treatment:** retained for revenue; excluded from customer-level Gold via `customer_known = 0`.

### 3. Unknown `product_id` (~9 rows, ~0.2%)

`product_id` on sales with no match in `products_clean` (examples include IDs such as P240, P243, P252, …).

**Possible causes:** discontinued catalog rows, sync lag, typo, new SKUs not yet in master.

**Treatment:** retained for revenue via `Sales = quantity × unit_price`; excluded from product-level metrics via `product_known = 0`. Note: `base_price`, `category`, and `product_name` are NULL for these rows, so GrossSales / DiscountAmount / category rollups do not include them.

## Severity model (Silver DQ extension)

Extended checks in `sql/08_silver_dq_extended.sql` classify issues as:

| Severity | Meaning | Pipeline behaviour |
| -------- | ------- | ------------------ |
| **BLOCKING** | Data corruption that breaks metrics (e.g. qty ≤ 0, future order dates) | Logged; run should be treated as blocked if any issue_count &gt; 0 |
| **WARNING** | Ambiguity or soft anomaly | Logged; pipeline continues |

Results are written to `retail.gold_validation_log` with a derived `pipeline_action` (`BLOCKED` / `WARNED` / `PASSED`).

## Recommendations for production

1. Add upstream constraints or soft-validation at source for quantity, unit price floors, and payment method.
2. Investigate the unknown customer/product IDs with the source system owners.
3. Schedule the DQ suite after each load and alert on any BLOCKING row.
4. Keep Gold builds idempotent so a failed run can be re-executed cleanly after fixes.
