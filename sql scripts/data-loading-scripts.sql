-- =====================================================
-- 1. DATA POPULATION FROM STAGING TABLE
-- =====================================================

-- Step 1: Populate Stores Master Table
INSERT IGNORE INTO stores (store_id, region, store_name)
SELECT DISTINCT 
    Store_ID as store_id,
    Region as region,
    CONCAT('Store ', Store_ID, ' - ', Region) as store_name
FROM staging_inventory_data
ORDER BY Store_ID, Region;

-- Step 2: Populate Products Master Table
INSERT IGNORE INTO products (product_id, category, product_name)
SELECT DISTINCT 
    Product_ID as product_id,
    Category as category,
    CONCAT(Category, ' Product ', Product_ID) as product_name
FROM staging_inventory_data
ORDER BY Category, Product_ID;

-- Step 3: Load Main Inventory Data
INSERT IGNORE INTO inventory_data (
    date, store_id, region, product_id, inventory_level, units_sold, 
    units_ordered, demand_forecast, price, discount, 
    weather_condition, holiday_promotion, competitor_pricing, seasonality
)
SELECT 
    STR_TO_DATE(Date, '%Y-%m-%d') as date,
    Store_ID as store_id,
    Region as region,
    Product_ID as product_id,
    Inventory_Level as inventory_level,
    Units_Sold as units_sold,
    Units_Ordered as units_ordered,
    Demand_Forecast as demand_forecast,
    Price as price,
    Discount as discount,
    Weather_Condition as weather_condition,
    Holiday_Promotion as holiday_promotion,
    Competitor_Pricing as competitor_pricing,
    Seasonality as seasonality
FROM staging_inventory_data
WHERE STR_TO_DATE(Date, '%Y-%m-%d') IS NOT NULL
ORDER BY date, store_id, region, product_id;

-- =====================================================
-- 2. DATA QUALITY VALIDATION
-- =====================================================

-- Comprehensive data quality check
SELECT 
    'Total Records' as metric,
    COUNT(*) as value,
    '' as details
FROM inventory_data
UNION ALL
SELECT 
    'Date Range' as metric,
    DATEDIFF(MAX(date), MIN(date)) as value,
    CONCAT(MIN(date), ' to ', MAX(date)) as details
FROM inventory_data
UNION ALL
SELECT 
    'Unique Store-Region Combinations' as metric,
    COUNT(DISTINCT CONCAT(store_id, '-', region)) as value,
    '' as details
FROM inventory_data
UNION ALL
SELECT 
    'Unique Products' as metric,
    COUNT(DISTINCT product_id) as value,
    '' as details
FROM inventory_data
UNION ALL
SELECT 
    'Unique Categories' as metric,
    COUNT(DISTINCT p.category) as value,
    GROUP_CONCAT(DISTINCT p.category ORDER BY p.category) as details
FROM inventory_data i
JOIN products p ON i.product_id = p.product_id
UNION ALL
SELECT 
    'Records with Negative Inventory' as metric,
    COUNT(*) as value,
    'Should be 0' as details
FROM inventory_data
WHERE inventory_level < 0
UNION ALL
SELECT 
    'Records with Zero Sales and Inventory' as metric,
    COUNT(*) as value,
    'May indicate data quality issues' as details
FROM inventory_data
WHERE units_sold = 0 AND inventory_level = 0;

-- Regional distribution analysis
SELECT 
    region,
    COUNT(DISTINCT store_id) as stores_count,
    COUNT(DISTINCT product_id) as products_count,
    COUNT(*) as total_records,
    ROUND(AVG(inventory_level), 2) as avg_inventory_level,
    ROUND(AVG(units_sold), 2) as avg_units_sold
FROM inventory_data
GROUP BY region
ORDER BY region;

-- Category distribution analysis  
SELECT 
    p.category,
    COUNT(DISTINCT CONCAT(i.store_id, '-', i.region)) as store_region_combinations,
    COUNT(DISTINCT i.product_id) as products_count,
    COUNT(*) as total_records,
    ROUND(AVG(i.price), 2) as avg_price,
    ROUND(AVG(i.units_sold), 2) as avg_units_sold
FROM inventory_data i
JOIN products p ON i.product_id = p.product_id
GROUP BY p.category
ORDER BY p.category;