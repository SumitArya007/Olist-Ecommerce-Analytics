/* ============================================================
   1. DATABASE SETUP
   ============================================================ */
IF DB_ID('OlistEcommerceAnalytics') IS NULL
BEGIN
    CREATE DATABASE OlistEcommerceAnalytics;
END;
GO

USE OlistEcommerceAnalytics;
GO

/* ============================================================
   END OF 1. DATABASE SETUP
   ============================================================ */

   /* ============================================================
   2. DATA QUALITY CHECKS
   ============================================================ */

-- 2.1 Row counts of imported tables
SELECT 'customers_clean' AS table_name, COUNT(*) AS row_count
FROM dbo.customers_clean
UNION ALL
SELECT 'orders_clean', COUNT(*)
FROM dbo.orders_clean
UNION ALL
SELECT 'order_items_clean', COUNT(*)
FROM dbo.order_items_clean
UNION ALL
SELECT 'products_clean', COUNT(*)
FROM dbo.products_clean
UNION ALL
SELECT 'sellers_clean', COUNT(*)
FROM dbo.sellers_clean
UNION ALL
SELECT 'payments_clean', COUNT(*)
FROM dbo.payments_clean
UNION ALL
SELECT 'reviews_clean', COUNT(*)
FROM dbo.reviews_clean
UNION ALL
SELECT 'customer_order_counts', COUNT(*)
FROM dbo.customer_order_counts
UNION ALL
SELECT 'product_demand_proxy', COUNT(*)
FROM dbo.product_demand_proxy;
GO


-- 2.2 Duplicate checks for key columns

SELECT
    order_id,
    COUNT(*) AS duplicate_count
FROM dbo.orders_clean
GROUP BY order_id
HAVING COUNT(*) > 1;
GO


SELECT
    customer_id,
    COUNT(*) AS duplicate_count
FROM dbo.customers_clean
GROUP BY customer_id
HAVING COUNT(*) > 1;
GO


SELECT
    product_id,
    COUNT(*) AS duplicate_count
FROM dbo.products_clean
GROUP BY product_id
HAVING COUNT(*) > 1;
GO


SELECT
    seller_id,
    COUNT(*) AS duplicate_count
FROM dbo.sellers_clean
GROUP BY seller_id
HAVING COUNT(*) > 1;
GO


-- 2.3 Missing-value checks

SELECT
    COUNT(*) AS total_orders,
    SUM(CASE WHEN order_approved_at IS NULL THEN 1 ELSE 0 END)
        AS missing_order_approved_at,
    SUM(CASE WHEN order_delivered_carrier_date IS NULL THEN 1 ELSE 0 END)
        AS missing_carrier_date,
    SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END)
        AS missing_customer_delivery_date
FROM dbo.orders_clean;
GO


SELECT
    SUM(CASE WHEN product_category_name IS NULL THEN 1 ELSE 0 END)
        AS missing_product_category,
    SUM(CASE WHEN product_weight_g IS NULL THEN 1 ELSE 0 END)
        AS missing_product_weight,
    SUM(CASE WHEN product_length_cm IS NULL THEN 1 ELSE 0 END)
        AS missing_product_length,
    SUM(CASE WHEN product_height_cm IS NULL THEN 1 ELSE 0 END)
        AS missing_product_height,
    SUM(CASE WHEN product_width_cm IS NULL THEN 1 ELSE 0 END)
        AS missing_product_width
FROM dbo.products_clean;
GO


-- 2.4 Business-rule checks

SELECT
    SUM(CASE WHEN price < 0 THEN 1 ELSE 0 END) AS negative_price_rows,
    SUM(CASE WHEN freight_value < 0 THEN 1 ELSE 0 END) AS negative_freight_rows
FROM dbo.order_items_clean;
GO


SELECT
    SUM(CASE WHEN payment_value < 0 THEN 1 ELSE 0 END)
        AS negative_payment_value_rows
FROM dbo.payments_clean;
GO


SELECT
    SUM(CASE WHEN review_score NOT BETWEEN 1 AND 5 THEN 1 ELSE 0 END)
        AS invalid_review_score_rows
FROM dbo.reviews_clean;
GO


SELECT
    COUNT(*) AS invalid_purchase_delivery_sequence
FROM dbo.orders_clean
WHERE order_purchase_timestamp IS NOT NULL
  AND order_delivered_customer_date IS NOT NULL
  AND order_purchase_timestamp > order_delivered_customer_date;
GO


/* ============================================================
   END OF 2. DATA QUALITY CHECKS
   ============================================================ */


   /* ============================================================
   3. ANALYTICAL VIEWS
   ============================================================ */


/* ------------------------------------------------------------
   3.1 ORDER ITEM SUMMARY VIEW

   Purpose:
   Convert multiple item rows into one row per order.
   This prevents duplicate revenue when joining with payments.
   ------------------------------------------------------------ */

CREATE OR ALTER VIEW dbo.vw_order_item_summary
AS
SELECT
    order_id,

    COUNT(*) AS item_lines,

    COUNT(DISTINCT product_id) AS unique_products,

    COUNT(DISTINCT seller_id) AS unique_sellers,

    SUM(price) AS merchandise_value,

    SUM(freight_value) AS freight_value,

    SUM(price + freight_value) AS order_total_with_freight

FROM dbo.order_items_clean

GROUP BY order_id;
GO



/* ------------------------------------------------------------
   3.2 PAYMENT SUMMARY VIEW

   Purpose:
   Convert multiple payment rows into one row per order.
   ------------------------------------------------------------ */

CREATE OR ALTER VIEW dbo.vw_payment_summary
AS
SELECT
    order_id,

    COUNT(*) AS payment_rows,

    SUM(payment_value) AS payment_value,

    MAX(payment_installments) AS max_installments

FROM dbo.payments_clean

GROUP BY order_id;
GO



/* ------------------------------------------------------------
   3.3 ENRICHED ORDER-LEVEL VIEW

   Purpose:
   Combine orders, item summary, and payment summary
   while keeping exactly one row per order.
   ------------------------------------------------------------ */

