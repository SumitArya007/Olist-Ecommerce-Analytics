# Olist E-Commerce Analytics

End-to-end data analytics project using the **real Brazilian E-Commerce Public Dataset by Olist** with **Python, Microsoft SQL Server, and Excel**.

The project demonstrates a practical data analyst workflow:

**Raw Data → Python Cleaning & EDA → SQL Server Analysis → Excel QA / MIS → Business Insights**

---

## Project Overview

Olist is a Brazilian e-commerce marketplace. This project uses the public Olist e-commerce dataset to analyze marketplace performance across:

- orders and merchandise value,
- product categories,
- customers,
- sellers,
- payments,
- delivery performance,
- customer reviews,
- historical product-demand velocity.

The objective is not only to calculate KPIs. The project demonstrates how to work with a real multi-table dataset, validate data quality, clean and engineer features, avoid many-to-many join errors, perform business analysis in SQL Server, and reconcile outputs in Excel before reporting results.

---

## Tech Stack

- **Python:** Pandas, NumPy, Matplotlib
- **Microsoft SQL Server / T-SQL**
- **Microsoft Excel**
- **Jupyter Notebook**

---

## Data Source

**Dataset:** Brazilian E-Commerce Public Dataset by Olist  
**Source:** Kaggle  
**Dataset page:** https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce

The dataset contains anonymized marketplace data including customers, orders, order items, products, sellers, payments, reviews, and product-category translations.

The raw dataset files are **not redistributed in this repository**. Download the original CSV files from Kaggle and place them inside:

```text
data/raw/
```

Expected files:

```text
olist_customers_dataset.csv
olist_orders_dataset.csv
olist_order_items_dataset.csv
olist_products_dataset.csv
olist_sellers_dataset.csv
olist_order_payments_dataset.csv
olist_order_reviews_dataset.csv
product_category_name_translation.csv
```

---

## Business Questions

1. How do orders and delivered merchandise value change over time?
2. Which product categories contribute the most merchandise value?
3. How does delivery performance vary across orders, categories, and sellers?
4. Are late deliveries associated with lower customer review scores?
5. Which sellers show stronger commercial and operational performance?
6. What percentage of customers place repeat orders?
7. Which payment methods account for the highest payment value?
8. Which products show faster or slower historical demand velocity?
9. Do monthly and category-level merchandise value and freight totals reconcile across analytical layers?

---

## Project Workflow

```text
Olist Raw CSV Files
        |
        v
Python / Pandas
- Data profiling
- Missing-value analysis
- Duplicate checks
- Datatype cleaning
- Referential-integrity checks
- Business-rule validation
- Outlier flagging
- Feature engineering
- Exploratory data analysis
        |
        v
Processed CSV Files
        |
        v
Microsoft SQL Server
- Relational analysis
- Analytical views
- CTEs
- Window functions
- KPI calculations
- Category / seller / customer analysis
- Delivery / review / payment analysis
- Demand-velocity analysis
        |
        v
Microsoft Excel
- KPI review
- Cross-layer QA
- GMV reconciliation
- Freight reconciliation
- MIS / management-review layer
        |
        v
Business Insights
```

---

## Python Data Cleaning & EDA

Main notebook:

```text
01_data_cleaning_eda.ipynb
```

### Cleaning and QA

The Python workflow includes:

- dataset row/column profiling,
- missing-value counts and percentages,
- exact duplicate detection,
- business-key duplicate checks,
- datetime conversion,
- numeric datatype conversion,
- whitespace and blank-string cleanup,
- Portuguese-to-English product-category mapping,
- referential-integrity checks,
- negative-value validation,
- review-score validation,
- purchase/delivery date validation.

### Important Cleaning Decisions

Missing values are **not blindly filled**.

For example, a cancelled or undelivered order may legitimately have a missing customer-delivery timestamp.

Exact duplicate rows can be removed, but repeated `order_id` values in tables such as `order_items` are not treated as duplicate errors because a single order can contain multiple items.

---

## Outlier Analysis

The notebook uses the **IQR method** to flag unusual values in areas such as:

- merchandise value,
- freight value,
- delivery time.

