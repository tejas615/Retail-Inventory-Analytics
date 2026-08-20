-- =====================================================
-- 1. REAL-TIME STOCK LEVEL MONITORING
-- =====================================================

-- Query 1: Current Stock Levels with Status Classification
-- Purpose: Monitor current inventory levels across all store-product combinations

CREATE OR REPLACE VIEW vw_current_stock_levels AS
WITH current_inventory AS (
    SELECT 
        i.store_id,
        i.region, 
        i.product_id,
        p.category,
        i.inventory_level,
        i.price,
        i.discount,
        i.seasonality,
        i.weather_condition,
        (i.inventory_level * i.price * (1 - i.discount/100)) AS inventory_value,
        CASE 
            WHEN i.inventory_level <= 10 THEN 'CRITICAL'
            WHEN i.inventory_level <= 50 THEN 'LOW'
            WHEN i.inventory_level <= 200 THEN 'NORMAL'
            ELSE 'HIGH'
        END AS stock_status,
        ROW_NUMBER() OVER (
            PARTITION BY i.store_id, i.region, i.product_id 
            ORDER BY i.date DESC
        ) AS rn
    FROM inventory_data i
    JOIN products p ON i.product_id = p.product_id
)
SELECT 
    store_id,
    region,
    product_id,
    category,
    inventory_level,
    ROUND(price, 2) AS price,
    ROUND(discount, 2) AS discount_pct,
    ROUND(inventory_value, 2) AS inventory_value,
    stock_status,
    seasonality,
    weather_condition
FROM current_inventory 
WHERE rn = 1
ORDER BY 
    CASE stock_status 
        WHEN 'CRITICAL' THEN 1 
        WHEN 'LOW' THEN 2 
        WHEN 'NORMAL' THEN 3 
        ELSE 4 
    END,
    inventory_level ASC;

SELECT * FROM vw_current_stock_levels;

-- =====================================================
-- 2. LOW INVENTORY DETECTION AND REORDER ALERTS
-- =====================================================

-- Query 2: Reorder Point Analysis with Safety Stock Calculations
-- Purpose: Identify products requiring reorder based on statistical calculations

CREATE OR REPLACE VIEW vw_reorder_analysis AS
WITH 
  -- Get the data’s max date
  max_date_cte AS (
    SELECT MAX(date) AS latest_date
    FROM inventory_data
  ),

  -- Sales stats over the trailing 90 days
  sales_stats AS (
    SELECT
      i.store_id,
      i.region,
      i.product_id,
      AVG(i.units_sold) AS avg_daily_sales,
      STDDEV(i.units_sold) AS std_dev_sales,
      COUNT(*) AS days_of_data
    FROM inventory_data i
    JOIN max_date_cte m
      ON i.date BETWEEN DATE_SUB(m.latest_date, INTERVAL 90 DAY) 
                    AND m.latest_date
    GROUP BY i.store_id, i.region, i.product_id
    HAVING COUNT(*) >= 30
  ),

  -- Calculate safety stock & reorder point
  reorder_calc AS (
    SELECT
      ss.store_id,
      ss.region,
      ss.product_id,
      ss.avg_daily_sales,
      ss.std_dev_sales,
      7 AS lead_time_days,
      -- 95% service level
      GREATEST(
        0,
        ROUND(1.65 * COALESCE(ss.std_dev_sales, ss.avg_daily_sales*0.3) * SQRT(7))
      ) AS safety_stock,
      ROUND(
        ss.avg_daily_sales * 7
        + GREATEST(
            0,
            1.65 * COALESCE(ss.std_dev_sales, ss.avg_daily_sales*0.3) * SQRT(7)
          )
      ) AS reorder_point
    FROM sales_stats ss
  ),

  -- Grab exactly the latest inventory_level per SKU
  latest_stock AS (
    SELECT
      t.store_id,
      t.region,
      t.product_id,
      t.inventory_level
    FROM (
      SELECT
        i.store_id,
        i.region,
        i.product_id,
        i.inventory_level,
        ROW_NUMBER() OVER (
          PARTITION BY i.store_id, i.region, i.product_id
          ORDER BY i.date DESC
        ) AS rn
      FROM inventory_data i
      JOIN max_date_cte m
        ON i.date <= m.latest_date
    ) t
    WHERE t.rn = 1
  ),

  -- Combine stock + reorder calc + compute extra metrics
  coverage AS (
    SELECT
      ls.store_id,
      ls.region,
      ls.product_id,
      ls.inventory_level,
      rc.avg_daily_sales,
      rc.std_dev_sales,
      rc.lead_time_days,
      rc.safety_stock,
      rc.reorder_point,
      -- days of supply at current avg
      ROUND(ls.inventory_level / GREATEST(rc.avg_daily_sales, 0.1), 0) 
        AS days_of_supply,
      -- suggested order to hit (reorder_point + safety_stock)
      GREATEST(
        0,
        (rc.reorder_point + rc.safety_stock) - ls.inventory_level
      ) AS suggested_order_qty,
      -- coverage ratio
      ls.inventory_level / GREATEST(rc.reorder_point, 1) AS coverage_ratio
    FROM latest_stock ls
    JOIN reorder_calc rc
      ON  ls.store_id = rc.store_id
     AND ls.region = rc.region
     AND ls.product_id = rc.product_id
  ),

  -- Rank into 4 quartiles per category
  ranked AS (
    SELECT
      c.*,
      p.category,
      NTILE(4) OVER (
        PARTITION BY p.category
        ORDER BY c.coverage_ratio
      ) AS quartile_rank
    FROM coverage c
    JOIN products p
      ON c.product_id = p.product_id
  )