CREATE OR ALTER VIEW dbo.vw_orders_enriched
AS
SELECT
    o.order_id,

    o.customer_id,

    o.order_status,

    o.order_purchase_timestamp,

    o.order_approved_at,

    o.order_delivered_carrier_date,

    o.order_delivered_customer_date,

    o.order_estimated_delivery_date,

    o.purchase_year,

    o.purchase_month,

    o.purchase_weekday,

    o.delivery_days,

    o.delivery_delay_days,

    o.is_late_delivery,

    o.is_delivered,

    o.is_cancelled,


    -- Order item metrics
    i.item_lines,

    i.unique_products,

    i.unique_sellers,

    i.merchandise_value,

    i.freight_value,

    i.order_total_with_freight,


    -- Freight burden percentage
    CASE
        WHEN i.merchandise_value > 0
        THEN (i.freight_value * 100.0) / i.merchandise_value
        ELSE NULL
    END AS freight_ratio_pct,


    -- Payment metrics
    p.payment_rows,

    p.payment_value,

    p.max_installments,


    -- Reconciliation difference
    p.payment_value - i.order_total_with_freight
        AS payment_vs_order_value_difference

FROM dbo.orders_clean AS o

LEFT JOIN dbo.vw_order_item_summary AS i
    ON o.order_id = i.order_id

LEFT JOIN dbo.vw_payment_summary AS p
    ON o.order_id = p.order_id;
GO



/* ------------------------------------------------------------
   3.4 VERIFY ANALYTICAL VIEWS
   ------------------------------------------------------------ */

SELECT COUNT(*) AS order_item_summary_rows
FROM dbo.vw_order_item_summary;
GO


SELECT COUNT(*) AS payment_summary_rows
FROM dbo.vw_payment_summary;
GO


SELECT COUNT(*) AS orders_enriched_rows
FROM dbo.vw_orders_enriched;
GO


-- Check that the enriched view still has one row per order
SELECT
    order_id,
    COUNT(*) AS row_count
FROM dbo.vw_orders_enriched
GROUP BY order_id
HAVING COUNT(*) > 1;
GO



/* ============================================================
   END OF 3. ANALYTICAL VIEWS
   ============================================================ */


   /* ============================================================
   4. EXECUTIVE KPI ANALYSIS
   ============================================================ */


/* ------------------------------------------------------------
   4.1 OVERALL BUSINESS KPIs

   Purpose:
   Create a high-level summary of marketplace performance.

   KPIs:
   - Total Orders
   - Delivered Orders
   - Delivered Merchandise Value
   - Average Delivered Order Value
   - Delivered Freight Value
   - Cancellation Rate
   - On-Time Delivery Rate
   - Average Delivery Days
   ------------------------------------------------------------ */

SELECT
    COUNT(DISTINCT order_id) AS total_orders,

    COUNT(DISTINCT CASE
        WHEN order_status = 'delivered'
        THEN order_id
    END) AS delivered_orders,


    -- Merchandise value from successfully delivered orders
    SUM(CASE
        WHEN order_status = 'delivered'
        THEN merchandise_value
        ELSE 0
    END) AS delivered_merchandise_value,


    -- Average merchandise value per delivered order
    AVG(CASE
        WHEN order_status = 'delivered'
        THEN merchandise_value
    END) AS avg_delivered_order_value,


    -- Total freight associated with delivered orders
    SUM(CASE
        WHEN order_status = 'delivered'
        THEN freight_value
        ELSE 0
    END) AS delivered_freight_value,


    -- Percentage of orders that were cancelled
    100.0 *
    SUM(CASE
        WHEN order_status = 'canceled'
        THEN 1
        ELSE 0
    END)
    / NULLIF(COUNT(*), 0)
        AS cancellation_rate_pct,


    -- Percentage of delivered orders completed
    -- on or before the estimated delivery date
    100.0 *
    SUM(CASE
        WHEN order_status = 'delivered'
             AND is_late_delivery = 0
        THEN 1
        ELSE 0
    END)
    /
    NULLIF(
        SUM(CASE
            WHEN order_status = 'delivered'
            THEN 1
            ELSE 0
        END),
        0
    )
        AS on_time_delivery_rate_pct,


    -- Average number of days from purchase to delivery
    AVG(CASE
        WHEN order_status = 'delivered'
        THEN delivery_days
    END) AS avg_delivery_days

FROM dbo.vw_orders_enriched;
GO



/* ============================================================
   END OF 4. EXECUTIVE KPI ANALYSIS
   ============================================================ */

   /* ============================================================
   5. MONTHLY TREND ANALYSIS
   ============================================================ */


/* ------------------------------------------------------------
   5.1 MONTHLY ORDER AND MERCHANDISE VALUE TREND

   Purpose:
   Analyze how orders, merchandise value, and freight
   change month by month.
   ------------------------------------------------------------ */

SELECT
    purchase_month,

    COUNT(DISTINCT order_id) AS total_orders,

    COUNT(DISTINCT CASE
        WHEN order_status = 'delivered'
        THEN order_id
    END) AS delivered_orders,

    SUM(CASE
        WHEN order_status = 'delivered'
        THEN merchandise_value
        ELSE 0
    END) AS delivered_merchandise_value,

    SUM(CASE
        WHEN order_status = 'delivered'
        THEN freight_value
        ELSE 0
    END) AS delivered_freight_value,

    AVG(CASE
        WHEN order_status = 'delivered'
        THEN merchandise_value
    END) AS avg_delivered_order_value

FROM dbo.vw_orders_enriched

GROUP BY purchase_month

ORDER BY purchase_month;
GO



/* ------------------------------------------------------------
   5.2 MONTHLY CANCELLATION AND DELIVERY PERFORMANCE

   Purpose:
   Track operational performance month by month.
   ------------------------------------------------------------ */

SELECT
    purchase_month,

    COUNT(*) AS total_orders,

    100.0 *
    SUM(CASE
        WHEN order_status = 'canceled'
        THEN 1
        ELSE 0
    END)
    / NULLIF(COUNT(*), 0)
        AS cancellation_rate_pct,

    100.0 *
    SUM(CASE
        WHEN order_status = 'delivered'
             AND is_late_delivery = 0
        THEN 1
        ELSE 0
    END)
    /
    NULLIF(
        SUM(CASE
            WHEN order_status = 'delivered'
            THEN 1
            ELSE 0
        END),
        0
    )
        AS on_time_delivery_rate_pct,

    AVG(CASE
        WHEN order_status = 'delivered'
        THEN delivery_days
    END) AS avg_delivery_days

FROM dbo.vw_orders_enriched

GROUP BY purchase_month

ORDER BY purchase_month;
GO



/* ============================================================
   END OF 5. MONTHLY TREND ANALYSIS
   ============================================================ */

   /* ============================================================
   6. MONTH-OVER-MONTH GROWTH ANALYSIS
   ============================================================ */


/* ------------------------------------------------------------
   6.1 MONTH-OVER-MONTH MERCHANDISE VALUE GROWTH

   Purpose:
   Compare each month's delivered merchandise value
   with the previous month using LAG().
   ------------------------------------------------------------ */

