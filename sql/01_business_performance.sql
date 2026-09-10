USE ecommerce_analysis;

/*
企业经营分析

主线：
1. 年度经营表现与同比变化
2. 月度趋势与季度增长贡献
3. 收入增长来自客户数、购买频次还是客单价
4. 地区收入、毛利与增长贡献
5. 订单状态结构与取消订单核验

统一口径：
1. 分析期：2025-01-01 至 2025-12-31。
   对比期：2024-01-01 至 2024-12-31，均为完整自然年。
2. 经营收入、毛利、客户数、订单数仅统计 Delivered 订单。
   按 order_date 归属期间；这是下单日期，不是实际签收日期。
3. Revenue = SUM(orders.subtotal) = SUM(order_items.item_revenue)。
   商品收入不含税费及运费，使用前先执行 0B 核对两表金额。
4. Gross Profit = SUM(order_items.profit)，仅为商品毛利。
   Gross Margin = Gross Profit / Revenue，不是企业净利润率。
5. Buyers = 当期有 Delivered 订单的去重客户数。
   Purchase Frequency = Delivered Orders / Buyers。
   AOV = Revenue / Delivered Orders。
6. 原代码的 SUM(final_amount) 保留为 delivered_order_amount。
   它包含税费及运费，与 Revenue 分开命名，不视为已验证实收。
7. 订单健康使用当期全部状态的订单作为分母。
   Returned Order Share 是退货状态订单占比，不是退货发生率。
   Processing 单独展示；当前状态不能还原历史时点状态。
8. 金额单位为 INR；带 _pct 的结果已经乘以 100。
   _change_pp 表示百分点变化；中间计算不四舍五入。

执行说明：MySQL 8.0+，可在 MySQL Workbench 中整份执行。
单独执行某一段前，先执行 USE 和下面的日期参数。
所有语句均为查询或会话参数设置，不修改原始数据。
*/

SET @compare_start = '2024-01-01';
SET @analysis_start = '2025-01-01';
SET @analysis_end = '2026-01-01';
SET @as_of_date = '2025-12-31';


/* ================================================================
0A. 原始表规模核对

分析目的：确认使用的是原项目的四张表；此处统计全表。
================================================================ */

SELECT 'customers' AS table_name, COUNT(*) AS row_count
FROM customers
UNION ALL
SELECT 'orders', COUNT(*)
FROM orders
UNION ALL
SELECT 'order_items', COUNT(*)
FROM order_items
UNION ALL
SELECT 'products', COUNT(*)
FROM products;


/* ================================================================
0B. 订单粒度与金额口径核对

分析目的：核对 2024—2025 年关联完整性与金额；异常计数应为 0。
================================================================ */

WITH item_order_totals AS (
    SELECT
        order_id,
        SUM(item_revenue) AS item_revenue,
        SUM(item_cost) AS item_cost,
        SUM(profit) AS gross_profit
    FROM order_items
    GROUP BY order_id
)

SELECT
    COUNT(*) AS total_orders,
    COUNT(DISTINCT o.order_id) AS distinct_orders,
    MIN(o.order_date) AS first_order_date,
    MAX(o.order_date) AS last_order_date,
    COUNT(DISTINCT DATE_FORMAT(o.order_date, '%Y-%m')) AS observed_months,
    SUM(CASE WHEN i.order_id IS NULL THEN 1 ELSE 0 END) AS missing_item_orders,
    SUM(
        CASE
            WHEN o.subtotal IS NULL
                OR ABS(o.subtotal - i.item_revenue) > 0.01
                THEN 1
            ELSE 0
        END
    ) AS subtotal_mismatch_orders,
    SUM(
        CASE
            WHEN ABS(i.gross_profit - (i.item_revenue - i.item_cost)) > 0.01
                THEN 1
            ELSE 0
        END
    ) AS profit_mismatch_orders,
    SUM(
        CASE
            WHEN o.final_amount IS NULL
                OR o.shipping_fee IS NULL
                OR o.tax_amount IS NULL
                OR ABS(o.final_amount - o.subtotal
                       - o.shipping_fee - o.tax_amount) > 0.01
                THEN 1
            ELSE 0
        END
    ) AS final_amount_mismatch_orders