SELECT
  r.store_id,
  r.region,
  r.product_id,
  r.category,
  r.inventory_level AS current_stock,
  ROUND(r.avg_daily_sales, 2) AS avg_daily_sales,
  ROUND(r.std_dev_sales, 2) AS std_dev_sales,
  r.lead_time_days,
  r.safety_stock,
  r.reorder_point,
  r.days_of_supply,
  r.suggested_order_qty,
  ROUND(r.coverage_ratio, 2) AS coverage_ratio,
  CASE r.quartile_rank
    WHEN 1 THEN 'CRITICAL'
    WHEN 2 THEN 'LOW'
    WHEN 3 THEN 'MODERATE'
    ELSE 'ADEQUATE'
  END AS alert_level
FROM ranked r
ORDER BY
  r.category,
  r.coverage_ratio ASC;

SELECT * FROM vw_reorder_analysis;

-- =====================================================
-- 3. INVENTORY TURNOVER ANALYSIS
-- =====================================================

-- Query 3: Inventory Turnover and Movement Classification
-- Purpose: Analyze inventory efficiency and identify fast/slow movers

CREATE OR REPLACE VIEW vw_inventory_turnover AS
WITH 
  -- True latest date
  max_date_cte AS (
    SELECT MAX(date) AS latest_date
    FROM inventory_data
  ),

  -- Compute turnover metrics over the last 90 days
  turnover_calculations AS (
    SELECT 
      i.store_id,
      i.region,
      i.product_id,
      p.category,
      SUM(i.units_sold) AS total_units_sold_90d,
      AVG(i.units_sold) AS avg_daily_sales,
      AVG(i.inventory_level) AS avg_inventory_level,
      AVG(i.price) AS avg_unit_price,
      ROUND(                                                    
        SUM(i.units_sold * i.price * (1 - i.discount/100)), 2
      ) AS cogs_90_days,
      ROUND(                                                      
        AVG(i.inventory_level * i.price * (1 - i.discount/100)), 2
      ) AS avg_inventory_value,
      CASE 
        WHEN AVG(i.inventory_level) > 0 THEN 
          ROUND(
            (SUM(i.units_sold) * 365.0 / 90.0) 
            / AVG(i.inventory_level), 
            2
          )
        ELSE 0 
      END AS inventory_turnover_ratio
    FROM inventory_data i
    JOIN products p 
      ON i.product_id = p.product_id
    JOIN max_date_cte m
      ON i.date BETWEEN DATE_SUB(m.latest_date, INTERVAL 90 DAY) 
                   AND m.latest_date
    GROUP BY 
      i.store_id, 
      i.region, 
      i.product_id, 
      p.category
  ),

  -- Add days_of_supply and preserve avg_unit_price
  enriched AS (
    SELECT
      tc.*,
      CASE 
        WHEN tc.avg_daily_sales > 0 THEN 
          ROUND(tc.avg_inventory_level / tc.avg_daily_sales, 0)
        ELSE 999 
      END AS days_of_supply
    FROM turnover_calculations tc
  ),

  -- Quartile rank within each category by inventory_turnover_ratio
  ranked AS (
    SELECT
      e.*,
      NTILE(4) OVER (
        PARTITION BY e.category 
        ORDER BY e.inventory_turnover_ratio DESC
      ) AS quartile_rank
    FROM enriched e
  )

