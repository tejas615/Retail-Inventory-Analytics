# Urban Retail Co. Inventory Management Database Schema

-- =====================================================
-- 1. DATABASE SETUP
-- =====================================================

-- Create database
CREATE DATABASE IF NOT EXISTS urban_retail_inventory;
USE urban_retail_inventory;

SET SQL_MODE = 'STRICT_TRANS_TABLES,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO';

-- =====================================================
-- 2. CORE TABLES
-- =====================================================

-- Stores Master Table
CREATE TABLE stores (
    store_id VARCHAR(10) NOT NULL COMMENT 'Store identifier',
    region VARCHAR(50) NOT NULL COMMENT 'Store region (West, East, South, etc.)',
    store_name VARCHAR(100) COMMENT 'Generated store name',
    store_type VARCHAR(50) DEFAULT 'Retail' COMMENT 'Type of store',
    
    -- Composite primary key for store_id and region
    PRIMARY KEY (store_id, region),
    
    -- Performance indexes
    INDEX idx_region (region),
    INDEX idx_store_id (store_id)
) ENGINE=InnoDB COMMENT='Master table for store information with composite PK';

-- Products Master Table
CREATE TABLE products (
    product_id VARCHAR(10) NOT NULL PRIMARY KEY COMMENT 'Unique product identifier',
    category VARCHAR(50) NOT NULL COMMENT 'Product category (Electronics, Toys, etc.)',
    product_name VARCHAR(100) COMMENT 'Product name (auto-generated)',
    
    -- Performance indexes
    INDEX idx_category (category)
) ENGINE=InnoDB COMMENT='Master table for product information';

-- Staging Table for CSV Import 
CREATE TABLE staging_inventory_data (
    Date VARCHAR(20) COMMENT 'Date string from CSV',
    Store_ID VARCHAR(10) COMMENT 'Store identifier from CSV',
    Product_ID VARCHAR(10) COMMENT 'Product identifier from CSV',
    Category VARCHAR(50) COMMENT 'Product category from CSV',
    Region VARCHAR(50) COMMENT 'Store region from CSV',
    Inventory_Level INT COMMENT 'Current inventory level',
    Units_Sold INT COMMENT 'Units sold on this date',
    Units_Ordered INT COMMENT 'Units ordered on this date',
    Demand_Forecast DECIMAL(10,2) COMMENT 'Forecasted demand',
    Price DECIMAL(10,2) COMMENT 'Product price',
    Discount DECIMAL(5,2) COMMENT 'Discount percentage',
    Weather_Condition VARCHAR(20) COMMENT 'Weather on this date',
    Holiday_Promotion VARCHAR(50) COMMENT 'Holiday or promotion info',
    Competitor_Pricing DECIMAL(10,2) COMMENT 'Competitor price',
    Seasonality VARCHAR(20) COMMENT 'Season on this date (Winter, Summer, etc.)'
) ENGINE=InnoDB COMMENT='Staging table for CSV data import';

-- Main Inventory Data Fact Table
CREATE TABLE inventory_data (
    date DATE NOT NULL COMMENT 'Transaction date',
    store_id VARCHAR(10) NOT NULL COMMENT 'Store identifier',
    region VARCHAR(50) NOT NULL COMMENT 'Store region',
    product_id VARCHAR(10) NOT NULL COMMENT 'Product identifier',
    inventory_level INT NOT NULL DEFAULT 0 COMMENT 'Inventory level on this date',
    units_sold INT NOT NULL DEFAULT 0 COMMENT 'Units sold on this date',
    units_ordered INT NOT NULL DEFAULT 0 COMMENT 'Units ordered on this date',
    demand_forecast DECIMAL(10,2) NOT NULL DEFAULT 0 COMMENT 'Demand forecast',
    price DECIMAL(10,2) NOT NULL DEFAULT 0 COMMENT 'Product price',
    discount DECIMAL(5,2) NOT NULL DEFAULT 0 COMMENT 'Discount percentage',
    weather_condition VARCHAR(20) COMMENT 'Weather condition on this date',
    holiday_promotion VARCHAR(50) COMMENT 'Holiday/promotion information',
    competitor_pricing DECIMAL(10,2) DEFAULT 0 COMMENT 'Competitor pricing',
    seasonality VARCHAR(20) COMMENT 'Season on this date',
    created_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT 'Record creation timestamp',
    
    PRIMARY KEY (date, store_id, region, product_id),
    
    FOREIGN KEY (store_id, region) REFERENCES stores(store_id, region) 
        ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (product_id) REFERENCES products(product_id) 
        ON UPDATE CASCADE ON DELETE RESTRICT,

    INDEX idx_date_store_region (date, store_id, region),
    INDEX idx_store_region_product (store_id, region, product_id),
    INDEX idx_date_range (date),
    INDEX idx_category_lookup (product_id, date),
    INDEX idx_seasonality (seasonality),
    INDEX idx_weather (weather_condition)
) ENGINE=InnoDB COMMENT='Main fact table for daily inventory data';

