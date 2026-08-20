-- =====================================================
-- 1. EXECUTIVE KPI DASHBOARD
-- =====================================================

-- Query 1: Executive KPI Summary
-- Purpose: Single view of critical KPIs for management reporting
-- Export: Use for Executive Dashboard visualization

CREATE OR REPLACE VIEW vw_executive_kpi_dashboard AS
WITH 
  max_date_cte AS (
    SELECT MAX(date) AS latest_date
    FROM inventory_data
  ),

  -- Compute current metrics over the *last 7 days* of data
  current_metrics AS (
    SELECT 
      COUNT(DISTINCT CONCAT(i.store_id, '-', i.region)) AS total_store_locations,
      COUNT(DISTINCT i.product_id) AS total_products,
      SUM(i.inventory_level) AS total_inventory_units,
      SUM(i.inventory_level * i.price * (1 - i.discount/100)) AS total_inventory_value,
      SUM(i.units_sold) AS total_units_sold,
      MAX(m.latest_date) AS data_updated_date
    FROM inventory_data i
    JOIN max_date_cte m
      ON i.date BETWEEN DATE_SUB(m.latest_date, INTERVAL 7 DAY)
                    AND m.latest_date
  ),

  -- Turnover summary (uses your existing turnover view)
  turnover_summary AS (
    SELECT 
      AVG(inventory_turnover_ratio) AS avg_turnover_ratio,
      COUNT(IF(movement_type = 'FAST_MOVER', 1, NULL)) AS fast_moving_products,
      COUNT(IF(movement_type = 'MEDIUM_MOVER', 1, NULL)) AS medium_moving_products,
      COUNT(IF(movement_type = 'SLOW_MOVER', 1, NULL)) AS slow_moving_products,
      COUNT(IF(movement_type = 'NON_MOVER', 1, NULL)) AS non_moving_products
    FROM vw_inventory_turnover
  ),

  -- Stock status summary (uses existing stock view)
  stock_status AS (
    SELECT 
      COUNT(IF(stock_status = 'CRITICAL', 1, NULL)) AS critical_stock_items,
      COUNT(IF(stock_status = 'LOW', 1, NULL)) AS low_stock_items,
      COUNT(IF(stock_status = 'NORMAL', 1, NULL)) AS normal_stock_items,
      COUNT(IF(stock_status = 'HIGH', 1, NULL)) AS high_stock_items,
      COUNT(*) AS total_products
    FROM vw_current_stock_levels
  ),

  -- ABC summary (uses existing ABC classification view)
  abc_summary AS (
    SELECT 
      COUNT(IF(abc_classification = 'A', 1, NULL)) AS class_a_products,
      COUNT(IF(abc_classification = 'B', 1, NULL)) AS class_b_products,
      COUNT(IF(abc_classification = 'C', 1, NULL)) AS class_c_products,
      SUM(IF(abc_classification = 'A', total_revenue, 0)) AS class_a_revenue,
      SUM(IF(abc_classification = 'B', total_revenue, 0)) AS class_b_revenue,
      SUM(IF(abc_classification = 'C', total_revenue, 0)) AS class_c_revenue,
      SUM(total_revenue) AS total_revenue
    FROM vw_abc_classification
  )