WITH monthly_sales AS
(
    SELECT
        purchase_month,

        SUM(CASE
            WHEN order_status = 'delivered'
            THEN merchandise_value
            ELSE 0
        END) AS monthly_merchandise_value

    FROM dbo.vw_orders_enriched

    GROUP BY purchase_month
),

monthly_with_previous AS
(
    SELECT
        purchase_month,

        monthly_merchandise_value,

        LAG(monthly_merchandise_value)
            OVER (ORDER BY purchase_month)
            AS previous_month_value

    FROM monthly_sales
)

SELECT
    purchase_month,

    monthly_merchandise_value,

    previous_month_value,

    CASE
        WHEN previous_month_value IS NULL
             OR previous_month_value = 0
        THEN NULL

        ELSE
            (
                monthly_merchandise_value
                - previous_month_value
            )
            * 100.0
            / previous_month_value
    END AS mom_growth_pct

FROM monthly_with_previous

ORDER BY purchase_month;
GO



/* ------------------------------------------------------------
   6.2 MONTH-OVER-MONTH ORDER GROWTH

   Purpose:
   Measure how total order volume changes compared
   with the previous month.
   ------------------------------------------------------------ */

WITH monthly_orders AS
(
    SELECT
        purchase_month,

        COUNT(DISTINCT order_id) AS total_orders

    FROM dbo.vw_orders_enriched

    GROUP BY purchase_month
),

orders_with_previous AS
(
    SELECT
        purchase_month,

        total_orders,

        LAG(total_orders)
            OVER (ORDER BY purchase_month)
            AS previous_month_orders

    FROM monthly_orders
)

SELECT
    purchase_month,

    total_orders,

    previous_month_orders,

    CASE
        WHEN previous_month_orders IS NULL
             OR previous_month_orders = 0
        THEN NULL

        ELSE
            (
                total_orders
                - previous_month_orders
            )
            * 100.0
            / previous_month_orders
    END AS mom_order_growth_pct

FROM orders_with_previous

ORDER BY purchase_month;
GO



/* ============================================================
   END OF 6. MONTH-OVER-MONTH GROWTH ANALYSIS
   ============================================================ */

   /* ============================================================
   7. PRODUCT CATEGORY ANALYSIS
   ============================================================ */


/* ------------------------------------------------------------
   7.1 CATEGORY PERFORMANCE SUMMARY

   Purpose:
   Compare product categories based on delivered orders,
   item volume, merchandise value, freight and average price.
   ------------------------------------------------------------ */

SELECT
    COALESCE(p.product_category_english, 'unknown')
        AS product_category,

    COUNT(DISTINCT oi.order_id)
        AS delivered_orders,

    COUNT(*)
        AS delivered_item_lines,

    SUM(oi.price)
        AS merchandise_value,

    SUM(oi.freight_value)
        AS freight_value,

    AVG(oi.price)
        AS avg_item_price

FROM dbo.order_items_clean AS oi

LEFT JOIN dbo.products_clean AS p
    ON oi.product_id = p.product_id

INNER JOIN dbo.orders_clean AS o
    ON oi.order_id = o.order_id

WHERE o.order_status = 'delivered'

GROUP BY
    COALESCE(p.product_category_english, 'unknown')

ORDER BY merchandise_value DESC;
GO



/* ------------------------------------------------------------
   7.2 TOP 15 PRODUCT CATEGORIES BY MERCHANDISE VALUE

   Purpose:
   Rank categories using DENSE_RANK().
   ------------------------------------------------------------ */

WITH category_sales AS
(
    SELECT
        COALESCE(p.product_category_english, 'unknown')
            AS product_category,

        SUM(oi.price)
            AS merchandise_value

    FROM dbo.order_items_clean AS oi

    LEFT JOIN dbo.products_clean AS p
        ON oi.product_id = p.product_id

    INNER JOIN dbo.orders_clean AS o
        ON oi.order_id = o.order_id

    WHERE o.order_status = 'delivered'

    GROUP BY
        COALESCE(p.product_category_english, 'unknown')
),

ranked_categories AS
(
    SELECT
        product_category,

        merchandise_value,

        DENSE_RANK()
            OVER (ORDER BY merchandise_value DESC)
            AS category_rank

    FROM category_sales
)

SELECT
    product_category,

    merchandise_value,

    category_rank

FROM ranked_categories

WHERE category_rank <= 15

ORDER BY category_rank;
GO



/* ------------------------------------------------------------
   7.3 FREIGHT BURDEN BY CATEGORY

   Purpose:
   Identify categories where freight represents a larger
   share of merchandise value.
   ------------------------------------------------------------ */

SELECT
    COALESCE(p.product_category_english, 'unknown')
        AS product_category,

    SUM(oi.price)
        AS merchandise_value,

    SUM(oi.freight_value)
        AS freight_value,

    CASE
        WHEN SUM(oi.price) > 0
        THEN
            SUM(oi.freight_value) * 100.0
            / SUM(oi.price)
        ELSE NULL
    END AS freight_ratio_pct

FROM dbo.order_items_clean AS oi

INNER JOIN dbo.orders_clean AS o
    ON oi.order_id = o.order_id

LEFT JOIN dbo.products_clean AS p
    ON oi.product_id = p.product_id

WHERE o.order_status = 'delivered'

GROUP BY
    COALESCE(p.product_category_english, 'unknown')

ORDER BY freight_ratio_pct DESC;
GO



/* ============================================================
   END OF 7. PRODUCT CATEGORY ANALYSIS
   ============================================================ */

   /* ============================================================
   8. SELLER PERFORMANCE ANALYSIS
   ============================================================ */


/* ------------------------------------------------------------
   8.1 SELLER PERFORMANCE SUMMARY

   Purpose:
   Compare sellers based on delivered orders,
   merchandise value, freight, delivery time,
   and on-time performance.
   ------------------------------------------------------------ */

SELECT
    s.seller_id,

    s.seller_state,

    COUNT(DISTINCT oi.order_id)
        AS delivered_orders,

    SUM(oi.price)
        AS merchandise_value,

    SUM(oi.freight_value)
        AS freight_value,

    AVG(CAST(o.delivery_days AS DECIMAL(18,2)))
        AS avg_delivery_days,

    100.0 *
    SUM(CASE
        WHEN o.is_late_delivery = 0
        THEN 1
        ELSE 0
    END)
    / NULLIF(COUNT(*), 0)
        AS on_time_item_line_rate_pct

FROM dbo.order_items_clean AS oi

INNER JOIN dbo.orders_clean AS o
    ON oi.order_id = o.order_id

