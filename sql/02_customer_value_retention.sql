USE ecommerce_analysis;

/*
用户价值与未购预警分析

主线：
1. 用户整体概览与年度成交表现
2. 客户基础行为
3. 年末未购时长结构
4. 年度高消费客户识别
5. 高消费客户的收入与商品毛利贡献
6. 复购间隔、预警阈值回看与固定窗口二购
7. 高消费预警客户与其他预警客户比较
8. 高消费预警客户核心指标
9. 预警客户的运营分层
10. 最终客户名单

统一口径：
1. MySQL 8.0+；先执行 USE 和下面的日期参数，再执行所需查询。
   各段 CTE 独立，可单独执行；全部代码只读取原表，不修改原始数据。
   第2、4节明细超过1000行；在Workbench关闭Limit to 1000 rows后查看完整结果。
2. 年度分析为2025年，对比2024年；经营指标只统计当前状态 Delivered 的订单。
   年份、首次及最近成交日期均按这些订单的 order_date 划分，不是签收日期。
3. Revenue = SUM(orders.subtotal)，不含税和运费；与企业经营板块一致。
   Gross Profit = SUM(order_items.profit)，仅为商品毛利，不是净利润。
   商品明细先汇总到订单再关联，避免订单金额被明细行数放大。
4. Top 20%按各年有Delivered订单的客户Revenue降序取NTILE(5)第一组。
   并列时按customer_id升序打破并列，人数约为五分之一，不是金额分位阈值。
   高消费不等于高盈利，名单单独标注非正毛利客户。
5. 历史首次及最近成交使用截至2025年底的数据内历史，不能只取2025年。
   客户表的total_spend、total_orders、customer_status不用于价值或预警计算。
6. Active、At Risk、Hibernating是未购时长标签，不是已验证的流失概率。
   90、120、180天是运营分组规则；第6节提供回看证据，不宣称最优阈值。
7. 第6C节30/60/90天二购均使用各年1月1日至10月2日首购客户，统一样本。
   首购是数据内首个Delivered订单；不同order_id同日下单也计二购。
   分母包含窗口内未二购者，排除没有完整90天观察期的晚期首购客户。
8. 数据只有当前订单状态，没有历史状态日志。回看按订单日期切分，
   无法还原当时真实可见的Delivered状态；回看结果为描述性证据。
9. 金额单位INR；百分比字段以0至100输出，pp表示百分点。
*/

SET @compare_start = CAST('2024-01-01' AS DATE);
SET @analysis_start = CAST('2025-01-01' AS DATE);
SET @analysis_end = CAST('2026-01-01' AS DATE);
SET @as_of_date = CAST('2025-12-31' AS DATE);

/* ================================================================
   0. 数据关联与金额核验

   异常数应为0；若存在缺失或重复，应先核查，不用0填充未知商品毛利。
   ================================================================ */

WITH item_totals AS (
    SELECT
        order_id,
        SUM(item_revenue) AS item_revenue,
        SUM(profit) AS gross_profit
    FROM order_items
    GROUP BY order_id
)
SELECT
    (SELECT COUNT(*) - COUNT(DISTINCT customer_id) FROM customers) AS duplicate_customer_ids,
    (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM orders) AS duplicate_order_ids,
    (SELECT COUNT(*) - COUNT(DISTINCT order_item_id) FROM order_items) AS duplicate_item_ids,
    COUNT(*) AS order_count,
    SUM(CASE WHEN c.customer_id IS NULL THEN 1 ELSE 0 END) AS missing_customer_orders,
    SUM(CASE WHEN t.order_id IS NULL THEN 1 ELSE 0 END) AS missing_item_orders,
    SUM(CASE WHEN ABS(o.subtotal - t.item_revenue) > 0.01 THEN 1 ELSE 0 END) AS subtotal_mismatch_orders,
    SUM(CASE WHEN o.order_date < c.customer_signup_date THEN 1 ELSE 0 END) AS orders_before_signup
FROM orders o
LEFT JOIN customers c
    ON o.customer_id = c.customer_id
LEFT JOIN item_totals t
    ON o.order_id = t.order_id
WHERE o.order_date < @analysis_end;


/* ================================================================
   1A. 截至2025年底的客户成交覆盖

   这是客户快照的历史成交覆盖，不是2025年流量转化率。
   ================================================================ */

WITH customer_order_status AS (
    SELECT
        c.customer_id,
        COUNT(o.order_id) AS all_orders,
        SUM(CASE WHEN o.order_status = 'Delivered' THEN 1 ELSE 0 END) AS delivered_orders
    FROM customers c
    LEFT JOIN orders o
        ON c.customer_id = o.customer_id
       AND o.order_date < @analysis_end
    WHERE c.customer_signup_date < @analysis_end
    GROUP BY c.customer_id
),
customer_groups AS (
    SELECT
        customer_id,
        CASE
            WHEN delivered_orders > 0 THEN '有Delivered成交'
            WHEN all_orders = 0 THEN '无订单记录'
            ELSE '有下单但无Delivered'
        END AS customer_order_group
    FROM customer_order_status
)
SELECT
    customer_order_group,
    COUNT(*) AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS customer_share_pct
FROM customer_groups
GROUP BY customer_order_group
ORDER BY customers DESC;


/* ================================================================
   1B. 2025年与2024年客户成交表现

   Annual Repeat Buyer Share为年内至少两单客户占比，不等于固定90天二购率。
   ================================================================ */