Outliers are **flagged rather than automatically removed** because unusual transactions can still be valid real-world observations.

---

## Feature Engineering

Python creates analytical fields such as:

```text
purchase_year
purchase_month
purchase_weekday
delivery_days
delivery_delay_days
is_late_delivery
is_delivered
is_cancelled
item_lines
merchandise_value
freight_value
order_total_with_freight
freight_ratio_pct
payment_value
customer_order_count
is_repeat_customer
```

---

## Exploratory Data Analysis

The notebook includes EDA for:

- order-status distribution,
- monthly order trend,
- monthly delivered merchandise value,
- product-category performance,
- delivery-time distribution,
- late delivery vs review score,
- repeat-customer behavior,
- payment-method distribution,
- product demand velocity.

Charts are saved to:

```text
reports/figures/
```

---

## Data Quality Reports

Python exports QA reports to:

```text
reports/data_quality/
```

Examples include:

```text
dataset_summary.csv
missing_values_report.csv
duplicate_report.csv
key_duplicate_report.csv
referential_integrity_report.csv
business_rule_report.csv
outlier_report.csv
final_qa_summary.csv
```

---

## SQL Server Analysis

Microsoft SQL Server is used for the relational and business-analysis layer.

Main SQL file:

```text
sql/olist_ecommerce_analysis.sql
```

The SQL analysis covers:

- data-quality checks,
- analytical views,
- joins and aggregations,
- `CASE` expressions,
- CTEs,
- subqueries,
- window functions,
- `LAG`,
- `DENSE_RANK`,
- `NTILE`,
- executive KPI analysis,
- monthly trend analysis,
- month-over-month analysis,
- product-category analysis,
- seller performance,
- customer analysis,
- payment analysis,
- delivery analysis,
- review analysis,
- historical product-demand segmentation.

---

## Important Data-Modeling Decision

Olist contains several one-to-many relationships.

For example:

- one order can contain multiple order items,
- one order can contain multiple payment rows.

Directly joining these tables at transaction-line grain can create a **many-to-many fan-out** and inflate monetary values.

To prevent this, the project aggregates relevant tables to the required analytical grain before joining them. For example, order-item and payment data are aggregated separately to one row per `order_id` before they are combined in the enriched order view.

This design is especially important for reliable merchandise-value, freight, payment, and order-count calculations.

---

## Excel QA / MIS Layer

Workbook:

```text
excel/Olist_Excel_QA_and_MIS.xlsx
```

Excel is used as a **cross-layer QA, reconciliation, and management-review layer** rather than as a second transaction-processing system.

The workbook contains:

- `Monthly_KPI_Input`
- `Category_Input`
- `Seller_Input`
- `Product_Demand_Input`
- `QA_Checks`

### Verified Reconciliation Results

After loading the SQL outputs into Excel, the QA layer confirms:

| Check | Result |
|---|---:|
| Monthly rows loaded | 25 |
| Monthly merchandise value | R$ 13,221,498.11 |
| Category merchandise value | R$ 13,221,498.11 |
| GMV difference | **R$ 0.00** |
| Monthly freight | R$ 2,198,275.64 |
| Category freight | R$ 2,198,275.64 |
| Freight difference | **R$ 0.00** |
| Seller rows loaded | 2,970 |
| Product-demand rows loaded | 32,216 |

The zero GMV and freight differences provide an additional validation that the monthly and category analytical layers reconcile when equivalent filters are applied.

---

## Selected Verified KPIs

The analysis produced the following overall results:

| KPI | Value |
|---|---:|
| Total orders | 99,441 |
| Delivered orders | 96,478 |
| Delivered merchandise value | R$ 13,221,498.11 |
| Average delivered order value | R$ 137.04 |
| Delivered freight value | R$ 2,198,275.64 |
| Cancellation rate | 0.63% |
| On-time delivery rate | 91.89% |
| Average delivery time | 12.56 days |

---

## Historical Demand-Velocity Proxy

The project includes a product-level demand-planning output using historical delivered-order behavior.

It considers fields such as:

- delivered orders,
- delivered item lines,
- delivered merchandise value,
- first and last sale dates,
- active months,
- item lines per active month,
- days since last sale,
- demand segment.