LEFT JOIN dbo.sellers_clean AS s
    ON oi.seller_id = s.seller_id

WHERE o.order_status = 'delivered'

GROUP BY
    s.seller_id,
    s.seller_state

ORDER BY merchandise_value DESC;
GO



/* ------------------------------------------------------------
   8.2 TOP 20 SELLERS BY MERCHANDISE VALUE

   Purpose:
   Identify the highest-value sellers.
   ------------------------------------------------------------ */

WITH seller_sales AS
(
    SELECT
        s.seller_id,

        s.seller_state,

        COUNT(DISTINCT oi.order_id)
            AS delivered_orders,

        SUM(oi.price)
            AS merchandise_value

    FROM dbo.order_items_clean AS oi

    INNER JOIN dbo.orders_clean AS o
        ON oi.order_id = o.order_id

    LEFT JOIN dbo.sellers_clean AS s
        ON oi.seller_id = s.seller_id

    WHERE o.order_status = 'delivered'

    GROUP BY
        s.seller_id,
        s.seller_state
),

ranked_sellers AS
(
    SELECT
        seller_id,

        seller_state,

        delivered_orders,

        merchandise_value,

        DENSE_RANK()
            OVER (ORDER BY merchandise_value DESC)
            AS seller_rank

    FROM seller_sales
)

SELECT
    seller_id,

    seller_state,

    delivered_orders,

    merchandise_value,

    seller_rank

FROM ranked_sellers

WHERE seller_rank <= 20

ORDER BY seller_rank;
GO



/* ------------------------------------------------------------
   8.3 SELLERS WITH LOWER ON-TIME PERFORMANCE

   Purpose:
   Identify sellers with meaningful delivered volume
   but weaker on-time delivery performance.

   Note:
   Minimum 20 delivered item lines are used so that
   very small sellers do not dominate the result.
   ------------------------------------------------------------ */

SELECT
    s.seller_id,

    s.seller_state,

    COUNT(*) AS delivered_item_lines,

    COUNT(DISTINCT oi.order_id)
        AS delivered_orders,

    100.0 *
    SUM(CASE
        WHEN o.is_late_delivery = 0
        THEN 1
        ELSE 0
    END)
    / NULLIF(COUNT(*), 0)
        AS on_time_item_line_rate_pct,

    AVG(CAST(o.delivery_days AS DECIMAL(18,2)))
        AS avg_delivery_days

FROM dbo.order_items_clean AS oi

INNER JOIN dbo.orders_clean AS o
    ON oi.order_id = o.order_id

LEFT JOIN dbo.sellers_clean AS s
    ON oi.seller_id = s.seller_id

WHERE o.order_status = 'delivered'

GROUP BY
    s.seller_id,
    s.seller_state

HAVING COUNT(*) >= 20

ORDER BY
    on_time_item_line_rate_pct ASC,
    delivered_orders DESC;
GO



/* ============================================================
   END OF 8. SELLER PERFORMANCE ANALYSIS
   ============================================================ */

   /* ============================================================
   9. CUSTOMER ANALYSIS
   ============================================================ */


/* ------------------------------------------------------------
   9.1 UNIQUE AND REPEAT CUSTOMER SUMMARY

   Purpose:
   Measure customer retention using customer_unique_id.

   Important:
   customer_id is order-specific in this dataset.
   customer_unique_id should be used for repeat-customer analysis.
   ------------------------------------------------------------ */

WITH customer_orders AS
(
    SELECT
        c.customer_unique_id,

        COUNT(DISTINCT o.order_id)
            AS order_count

    FROM dbo.orders_clean AS o

    INNER JOIN dbo.customers_clean AS c
        ON o.customer_id = c.customer_id

    GROUP BY
        c.customer_unique_id
)

SELECT
    COUNT(*) AS unique_customers,

    SUM(CASE
        WHEN order_count > 1
        THEN 1
        ELSE 0
    END) AS repeat_customers,

    100.0 *
    SUM(CASE
        WHEN order_count > 1
        THEN 1
        ELSE 0
    END)
    / NULLIF(COUNT(*), 0)
        AS repeat_customer_rate_pct

FROM customer_orders;
GO



/* ------------------------------------------------------------
   9.2 CUSTOMER ORDER FREQUENCY DISTRIBUTION

   Purpose:
   Understand how many customers placed
   1 order, 2 orders, 3 orders, and so on.
   ------------------------------------------------------------ */

WITH customer_frequency AS
(
    SELECT
        c.customer_unique_id,

        COUNT(DISTINCT o.order_id)
            AS order_count

    FROM dbo.orders_clean AS o

    INNER JOIN dbo.customers_clean AS c
        ON o.customer_id = c.customer_id

    GROUP BY
        c.customer_unique_id
)

SELECT
    order_count,

    COUNT(*) AS customers

FROM customer_frequency

GROUP BY order_count

ORDER BY order_count;
GO



/* ------------------------------------------------------------
   9.3 CUSTOMER STATE ANALYSIS

   Purpose:
   Compare customer geography based on orders,
   unique customers, and delivered merchandise value.
   ------------------------------------------------------------ */

SELECT
    c.customer_state,

    COUNT(DISTINCT o.order_id)
        AS total_orders,

    COUNT(DISTINCT c.customer_unique_id)
        AS unique_customers,

    SUM(CASE
        WHEN o.order_status = 'delivered'
        THEN e.merchandise_value
        ELSE 0
    END) AS delivered_merchandise_value,

    AVG(CASE
        WHEN o.order_status = 'delivered'
        THEN e.merchandise_value
    END) AS avg_delivered_order_value

FROM dbo.orders_clean AS o

INNER JOIN dbo.customers_clean AS c
    ON o.customer_id = c.customer_id

LEFT JOIN dbo.vw_orders_enriched AS e
    ON o.order_id = e.order_id

GROUP BY
    c.customer_state

ORDER BY
    delivered_merchandise_value DESC;
GO



/* ------------------------------------------------------------
   9.4 CUSTOMER FREQUENCY SEGMENTATION USING NTILE

   Purpose:
   Divide customers into four groups based on
   historical order frequency.

   NTILE(4):
   1 = highest frequency group
   4 = lowest frequency group
   ------------------------------------------------------------ */

WITH customer_metrics AS
(
    SELECT
        c.customer_unique_id,

        COUNT(DISTINCT o.order_id)
            AS order_count,

        MIN(o.order_purchase_timestamp)
            AS first_order_date,

        MAX(o.order_purchase_timestamp)
            AS last_order_date

    FROM dbo.orders_clean AS o

    INNER JOIN dbo.customers_clean AS c
        ON o.customer_id = c.customer_id

    GROUP BY
        c.customer_unique_id
),