WITH order_profit AS (
    SELECT
        order_id,
        SUM(profit) AS gross_profit
    FROM order_items
    GROUP BY order_id
),
delivered_orders AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.order_date,
        o.subtotal AS revenue,
        p.gross_profit
    FROM orders o
    JOIN order_profit p
        ON o.order_id = p.order_id
    WHERE o.order_status = 'Delivered'
      AND o.order_date < @analysis_end
),
customer_year AS (
    SELECT
        YEAR(order_date) AS order_year,
        customer_id,
        COUNT(*) AS delivered_orders,
        SUM(revenue) AS revenue,
        SUM(gross_profit) AS gross_profit
    FROM delivered_orders
    WHERE order_date >= @compare_start
    GROUP BY
        YEAR(order_date),
        customer_id
)

SELECT
    order_year,
    COUNT(*) AS buyers,
    SUM(delivered_orders) AS delivered_orders,
    ROUND(SUM(revenue), 2) AS revenue,
    ROUND(SUM(gross_profit), 2) AS gross_profit,
    ROUND(100.0 * SUM(gross_profit) / NULLIF(SUM(revenue), 0), 2) AS gross_margin_pct,
    ROUND(1.0 * SUM(delivered_orders) / NULLIF(COUNT(*), 0), 4) AS purchase_frequency,
    ROUND(SUM(revenue) / NULLIF(SUM(delivered_orders), 0), 2) AS aov,
    SUM(CASE WHEN delivered_orders >= 2 THEN 1 ELSE 0 END) AS annual_repeat_buyers,
    ROUND(
        100.0 * SUM(CASE WHEN delivered_orders >= 2 THEN 1 ELSE 0 END) / COUNT(*),
        2
    ) AS annual_repeat_buyer_share_pct
FROM customer_year
GROUP BY order_year
ORDER BY order_year;


/* ================================================================
   1C. 数据内新增成交客户与既有客户贡献

   新增指数据内首次Delivered订单在当年，既有指首次订单在当年之前；各年人群动态变化。
   ================================================================ */

WITH order_profit AS (
    SELECT
        order_id,
        SUM(profit) AS gross_profit
    FROM order_items
    GROUP BY order_id
),
delivered_orders AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.order_date,
        o.subtotal AS revenue,
        p.gross_profit
    FROM orders o
    JOIN order_profit p
        ON o.order_id = p.order_id
    WHERE o.order_status = 'Delivered'
      AND o.order_date < @analysis_end
),
customer_history AS (
    SELECT
        customer_id,
        MIN(order_date) AS first_delivered_order_date,
        MAX(order_date) AS last_delivered_order_date,
        COUNT(*) AS historical_orders,
        SUM(revenue) AS historical_revenue
    FROM delivered_orders
    GROUP BY customer_id
),
customer_year AS (
    SELECT
        YEAR(order_date) AS order_year,
        customer_id,
        COUNT(*) AS delivered_orders,
        SUM(revenue) AS revenue,
        SUM(gross_profit) AS gross_profit
    FROM delivered_orders
    WHERE order_date >= @compare_start
    GROUP BY
        YEAR(order_date),
        customer_id
),
customer_groups AS (
    SELECT
        y.order_year,
        y.customer_id,
        y.revenue,
        y.gross_profit,
        CASE
            WHEN YEAR(h.first_delivered_order_date) = y.order_year THEN 'New Observed Buyers'
            ELSE 'Existing Buyers'
        END AS customer_group
    FROM customer_year y
    JOIN customer_history h
        ON y.customer_id = h.customer_id
),
group_totals AS (
    SELECT
        order_year,
        customer_group,
        COUNT(*) AS buyers,
        SUM(revenue) AS revenue,
        SUM(gross_profit) AS gross_profit
    FROM customer_groups
    GROUP BY order_year, customer_group
)

SELECT
    order_year,
    customer_group,
    buyers,
    ROUND(revenue, 2) AS revenue,
    ROUND(gross_profit, 2) AS gross_profit,
    ROUND(100.0 * revenue / SUM(revenue) OVER (PARTITION BY order_year), 2) AS revenue_share_pct,
    ROUND(
        revenue - LAG(revenue) OVER (PARTITION BY customer_group ORDER BY order_year),
        2
    ) AS revenue_change
FROM group_totals
ORDER BY customer_group, order_year;


/* ================================================================
   2. 2025年客户基础行为表

   每行一位2025年成交客户。历史日期用于判断客户关系，金额单独标明年度与历史。
   ================================================================ */

WITH order_profit AS (
    SELECT
        order_id,
        SUM(profit) AS gross_profit
    FROM order_items
    GROUP BY order_id
),
delivered_orders AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.order_date,
        o.subtotal AS revenue,
        p.gross_profit
    FROM orders o
    JOIN order_profit p
        ON o.order_id = p.order_id
    WHERE o.order_status = 'Delivered'
      AND o.order_date < @analysis_end
),
customer_history AS (
    SELECT
        customer_id,
        MIN(order_date) AS first_delivered_order_date,
        MAX(order_date) AS last_delivered_order_date,
        COUNT(*) AS historical_orders,
        SUM(revenue) AS historical_revenue
    FROM delivered_orders
    GROUP BY customer_id
),
customer_year AS (
    SELECT
        YEAR(order_date) AS order_year,
        customer_id,
        COUNT(*) AS delivered_orders,
        SUM(revenue) AS revenue,
        SUM(gross_profit) AS gross_profit
    FROM delivered_orders
    WHERE order_date >= @compare_start
    GROUP BY
        YEAR(order_date),
        customer_id
),
customer_rank AS (
    SELECT
        order_year,
        customer_id,
        delivered_orders,
        revenue,
        gross_profit,
        NTILE(5) OVER (
            PARTITION BY order_year
            ORDER BY revenue DESC, customer_id
        ) AS spend_rank
    FROM customer_year
),
customer_profile AS (
    SELECT
        h.customer_id,
        h.first_delivered_order_date,
        h.last_delivered_order_date,
        h.historical_orders,
        h.historical_revenue,
        COALESCE(r.delivered_orders, 0) AS orders_2025,
        COALESCE(r.revenue, 0) AS revenue_2025,
        COALESCE(r.gross_profit, 0) AS gross_profit_2025,
        r.spend_rank,
        DATEDIFF(@as_of_date, h.last_delivered_order_date) AS recency_days,
        CASE
            WHEN DATEDIFF(@as_of_date, h.last_delivered_order_date) <= 90
                THEN 'Active'
            WHEN DATEDIFF(@as_of_date, h.last_delivered_order_date) <= 180
                THEN 'At Risk'
            WHEN DATEDIFF(@as_of_date, h.last_delivered_order_date) <= 365
                THEN 'Hibernating'
            ELSE 'Over 365 Days'
        END AS lifecycle_status
    FROM customer_history h
    LEFT JOIN customer_rank r
        ON h.customer_id = r.customer_id
       AND r.order_year = YEAR(@analysis_start)
)