This is intentionally described as a **historical demand-velocity / inventory-planning proxy**.

It is **not** a measurement of physical inventory.

---

## Important Project Limitations

### Profit

The public dataset provides selling price and freight information but does not provide product **COGS** or complete marketplace fee data.

Therefore this project does **not** claim to calculate true gross profit or net profit.

### Inventory

The dataset does not provide warehouse stock-on-hand snapshots.

Therefore this project does **not** claim to calculate actual inventory levels, stock-outs, or inventory turnover.

The product-demand output is only a historical demand-velocity proxy for planning discussion.

### Causality

Relationships found during EDA, such as late delivery and review score, are presented as **associations**, not proof of causation.

---

## Repository Structure

```text
Olist-Ecommerce-Analytics/
│
├── README.md
├── 01_data_cleaning_eda.ipynb
├── requirements.txt
├── data_source.md
├── .gitignore
│
├── data/
│   ├── raw/
│   └── processed/
│
├── sql/
│   └── olist_ecommerce_analysis.sql
│
├── excel/
│   └── Olist_Excel_QA_and_MIS.xlsx
│
├── reports/
│   ├── data_quality/
│   └── figures/
│
└── assets/
```

---

## How to Run

### 1. Download the Olist dataset

Download the original files from Kaggle and place the CSV files inside:

```text
data/raw/
```

### 2. Install Python dependencies

```bash
pip install -r requirements.txt
```

The project uses:

```text
pandas
numpy
matplotlib
jupyter
```

### 3. Run the Python notebook

Start Jupyter:

```bash
jupyter notebook
```

Open:

```text
01_data_cleaning_eda.ipynb
```

Run the notebook from top to bottom.

The notebook creates cleaned datasets under:

```text
data/processed/
```

and QA / EDA outputs under:

```text
reports/data_quality/
reports/figures/
```

### 4. Load cleaned data into SQL Server

Create/use the database:

```text
OlistEcommerceAnalytics
```

Import the cleaned CSV outputs into their corresponding SQL Server tables using SSMS.

Then run:

```text
sql/olist_ecommerce_analysis.sql
```

### 5. Populate the Excel QA / MIS workbook

Open:

```text
excel/Olist_Excel_QA_and_MIS.xlsx
```

Export/paste the matching SQL outputs into:

```text
Monthly_KPI_Input
Category_Input
Seller_Input
Product_Demand_Input
```

Then review:

```text
QA_Checks
```

The reconciliation checks should pass when the SQL outputs and filters match.

---

## Interview Talking Points

### Why Python?

Python provides a repeatable workflow for data profiling, cleaning, validation, feature engineering, outlier analysis, EDA, and generation of processed datasets.

### Why SQL Server?

SQL Server is used for relational analysis, business KPI calculations, advanced joins, analytical views, CTEs, and window functions.

### Why Excel?

Excel provides an independent management-review and reconciliation layer. In this project it confirms that key monetary outputs agree across different analytical slices.

### How did you prevent inflated sales values?

The project avoids joining multiple one-to-many tables directly. Relevant datasets are aggregated to the correct business grain before being joined, which prevents many-to-many fan-out.

### Why not delete all outliers?

An unusual value can still be a valid transaction. The project flags outliers for review instead of automatically deleting them.

### Why not calculate profit?

The dataset does not provide COGS, so presenting merchandise value as profit would be misleading.

### Is the demand segment actual inventory analysis?

No. It is a historical demand-velocity proxy based on delivered sales activity. The source does not contain physical stock snapshots.

---

## Skills Demonstrated

- Data Cleaning
- Exploratory Data Analysis
- Pandas
- NumPy
- Matplotlib
- Jupyter Notebook
- Microsoft SQL Server
- T-SQL
- Relational Data Analysis
- CTEs
- Window Functions
- Data Validation
- Data Modeling
- Business KPI Analysis
- Excel QA / MIS
- Cross-Layer Reconciliation
- Business Analysis
- Data Storytelling

---

## Author

**Sumit Arya**

GitHub: https://github.com/SumitArya007