customer_segments AS
(
    SELECT
        customer_unique_id,

        order_count,

        first_order_date,

        last_order_date,

        NTILE(4) OVER
        (
            ORDER BY order_count DESC
        ) AS frequency_quartile

    FROM customer_metrics
)

SELECT
    customer_unique_id,

    order_count,

    first_order_date,

    last_order_date,

    frequency_quartile

FROM customer_segments

ORDER BY
    frequency_quartile,
    order_count DESC;
GO



/* ------------------------------------------------------------
   9.5 CUSTOMER FREQUENCY SEGMENT SUMMARY

   Purpose:
   Summarize the NTILE customer segments.
   ------------------------------------------------------------ */

WITH customer_metrics AS
(
    SELECT
        c.customer_unique_id,

        COUNT(DISTINCT o.order_id)
            AS order_count

    FROM dbo.orders_clean AS o

    INNER JOIN dbo.customers_clean AS c
        ON o.customer_id = c.customer_id

    GROUP BY
        c.customer_unique_id
),

customer_segments AS
(
    SELECT
        customer_unique_id,

        order_count,

        NTILE(4) OVER
        (
            ORDER BY order_count DESC
        ) AS frequency_quartile

    FROM customer_metrics
)

SELECT
    frequency_quartile,

    COUNT(*) AS customers,

    AVG(CAST(order_count AS DECIMAL(18,2)))
        AS avg_orders_per_customer,

    MIN(order_count)
        AS minimum_orders,

    MAX(order_count)
        AS maximum_orders

FROM customer_segments

GROUP BY
    frequency_quartile

ORDER BY
    frequency_quartile;
GO



/* ============================================================
   END OF 9. CUSTOMER ANALYSIS
   ============================================================ */

   /* ============================================================
   10. PAYMENT ANALYSIS
   ============================================================ */


/* ------------------------------------------------------------
   10.1 PAYMENT METHOD SUMMARY

   Purpose:
   Compare payment methods by transaction volume,
   total payment value, average payment value,
   and installment usage.
   ------------------------------------------------------------ */

SELECT
    payment_type,

    COUNT(*) AS payment_rows,

    COUNT(DISTINCT order_id)
        AS orders,

    SUM(payment_value)
        AS total_payment_value,

    AVG(payment_value)
        AS avg_payment_value,

    AVG(CAST(payment_installments AS DECIMAL(18,2)))
        AS avg_installments

FROM dbo.payments_clean

GROUP BY payment_type

ORDER BY total_payment_value DESC;
GO



/* ------------------------------------------------------------
   10.2 PAYMENT METHOD SHARE

   Purpose:
   Calculate each payment method's percentage
   contribution to total payment value.
   ------------------------------------------------------------ */

WITH payment_totals AS
(
    SELECT
        payment_type,

        SUM(payment_value)
            AS payment_value

    FROM dbo.payments_clean

    GROUP BY payment_type
),

grand_total AS
(
    SELECT
        SUM(payment_value)
            AS total_payment_value

    FROM payment_totals
)

SELECT
    p.payment_type,

    p.payment_value,

    100.0 *
    p.payment_value
    / NULLIF(g.total_payment_value, 0)
        AS payment_value_share_pct

FROM payment_totals AS p

CROSS JOIN grand_total AS g

ORDER BY
    payment_value_share_pct DESC;
GO



/* ------------------------------------------------------------
   10.3 INSTALLMENT ANALYSIS

   Purpose:
   Analyze how customers use installment payments.
   ------------------------------------------------------------ */

SELECT
    payment_installments,

    COUNT(*) AS payment_rows,

    COUNT(DISTINCT order_id)
        AS orders,

    SUM(payment_value)
        AS total_payment_value,

    AVG(payment_value)
        AS avg_payment_value

FROM dbo.payments_clean

GROUP BY payment_installments

ORDER BY payment_installments;
GO



/* ------------------------------------------------------------
   10.4 PAYMENT RECONCILIATION SUMMARY

   Purpose:
   Compare total payment value with
   item value + freight at order level.

   Note:
   Differences should be investigated and not
   automatically treated as errors.
   ------------------------------------------------------------ */

SELECT
    COUNT(*) AS orders_compared,

    SUM(CASE
        WHEN ABS(payment_vs_order_value_difference) <= 0.01
        THEN 1
        ELSE 0
    END) AS reconciled_orders,

    SUM(CASE
        WHEN ABS(payment_vs_order_value_difference) > 0.01
        THEN 1
        ELSE 0
    END) AS orders_with_difference,

    AVG(
        ABS(payment_vs_order_value_difference)
    ) AS avg_absolute_difference

FROM dbo.vw_orders_enriched

WHERE payment_value IS NOT NULL
  AND order_total_with_freight IS NOT NULL;
GO



/* ============================================================
   END OF 10. PAYMENT ANALYSIS
   ============================================================ */

   /* ============================================================
   11. DELIVERY ANALYSIS
   ============================================================ */


/* ------------------------------------------------------------
   11.1 OVERALL DELIVERY PERFORMANCE

   Purpose:
   Measure delivery speed and late-delivery behavior.
   ------------------------------------------------------------ */

SELECT
    COUNT(DISTINCT order_id) AS delivered_orders,

    AVG(CAST(delivery_days AS DECIMAL(18,2)))
        AS avg_delivery_days,

    AVG(CAST(delivery_delay_days AS DECIMAL(18,2)))
        AS avg_delivery_delay_days,

    SUM(CASE
        WHEN is_late_delivery = 1
        THEN 1
        ELSE 0
    END) AS late_orders,

    100.0 *
    SUM(CASE
        WHEN is_late_delivery = 1
        THEN 1
        ELSE 0
    END)
    / NULLIF(COUNT(*), 0)
        AS late_delivery_rate_pct,

    100.0 *
    SUM(CASE
        WHEN is_late_delivery = 0
        THEN 1
        ELSE 0
    END)
    / NULLIF(COUNT(*), 0)
        AS on_time_delivery_rate_pct

FROM dbo.orders_clean

WHERE order_status = 'delivered';
GO



/* ------------------------------------------------------------
   11.2 DELIVERY PERFORMANCE BY CUSTOMER STATE

   Purpose:
   Compare delivery speed and lateness across states.
   ------------------------------------------------------------ */