FROM orders o
LEFT JOIN item_order_totals i
    ON o.order_id = i.order_id
WHERE o.order_date >= @compare_start
  AND o.order_date < @analysis_end;


/* ================================================================
1A. 年度整体经营情况

分析目的：在同一张结果中比较 2024 年与 2025 年经营规模和盈利。
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
        o.delivery_state,
        o.subtotal AS revenue,
        o.final_amount AS delivered_order_amount,
        p.gross_profit
    FROM orders o
    JOIN order_profit p
        ON o.order_id = p.order_id
    WHERE o.order_status = 'Delivered'
      AND o.order_date >= @compare_start
      AND o.order_date < @analysis_end
),

annual_metrics AS (
    SELECT
        YEAR(order_date) AS order_year,
        COUNT(*) AS delivered_orders,
        COUNT(DISTINCT customer_id) AS buyers,
        SUM(revenue) AS revenue,
        SUM(gross_profit) AS gross_profit,
        SUM(delivered_order_amount) AS delivered_order_amount
    FROM delivered_orders
    GROUP BY YEAR(order_date)
)

SELECT
    order_year,
    delivered_orders,
    buyers,
    ROUND(revenue, 2) AS revenue,
    ROUND(gross_profit, 2) AS gross_profit,
    ROUND(100.0 * gross_profit / NULLIF(revenue, 0), 2) AS gross_margin_pct,
    ROUND(delivered_orders / NULLIF(buyers, 0), 4) AS purchase_frequency,
    ROUND(revenue / NULLIF(delivered_orders, 0), 2) AS aov,
    ROUND(delivered_order_amount, 2) AS delivered_order_amount
FROM annual_metrics
ORDER BY order_year;


/* ================================================================
1B. 核心指标同比变化

分析目的：同比增长率与毛利率百分点变化分开呈现。
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
        o.delivery_state,
        o.subtotal AS revenue,
        o.final_amount AS delivered_order_amount,
        p.gross_profit
    FROM orders o
    JOIN order_profit p
        ON o.order_id = p.order_id
    WHERE o.order_status = 'Delivered'
      AND o.order_date >= @compare_start
      AND o.order_date < @analysis_end
),

annual_metrics AS (
    SELECT
        YEAR(order_date) AS order_year,
        COUNT(*) AS delivered_orders,
        COUNT(DISTINCT customer_id) AS buyers,
        SUM(revenue) AS revenue,
        SUM(gross_profit) AS gross_profit,
        SUM(delivered_order_amount) AS delivered_order_amount
    FROM delivered_orders
    GROUP BY YEAR(order_date)
),

metric_comparison AS (
    SELECT
        current_year.revenue AS revenue_2025,
        previous_year.revenue AS revenue_2024,
        current_year.gross_profit AS profit_2025,
        previous_year.gross_profit AS profit_2024,
        current_year.delivered_orders AS orders_2025,
        previous_year.delivered_orders AS orders_2024,
        current_year.buyers AS buyers_2025,
        previous_year.buyers AS buyers_2024
    FROM annual_metrics current_year
    JOIN annual_metrics previous_year
        ON previous_year.order_year = YEAR(@compare_start)
    WHERE current_year.order_year = YEAR(@analysis_start)
),

metric_rows AS (
    SELECT
        1 AS sort_order,
        'Revenue' AS metric_name,
        'INR' AS unit,
        revenue_2024 AS value_2024,
        revenue_2025 AS value_2025
    FROM metric_comparison
    UNION ALL
    SELECT 2, 'Gross Profit', 'INR', profit_2024, profit_2025
    FROM metric_comparison
    UNION ALL
    SELECT 3, 'Delivered Orders', 'orders', orders_2024, orders_2025
    FROM metric_comparison
    UNION ALL
    SELECT 4, 'Buyers', 'customers', buyers_2024, buyers_2025
    FROM metric_comparison
    UNION ALL
    SELECT 5, 'Purchase Frequency', 'orders/customer',
        orders_2024 / NULLIF(buyers_2024, 0),
        orders_2025 / NULLIF(buyers_2025, 0)
    FROM metric_comparison
    UNION ALL
    SELECT 6, 'AOV', 'INR/order',
        revenue_2024 / NULLIF(orders_2024, 0),
        revenue_2025 / NULLIF(orders_2025, 0)
    FROM metric_comparison
    UNION ALL
    SELECT 7, 'Gross Margin', '%',
        100.0 * profit_2024 / NULLIF(revenue_2024, 0),
        100.0 * profit_2025 / NULLIF(revenue_2025, 0)
    FROM metric_comparison
)

SELECT
    metric_name,
    unit,
    ROUND(value_2024, 4) AS value_2024,
    ROUND(value_2025, 4) AS value_2025,
    ROUND(value_2025 - value_2024, 4) AS absolute_change,
    CASE
        WHEN metric_name <> 'Gross Margin'
            THEN ROUND(100.0 * (value_2025 - value_2024)
                       / NULLIF(value_2024, 0), 2)
    END AS yoy_growth_pct,
    CASE
        WHEN metric_name = 'Gross Margin'
            THEN ROUND(value_2025 - value_2024, 2)
    END AS gross_margin_change_pp
FROM metric_rows
ORDER BY sort_order;


/* ================================================================
2A. 月度经营趋势与同月同比

分析目的：用同月同比识别增长节奏，同时检查毛利是否同步变化。
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
        o.delivery_state,
        o.subtotal AS revenue,
        o.final_amount AS delivered_order_amount,
        p.gross_profit
    FROM orders o
    JOIN order_profit p
        ON o.order_id = p.order_id
    WHERE o.order_status = 'Delivered'
      AND o.order_date >= @compare_start
      AND o.order_date < @analysis_end
),

monthly_metrics AS (
    SELECT
        YEAR(order_date) AS order_year,
        MONTH(order_date) AS order_month,
        COUNT(*) AS delivered_orders,
        SUM(revenue) AS revenue,
        SUM(gross_profit) AS gross_profit
    FROM delivered_orders
    GROUP BY YEAR(order_date), MONTH(order_date)
)

SELECT
    current_month.order_month,
    ROUND(previous_month.revenue, 2) AS revenue_2024,
    ROUND(current_month.revenue, 2) AS revenue_2025,
    ROUND(100.0 * (current_month.revenue - previous_month.revenue)
          / NULLIF(previous_month.revenue, 0), 2) AS revenue_yoy_pct,
    previous_month.delivered_orders AS orders_2024,
    current_month.delivered_orders AS orders_2025,
    ROUND(current_month.revenue
          / NULLIF(current_month.delivered_orders, 0), 2) AS aov_2025,
    ROUND(previous_month.gross_profit, 2) AS gross_profit_2024,
    ROUND(current_month.gross_profit, 2) AS gross_profit_2025,
    ROUND(100.0 * (current_month.gross_profit - previous_month.gross_profit)
          / NULLIF(previous_month.gross_profit, 0), 2) AS gross_profit_yoy_pct,
    ROUND(100.0 * previous_month.gross_profit
          / NULLIF(previous_month.revenue, 0), 2) AS gross_margin_2024_pct,
    ROUND(100.0 * current_month.gross_profit
          / NULLIF(current_month.revenue, 0), 2) AS gross_margin_2025_pct
FROM monthly_metrics current_month
LEFT JOIN monthly_metrics previous_month
    ON current_month.order_month = previous_month.order_month
   AND previous_month.order_year = YEAR(@compare_start)
WHERE current_month.order_year = YEAR(@analysis_start)
ORDER BY current_month.order_month;


/* ================================================================
2B. 各季度对全年收入增量的贡献

分析目的：区分当年收入占比与同比收入增量贡献，避免混用分母。
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
        o.delivery_state,
        o.subtotal AS revenue,
        o.final_amount AS delivered_order_amount,
        p.gross_profit
    FROM orders o
    JOIN order_profit p
        ON o.order_id = p.order_id
    WHERE o.order_status = 'Delivered'
      AND o.order_date >= @compare_start
      AND o.order_date < @analysis_end
),

quarterly_metrics AS (
    SELECT
        YEAR(order_date) AS order_year,
        QUARTER(order_date) AS order_quarter,
        SUM(revenue) AS revenue
    FROM delivered_orders
    GROUP BY YEAR(order_date), QUARTER(order_date)
),

quarter_comparison AS (
    SELECT
        current_quarter.order_quarter,
        previous_quarter.revenue AS revenue_2024,
        current_quarter.revenue AS revenue_2025,
        current_quarter.revenue - previous_quarter.revenue AS revenue_increase
    FROM quarterly_metrics current_quarter
    JOIN quarterly_metrics previous_quarter
        ON current_quarter.order_quarter = previous_quarter.order_quarter
       AND previous_quarter.order_year = YEAR(@compare_start)
    WHERE current_quarter.order_year = YEAR(@analysis_start)
)

SELECT
    order_quarter,
    ROUND(revenue_2024, 2) AS revenue_2024,
    ROUND(revenue_2025, 2) AS revenue_2025,
    ROUND(revenue_increase, 2) AS revenue_increase,
    ROUND(100.0 * revenue_increase / NULLIF(revenue_2024, 0), 2) AS revenue_yoy_pct,
    ROUND(100.0 * revenue_2024
          / NULLIF(SUM(revenue_2024) OVER (), 0), 2) AS revenue_share_2024_pct,
    ROUND(100.0 * revenue_2025
          / NULLIF(SUM(revenue_2025) OVER (), 0), 2) AS revenue_share_2025_pct,
    ROUND(100.0 * revenue_increase
          / NULLIF(SUM(revenue_increase) OVER (), 0), 2) AS growth_contribution_pct
FROM quarter_comparison
ORDER BY order_quarter;


/* ================================================================
3. 收入增长贡献拆解

分析目的：量化客户数、频次、AOV 对收入增量的贡献。

计算依据：Revenue = Buyers × Purchase Frequency × AOV。
采用 Shapley 分解，对三个因素的六种替换顺序取平均。
每个因素的贡献 = 该因素的增量 × 其余两个因素组合的加权平均。
下面 2、1、1、2 的权重除以 6，分别对应四种组合出现的次数。
三项贡献合计应等于 Revenue_2025 - Revenue_2024。
这是收入恒等式的算术分解，不用于认定获客或营销动作的因果效果。
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
        o.delivery_state,
        o.subtotal AS revenue,
        o.final_amount AS delivered_order_amount,
        p.gross_profit
    FROM orders o
    JOIN order_profit p
        ON o.order_id = p.order_id
    WHERE o.order_status = 'Delivered'
      AND o.order_date >= @compare_start
      AND o.order_date < @analysis_end
),

annual_metrics AS (
    SELECT
        YEAR(order_date) AS order_year,
        COUNT(*) AS delivered_orders,
        COUNT(DISTINCT customer_id) AS buyers,
        SUM(revenue) AS revenue,
        SUM(gross_profit) AS gross_profit,
        SUM(delivered_order_amount) AS delivered_order_amount
    FROM delivered_orders
    GROUP BY YEAR(order_date)
),

annual_factors AS (
    SELECT
        order_year,
        revenue,
        buyers,
        CAST(delivered_orders AS DECIMAL(30, 12))
            / NULLIF(buyers, 0) AS purchase_frequency,
        CAST(revenue AS DECIMAL(30, 12))
            / NULLIF(delivered_orders, 0) AS aov
    FROM annual_metrics
),

factor_comparison AS (
    SELECT
        previous_year.buyers AS buyers_2024,
        current_year.buyers AS buyers_2025,
        previous_year.purchase_frequency AS frequency_2024,
        current_year.purchase_frequency AS frequency_2025,
        previous_year.aov AS aov_2024,
        current_year.aov AS aov_2025,
        current_year.revenue - previous_year.revenue AS revenue_increase
    FROM annual_factors current_year
    JOIN annual_factors previous_year
        ON previous_year.order_year = YEAR(@compare_start)
    WHERE current_year.order_year = YEAR(@analysis_start)
),

factor_contributions AS (
    SELECT
        1 AS sort_order,
        'Buyers' AS growth_factor,
        buyers_2024 AS value_2024,
        buyers_2025 AS value_2025,
        (buyers_2025 - buyers_2024) * (
            2 * frequency_2024 * aov_2024
            + frequency_2025 * aov_2024
            + frequency_2024 * aov_2025
            + 2 * frequency_2025 * aov_2025
        ) / 6.0 AS revenue_contribution,
        revenue_increase
    FROM factor_comparison

    UNION ALL

    SELECT
        2,
        'Purchase Frequency',
        frequency_2024,
        frequency_2025,
        (frequency_2025 - frequency_2024) * (
            2 * buyers_2024 * aov_2024
            + buyers_2025 * aov_2024
            + buyers_2024 * aov_2025
            + 2 * buyers_2025 * aov_2025
        ) / 6.0,
        revenue_increase
    FROM factor_comparison

    UNION ALL

    SELECT
        3,
        'AOV',
        aov_2024,
        aov_2025,
        (aov_2025 - aov_2024) * (
            2 * buyers_2024 * frequency_2024
            + buyers_2025 * frequency_2024
            + buyers_2024 * frequency_2025
            + 2 * buyers_2025 * frequency_2025
        ) / 6.0,
        revenue_increase
    FROM factor_comparison
)

SELECT
    growth_factor,
    ROUND(value_2024, 4) AS value_2024,
    ROUND(value_2025, 4) AS value_2025,
    ROUND(100.0 * (value_2025 - value_2024)
          / NULLIF(value_2024, 0), 2) AS factor_yoy_pct,
    ROUND(revenue_contribution, 2) AS revenue_contribution,
    ROUND(100.0 * revenue_contribution
          / NULLIF(revenue_increase, 0), 2) AS growth_contribution_pct,
    ROUND(SUM(revenue_contribution) OVER () - revenue_increase, 2)
        AS decomposition_check_difference
FROM factor_contributions
ORDER BY sort_order;


/* ================================================================
4. 地区经营表现与增长贡献

分析目的：合并原代码的地区销售、订单量和 AOV，并补充毛利与同比。
地区使用订单的 delivery_state，避免用客户当前地址替代历史收货地区。
地区收入贡献可相加，客户数不能跨地区直接相加，因此此表不展示地区客户数。
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
        o.delivery_state,
        o.subtotal AS revenue,
        o.final_amount AS delivered_order_amount,
        p.gross_profit
    FROM orders o
    JOIN order_profit p
        ON o.order_id = p.order_id
    WHERE o.order_status = 'Delivered'
      AND o.order_date >= @compare_start
      AND o.order_date < @analysis_end
),

state_comparison AS (
    SELECT
        delivery_state,
        SUM(CASE WHEN YEAR(order_date) = YEAR(@compare_start)
                 THEN revenue ELSE 0 END) AS revenue_2024,
        SUM(CASE WHEN YEAR(order_date) = YEAR(@analysis_start)
                 THEN revenue ELSE 0 END) AS revenue_2025,
        SUM(CASE WHEN YEAR(order_date) = YEAR(@compare_start)
                 THEN gross_profit ELSE 0 END) AS gross_profit_2024,
        SUM(CASE WHEN YEAR(order_date) = YEAR(@analysis_start)
                 THEN gross_profit ELSE 0 END) AS gross_profit_2025,
        SUM(CASE WHEN YEAR(order_date) = YEAR(@analysis_start)
                 THEN 1 ELSE 0 END) AS delivered_orders_2025
    FROM delivered_orders
    GROUP BY delivery_state
)

SELECT
    delivery_state,
    delivered_orders_2025,
    ROUND(revenue_2024, 2) AS revenue_2024,
    ROUND(revenue_2025, 2) AS revenue_2025,
    ROUND(revenue_2025 - revenue_2024, 2) AS revenue_increase,
    ROUND(100.0 * (revenue_2025 - revenue_2024)
          / NULLIF(revenue_2024, 0), 2) AS revenue_yoy_pct,
    ROUND(revenue_2025 / NULLIF(delivered_orders_2025, 0), 2) AS aov_2025,
    ROUND(gross_profit_2024, 2) AS gross_profit_2024,
    ROUND(gross_profit_2025, 2) AS gross_profit_2025,
    ROUND(100.0 * gross_profit_2024
          / NULLIF(revenue_2024, 0), 2) AS gross_margin_2024_pct,
    ROUND(100.0 * gross_profit_2025
          / NULLIF(revenue_2025, 0), 2) AS gross_margin_2025_pct,
    ROUND(100.0 * revenue_2025
          / NULLIF(SUM(revenue_2025) OVER (), 0), 2) AS revenue_share_2025_pct,
    ROUND(100.0 * (revenue_2025 - revenue_2024)
          / NULLIF(SUM(revenue_2025 - revenue_2024) OVER (), 0), 2)
        AS growth_contribution_pct
FROM state_comparison
ORDER BY revenue_2025 DESC;


/* ================================================================
5A. 全年订单状态结构

分析目的：全部状态订单均进入分母，五类状态占比应合计为 100%。
Delivered 占比受年底 Processing 订单影响，不能直接等同于履约成功率。
Returned 仅解释为当前退货状态占比；Failed 不直接解释为支付失败。
================================================================ */