-- Inventory KPIs Calculated Metrics Table
CREATE TABLE inventory_kpis (
    id BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT 'Auto-generated ID',
    store_id VARCHAR(10) NOT NULL COMMENT 'Store identifier',
    region VARCHAR(50) NOT NULL COMMENT 'Store region',
    product_id VARCHAR(10) NOT NULL COMMENT 'Product identifier',
    calculation_date DATE NOT NULL COMMENT 'KPI calculation date',
    avg_daily_sales DECIMAL(10,2) DEFAULT 0 COMMENT 'Average daily sales (90-day)',
    inventory_turnover DECIMAL(10,2) DEFAULT 0 COMMENT 'Annualized inventory turnover',
    days_of_supply INT DEFAULT 0 COMMENT 'Days of supply at current sales rate',
    reorder_point INT DEFAULT 0 COMMENT 'Calculated reorder point',
    safety_stock INT DEFAULT 0 COMMENT 'Calculated safety stock',
    abc_classification VARCHAR(1) DEFAULT 'C' COMMENT 'ABC classification (A/B/C)',
    movement_type VARCHAR(20) DEFAULT 'SLOW_MOVER' COMMENT 'Movement classification',
    service_level DECIMAL(5,2) DEFAULT 95.00 COMMENT 'Target service level percentage',
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    FOREIGN KEY (store_id, region) REFERENCES stores(store_id, region) 
        ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (product_id) REFERENCES products(product_id) 
        ON UPDATE CASCADE ON DELETE RESTRICT,

    INDEX idx_store_region_product_date (store_id, region, product_id, calculation_date),
    INDEX idx_abc_classification (abc_classification),
    INDEX idx_movement_type (movement_type),
    INDEX idx_calculation_date (calculation_date),
    
    UNIQUE KEY uk_store_region_product_date (store_id, region, product_id, calculation_date)
) ENGINE=InnoDB COMMENT='Calculated KPIs and metrics for inventory management';

-- =====================================================
-- 3. DATA LOADING
-- =====================================================

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/inventory_forecasting.csv'
INTO TABLE staging_inventory_data
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(Date, Store_ID, Product_ID, Category, Region, 
Inventory_Level, Units_Sold, Units_Ordered, Demand_Forecast, 
Price, Discount, Weather_Condition, Holiday_Promotion, 
Competitor_Pricing, Seasonality);

-- =====================================================
-- 4. VERIFICATION QUERIES
-- =====================================================

SELECT 
    TABLE_NAME, 
    TABLE_COMMENT,
    TABLE_ROWS
FROM INFORMATION_SCHEMA.TABLES 
WHERE TABLE_SCHEMA = 'urban_retail_inventory'
ORDER BY TABLE_NAME;

SELECT 
    TABLE_NAME, 
    COLUMN_NAME, 
    CONSTRAINT_NAME, 
    REFERENCED_TABLE_NAME, 
    REFERENCED_COLUMN_NAME
FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE 
WHERE TABLE_SCHEMA = 'urban_retail_inventory' 
  AND REFERENCED_TABLE_NAME IS NOT NULL
ORDER BY TABLE_NAME, COLUMN_NAME;