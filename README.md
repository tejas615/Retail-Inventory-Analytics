# Solving Inventory Inefficiencies Using SQL

A complete end-to-end data-driven solution for inventory analytics and decision support across a multi-store retail network. This project implements a normalized SQL schema, analytical views, and a live dashboard for real-time business insights.

---

## 🚀 Live Dashboard

Access the real-time web dashboard hosted separately:

🔗 [UrbanCo Inventory Management Dashboard (Live)](https://inventory-dashboard-eosin-six.vercel.app/)

---

## 🧠 Project Highlights

* **Normalized SQL Schema:** Includes `stores`, `products`, `inventory_data`, and `inventory_kpis` with composite primary keys and indexing.
* **ETL via SQL:** Bulk import from raw CSV, transformation into normalized tables, data validation, and KPI generation.
* **Analytics Layer:** Core SQL views like `vw_current_stock_levels`, `vw_reorder_analysis`, `vw_inventory_turnover`, `vw_abc_classification`, `vw_seasonal_analysis`.
* **Dashboard Reports:** Executive-focused summary views such as `vw_executive_kpi_dashboard`, `vw_stockout_risk`, and category/store performance metrics.
* **Live Visualization:** Real-time dashboard for key metrics and store-level insights.

---

## 📊 Sample Insights

* Reorder alerts based on safety stock and lead time
* Inventory turnover analysis across product categories
* ABC classification of products for optimized stock prioritization
* Seasonal demand forecasting with weather/event context
* Stockout risk prediction by store and region

---

## 📄 Documentation

* **[SQL Documentation](./sql-documentation.docx)** — technical breakdown of schema, views, and queries
* **[Executive Report](./Executive%20Report%20(Insights%20and%20Recommendations).docx)** — visual, business-oriented interpretation of outputs
* **[ER Diagram](./ERD.pdf)** — visual map of database structure

---

## 🛠 Technologies Used

* MySQL 8+
* SQL Views and Analytics
* CSV export queries
* Live Dashboard (Simple JS hosted separately)

---

## 📬 Feedback & Contributions

This project was developed as part of an academic analytics initiative. Feedback is welcome. For collaboration or suggestions, please open an issue.

---