WITH status_counts AS (
    SELECT
        order_status,
        SUM(CASE WHEN YEAR(order_date) = YEAR(@compare_start)
                 THEN 1 ELSE 0 END) AS orders_2024,
        SUM(CASE WHEN YEAR(order_date) = YEAR(@analysis_start)
                 THEN 1 ELSE 0 END) AS orders_2025
    FROM orders
    WHERE order_date >= @compare_start
      AND order_date < @analysis_end
    GROUP BY order_status
),

status_rates AS (
    SELECT
        *,
        100.0 * orders_2024 / NULLIF(SUM(orders_2024) OVER (), 0) AS share_2024_pct,
        100.0 * orders_2025 / NULLIF(SUM(orders_2025) OVER (), 0) AS share_2025_pct
    FROM status_counts
)

SELECT
    order_status,
    orders_2024,
    orders_2025,
    ROUND(share_2024_pct, 2) AS order_share_2024_pct,
    ROUND(share_2025_pct, 2) AS order_share_2025_pct,
    ROUND(share_2025_pct - share_2024_pct, 2) AS share_change_pp
FROM status_rates
ORDER BY FIELD(order_status, 'Delivered', 'Cancelled', 'Returned', 'Failed', 'Processing');


/* ================================================================
5B. 季度订单健康与取消情况

分析目的：检查取消占比上升是否仅出现在年末。
排除 Processing 后的 Delivered 比例仅作状态结构敏感性检查，
不是独立验证的履约成功率；不同时间订单的最终状态仍可能继续变化。
================================================================ */