SELECT 
  cm.total_store_locations,
  cm.total_products,
  cm.total_inventory_units,
  ROUND(cm.total_inventory_value, 2) AS total_inventory_value_usd,
  cm.total_units_sold AS weekly_units_sold,
  ROUND(ts.avg_turnover_ratio, 2) AS avg_turnover_ratio,
  ts.fast_moving_products,
  ts.medium_moving_products,
  ts.slow_moving_products,
  ts.non_moving_products,
  ss.critical_stock_items,
  ss.low_stock_items,
  (ss.critical_stock_items + ss.low_stock_items) AS total_alerts,
  ROUND(
    ((ss.total_products - ss.critical_stock_items)
      / GREATEST(ss.total_products,1)) * 100
  , 2) AS fill_rate_pct,
  abc.class_a_products,
  abc.class_b_products,
  abc.class_c_products,
  ROUND((abc.class_a_revenue / abc.total_revenue) * 100, 2) AS class_a_revenue_pct,
  ROUND((abc.class_b_revenue / abc.total_revenue) * 100, 2) AS class_b_revenue_pct,
  ROUND((abc.class_c_revenue / abc.total_revenue) * 100, 2) AS class_c_revenue_pct,
  cm.data_updated_date,                 
  -- Overall performance status
  CASE 
    WHEN ts.avg_turnover_ratio >= 4
         AND (ss.critical_stock_items / ss.total_products) < 0.05 
      THEN 'GOOD'
    WHEN ts.avg_turnover_ratio >= 2
         AND (ss.critical_stock_items / ss.total_products) < 0.10 
      THEN 'AVERAGE'
    ELSE 'NEEDS_IMPROVEMENT'
  END AS overall_status
FROM current_metrics cm
CROSS JOIN turnover_summary ts
CROSS JOIN stock_status ss
CROSS JOIN abc_summary abc;

SELECT *
FROM vw_executive_kpi_dashboard;

-- =====================================================
-- 2. STORE PERFORMANCE COMPARISON
-- =====================================================

-- Query 2: Store Performance Metrics
-- Purpose: Compare performance across store locations

CREATE OR REPLACE VIEW vw_store_performance AS
WITH 
  max_date_cte AS (
    SELECT MAX(date) AS latest_date
    FROM inventory_data
  ),

  -- Snapshot of current inventory at that latest date
  store_inventory AS (
    SELECT 
      i.store_id,
      i.region,
      COUNT(DISTINCT i.product_id) AS unique_products,
      SUM(i.inventory_level) AS total_inventory,
      ROUND(
        SUM(i.inventory_level * i.price * (1 - i.discount/100)), 
        2
      ) AS inventory_value,
      MAX(m.latest_date) AS latest_date
    FROM inventory_data i
    JOIN max_date_cte m 
      ON i.date = m.latest_date
    GROUP BY i.store_id, i.region
  ),

  -- Sales over the trailing 90 days *ending* at latest_date
  store_sales AS (
    SELECT 
      i.store_id,
      i.region,
      SUM(i.units_sold) AS total_units_sold_90d,
      ROUND(
        SUM(i.units_sold * i.price * (1 - i.discount/100)), 
        2
      ) AS total_revenue_90d,
      COUNT(DISTINCT i.date) AS days_count
    FROM inventory_data i
    JOIN max_date_cte m
      ON i.date BETWEEN DATE_SUB(m.latest_date, INTERVAL 90 DAY)
                    AND m.latest_date
    GROUP BY i.store_id, i.region
  ),

  -- Turnover metrics per store (from your turnover view)
  store_turnover AS (
    SELECT 
      store_id,
      region,
      ROUND(AVG(inventory_turnover_ratio), 2) AS avg_turnover,
      COUNT(IF(movement_type = 'FAST_MOVER', 1, NULL)) AS fast_movers,
      COUNT(
        IF(movement_type IN ('SLOW_MOVER','NON_MOVER'), 1, NULL)
      ) AS slow_movers
    FROM vw_inventory_turnover
    GROUP BY store_id, region
  ),

  -- Stock status counts per store (from your stock view)
  store_stock_status AS (
    SELECT 
      store_id,
      region,
      COUNT(IF(stock_status = 'CRITICAL', 1, NULL)) AS critical_items,
      COUNT(IF(stock_status = 'LOW', 1, NULL)) AS low_items,
      COUNT(*) AS total_items
    FROM vw_current_stock_levels
    GROUP BY store_id, region
  )