SELECT
    customer_id,
    first_delivered_order_date,
    last_delivered_order_date,
    recency_days,
    orders_2025,
    ROUND(revenue_2025, 2) AS revenue_2025,
    ROUND(gross_profit_2025, 2) AS gross_profit_2025,
    ROUND(100.0 * gross_profit_2025 / NULLIF(revenue_2025, 0), 2) AS gross_margin_2025_pct,
    historical_orders,
    ROUND(historical_revenue, 2) AS historical_revenue,
    spend_rank
FROM customer_profile
WHERE orders_2025 > 0
ORDER BY revenue_2025 DESC, customer_id;


/* ================================================================
   3. 全部历史成交客户的年末未购时长结构

   保留2025年没有购买的老客户；Over 365 Days仅表示超过365天未购，不命名为已流失。
   ================================================================ */

WITH order_profit AS (
    SELECT
        order_id,
        SUM(profit) AS gross_profit
    FROM order_items
    GROUP BY order_id
),
delivered_orders AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.order_date,
        o.subtotal AS revenue,
        p.gross_profit
    FROM orders o
    JOIN order_profit p
        ON o.order_id = p.order_id
    WHERE o.order_status = 'Delivered'
      AND o.order_date < @analysis_end
),
customer_history AS (
    SELECT
        customer_id,
        MIN(order_date) AS first_delivered_order_date,
        MAX(order_date) AS last_delivered_order_date,
        COUNT(*) AS historical_orders,
        SUM(revenue) AS historical_revenue
    FROM delivered_orders
    GROUP BY customer_id
),
customer_year AS (
    SELECT
        YEAR(order_date) AS order_year,
        customer_id,
        COUNT(*) AS delivered_orders,
        SUM(revenue) AS revenue,
        SUM(gross_profit) AS gross_profit
    FROM delivered_orders
    WHERE order_date >= @compare_start
    GROUP BY
        YEAR(order_date),
        customer_id
),
customer_rank AS (
    SELECT
        order_year,
        customer_id,
        delivered_orders,
        revenue,
        gross_profit,
        NTILE(5) OVER (
            PARTITION BY order_year
            ORDER BY revenue DESC, customer_id
        ) AS spend_rank
    FROM customer_year
),
customer_profile AS (
    SELECT
        h.customer_id,
        h.first_delivered_order_date,
        h.last_delivered_order_date,
        h.historical_orders,
        h.historical_revenue,
        COALESCE(r.delivered_orders, 0) AS orders_2025,
        COALESCE(r.revenue, 0) AS revenue_2025,
        COALESCE(r.gross_profit, 0) AS gross_profit_2025,
        r.spend_rank,
        DATEDIFF(@as_of_date, h.last_delivered_order_date) AS recency_days,
        CASE
            WHEN DATEDIFF(@as_of_date, h.last_delivered_order_date) <= 90
                THEN 'Active'
            WHEN DATEDIFF(@as_of_date, h.last_delivered_order_date) <= 180
                THEN 'At Risk'
            WHEN DATEDIFF(@as_of_date, h.last_delivered_order_date) <= 365
                THEN 'Hibernating'
            ELSE 'Over 365 Days'
        END AS lifecycle_status
    FROM customer_history h
    LEFT JOIN customer_rank r
        ON h.customer_id = r.customer_id
       AND r.order_year = YEAR(@analysis_start)
)

SELECT
    lifecycle_status,
    COUNT(*) AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS customer_share_pct,
    SUM(CASE WHEN orders_2025 > 0 THEN 1 ELSE 0 END) AS buyers_2025,
    ROUND(SUM(revenue_2025), 2) AS revenue_2025,
    ROUND(SUM(gross_profit_2025), 2) AS gross_profit_2025
FROM customer_profile
GROUP BY lifecycle_status
ORDER BY MIN(recency_days);


/* ================================================================
   4. 年度消费额前20%的客户

   保留原NTILE(5)识别方式；增加customer_id以确保并列情况下结果稳定。
   ================================================================ */

WITH order_profit AS (
    SELECT
        order_id,
        SUM(profit) AS gross_profit
    FROM order_items
    GROUP BY order_id
),
delivered_orders AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.order_date,
        o.subtotal AS revenue,
        p.gross_profit
    FROM orders o
    JOIN order_profit p
        ON o.order_id = p.order_id
    WHERE o.order_status = 'Delivered'
      AND o.order_date < @analysis_end
),
customer_year AS (
    SELECT
        YEAR(order_date) AS order_year,
        customer_id,
        COUNT(*) AS delivered_orders,
        SUM(revenue) AS revenue,
        SUM(gross_profit) AS gross_profit
    FROM delivered_orders
    WHERE order_date >= @compare_start
    GROUP BY
        YEAR(order_date),
        customer_id
),
customer_rank AS (
    SELECT
        order_year,
        customer_id,
        delivered_orders,
        revenue,
        gross_profit,
        NTILE(5) OVER (
            PARTITION BY order_year
            ORDER BY revenue DESC, customer_id
        ) AS spend_rank
    FROM customer_year
)