SELECT
  r.store_id,
  r.region,
  r.product_id,
  r.category,
  ROUND(r.avg_inventory_level, 0) AS avg_inventory_level,
  ROUND(r.avg_daily_sales, 2) AS avg_daily_sales,
  r.cogs_90_days,
  r.avg_inventory_value,
  r.inventory_turnover_ratio,
  r.days_of_supply,
  ROUND(r.avg_unit_price, 2) AS avg_unit_price,

  -- Movement Classification (quartile 1 = top 25% turnover)
  CASE r.quartile_rank
    WHEN 1 THEN 'FAST_MOVER'
    WHEN 2 THEN 'MEDIUM_MOVER'
    WHEN 3 THEN 'SLOW_MOVER'
    ELSE 'NON_MOVER'
  END AS movement_type,

  -- Performance Rating (same quartiles but different labels)
  CASE r.quartile_rank
    WHEN 1 THEN 'EXCELLENT'
    WHEN 2 THEN 'GOOD'
    WHEN 3 THEN 'AVERAGE'
    ELSE 'NEEDS_IMPROVEMENT'
  END AS performance_rating

FROM ranked r
ORDER BY r.category, r.inventory_turnover_ratio DESC;

SELECT * FROM vw_inventory_turnover;

-- =====================================================
-- 4. ABC PRODUCT CLASSIFICATION
-- =====================================================

-- Query 4: ABC Analysis for Product Classification
-- Purpose: Classify products based on revenue contribution (Pareto Analysis)

CREATE OR REPLACE VIEW vw_abc_classification AS
WITH 
max_date_cte AS (
    SELECT MAX(date) AS latest_date
    FROM inventory_data
  ),

product_revenue AS (
    SELECT 
        i.store_id,
        i.region,
        i.product_id,
        p.category,
        SUM(i.units_sold * i.price * (1 - i.discount/100)) AS total_revenue,
        SUM(i.units_sold) AS total_units_sold,
        AVG(i.price * (1 - i.discount/100)) AS avg_selling_price,
        AVG(i.inventory_level) AS avg_inventory_level
    FROM inventory_data i
    JOIN products p ON i.product_id = p.product_id
    JOIN max_date_cte m
    ON i.date BETWEEN DATE_SUB(m.latest_date, INTERVAL 180 DAY)
              AND m.latest_date
    GROUP BY i.store_id, i.region, i.product_id, p.category
),
revenue_with_percentage AS (
    SELECT 
        pr.*,
        ROUND((pr.total_revenue / SUM(pr.total_revenue) OVER (PARTITION BY pr.store_id, pr.region)) * 100, 2) AS revenue_percentage,
        ROW_NUMBER() OVER (PARTITION BY pr.store_id, pr.region ORDER BY pr.total_revenue DESC) AS revenue_rank
    FROM product_revenue pr
),
cumulative_analysis AS (
    SELECT 
        *,
        SUM(revenue_percentage) OVER (
            PARTITION BY store_id, region 
            ORDER BY revenue_rank 
            ROWS UNBOUNDED PRECEDING
        ) AS cumulative_percentage
    FROM revenue_with_percentage
)
SELECT 
    store_id,
    region,
    product_id,
    category,
    ROUND(total_revenue, 2) AS total_revenue,
    revenue_percentage,
    ROUND(cumulative_percentage, 2) AS cumulative_percentage,
    revenue_rank,
    -- ABC Classification based on cumulative revenue
    CASE 
        WHEN cumulative_percentage <= 80 THEN 'A'
        WHEN cumulative_percentage <= 95 THEN 'B'
        ELSE 'C'
    END AS abc_classification,
    -- Management Strategy
    CASE 
        WHEN cumulative_percentage <= 80 THEN 'TIGHT_CONTROL'
        WHEN cumulative_percentage <= 95 THEN 'MODERATE_CONTROL'
        ELSE 'BASIC_CONTROL'
    END AS management_strategy,
    total_units_sold,
    ROUND(avg_selling_price, 2) AS avg_selling_price,
    ROUND(avg_inventory_level, 0) AS avg_inventory_level