SELECT 
  si.store_id,
  si.region,
  si.unique_products,
  si.total_inventory AS current_inventory_units,
  si.inventory_value AS current_inventory_value_usd,

  -- average daily sales & revenue over that 90‑day window
  ROUND(ss.total_units_sold_90d / NULLIF(ss.days_count,1), 2) AS avg_daily_sales,
  ROUND(ss.total_revenue_90d   / NULLIF(ss.days_count,1), 2) AS avg_daily_revenue_usd,

  st.avg_turnover AS inventory_turnover_ratio,
  st.fast_movers,
  st.slow_movers,

  sss.critical_items,
  sss.low_items,
  (sss.critical_items + sss.low_items) AS total_alerts,

  -- fill rate = % of items not critical
  ROUND(
    ((sss.total_items - sss.critical_items)
      / GREATEST(sss.total_items,1)) * 100
  , 2) AS fill_rate_pct,

  -- Ranks
  DENSE_RANK() OVER (ORDER BY st.avg_turnover DESC) AS turnover_rank,
  DENSE_RANK() OVER (
    ORDER BY 
      ((sss.total_items - sss.critical_items) 
        / GREATEST(sss.total_items,1)) DESC
  ) AS service_level_rank,

  -- Performance rating
  CASE 
    WHEN st.avg_turnover >= 6 THEN 'EXCELLENT'
    WHEN st.avg_turnover >= 4 THEN 'GOOD'
    WHEN st.avg_turnover >= 2 THEN 'AVERAGE'
    ELSE 'NEEDS_IMPROVEMENT'
  END AS performance_rating,

  si.latest_date AS data_updated_date

FROM store_inventory si
JOIN store_sales ss 
  ON si.store_id = ss.store_id 
 AND si.region   = ss.region
JOIN store_turnover st 
  ON si.store_id = st.store_id 
 AND si.region   = st.region
JOIN store_stock_status sss 
  ON si.store_id = sss.store_id 
 AND si.region   = sss.region

ORDER BY st.avg_turnover DESC;

SELECT *
FROM vw_store_performance;

-- =====================================================
-- 3. CATEGORY PERFORMANCE ANALYSIS
-- =====================================================

-- Query 3: Category Performance Metrics
-- Purpose: Compare performance across product categories

CREATE OR REPLACE VIEW vw_category_performance AS
WITH 
  max_date_cte AS (
    SELECT MAX(date) AS latest_date
    FROM inventory_data
  ),

  -- Snapshot of current inventory by category at that latest date
  category_inventory AS (
    SELECT 
      p.category,
      COUNT(DISTINCT i.product_id) AS unique_products,
      SUM(i.inventory_level) AS total_inventory,
      ROUND(
        SUM(i.inventory_level * i.price * (1 - i.discount/100)), 
        2
      ) AS inventory_value,
      MAX(m.latest_date) AS data_updated_date
    FROM inventory_data i
    JOIN products p 
      ON i.product_id = p.product_id
    JOIN max_date_cte m 
      ON i.date = m.latest_date
    GROUP BY p.category
  ),

  -- Sales over the trailing 90 days ending at latest_date
  category_sales AS (
    SELECT 
      p.category,
      SUM(i.units_sold) AS total_units_sold_90d,
      ROUND(
        SUM(i.units_sold * i.price * (1 - i.discount/100)), 
        2
      ) AS total_revenue_90d,
      COUNT(DISTINCT i.date) AS days_count
    FROM inventory_data i
    JOIN products p 
      ON i.product_id = p.product_id
    JOIN max_date_cte m
      ON i.date BETWEEN DATE_SUB(m.latest_date, INTERVAL 90 DAY)
                    AND m.latest_date
    GROUP BY p.category
  ),

  -- Turnover metrics per category
  category_turnover AS (
    SELECT 
      category,
      ROUND(AVG(inventory_turnover_ratio), 2) AS avg_turnover,
      COUNT(IF(movement_type = 'FAST_MOVER', 1, NULL)) AS fast_movers,
      COUNT(
        IF(movement_type IN ('SLOW_MOVER','NON_MOVER'), 1, NULL)
      ) AS slow_movers
    FROM vw_inventory_turnover
    GROUP BY category
  ),

  -- Stock status counts per category
  category_stock_status AS (
    SELECT 
      category,
      COUNT(IF(stock_status = 'CRITICAL', 1, NULL)) AS critical_items,
      COUNT(IF(stock_status = 'LOW',      1, NULL)) AS low_items,
      COUNT(*) AS total_items
    FROM vw_current_stock_levels
    GROUP BY category
  ),

  -- ABC classification counts per category
  category_abc AS (
    SELECT 
      category,
      COUNT(IF(abc_classification = 'A', 1, NULL)) AS class_a_count,
      COUNT(IF(abc_classification = 'B', 1, NULL)) AS class_b_count,
      COUNT(IF(abc_classification = 'C', 1, NULL)) AS class_c_count
    FROM vw_abc_classification
    GROUP BY category
  )