SELECT
    order_year,
    customer_id,
    delivered_orders,
    ROUND(revenue, 2) AS revenue,
    ROUND(gross_profit, 2) AS gross_profit,
    ROUND(100.0 * gross_profit / NULLIF(revenue, 0), 2) AS gross_margin_pct,
    CASE
        WHEN gross_profit > 0 THEN '正毛利'
        ELSE '非正毛利'
    END AS profitability_group
FROM customer_rank
WHERE spend_rank = 1
ORDER BY order_year, revenue DESC, customer_id;


/* ================================================================
   5. 高消费客户的收入与商品毛利贡献

   同时对比收入集中度与毛利集中度；消费额高不能直接等同于盈利价值高。
   ================================================================ */

WITH order_profit AS (
    SELECT
        order_id,
        SUM(profit) AS gross_profit
    FROM order_items
    GROUP BY order_id
),
delivered_orders AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.order_date,
        o.subtotal AS revenue,
        p.gross_profit
    FROM orders o
    JOIN order_profit p
        ON o.order_id = p.order_id
    WHERE o.order_status = 'Delivered'
      AND o.order_date < @analysis_end
),
customer_year AS (
    SELECT
        YEAR(order_date) AS order_year,
        customer_id,
        COUNT(*) AS delivered_orders,
        SUM(revenue) AS revenue,
        SUM(gross_profit) AS gross_profit
    FROM delivered_orders
    WHERE order_date >= @compare_start
    GROUP BY
        YEAR(order_date),
        customer_id
),
customer_rank AS (
    SELECT
        order_year,
        customer_id,
        delivered_orders,
        revenue,
        gross_profit,
        NTILE(5) OVER (
            PARTITION BY order_year
            ORDER BY revenue DESC, customer_id
        ) AS spend_rank
    FROM customer_year
)

SELECT
    order_year,
    COUNT(*) AS buyers,
    SUM(CASE WHEN spend_rank = 1 THEN 1 ELSE 0 END) AS top20_buyers,
    ROUND(SUM(CASE WHEN spend_rank = 1 THEN revenue ELSE 0 END), 2) AS top20_revenue,
    ROUND(SUM(CASE WHEN spend_rank = 1 THEN gross_profit ELSE 0 END), 2) AS top20_gross_profit,
    ROUND(
        100.0 * SUM(CASE WHEN spend_rank = 1 THEN revenue ELSE 0 END) / NULLIF(SUM(revenue), 0),
        2
    ) AS top20_revenue_share_pct,
    ROUND(
        100.0 * SUM(CASE WHEN spend_rank = 1 THEN gross_profit ELSE 0 END) / NULLIF(SUM(gross_profit), 0),
        2
    ) AS top20_gross_profit_share_pct,
    SUM(CASE WHEN spend_rank = 1 AND gross_profit <= 0 THEN 1 ELSE 0 END) AS top20_nonpositive_buyers,
    ROUND(MIN(CASE WHEN spend_rank = 1 THEN revenue END), 2) AS top20_min_revenue
FROM customer_rank
GROUP BY order_year
ORDER BY order_year;


/* ================================================================
   6A. 2025年高消费客户的历史相邻订单间隔

   仅描述当前高消费客户已经发生的间隔；不包含尚未发生的复购，高频客户贡献多个间隔。
   ================================================================ */

WITH order_profit AS (
    SELECT
        order_id,
        SUM(profit) AS gross_profit
    FROM order_items
    GROUP BY order_id
),
delivered_orders AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.order_date,
        o.subtotal AS revenue,
        p.gross_profit
    FROM orders o
    JOIN order_profit p
        ON o.order_id = p.order_id
    WHERE o.order_status = 'Delivered'
      AND o.order_date < @analysis_end
),
customer_year AS (
    SELECT
        YEAR(order_date) AS order_year,
        customer_id,
        COUNT(*) AS delivered_orders,
        SUM(revenue) AS revenue,
        SUM(gross_profit) AS gross_profit
    FROM delivered_orders
    WHERE order_date >= @compare_start
    GROUP BY
        YEAR(order_date),
        customer_id
),
customer_rank AS (
    SELECT
        order_year,
        customer_id,
        delivered_orders,
        revenue,
        gross_profit,
        NTILE(5) OVER (
            PARTITION BY order_year
            ORDER BY revenue DESC, customer_id
        ) AS spend_rank
    FROM customer_year
),
ordered_purchases AS (
    SELECT
        d.customer_id,
        d.order_date,
        LAG(d.order_date) OVER (
            PARTITION BY d.customer_id
            ORDER BY d.order_date, d.order_id
        ) AS previous_order_date
    FROM delivered_orders d
    JOIN customer_rank r
        ON d.customer_id = r.customer_id
       AND r.order_year = YEAR(@analysis_start)
       AND r.spend_rank = 1
),
purchase_intervals AS (
    SELECT
        customer_id,
        DATEDIFF(order_date, previous_order_date) AS interval_days
    FROM ordered_purchases
    WHERE previous_order_date IS NOT NULL
)

