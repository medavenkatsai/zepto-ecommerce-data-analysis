SHOW databases;


CREATE DATABASE IF NOT EXISTS zepto_analysis;
USE zepto_analysis;

-- =========================================================
-- 01. RAW TABLE
-- =========================================================
DROP TABLE IF EXISTS zepto_products_raw;

CREATE TABLE zepto_products_raw (
    Category VARCHAR(100),
    name VARCHAR(255),
    mrp INT,
    discountPercent INT,
    availableQuantity INT,
    discountedSellingPrice INT,
    weightInGms INT,
    outOfStock BOOLEAN,
    quantity INT
);
SELECT *
FROM zepto_analysis;
-- Import the CSV with MySQL Workbench Table Data Import Wizard.
-- File: zepto_v2.csv
-- Encoding: Windows-1252/CP1252 if UTF-8 import fails.

-- =========================================================
-- 02. DATA QUALITY CHECKS
-- =========================================================

SELECT COUNT(*) AS total_rows
FROM zepto_products_raw;

SELECT COUNT(*) - COUNT(DISTINCT CONCAT_WS('|',
    Category, name, mrp, discountPercent, availableQuantity,
    discountedSellingPrice, weightInGms, outOfStock, quantity
)) AS duplicate_rows
FROM zepto_products_raw;

SELECT
    SUM(Category IS NULL) AS null_category,
    SUM(name IS NULL) AS null_name,
    SUM(mrp IS NULL) AS null_mrp,
    SUM(discountPercent IS NULL) AS null_discount,
    SUM(availableQuantity IS NULL) AS null_inventory,
    SUM(discountedSellingPrice IS NULL) AS null_selling_price,
    SUM(weightInGms IS NULL) AS null_weight,
    SUM(outOfStock IS NULL) AS null_stock_flag,
    SUM(quantity IS NULL) AS null_quantity
FROM zepto_products_raw;

SELECT *
FROM zepto_products_raw
WHERE mrp < 0
   OR discountedSellingPrice < 0
   OR availableQuantity < 0
   OR discountPercent NOT BETWEEN 0 AND 100;

SELECT *
FROM zepto_products_raw
WHERE discountedSellingPrice > mrp;

SELECT *
FROM zepto_products_raw
WHERE weightInGms = 0;

-- =========================================================
-- 03. CLEANED TABLE
-- =========================================================

DROP TABLE IF EXISTS zepto_products;

CREATE TABLE zepto_products AS
SELECT DISTINCT
    TRIM(Category) AS Category,
    TRIM(name) AS product_name,
    mrp,
    discountPercent,
    availableQuantity,
    discountedSellingPrice,
    weightInGms,
    outOfStock,
    quantity
FROM zepto_products_raw
WHERE mrp IS NOT NULL
  AND discountedSellingPrice IS NOT NULL
  AND discountPercent BETWEEN 0 AND 100
  AND availableQuantity >= 0;

ALTER TABLE zepto_products
ADD COLUMN product_id INT AUTO_INCREMENT PRIMARY KEY FIRST;

-- =========================================================
-- 04. ANALYSIS VIEW
-- =========================================================

CREATE OR REPLACE VIEW zepto_analysis AS
SELECT
    product_id,
    Category,
    product_name,
    mrp / 100.0 AS mrp_rupees,
    discountPercent,
    availableQuantity,
    discountedSellingPrice / 100.0 AS selling_price_rupees,
    weightInGms,
    outOfStock,
    quantity,
    ROUND((mrp - discountedSellingPrice) / 100.0, 2)
        AS discount_amount_rupees,
    ROUND(
        (discountedSellingPrice / 100.0) / NULLIF(weightInGms, 0),
        4
    ) AS price_per_gram,
    CASE
        WHEN outOfStock = TRUE THEN 'Out of Stock'
        WHEN availableQuantity <= 2 THEN 'Low Stock'
        WHEN availableQuantity <= 5 THEN 'Medium Stock'
        ELSE 'Healthy Stock'
    END AS inventory_status,
    CASE
        WHEN outOfStock = TRUE THEN 'Critical'
        WHEN availableQuantity <= 2 AND discountPercent >= 20
            THEN 'High Priority'
        WHEN availableQuantity <= 2
            THEN 'Medium Priority'
        ELSE 'Normal'
    END AS opportunity_status
FROM zepto_products;

-- =========================================================
-- 05. BUSINESS QUESTIONS
-- =========================================================

-- Q1. Total number of SKUs
SELECT COUNT(*) AS total_skus
FROM zepto_analysis;