SELECT 
  ci.category,
  ci.unique_products,
  ci.total_inventory AS current_inventory_units,
  ci.inventory_value AS current_inventory_value_usd,
  ROUND(cs.total_units_sold_90d / NULLIF(cs.days_count,1), 2) AS avg_daily_sales,
  ROUND(cs.total_revenue_90d   / NULLIF(cs.days_count,1), 2) AS avg_daily_revenue_usd,
  cs.total_revenue_90d AS total_revenue_90d_usd,
  ct.avg_turnover AS inventory_turnover_ratio,
  ct.fast_movers,
  ct.slow_movers,
  css.critical_items,
  css.low_items,
  (css.critical_items + css.low_items) AS total_alerts,
  ROUND(
    ((css.total_items - css.critical_items)
      / GREATEST(css.total_items,1)) * 100
  , 2) AS fill_rate_pct,
  ca.class_a_count,
  ca.class_b_count,
  ca.class_c_count,
  -- Performance Metrics
  ROUND(
    ci.total_inventory 
    / GREATEST(cs.total_units_sold_90d / NULLIF(cs.days_count,1),0.1)
  , 0) AS days_of_supply,
  ROUND(
    cs.total_revenue_90d / 
      NULLIF(ci.inventory_value,1)
  , 2) AS inventory_roi_90d,
  -- Category Ranking
  DENSE_RANK() OVER (ORDER BY ct.avg_turnover DESC) AS turnover_rank,
  DENSE_RANK() OVER (ORDER BY cs.total_revenue_90d DESC) AS revenue_rank,
  -- Performance Rating
  CASE 
    WHEN ct.avg_turnover >= 6 THEN 'EXCELLENT'
    WHEN ct.avg_turnover >= 4 THEN 'GOOD'
    WHEN ct.avg_turnover >= 2 THEN 'AVERAGE'
    ELSE 'NEEDS_IMPROVEMENT'
  END AS performance_rating,
  ci.data_updated_date AS data_updated_date

FROM category_inventory ci
JOIN category_sales cs 
  ON ci.category = cs.category
JOIN category_turnover ct 
  ON ci.category = ct.category
JOIN category_stock_status css 
  ON ci.category = css.category
JOIN category_abc ca 
  ON ci.category = ca.category

ORDER BY cs.total_revenue_90d DESC;

-- Export this view for Category Performance Dashboard
SELECT *
FROM vw_category_performance;

-- =====================================================
-- 4. SEASONALITY IMPACT SUMMARY
-- =====================================================

-- Query 4: Seasonal Performance Summary
-- Purpose: Understand seasonal impacts on inventory and sales