SELECT
    c.customer_state,

    COUNT(DISTINCT o.order_id)
        AS delivered_orders,

    AVG(CAST(o.delivery_days AS DECIMAL(18,2)))
        AS avg_delivery_days,

    AVG(CAST(o.delivery_delay_days AS DECIMAL(18,2)))
        AS avg_delivery_delay_days,

    100.0 *
    SUM(CASE
        WHEN o.is_late_delivery = 1
        THEN 1
        ELSE 0
    END)
    / NULLIF(COUNT(*), 0)
        AS late_delivery_rate_pct

FROM dbo.orders_clean AS o

INNER JOIN dbo.customers_clean AS c
    ON o.customer_id = c.customer_id

WHERE o.order_status = 'delivered'

GROUP BY
    c.customer_state

ORDER BY
    late_delivery_rate_pct DESC;
GO



/* ------------------------------------------------------------
   11.3 DELIVERY PERFORMANCE BY PRODUCT CATEGORY

   Purpose:
   Identify categories associated with slower
   or weaker delivery performance.
   ------------------------------------------------------------ */

SELECT
    COALESCE(p.product_category_english, 'unknown')
        AS product_category,

    COUNT(DISTINCT oi.order_id)
        AS delivered_orders,

    AVG(CAST(o.delivery_days AS DECIMAL(18,2)))
        AS avg_delivery_days,

    100.0 *
    SUM(CASE
        WHEN o.is_late_delivery = 1
        THEN 1
        ELSE 0
    END)
    / NULLIF(COUNT(*), 0)
        AS late_item_line_rate_pct

FROM dbo.order_items_clean AS oi

INNER JOIN dbo.orders_clean AS o
    ON oi.order_id = o.order_id

LEFT JOIN dbo.products_clean AS p
    ON oi.product_id = p.product_id

WHERE o.order_status = 'delivered'

GROUP BY
    COALESCE(p.product_category_english, 'unknown')

ORDER BY
    late_item_line_rate_pct DESC;
GO



/* ------------------------------------------------------------
   11.4 LONGEST DELIVERY ORDERS

   Purpose:
   Identify extreme delivery-time cases for
   operational investigation.
   ------------------------------------------------------------ */

SELECT TOP 20
    order_id,

    customer_id,

    order_purchase_timestamp,

    order_delivered_customer_date,

    order_estimated_delivery_date,

    delivery_days,

    delivery_delay_days,

    is_late_delivery

FROM dbo.orders_clean

WHERE order_status = 'delivered'
  AND delivery_days IS NOT NULL

ORDER BY
    delivery_days DESC;
GO



/* ============================================================
   END OF 11. DELIVERY ANALYSIS
   ============================================================ */

   /* ============================================================
   12. REVIEW & CUSTOMER EXPERIENCE ANALYSIS
   ============================================================ */


/* ------------------------------------------------------------
   12.1 REVIEW SCORE DISTRIBUTION

   Purpose:
   Understand how customer ratings are distributed.
   ------------------------------------------------------------ */

SELECT
    review_score,

    COUNT(*) AS review_count,

    100.0 * COUNT(*)
    / NULLIF(
        SUM(COUNT(*)) OVER (),
        0
    ) AS review_share_pct

FROM dbo.reviews_clean

GROUP BY review_score

ORDER BY review_score;
GO



/* ------------------------------------------------------------
   12.2 AVERAGE REVIEW SCORE

   Purpose:
   Measure overall customer satisfaction using review scores.
   ------------------------------------------------------------ */

SELECT
    AVG(CAST(review_score AS DECIMAL(18,2)))
        AS avg_review_score,

    COUNT(*) AS total_reviews

FROM dbo.reviews_clean;
GO



/* ------------------------------------------------------------
   12.3 LATE DELIVERY VS REVIEW SCORE

   Purpose:
   Compare review performance between late
   and on-time / early deliveries.

   Note:
   This shows association, not causation.
   ------------------------------------------------------------ */

WITH review_by_order AS
(
    SELECT
        order_id,

        AVG(CAST(review_score AS DECIMAL(18,2)))
            AS avg_review_score

    FROM dbo.reviews_clean

    GROUP BY order_id
)

SELECT
    CASE
        WHEN o.is_late_delivery = 1
        THEN 'Late'
        ELSE 'On time / early'
    END AS delivery_group,

    COUNT(DISTINCT o.order_id)
        AS orders,

    AVG(r.avg_review_score)
        AS avg_review_score

FROM dbo.orders_clean AS o

INNER JOIN review_by_order AS r
    ON o.order_id = r.order_id

WHERE o.order_status = 'delivered'

GROUP BY
    CASE
        WHEN o.is_late_delivery = 1
        THEN 'Late'
        ELSE 'On time / early'
    END;
GO



/* ------------------------------------------------------------
   12.4 REVIEW SCORE BY PRODUCT CATEGORY

   Purpose:
   Identify categories associated with stronger
   or weaker customer ratings.
   ------------------------------------------------------------ */

WITH review_by_order AS
(
    SELECT
        order_id,

        AVG(CAST(review_score AS DECIMAL(18,2)))
            AS avg_review_score

    FROM dbo.reviews_clean

    GROUP BY order_id
)

SELECT
    COALESCE(p.product_category_english, 'unknown')
        AS product_category,

    COUNT(DISTINCT oi.order_id)
        AS reviewed_orders,

    AVG(r.avg_review_score)
        AS avg_review_score

FROM dbo.order_items_clean AS oi

INNER JOIN review_by_order AS r
    ON oi.order_id = r.order_id

LEFT JOIN dbo.products_clean AS p
    ON oi.product_id = p.product_id

GROUP BY
    COALESCE(p.product_category_english, 'unknown')

HAVING COUNT(DISTINCT oi.order_id) >= 20

ORDER BY
    avg_review_score DESC;
GO



/* ------------------------------------------------------------
   12.5 REVIEW SCORE BY SELLER

   Purpose:
   Compare seller-level customer experience.

   Minimum 20 reviewed orders are used to reduce
   noise from very small sellers.
   ------------------------------------------------------------ */

WITH review_by_order AS
(
    SELECT
        order_id,

        AVG(CAST(review_score AS DECIMAL(18,2)))
            AS avg_review_score

    FROM dbo.reviews_clean

    GROUP BY order_id
)

SELECT
    s.seller_id,

    s.seller_state,

    COUNT(DISTINCT oi.order_id)
        AS reviewed_orders,

    AVG(r.avg_review_score)
        AS avg_review_score

FROM dbo.order_items_clean AS oi

INNER JOIN review_by_order AS r
    ON oi.order_id = r.order_id

LEFT JOIN dbo.sellers_clean AS s
    ON oi.seller_id = s.seller_id

GROUP BY
    s.seller_id,
    s.seller_state