FROM cumulative_analysis
ORDER BY store_id, region, revenue_rank;

SELECT * FROM vw_abc_classification;

-- =====================================================
-- 5. SEASONAL AND WEATHER ANALYSIS
-- =====================================================

-- Query 5: Seasonal Demand Patterns
-- Purpose: Analyze demand patterns by season and weather

CREATE OR REPLACE VIEW vw_seasonal_analysis AS
WITH 
max_date_cte AS (
    SELECT MAX(date) AS latest_date
    FROM inventory_data
  ),
  
seasonal_sales AS (
    SELECT 
        seasonality,
        weather_condition,
        p.category,
        i.store_id,
        i.region,
        SUM(i.units_sold) AS total_units_sold,
        SUM(i.units_sold * i.price * (1 - i.discount/100)) AS total_revenue,
        AVG(i.units_sold) AS avg_daily_sales,
        AVG(i.inventory_level) AS avg_inventory_level,
        COUNT(DISTINCT i.date) AS days_count
    FROM inventory_data i
    JOIN products p ON i.product_id = p.product_id
    JOIN max_date_cte m 
      ON i.date BETWEEN DATE_SUB(m.latest_date, INTERVAL 12 MONTH)
                    AND m.latest_date
    WHERE i.seasonality IS NOT NULL
    GROUP BY seasonality, weather_condition, p.category, i.store_id, i.region
),
category_baselines AS (
    SELECT 
        category,
        store_id,
        region,
        AVG(avg_daily_sales) AS category_baseline_sales
    FROM seasonal_sales
    GROUP BY category, store_id, region
)
SELECT 
    ss.seasonality,
    ss.weather_condition,
    ss.category,
    ss.store_id,
    ss.region,
    ss.total_units_sold,
    ROUND(ss.total_revenue, 2) AS total_revenue,
    ROUND(ss.avg_daily_sales, 2) AS avg_daily_sales,
    ROUND(ss.avg_inventory_level, 0) AS avg_inventory_level,
    ss.days_count,
    ROUND(cb.category_baseline_sales, 2) AS category_baseline,
    -- Seasonal Index
    ROUND((ss.avg_daily_sales / GREATEST(cb.category_baseline_sales, 0.1)) * 100, 2) AS seasonal_index,
    -- Impact Classification
    CASE 
        WHEN (ss.avg_daily_sales / GREATEST(cb.category_baseline_sales, 0.1)) >= 1.2 THEN 'HIGH_IMPACT'
        WHEN (ss.avg_daily_sales / GREATEST(cb.category_baseline_sales, 0.1)) >= 0.8 THEN 'NORMAL_IMPACT'
        ELSE 'LOW_IMPACT'
    END AS impact_classification
FROM seasonal_sales ss
JOIN category_baselines cb ON ss.category = cb.category 
    AND ss.store_id = cb.store_id 
    AND ss.region = cb.region
ORDER BY ss.category, ss.seasonality, ss.weather_condition;

SELECT * FROM vw_seasonal_analysis;