CREATE OR REPLACE VIEW vw_seasonality_summary AS
WITH season_performance AS (
    SELECT 
        seasonality,
        SUM(total_units_sold) AS total_units_sold,
        ROUND(SUM(total_revenue), 2) AS total_revenue,
        AVG(avg_daily_sales) AS avg_daily_sales,
        SUM(days_count) AS total_days,
        COUNT(DISTINCT CONCAT(store_id, region, category)) AS category_location_count
    FROM vw_seasonal_analysis
    GROUP BY seasonality
),
impact_counts AS (
    SELECT 
        seasonality,
        COUNT(CASE WHEN impact_classification = 'HIGH_IMPACT' THEN 1 END) AS high_impact_count,
        COUNT(CASE WHEN impact_classification = 'NORMAL_IMPACT' THEN 1 END) AS normal_impact_count,
        COUNT(CASE WHEN impact_classification = 'LOW_IMPACT' THEN 1 END) AS low_impact_count,
        COUNT(*) AS total_combinations
    FROM vw_seasonal_analysis
    GROUP BY seasonality
),
category_impact AS (
    SELECT 
        seasonality,
        category,
        AVG(seasonal_index) AS avg_seasonal_index,
        COUNT(*) AS data_points
    FROM vw_seasonal_analysis
    GROUP BY seasonality, category
),
overall_baseline AS (
    SELECT 
        AVG(avg_daily_sales) AS overall_avg_daily_sales,
        SUM(total_units_sold) / SUM(total_days) AS overall_daily_sales
    FROM season_performance
)
SELECT 
    sp.seasonality,
    sp.total_units_sold,
    sp.total_revenue AS total_revenue_usd,
    ROUND(sp.avg_daily_sales, 2) AS avg_daily_sales,
    sp.total_days,
    sp.category_location_count,
    ic.high_impact_count,
    ic.normal_impact_count,
    ic.low_impact_count,
    -- Impact percentage
    ROUND((ic.high_impact_count / ic.total_combinations) * 100, 2) AS high_impact_pct,
    -- Seasonal index vs overall
    ROUND((sp.avg_daily_sales / ob.overall_avg_daily_sales) * 100, 2) AS seasonal_index,
    -- Season classification
    CASE 
        WHEN (sp.avg_daily_sales / ob.overall_avg_daily_sales) >= 1.2 THEN 'HIGH_SEASON'
        WHEN (sp.avg_daily_sales / ob.overall_avg_daily_sales) >= 0.8 THEN 'NORMAL_SEASON'
        ELSE 'LOW_SEASON'
    END AS season_classification,
    -- Category with highest seasonal impact
    (
        SELECT category FROM category_impact ci2 
        WHERE ci2.seasonality = sp.seasonality 
        ORDER BY ci2.avg_seasonal_index DESC LIMIT 1
    ) AS highest_impact_category,
    (
        SELECT avg_seasonal_index FROM category_impact ci2 
        WHERE ci2.seasonality = sp.seasonality 
        ORDER BY ci2.avg_seasonal_index DESC LIMIT 1
    ) AS highest_impact_index
FROM season_performance sp
JOIN impact_counts ic ON sp.seasonality = ic.seasonality
CROSS JOIN overall_baseline ob
ORDER BY seasonal_index DESC;

SELECT * 
FROM vw_seasonality_summary;

-- =====================================================
-- 5. STOCKOUT RISK ASSESSMENT
-- =====================================================

-- Query 5: Stockout Risk Analysis
-- Purpose: Identify products with highest stockout risk