SELECT
    COUNT(DISTINCT customer_id) AS customers_with_repeat_intervals,
    COUNT(*) AS observed_intervals,
    ROUND(AVG(interval_days), 2) AS avg_interval_days,
    ROUND(100.0 * SUM(CASE WHEN interval_days <= 90 THEN 1 ELSE 0 END) / COUNT(*), 2) AS within_90_days_pct,
    ROUND(100.0 * SUM(CASE WHEN interval_days <= 180 THEN 1 ELSE 0 END) / COUNT(*), 2) AS within_180_days_pct
FROM purchase_intervals;


/* ================================================================
   6B. 90天预警线的历史回看

   各回看日按之前12个自然月Revenue选Top20%，未来90天只作结果观察，不参与筛人。
   使用当前Delivered状态，不能还原历史状态；各组差异不代表召回干预效果。
   ================================================================ */

WITH order_profit AS (
    SELECT
        order_id,
        SUM(profit) AS gross_profit
    FROM order_items
    GROUP BY order_id
),
delivered_orders AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.order_date,
        o.subtotal AS revenue,
        p.gross_profit
    FROM orders o
    JOIN order_profit p
        ON o.order_id = p.order_id
    WHERE o.order_status = 'Delivered'
      AND o.order_date < @analysis_end
),
snapshot_dates AS (
    SELECT
        CAST('2024-12-31' AS DATE) AS snapshot_date,
        CAST('2024-01-01' AS DATE) AS value_start
    UNION ALL
    SELECT
        CAST('2025-06-30' AS DATE),
        CAST('2024-07-01' AS DATE)
),
snapshot_values AS (
    SELECT
        s.snapshot_date,
        d.customer_id,
        SUM(d.revenue) AS trailing_revenue,
        MAX(d.order_date) AS last_order_date
    FROM snapshot_dates s
    JOIN delivered_orders d
        ON d.order_date >= s.value_start
       AND d.order_date < DATE_ADD(s.snapshot_date, INTERVAL 1 DAY)
    GROUP BY s.snapshot_date, d.customer_id
),
snapshot_rank AS (
    SELECT
        snapshot_date,
        customer_id,
        last_order_date,
        NTILE(5) OVER (
            PARTITION BY snapshot_date
            ORDER BY trailing_revenue DESC, customer_id
        ) AS spend_rank
    FROM snapshot_values
),
snapshot_followup AS (
    SELECT
        s.snapshot_date,
        s.customer_id,
        DATEDIFF(s.snapshot_date, s.last_order_date) AS recency_days,
        MAX(CASE WHEN d.order_id IS NOT NULL THEN 1 ELSE 0 END) AS bought_next_90_days
    FROM snapshot_rank s
    LEFT JOIN delivered_orders d
        ON s.customer_id = d.customer_id
       AND d.order_date >= DATE_ADD(s.snapshot_date, INTERVAL 1 DAY)
       AND d.order_date < DATE_ADD(s.snapshot_date, INTERVAL 91 DAY)
    WHERE s.spend_rank = 1
    GROUP BY s.snapshot_date, s.customer_id, s.last_order_date
),
snapshot_groups AS (
    SELECT
        snapshot_date,
        recency_days,
        bought_next_90_days,
        CASE
            WHEN recency_days <= 90 THEN '0-90天'
            WHEN recency_days <= 120 THEN '91-120天'
            WHEN recency_days <= 180 THEN '121-180天'
            ELSE '181-365天'
        END AS recency_group
    FROM snapshot_followup
)

SELECT
    snapshot_date,
    recency_group,
    COUNT(*) AS customers,
    SUM(bought_next_90_days) AS next_90_day_buyers,
    ROUND(100.0 * SUM(bought_next_90_days) / COUNT(*), 2) AS next_90_day_purchase_rate_pct
FROM snapshot_groups
GROUP BY snapshot_date, recency_group
ORDER BY snapshot_date, MIN(recency_days);


/* ================================================================
   6C. 同期首购客户的30天60天90天二购表现

   各年均取1月1日至10月2日首购客户，所有窗口使用同一批人；先排序全部历史订单再筛首购日期。
   ================================================================ */

WITH order_profit AS (
    SELECT
        order_id,
        SUM(profit) AS gross_profit
    FROM order_items
    GROUP BY order_id
),
delivered_orders AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.order_date,
        o.subtotal AS revenue,
        p.gross_profit
    FROM orders o
    JOIN order_profit p
        ON o.order_id = p.order_id
    WHERE o.order_status = 'Delivered'
      AND o.order_date < @analysis_end
),
ordered_purchases AS (
    SELECT
        customer_id,
        order_date,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY order_date, order_id
        ) AS order_sequence
    FROM delivered_orders
),
first_second_purchase AS (
    SELECT
        customer_id,
        MIN(CASE WHEN order_sequence = 1 THEN order_date END) AS first_order_date,
        MIN(CASE WHEN order_sequence = 2 THEN order_date END) AS second_order_date
    FROM ordered_purchases
    WHERE order_sequence <= 2
    GROUP BY customer_id
),
eligible_cohort AS (
    SELECT
        customer_id,
        YEAR(first_order_date) AS cohort_year,
        DATEDIFF(second_order_date, first_order_date) AS second_purchase_days
    FROM first_second_purchase
    WHERE (
        first_order_date >= '2024-01-01'
        AND first_order_date < '2024-10-03'
    ) OR (
        first_order_date >= '2025-01-01'
        AND first_order_date < '2025-10-03'
    )
),
observation_windows AS (
    SELECT 30 AS window_days
    UNION ALL SELECT 60
    UNION ALL SELECT 90
)

SELECT
    e.cohort_year,
    w.window_days,
    COUNT(*) AS eligible_customers,
    SUM(CASE WHEN e.second_purchase_days <= w.window_days THEN 1 ELSE 0 END) AS second_purchase_customers,
    ROUND(
        100.0 * SUM(CASE WHEN e.second_purchase_days <= w.window_days THEN 1 ELSE 0 END) / COUNT(*),
        2
    ) AS second_purchase_rate_pct