WITH quarter_status AS (
    SELECT
        YEAR(order_date) AS order_year,
        QUARTER(order_date) AS order_quarter,
        COUNT(*) AS total_orders,
        SUM(CASE WHEN order_status = 'Delivered' THEN 1 ELSE 0 END) AS delivered_orders,
        SUM(CASE WHEN order_status = 'Cancelled' THEN 1 ELSE 0 END) AS cancelled_orders,
        SUM(CASE WHEN order_status = 'Returned' THEN 1 ELSE 0 END) AS returned_orders,
        SUM(CASE WHEN order_status = 'Failed' THEN 1 ELSE 0 END) AS failed_orders,
        SUM(CASE WHEN order_status = 'Processing' THEN 1 ELSE 0 END) AS processing_orders
    FROM orders
    WHERE order_date >= @compare_start
      AND order_date < @analysis_end
    GROUP BY YEAR(order_date), QUARTER(order_date)
)

SELECT
    order_year,
    order_quarter,
    total_orders,
    delivered_orders,
    cancelled_orders,
    returned_orders,
    failed_orders,
    processing_orders,
    ROUND(100.0 * cancelled_orders / NULLIF(total_orders, 0), 2) AS cancelled_share_pct,
    ROUND(100.0 * delivered_orders / NULLIF(total_orders, 0), 2) AS delivered_share_pct,
    ROUND(100.0 * processing_orders / NULLIF(total_orders, 0), 2) AS processing_share_pct,
    ROUND(100.0 * delivered_orders
          / NULLIF(total_orders - processing_orders, 0), 2)
        AS delivered_share_excluding_processing_pct