HAVING COUNT(DISTINCT oi.order_id) >= 20

ORDER BY
    avg_review_score DESC;
GO



/* ============================================================
   END OF 12. REVIEW & CUSTOMER EXPERIENCE ANALYSIS
   ============================================================ */

   /* ============================================================
   13. PRODUCT DEMAND PROXY ANALYSIS
   ============================================================ */


/* ------------------------------------------------------------
   13.1 PRODUCT DEMAND SUMMARY

   Purpose:
   Analyze historical product demand using the
   demand-velocity table created in Python.

   Important:
   This is NOT physical inventory data.
   ------------------------------------------------------------ */

SELECT
    product_id,

    delivered_orders,

    delivered_item_lines,

    delivered_merchandise_value,

    first_sale_date,

    last_sale_date,

    active_months,

    item_lines_per_active_month,

    days_since_last_sale,

    demand_segment

FROM dbo.product_demand_proxy

ORDER BY
    item_lines_per_active_month DESC,
    delivered_merchandise_value DESC;
GO



/* ------------------------------------------------------------
   13.2 DEMAND SEGMENT SUMMARY

   Purpose:
   Compare fast-moving, slow-moving, moderate,
   and inactive/old products.
   ------------------------------------------------------------ */

SELECT
    demand_segment,

    COUNT(*) AS products,

    SUM(delivered_item_lines)
        AS delivered_item_lines,

    SUM(delivered_orders)
        AS delivered_orders,

    SUM(delivered_merchandise_value)
        AS delivered_merchandise_value,

    AVG(item_lines_per_active_month)
        AS avg_item_lines_per_active_month,

    AVG(CAST(days_since_last_sale AS DECIMAL(18,2)))
        AS avg_days_since_last_sale

FROM dbo.product_demand_proxy

GROUP BY demand_segment

ORDER BY delivered_merchandise_value DESC;
GO



/* ------------------------------------------------------------
   13.3 TOP 20 FAST-MOVING PRODUCTS

   Purpose:
   Identify products with stronger recent
   historical demand velocity.
   ------------------------------------------------------------ */

SELECT TOP 20
    product_id,

    delivered_orders,

    delivered_item_lines,

    delivered_merchandise_value,

    item_lines_per_active_month,

    days_since_last_sale,

    demand_segment

FROM dbo.product_demand_proxy

WHERE demand_segment = 'fast_moving_recent'

ORDER BY
    item_lines_per_active_month DESC,
    delivered_merchandise_value DESC;
GO



/* ------------------------------------------------------------
   13.4 INACTIVE / OLD PRODUCTS

   Purpose:
   Identify products that have not shown
   recent historical sales activity.
   ------------------------------------------------------------ */

SELECT TOP 50
    product_id,

    delivered_orders,

    delivered_item_lines,

    delivered_merchandise_value,

    last_sale_date,

    days_since_last_sale,

    demand_segment

FROM dbo.product_demand_proxy

WHERE demand_segment = 'inactive_or_old'

ORDER BY
    days_since_last_sale DESC;
GO



/* ============================================================
   END OF 13. PRODUCT DEMAND PROXY ANALYSIS
   ============================================================ */

   /* ============================================================
   14. POWER BI READY VIEWS
   ============================================================ */


/* ------------------------------------------------------------
   14.1 MONTHLY KPI VIEW

   Purpose:
   Provide a clean monthly summary table for
   Power BI trend charts and KPI reporting.
   ------------------------------------------------------------ */

CREATE OR ALTER VIEW dbo.vw_powerbi_monthly_kpi
AS
SELECT
    purchase_month,

    COUNT(DISTINCT order_id)
        AS purchased_orders,

    COUNT(DISTINCT CASE
        WHEN order_status = 'delivered'
        THEN order_id
    END)
        AS delivered_orders,

    SUM(CASE
        WHEN order_status = 'delivered'
        THEN merchandise_value
        ELSE 0
    END)
        AS merchandise_value,

    SUM(CASE
        WHEN order_status = 'delivered'
        THEN freight_value
        ELSE 0
    END)
        AS freight_value,

    AVG(CASE
        WHEN order_status = 'delivered'
        THEN merchandise_value
    END)
        AS avg_order_value,

    100.0 *
    SUM(CASE
        WHEN order_status = 'canceled'
        THEN 1
        ELSE 0
    END)
    / NULLIF(COUNT(*), 0)
        AS cancellation_rate_pct,

    100.0 *
    SUM(CASE
        WHEN order_status = 'delivered'
             AND is_late_delivery = 0
        THEN 1
        ELSE 0
    END)
    /
    NULLIF(
        SUM(CASE
            WHEN order_status = 'delivered'
            THEN 1
            ELSE 0
        END),
        0
    )
        AS on_time_rate_pct,

    AVG(CASE
        WHEN order_status = 'delivered'
        THEN delivery_days
    END)
        AS avg_delivery_days

FROM dbo.vw_orders_enriched

GROUP BY
    purchase_month;
GO



/* ------------------------------------------------------------
   14.2 CATEGORY PERFORMANCE VIEW

   Purpose:
   Provide category-level measures for
   Power BI product/category analysis.
   ------------------------------------------------------------ */

CREATE OR ALTER VIEW dbo.vw_powerbi_category_performance
AS
SELECT
    COALESCE(p.product_category_english, 'unknown')
        AS product_category,

    COUNT(DISTINCT oi.order_id)
        AS delivered_orders,

    COUNT(*)
        AS delivered_item_lines,

    SUM(oi.price)
        AS merchandise_value,

    SUM(oi.freight_value)
        AS freight_value,

    AVG(oi.price)
        AS avg_item_price,

    CASE
        WHEN SUM(oi.price) > 0
        THEN
            SUM(oi.freight_value) * 100.0
            / SUM(oi.price)
        ELSE NULL
    END
        AS freight_ratio_pct

FROM dbo.order_items_clean AS oi

INNER JOIN dbo.orders_clean AS o
    ON oi.order_id = o.order_id

LEFT JOIN dbo.products_clean AS p
    ON oi.product_id = p.product_id

WHERE o.order_status = 'delivered'

GROUP BY
    COALESCE(p.product_category_english, 'unknown');
GO



/* ------------------------------------------------------------
   14.3 SELLER PERFORMANCE VIEW

   Purpose:
   Provide seller-level metrics for Power BI.
   ------------------------------------------------------------ */