FROM eligible_cohort e
CROSS JOIN observation_windows w
GROUP BY e.cohort_year, w.window_days
ORDER BY e.cohort_year, w.window_days;


/* ================================================================
   7. 高消费预警客户与其他预警客户比较

   分母为全部91至180天未购客户；收入与毛利均为2025年，不与历史累计金额混用。
   ================================================================ */

WITH order_profit AS (
    SELECT
        order_id,
        SUM(profit) AS gross_profit
    FROM order_items
    GROUP BY order_id
),
delivered_orders AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.order_date,
        o.subtotal AS revenue,
        p.gross_profit
    FROM orders o
    JOIN order_profit p
        ON o.order_id = p.order_id
    WHERE o.order_status = 'Delivered'
      AND o.order_date < @analysis_end
),
customer_history AS (
    SELECT
        customer_id,
        MIN(order_date) AS first_delivered_order_date,
        MAX(order_date) AS last_delivered_order_date,
        COUNT(*) AS historical_orders,
        SUM(revenue) AS historical_revenue
    FROM delivered_orders
    GROUP BY customer_id
),
customer_year AS (
    SELECT
        YEAR(order_date) AS order_year,
        customer_id,
        COUNT(*) AS delivered_orders,
        SUM(revenue) AS revenue,
        SUM(gross_profit) AS gross_profit
    FROM delivered_orders
    WHERE order_date >= @compare_start
    GROUP BY
        YEAR(order_date),
        customer_id
),
customer_rank AS (
    SELECT
        order_year,
        customer_id,
        delivered_orders,
        revenue,
        gross_profit,
        NTILE(5) OVER (
            PARTITION BY order_year
            ORDER BY revenue DESC, customer_id
        ) AS spend_rank
    FROM customer_year
),
customer_profile AS (
    SELECT
        h.customer_id,
        h.first_delivered_order_date,
        h.last_delivered_order_date,
        h.historical_orders,
        h.historical_revenue,
        COALESCE(r.delivered_orders, 0) AS orders_2025,
        COALESCE(r.revenue, 0) AS revenue_2025,
        COALESCE(r.gross_profit, 0) AS gross_profit_2025,
        r.spend_rank,
        DATEDIFF(@as_of_date, h.last_delivered_order_date) AS recency_days,
        CASE
            WHEN DATEDIFF(@as_of_date, h.last_delivered_order_date) <= 90
                THEN 'Active'
            WHEN DATEDIFF(@as_of_date, h.last_delivered_order_date) <= 180
                THEN 'At Risk'
            WHEN DATEDIFF(@as_of_date, h.last_delivered_order_date) <= 365
                THEN 'Hibernating'
            ELSE 'Over 365 Days'
        END AS lifecycle_status
    FROM customer_history h
    LEFT JOIN customer_rank r
        ON h.customer_id = r.customer_id
       AND r.order_year = YEAR(@analysis_start)
),
warning_groups AS (
    SELECT
        customer_id,
        revenue_2025,
        gross_profit_2025,
        CASE
            WHEN spend_rank = 1 THEN 'Top20 Warning'
            ELSE 'Other Warning'
        END AS warning_group
    FROM customer_profile
    WHERE recency_days BETWEEN 91 AND 180
)

SELECT
    warning_group,
    COUNT(*) AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS customer_share_pct,
    ROUND(SUM(revenue_2025), 2) AS revenue_2025,
    ROUND(SUM(gross_profit_2025), 2) AS gross_profit_2025,
    ROUND(100.0 * SUM(revenue_2025) / NULLIF(SUM(SUM(revenue_2025)) OVER (), 0), 2) AS revenue_share_pct,
    ROUND(100.0 * SUM(gross_profit_2025) / NULLIF(SUM(SUM(gross_profit_2025)) OVER (), 0), 2) AS gross_profit_share_pct
FROM warning_groups
GROUP BY warning_group
ORDER BY revenue_2025 DESC;


/* ================================================================
   8. 高消费预警客户的年度价值

   显示年度收入贡献；这部分历史成交额不等于未来可挽回收入。
   ================================================================ */