-- Q2. Number of categories
SELECT COUNT(DISTINCT Category) AS category_count
FROM zepto_analysis;

-- Q3. Products per category
SELECT Category, COUNT(*) AS product_count
FROM zepto_analysis
GROUP BY Category
ORDER BY product_count DESC;

-- Q4. Average MRP and selling price
SELECT
    ROUND(AVG(mrp_rupees), 2) AS avg_mrp,
    ROUND(AVG(selling_price_rupees), 2) AS avg_selling_price
FROM zepto_analysis;

-- Q5. Average discount
SELECT ROUND(AVG(discountPercent), 2) AS avg_discount_percent
FROM zepto_analysis;

-- Q6. Maximum discount
SELECT MAX(discountPercent) AS max_discount_percent
FROM zepto_analysis;

-- Q7. Overall out-of-stock rate
SELECT
    SUM(outOfStock) AS out_of_stock_skus,
    ROUND(SUM(outOfStock) * 100.0 / COUNT(*), 2)
        AS out_of_stock_rate
FROM zepto_analysis;

-- Q8. Out-of-stock rate by category
SELECT
    Category,
    COUNT(*) AS total_products,
    SUM(outOfStock) AS out_of_stock_products,
    ROUND(SUM(outOfStock) * 100.0 / COUNT(*), 2)
        AS out_of_stock_rate
FROM zepto_analysis
GROUP BY Category
ORDER BY out_of_stock_rate DESC;

-- Q9. Category with highest average discount
SELECT
    Category,
    ROUND(AVG(discountPercent), 2) AS avg_discount
FROM zepto_analysis
GROUP BY Category
ORDER BY avg_discount DESC
LIMIT 10;

-- Q10. Top 10 discounted products
SELECT
    product_name,
    Category,
    discountPercent,
    ROUND(mrp_rupees,2),
    ROUND(selling_price_rupees,2)
FROM zepto_analysis
ORDER BY discountPercent DESC, mrp_rupees DESC
LIMIT 10;

-- Q11. Low-stock products
SELECT
    product_name,
    Category,
    availableQuantity,
    inventory_status
FROM zepto_analysis
WHERE outOfStock = FALSE
  AND availableQuantity <= 2
ORDER BY availableQuantity, product_name;

-- Q12. Count of low-stock products
SELECT COUNT(*) AS low_stock_products
FROM zepto_analysis
WHERE outOfStock = FALSE
  AND availableQuantity <= 2;

-- Q13. High-priority inventory opportunities
SELECT COUNT(*) AS high_priority_products
FROM zepto_analysis
WHERE opportunity_status = 'High Priority';

-- Q14. Estimated inventory value by category
SELECT
    Category,
    ROUND(SUM(selling_price_rupees * availableQuantity), 2)
        AS estimated_inventory_value
FROM zepto_analysis
WHERE outOfStock = FALSE
GROUP BY Category
ORDER BY estimated_inventory_value DESC;

-- Q15. Overall estimated inventory value
SELECT
    ROUND(SUM(selling_price_rupees * availableQuantity), 2)
        AS estimated_inventory_value
FROM zepto_analysis
WHERE outOfStock = FALSE;

-- Q16. Top 20 highest-MRP products
SELECT
    product_name,
    Category,
    ROUND(mrp_rupees,2),
    ROUND(selling_price_rupees,2)
FROM zepto_analysis
ORDER BY mrp_rupees DESC
LIMIT 20;

-- Q17. Price-band distribution
SELECT
    CASE
        WHEN selling_price_rupees < 50 THEN 'Under ₹50'
        WHEN selling_price_rupees < 100 THEN '₹50–₹100'
        WHEN selling_price_rupees < 250 THEN '₹100–₹250'
        WHEN selling_price_rupees < 500 THEN '₹250–₹500'
        ELSE 'Above ₹500'
    END AS price_band,
    COUNT(*) AS product_count
FROM zepto_analysis
GROUP BY price_band
ORDER BY
    CASE price_band
        WHEN 'Under ₹50' THEN 1
        WHEN '₹50–₹100' THEN 2
        WHEN '₹100–₹250' THEN 3
        WHEN '₹250–₹500' THEN 4
        ELSE 5
    END;

-- Q18. Highest price-per-gram products
SELECT
    product_name,
    Category,
    weightInGms,
    ROUND(selling_price_rupees,2),
    price_per_gram
FROM zepto_analysis
WHERE weightInGms > 0
ORDER BY price_per_gram DESC
LIMIT 10;

-- Q19. Total catalog discount value
SELECT
    ROUND(SUM(discount_amount_rupees), 2) AS total_discount_value