CREATE OR REPLACE VIEW vw_stockout_risk AS
WITH stock_risk_factors AS (
    SELECT 
        cs.store_id,
        cs.region,
        cs.product_id,
        p.category,
        cs.inventory_level,
        ra.avg_daily_sales,
        ra.reorder_point,
        ra.safety_stock,
        ra.days_of_supply,
        it.inventory_turnover_ratio,
        it.movement_type,
        abc.abc_classification,
        abc.revenue_percentage,
        -- compute coverage_ratio on the fly
        cs.inventory_level / GREATEST(ra.reorder_point, 1) AS coverage_ratio,
        -- tighter, percentile‑style inventory risk
        CASE
          WHEN cs.inventory_level = 0 THEN 100
          WHEN cs.inventory_level / GREATEST(ra.reorder_point,1) <= 0.10 THEN 90
          WHEN cs.inventory_level / GREATEST(ra.reorder_point,1) <= 0.25 THEN 70
          WHEN cs.inventory_level / GREATEST(ra.reorder_point,1) <= 0.50 THEN 40
          ELSE 10
        END AS inventory_risk_score,
        -- more selective revenue impact
        CASE
          WHEN abc.revenue_percentage >= 90 THEN 100
          WHEN abc.revenue_percentage >= 50 THEN 60
          ELSE 20
        END AS revenue_impact_score,
        -- slightly dampened demand volatility
        CASE
          WHEN it.movement_type = 'FAST_MOVER'   THEN 80
          WHEN it.movement_type = 'MEDIUM_MOVER' THEN 50
          WHEN it.movement_type = 'SLOW_MOVER'   THEN 20
          ELSE 10
        END AS demand_volatility_score
    FROM vw_current_stock_levels cs
    JOIN products p 
      ON cs.product_id = p.product_id
    LEFT JOIN vw_reorder_analysis ra 
      ON cs.store_id   = ra.store_id 
     AND cs.region     = ra.region 
     AND cs.product_id = ra.product_id
    LEFT JOIN vw_inventory_turnover it 
      ON cs.store_id   = it.store_id 
     AND cs.region     = it.region 
     AND cs.product_id = it.product_id
    LEFT JOIN vw_abc_classification abc 
      ON cs.store_id   = abc.store_id 
     AND cs.region     = abc.region 
     AND cs.product_id = abc.product_id
)
SELECT 
    store_id,
    region,
    product_id,
    category,
    inventory_level,
    ROUND(avg_daily_sales, 2) AS avg_daily_sales,
    reorder_point,
    safety_stock,
    GREATEST(1, days_of_supply) AS days_of_supply,
    ROUND(inventory_turnover_ratio, 2) AS inventory_turnover_ratio,
    movement_type,
    abc_classification,
    ROUND(revenue_percentage, 2) AS revenue_percentage,

    -- re-weighted composite risk score
    ROUND(
      (inventory_risk_score * 0.4)
    + (revenue_impact_score * 0.4)
    + (demand_volatility_score * 0.2)
    ) AS stockout_risk_score,

    -- risk classification, with full composite expression
    CASE
      WHEN (inventory_risk_score * 0.4
          + revenue_impact_score * 0.4
          + demand_volatility_score * 0.2) >= 90 THEN 'CRITICAL_RISK'
      WHEN (inventory_risk_score * 0.4
          + revenue_impact_score * 0.4
          + demand_volatility_score * 0.2) >= 70 THEN 'HIGH_RISK'
      WHEN (inventory_risk_score * 0.4
          + revenue_impact_score * 0.4
          + demand_volatility_score * 0.2) >= 50 THEN 'MODERATE_RISK'
      ELSE 'LOW_RISK'
    END AS risk_classification,

    -- risk factors
    inventory_risk_score,
    revenue_impact_score,
    demand_volatility_score,

    -- suggested action, same full expression
    CASE
      WHEN (inventory_risk_score * 0.4
          + revenue_impact_score * 0.4
          + demand_volatility_score * 0.2) >= 90 THEN 'IMMEDIATE_REORDER'
      WHEN (inventory_risk_score * 0.4
          + revenue_impact_score * 0.4
          + demand_volatility_score * 0.2) >= 70 THEN 'REORDER_SOON'
      WHEN (inventory_risk_score * 0.4
          + revenue_impact_score * 0.4
          + demand_volatility_score * 0.2) >= 50 THEN 'MONITOR_CLOSELY'
      ELSE 'STANDARD_REVIEW'
    END AS recommended_action

FROM stock_risk_factors
WHERE avg_daily_sales > 0
ORDER BY stockout_risk_score DESC;

SELECT *
FROM vw_stockout_risk;