WITH order_profit AS (
    SELECT
        order_id,
        SUM(profit) AS gross_profit
    FROM order_items
    GROUP BY order_id
),
delivered_orders AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.order_date,
        o.subtotal AS revenue,
        p.gross_profit
    FROM orders o
    JOIN order_profit p
        ON o.order_id = p.order_id
    WHERE o.order_status = 'Delivered'
      AND o.order_date < @analysis_end
),
customer_history AS (
    SELECT
        customer_id,
        MIN(order_date) AS first_delivered_order_date,
        MAX(order_date) AS last_delivered_order_date,
        COUNT(*) AS historical_orders,
        SUM(revenue) AS historical_revenue
    FROM delivered_orders
    GROUP BY customer_id
),
customer_year AS (
    SELECT
        YEAR(order_date) AS order_year,
        customer_id,
        COUNT(*) AS delivered_orders,
        SUM(revenue) AS revenue,
        SUM(gross_profit) AS gross_profit
    FROM delivered_orders
    WHERE order_date >= @compare_start
    GROUP BY
        YEAR(order_date),
        customer_id
),
customer_rank AS (
    SELECT
        order_year,
        customer_id,
        delivered_orders,
        revenue,
        gross_profit,
        NTILE(5) OVER (
            PARTITION BY order_year
            ORDER BY revenue DESC, customer_id
        ) AS spend_rank
    FROM customer_year
),
customer_profile AS (
    SELECT
        h.customer_id,
        h.first_delivered_order_date,
        h.last_delivered_order_date,
        h.historical_orders,
        h.historical_revenue,
        COALESCE(r.delivered_orders, 0) AS orders_2025,
        COALESCE(r.revenue, 0) AS revenue_2025,
        COALESCE(r.gross_profit, 0) AS gross_profit_2025,
        r.spend_rank,
        DATEDIFF(@as_of_date, h.last_delivered_order_date) AS recency_days,
        CASE
            WHEN DATEDIFF(@as_of_date, h.last_delivered_order_date) <= 90
                THEN 'Active'
            WHEN DATEDIFF(@as_of_date, h.last_delivered_order_date) <= 180
                THEN 'At Risk'
            WHEN DATEDIFF(@as_of_date, h.last_delivered_order_date) <= 365
                THEN 'Hibernating'
            ELSE 'Over 365 Days'
        END AS lifecycle_status
    FROM customer_history h
    LEFT JOIN customer_rank r
        ON h.customer_id = r.customer_id
       AND r.order_year = YEAR(@analysis_start)
),
high_spend_warning AS (
    SELECT
        customer_id,
        first_delivered_order_date,
        last_delivered_order_date,
        historical_orders,
        historical_revenue,
        orders_2025,
        revenue_2025,
        gross_profit_2025,
        recency_days,
        CASE
            WHEN recency_days <= 120 THEN 'Early Warning'
            ELSE 'Deep Risk'
        END AS risk_stage,
        CASE
            WHEN gross_profit_2025 > 0 THEN '正毛利召回候选'
            ELSE '非正毛利核验'
        END AS action_group
    FROM customer_profile
    WHERE spend_rank = 1
      AND recency_days BETWEEN 91 AND 180
)

SELECT
    COUNT(*) AS high_spend_warning_customers,
    ROUND(SUM(revenue_2025), 2) AS revenue_2025,
    ROUND(SUM(gross_profit_2025), 2) AS gross_profit_2025,
    ROUND(AVG(revenue_2025), 2) AS avg_revenue_per_customer,
    ROUND(
        100.0 * SUM(revenue_2025) / NULLIF((
            SELECT SUM(revenue)
            FROM customer_year
            WHERE order_year = YEAR(@analysis_start)
        ), 0),
        2
    ) AS annual_revenue_share_pct,
    SUM(CASE WHEN gross_profit_2025 > 0 THEN 1 ELSE 0 END) AS positive_profit_customers,
    SUM(CASE WHEN gross_profit_2025 <= 0 THEN 1 ELSE 0 END) AS nonpositive_profit_customers
FROM high_spend_warning;


/* ================================================================
   9. 预警客户的毛利与未购时长分层

   Early Warning为91至120天，Deep Risk为121至180天；先按盈利性质决定动作，不认定深度预警召回收益更高。
   ================================================================ */

WITH order_profit AS (
    SELECT
        order_id,
        SUM(profit) AS gross_profit
    FROM order_items
    GROUP BY order_id
),
delivered_orders AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.order_date,
        o.subtotal AS revenue,
        p.gross_profit
    FROM orders o
    JOIN order_profit p
        ON o.order_id = p.order_id
    WHERE o.order_status = 'Delivered'
      AND o.order_date < @analysis_end
),
customer_history AS (
    SELECT
        customer_id,
        MIN(order_date) AS first_delivered_order_date,
        MAX(order_date) AS last_delivered_order_date,
        COUNT(*) AS historical_orders,
        SUM(revenue) AS historical_revenue
    FROM delivered_orders
    GROUP BY customer_id
),
customer_year AS (
    SELECT
        YEAR(order_date) AS order_year,
        customer_id,
        COUNT(*) AS delivered_orders,
        SUM(revenue) AS revenue,
        SUM(gross_profit) AS gross_profit
    FROM delivered_orders
    WHERE order_date >= @compare_start
    GROUP BY
        YEAR(order_date),
        customer_id
),
customer_rank AS (
    SELECT
        order_year,
        customer_id,
        delivered_orders,
        revenue,
        gross_profit,
        NTILE(5) OVER (
            PARTITION BY order_year
            ORDER BY revenue DESC, customer_id
        ) AS spend_rank
    FROM customer_year
),
customer_profile AS (
    SELECT
        h.customer_id,
        h.first_delivered_order_date,
        h.last_delivered_order_date,
        h.historical_orders,
        h.historical_revenue,
        COALESCE(r.delivered_orders, 0) AS orders_2025,
        COALESCE(r.revenue, 0) AS revenue_2025,
        COALESCE(r.gross_profit, 0) AS gross_profit_2025,
        r.spend_rank,
        DATEDIFF(@as_of_date, h.last_delivered_order_date) AS recency_days,
        CASE
            WHEN DATEDIFF(@as_of_date, h.last_delivered_order_date) <= 90
                THEN 'Active'
            WHEN DATEDIFF(@as_of_date, h.last_delivered_order_date) <= 180
                THEN 'At Risk'
            WHEN DATEDIFF(@as_of_date, h.last_delivered_order_date) <= 365
                THEN 'Hibernating'
            ELSE 'Over 365 Days'
        END AS lifecycle_status
    FROM customer_history h
    LEFT JOIN customer_rank r
        ON h.customer_id = r.customer_id
       AND r.order_year = YEAR(@analysis_start)
),
high_spend_warning AS (
    SELECT
        customer_id,
        first_delivered_order_date,
        last_delivered_order_date,
        historical_orders,
        historical_revenue,
        orders_2025,
        revenue_2025,
        gross_profit_2025,
        recency_days,
        CASE
            WHEN recency_days <= 120 THEN 'Early Warning'
            ELSE 'Deep Risk'
        END AS risk_stage,
        CASE
            WHEN gross_profit_2025 > 0 THEN '正毛利召回候选'
            ELSE '非正毛利核验'
        END AS action_group
    FROM customer_profile
    WHERE spend_rank = 1
      AND recency_days BETWEEN 91 AND 180
)