CREATE OR ALTER VIEW dbo.vw_powerbi_seller_performance
AS
SELECT
    s.seller_id,

    s.seller_state,

    COUNT(DISTINCT oi.order_id)
        AS delivered_orders,

    SUM(oi.price)
        AS merchandise_value,

    SUM(oi.freight_value)
        AS freight_value,

    AVG(CAST(o.delivery_days AS DECIMAL(18,2)))
        AS avg_delivery_days,

    100.0 *
    SUM(CASE
        WHEN o.is_late_delivery = 0
        THEN 1
        ELSE 0
    END)
    / NULLIF(COUNT(*), 0)
        AS on_time_item_line_rate_pct

FROM dbo.order_items_clean AS oi

INNER JOIN dbo.orders_clean AS o
    ON oi.order_id = o.order_id

LEFT JOIN dbo.sellers_clean AS s
    ON oi.seller_id = s.seller_id

WHERE o.order_status = 'delivered'

GROUP BY
    s.seller_id,
    s.seller_state;
GO



/* ------------------------------------------------------------
   14.4 CUSTOMER STATE VIEW

   Purpose:
   Provide geography-based customer metrics.
   ------------------------------------------------------------ */

CREATE OR ALTER VIEW dbo.vw_powerbi_customer_state
AS
SELECT
    c.customer_state,

    COUNT(DISTINCT o.order_id)
        AS total_orders,

    COUNT(DISTINCT c.customer_unique_id)
        AS unique_customers,

    SUM(CASE
        WHEN o.order_status = 'delivered'
        THEN e.merchandise_value
        ELSE 0
    END)
        AS delivered_merchandise_value,

    AVG(CASE
        WHEN o.order_status = 'delivered'
        THEN e.merchandise_value
    END)
        AS avg_delivered_order_value

FROM dbo.orders_clean AS o

INNER JOIN dbo.customers_clean AS c
    ON o.customer_id = c.customer_id

LEFT JOIN dbo.vw_orders_enriched AS e
    ON o.order_id = e.order_id

GROUP BY
    c.customer_state;
GO



/* ------------------------------------------------------------
   14.5 DELIVERY PERFORMANCE VIEW

   Purpose:
   Provide state-level delivery metrics for Power BI.
   ------------------------------------------------------------ */

CREATE OR ALTER VIEW dbo.vw_powerbi_delivery_state
AS
SELECT
    c.customer_state,

    COUNT(DISTINCT o.order_id)
        AS delivered_orders,

    AVG(CAST(o.delivery_days AS DECIMAL(18,2)))
        AS avg_delivery_days,

    AVG(CAST(o.delivery_delay_days AS DECIMAL(18,2)))
        AS avg_delivery_delay_days,

    100.0 *
    SUM(CASE
        WHEN o.is_late_delivery = 1
        THEN 1
        ELSE 0
    END)
    / NULLIF(COUNT(*), 0)
        AS late_delivery_rate_pct

FROM dbo.orders_clean AS o

INNER JOIN dbo.customers_clean AS c
    ON o.customer_id = c.customer_id

WHERE o.order_status = 'delivered'

GROUP BY
    c.customer_state;
GO



/* ------------------------------------------------------------
   14.6 CUSTOMER REPEAT SUMMARY VIEW

   Purpose:
   Provide a compact retention summary for Power BI.
   ------------------------------------------------------------ */

CREATE OR ALTER VIEW dbo.vw_powerbi_customer_repeat_summary
AS
SELECT
    COUNT(*) AS unique_customers,

    SUM(CASE
        WHEN customer_order_count > 1
        THEN 1
        ELSE 0
    END)
        AS repeat_customers,

    100.0 *
    SUM(CASE
        WHEN customer_order_count > 1
        THEN 1
        ELSE 0
    END)
    / NULLIF(COUNT(*), 0)
        AS repeat_customer_rate_pct

FROM dbo.customer_order_counts;
GO



/* ------------------------------------------------------------
   14.7 PRODUCT DEMAND VIEW

   Purpose:
   Provide the Python-created demand-velocity
   proxy directly to Power BI.

   Important:
   This is NOT physical inventory.
   ------------------------------------------------------------ */

CREATE OR ALTER VIEW dbo.vw_powerbi_product_demand
AS
SELECT
    product_id,

    delivered_orders,

    delivered_item_lines,

    delivered_merchandise_value,

    first_sale_date,

    last_sale_date,

    active_months,

    item_lines_per_active_month,

    days_since_last_sale,

    demand_segment

FROM dbo.product_demand_proxy;
GO



/* ------------------------------------------------------------
   14.8 VERIFY POWER BI VIEWS
   ------------------------------------------------------------ */

SELECT TOP 10 *
FROM dbo.vw_powerbi_monthly_kpi;
GO

SELECT TOP 10 *
FROM dbo.vw_powerbi_category_performance;
GO

SELECT TOP 10 *
FROM dbo.vw_powerbi_seller_performance;
GO

SELECT TOP 10 *
FROM dbo.vw_powerbi_customer_state;
GO

SELECT TOP 10 *
FROM dbo.vw_powerbi_delivery_state;
GO

SELECT *
FROM dbo.vw_powerbi_customer_repeat_summary;
GO

SELECT TOP 10 *
FROM dbo.vw_powerbi_product_demand;
GO



/* ============================================================
   END OF 14. POWER BI READY VIEWS
   ============================================================ */

   /* ============================================================
   PROJECT COMPLETE
   OLIST E-COMMERCE ANALYTICS
   Microsoft SQL Server / T-SQL
   ============================================================

   PROJECT WORKFLOW:

   1. Python / Pandas
      - Data profiling
      - Missing-value analysis
      - Duplicate checks
      - Data cleaning
      - Referential-integrity checks
      - Business-rule validation
      - Outlier flagging
      - Feature engineering
      - Exploratory Data Analysis
      - Processed CSV generation

   2. Microsoft SQL Server
      - Data-quality checks
      - Analytical views
      - KPI calculations
      - Monthly trend analysis
      - Month-over-month growth
      - Product category analysis
      - Seller analysis
      - Customer analysis
      - Payment analysis
      - Delivery analysis
      - Review analysis
      - Product demand proxy analysis
      - Power BI-ready views

   3. Microsoft Excel
      - QA
      - Reconciliation
      - MIS review

   4. Power BI
      - Interactive dashboards
      - DAX measures
      - Business insights


   IMPORTANT PROJECT LIMITATIONS:

   - Merchandise value is NOT profit.
     The dataset does not provide COGS.

   - Product demand proxy is NOT actual inventory.
     The dataset does not provide warehouse stock snapshots.

   - Associations such as late delivery vs review score
     should not be interpreted as proof of causation.

   - Order items and payments are aggregated before joining
     to avoid many-to-many fan-out and inflated monetary values.

   ============================================================ */