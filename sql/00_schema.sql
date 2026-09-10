/*
新环境可选：创建四张原始表。已有完整四表数据时不必执行。
使用IF NOT EXISTS，不删除或清空已有表；不会自动修改已有表结构。
列顺序与CSV一致；导入顺序customers → products → orders → order_items。
*/

CREATE DATABASE IF NOT EXISTS ecommerce_analysis
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE ecommerce_analysis;

/* customers：25,000行，18列。 */
CREATE TABLE IF NOT EXISTS `customers` (
    `customer_id` VARCHAR(32) NOT NULL,
    `customer_signup_date` DATE NULL,
    `gender` VARCHAR(255) NULL,
    `age` INT NULL,
    `age_group` VARCHAR(255) NULL,
    `state` VARCHAR(255) NULL,
    `city` VARCHAR(255) NULL,
    `pincode_prefix` VARCHAR(12) NULL,
    `customer_segment` VARCHAR(255) NULL,
    `preferred_device` VARCHAR(255) NULL,
    `preferred_payment_method` VARCHAR(255) NULL,
    `acquisition_channel` VARCHAR(255) NULL,
    `total_orders` INT NULL,
    `total_spend` DECIMAL(18,2) NULL,
    `last_order_date` DATE NULL,
    `average_order_value` DECIMAL(18,2) NULL,
    `customer_status` VARCHAR(255) NULL,
    `loyalty_tier` VARCHAR(255) NULL,
    PRIMARY KEY (`customer_id`)
) ENGINE=InnoDB;

/* products：550行，14列。 */
CREATE TABLE IF NOT EXISTS `products` (
    `product_id` VARCHAR(32) NOT NULL,
    `product_name` VARCHAR(255) NULL,
    `category` VARCHAR(255) NULL,
    `subcategory` VARCHAR(255) NULL,
    `brand` VARCHAR(255) NULL,
    `price` DECIMAL(18,2) NULL,
    `cost_price` DECIMAL(18,2) NULL,
    `discount_range` VARCHAR(255) NULL,
    `rating_average` DECIMAL(10,6) NULL,
    `rating_count` INT NULL,
    `stock_quantity` INT NULL,
    `product_launch_date` DATE NULL,
    `product_type` VARCHAR(255) NULL,
    `return_rate_baseline` DECIMAL(10,6) NULL,
    PRIMARY KEY (`product_id`)
) ENGINE=InnoDB;

/* orders：100,000行，16列。 */
CREATE TABLE IF NOT EXISTS `orders` (
    `order_id` VARCHAR(32) NOT NULL,
    `customer_id` VARCHAR(32) NULL,
    `order_date` DATE NULL,
    `order_time` TIME NULL,
    `order_status` VARCHAR(255) NULL,
    `shipping_method` VARCHAR(255) NULL,
    `delivery_city` VARCHAR(255) NULL,
    `delivery_state` VARCHAR(255) NULL,
    `coupon_code` VARCHAR(255) NULL,
    `discount_percentage` DECIMAL(10,6) NULL,
    `marketing_channel` VARCHAR(255) NULL,
    `subtotal` DECIMAL(18,2) NULL,
    `shipping_fee` DECIMAL(18,2) NULL,
    `tax_amount` DECIMAL(18,2) NULL,
    `final_amount` DECIMAL(18,2) NULL,
    `campaign_id` VARCHAR(32) NULL,
    PRIMARY KEY (`order_id`),
    KEY idx_orders_customer_date (customer_id, order_date),
    KEY idx_orders_date_status (order_date, order_status),
    CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
) ENGINE=InnoDB;

/* order_items：254,331行，9列。 */
CREATE TABLE IF NOT EXISTS `order_items` (
    `order_item_id` VARCHAR(32) NOT NULL,
    `order_id` VARCHAR(32) NULL,
    `product_id` VARCHAR(32) NULL,
    `quantity` INT NULL,
    `unit_price` DECIMAL(18,2) NULL,
    `discount_percentage` DECIMAL(10,6) NULL,
    `item_revenue` DECIMAL(18,2) NULL,
    `item_cost` DECIMAL(18,2) NULL,
    `profit` DECIMAL(18,2) NULL,
    PRIMARY KEY (`order_item_id`),
    KEY idx_items_order (order_id),
    KEY idx_items_product (product_id),
    CONSTRAINT fk_items_order FOREIGN KEY (order_id) REFERENCES orders(order_id),
    CONSTRAINT fk_items_product FOREIGN KEY (product_id) REFERENCES products(product_id)
) ENGINE=InnoDB;