SELECT
    action_group,
    risk_stage,
    COUNT(*) AS customers,
    ROUND(SUM(revenue_2025), 2) AS revenue_2025,
    ROUND(SUM(gross_profit_2025), 2) AS gross_profit_2025,
    ROUND(100.0 * SUM(gross_profit_2025) / NULLIF(SUM(revenue_2025), 0), 2) AS gross_margin_2025_pct
FROM high_spend_warning
GROUP BY action_group, risk_stage
ORDER BY
    CASE WHEN action_group = '正毛利召回候选' THEN 1 ELSE 2 END,
    CASE WHEN risk_stage = 'Early Warning' THEN 1 ELSE 2 END;


/* ================================================================
   10. 最终运营客户名单

   与Excel名单同源。排序仅便于核验，不是已验证的营销收益排名。客户属性为当前快照，只作辅助标签。
   ================================================================ */

WITH order_profit AS (
    SELECT
        order_id,
        SUM(profit) AS gross_profit
    FROM order_items
    GROUP BY order_id
),
delivered_orders AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.order_date,
        o.subtotal AS revenue,
        p.gross_profit
    FROM orders o
    JOIN order_profit p
        ON o.order_id = p.order_id
    WHERE o.order_status = 'Delivered'
      AND o.order_date < @analysis_end
),
customer_history AS (
    SELECT
        customer_id,
        MIN(order_date) AS first_delivered_order_date,
        MAX(order_date) AS last_delivered_order_date,
        COUNT(*) AS historical_orders,
        SUM(revenue) AS historical_revenue
    FROM delivered_orders
    GROUP BY customer_id
),
customer_year AS (
    SELECT
        YEAR(order_date) AS order_year,
        customer_id,
        COUNT(*) AS delivered_orders,
        SUM(revenue) AS revenue,
        SUM(gross_profit) AS gross_profit
    FROM delivered_orders
    WHERE order_date >= @compare_start
    GROUP BY
        YEAR(order_date),
        customer_id
),
customer_rank AS (
    SELECT
        order_year,
        customer_id,
        delivered_orders,
        revenue,
        gross_profit,
        NTILE(5) OVER (
            PARTITION BY order_year
            ORDER BY revenue DESC, customer_id
        ) AS spend_rank
    FROM customer_year
),
customer_profile AS (
    SELECT
        h.customer_id,
        h.first_delivered_order_date,
        h.last_delivered_order_date,
        h.historical_orders,
        h.historical_revenue,
        COALESCE(r.delivered_orders, 0) AS orders_2025,
        COALESCE(r.revenue, 0) AS revenue_2025,
        COALESCE(r.gross_profit, 0) AS gross_profit_2025,
        r.spend_rank,
        DATEDIFF(@as_of_date, h.last_delivered_order_date) AS recency_days,
        CASE
            WHEN DATEDIFF(@as_of_date, h.last_delivered_order_date) <= 90
                THEN 'Active'
            WHEN DATEDIFF(@as_of_date, h.last_delivered_order_date) <= 180
                THEN 'At Risk'
            WHEN DATEDIFF(@as_of_date, h.last_delivered_order_date) <= 365
                THEN 'Hibernating'
            ELSE 'Over 365 Days'
        END AS lifecycle_status
    FROM customer_history h
    LEFT JOIN customer_rank r
        ON h.customer_id = r.customer_id
       AND r.order_year = YEAR(@analysis_start)
),
high_spend_warning AS (
    SELECT
        customer_id,
        first_delivered_order_date,
        last_delivered_order_date,
        historical_orders,
        historical_revenue,
        orders_2025,
        revenue_2025,
        gross_profit_2025,
        recency_days,
        CASE
            WHEN recency_days <= 120 THEN 'Early Warning'
            ELSE 'Deep Risk'
        END AS risk_stage,
        CASE
            WHEN gross_profit_2025 > 0 THEN '正毛利召回候选'
            ELSE '非正毛利核验'
        END AS action_group
    FROM customer_profile
    WHERE spend_rank = 1
      AND recency_days BETWEEN 91 AND 180
)

SELECT
    h.customer_id,
    h.action_group,
    h.risk_stage,
    h.recency_days,
    h.last_delivered_order_date,
    h.orders_2025,
    ROUND(h.revenue_2025, 2) AS revenue_2025,
    ROUND(h.gross_profit_2025, 2) AS gross_profit_2025,
    ROUND(100.0 * h.gross_profit_2025 / NULLIF(h.revenue_2025, 0), 2) AS gross_margin_2025_pct,
    h.first_delivered_order_date,
    h.historical_orders,
    ROUND(h.historical_revenue, 2) AS historical_revenue,
    c.loyalty_tier,
    c.customer_segment,
    c.acquisition_channel,
    c.preferred_device,
    c.preferred_payment_method,
    '2025 Revenue Top20%; Recency 91-180 days' AS selection_basis,
    CASE
        WHEN h.gross_profit_2025 > 0 THEN '小规模分层召回试点，保留对照并核验增量毛利'
        ELSE '先核验商品结构与折扣，不直接追加优惠'
    END AS proposed_action
FROM high_spend_warning h
LEFT JOIN customers c
    ON h.customer_id = c.customer_id
ORDER BY
    CASE WHEN h.action_group = '正毛利召回候选' THEN 1 ELSE 2 END,
    h.gross_profit_2025 DESC,
    h.revenue_2025 DESC,
    h.customer_id;