FROM zepto_analysis;

-- Q20. Discount value by category
SELECT
    Category,
    ROUND(SUM(discount_amount_rupees), 2) AS discount_value
FROM zepto_analysis
GROUP BY Category
ORDER BY discount_value DESC;

-- Q21. Category summary
SELECT
    Category,
    COUNT(*) AS products,
    ROUND(AVG(discountPercent), 2) AS avg_discount,
    ROUND(AVG(selling_price_rupees), 2) AS avg_selling_price
FROM zepto_analysis
GROUP BY Category
ORDER BY products DESC;

-- Q22. Rank products by price within each category
SELECT
    Category,
    product_name,
    selling_price_rupees,
    RANK() OVER (
        PARTITION BY Category
        ORDER BY selling_price_rupees DESC
    ) AS price_rank
FROM zepto_analysis;

-- Q23. Top 3 highest-priced products in each category
WITH ranked_products AS (
    SELECT
        Category,
        product_name,
        selling_price_rupees,
        RANK() OVER (
            PARTITION BY Category
            ORDER BY selling_price_rupees DESC
        ) AS price_rank
    FROM zepto_analysis
)
SELECT *
FROM ranked_products
WHERE price_rank <= 3;

-- Q24. Category with the highest stock-out rate
SELECT
    Category,
    ROUND(SUM(outOfStock) * 100.0 / COUNT(*), 2)
        AS out_of_stock_rate
FROM zepto_analysis
GROUP BY Category
ORDER BY out_of_stock_rate DESC
LIMIT 1;

-- Q25. Products with high discount and low inventory
SELECT
    product_name,
    Category,
    availableQuantity,
    discountPercent,
    ROUND(selling_price_rupees,2)
FROM zepto_analysis
WHERE outOfStock = FALSE
  AND availableQuantity <= 2
  AND discountPercent >= 20
ORDER BY discountPercent DESC;

-- Q26. Inventory status distribution
SELECT
    inventory_status,
    COUNT(*) AS product_count
FROM zepto_analysis
GROUP BY inventory_status
ORDER BY product_count DESC;

-- Q27. Products above ₹500
SELECT COUNT(*) AS products_above_500
FROM zepto_analysis
WHERE selling_price_rupees > 500;

-- Q28. Median-style percentile analysis using MySQL 8
SELECT
    ROUND(AVG(mrp_rupees), 2) AS avg_mrp,
    ROUND(AVG(selling_price_rupees), 2) AS avg_selling_price,
    ROUND(MIN(selling_price_rupees), 2) AS min_selling_price,
    ROUND(MAX(selling_price_rupees), 2) AS max_selling_price
FROM zepto_analysis;

-- =========================================================
-- 06. POWER BI EXPORT QUERIES
-- =========================================================

-- Executive KPI dataset
SELECT
    COUNT(*) AS total_skus,
    COUNT(DISTINCT Category) AS categories,
    ROUND(AVG(mrp_rupees), 2) AS avg_mrp,
    ROUND(AVG(selling_price_rupees), 2) AS avg_selling_price,
    ROUND(AVG(discountPercent), 2) AS avg_discount,
    SUM(outOfStock) AS out_of_stock_skus,
    ROUND(SUM(outOfStock) * 100.0 / COUNT(*), 2) AS out_of_stock_rate,
    ROUND(SUM(selling_price_rupees * availableQuantity), 2)
        AS estimated_inventory_value
FROM zepto_analysis;

-- Category dashboard dataset
SELECT
    Category,
    COUNT(*) AS product_count,
    ROUND(AVG(mrp_rupees), 2) AS avg_mrp,
    ROUND(AVG(selling_price_rupees), 2) AS avg_selling_price,
    ROUND(AVG(discountPercent), 2) AS avg_discount,
    SUM(outOfStock) AS out_of_stock_products,
    ROUND(SUM(outOfStock) * 100.0 / COUNT(*), 2)
        AS out_of_stock_rate,
    SUM(availableQuantity) AS total_available_quantity,
    ROUND(SUM(selling_price_rupees * availableQuantity), 2)
        AS estimated_inventory_value
FROM zepto_analysis
GROUP BY Category
ORDER BY product_count DESC;

-- Product dashboard dataset
SELECT
    product_id,
    Category,
    product_name,
    mrp_rupees,
    selling_price_rupees,
    discountPercent,
    discount_amount_rupees,
    availableQuantity,
    weightInGms,
    outOfStock,
    quantity,
    price_per_gram,
    inventory_status,
    opportunity_status
FROM zepto_analysis;