FROM quarter_status
ORDER BY order_year, order_quarter;


/* ================================================================
5C. 年底 Processing 订单的下单时间

分析目的：确认在途状态的观察时间，避免把年末新订单直接认定为积压或失败。
order_age_days 仅表示下单至观察截止日的天数，不是实际处理耗时。
================================================================ */

SELECT
    COUNT(*) AS processing_orders,
    MIN(order_date) AS earliest_order_date,
    MAX(order_date) AS latest_order_date,
    MIN(DATEDIFF(@as_of_date, order_date)) AS min_order_age_days,
    MAX(DATEDIFF(@as_of_date, order_date)) AS max_order_age_days
FROM orders
WHERE order_date >= @analysis_start
  AND order_date < @analysis_end
  AND order_status = 'Processing';


/* ================================================================
5D. 地区取消订单核验优先级

分析目的：同时展示取消量、取消占比和占比变化。
按取消量排序是核验工作量排序，不表示该地区取消风险最高。
================================================================ */

WITH state_status AS (
    SELECT
        delivery_state,
        SUM(CASE WHEN YEAR(order_date) = YEAR(@compare_start)
                 THEN 1 ELSE 0 END) AS total_orders_2024,
        SUM(CASE WHEN YEAR(order_date) = YEAR(@analysis_start)
                 THEN 1 ELSE 0 END) AS total_orders_2025,
        SUM(CASE WHEN YEAR(order_date) = YEAR(@compare_start)
                  AND order_status = 'Cancelled' THEN 1 ELSE 0 END) AS cancelled_orders_2024,
        SUM(CASE WHEN YEAR(order_date) = YEAR(@analysis_start)
                  AND order_status = 'Cancelled' THEN 1 ELSE 0 END) AS cancelled_orders_2025
    FROM orders
    WHERE order_date >= @compare_start
      AND order_date < @analysis_end
    GROUP BY delivery_state
)

SELECT
    delivery_state,
    total_orders_2024,
    total_orders_2025,
    cancelled_orders_2024,
    cancelled_orders_2025,
    ROUND(100.0 * cancelled_orders_2024
          / NULLIF(total_orders_2024, 0), 2) AS cancelled_share_2024_pct,
    ROUND(100.0 * cancelled_orders_2025
          / NULLIF(total_orders_2025, 0), 2) AS cancelled_share_2025_pct,
    ROUND(100.0 * cancelled_orders_2025 / NULLIF(total_orders_2025, 0)
          - 100.0 * cancelled_orders_2024 / NULLIF(total_orders_2024, 0), 2)
        AS cancelled_share_change_pp,
    ROUND(100.0 * cancelled_orders_2025
          / NULLIF(SUM(cancelled_orders_2025) OVER (), 0), 2)
        AS share_of_cancelled_orders_2025_pct
FROM state_status
ORDER BY cancelled_orders_2025 DESC, delivery_state;
