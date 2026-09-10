USE ecommerce_analysis;

/*
商品经营分析  2025年对比2024年
仅统计当前 Delivered 订单，按 order_date 归属年度。
Revenue = SUM(item_revenue)，Gross Profit = SUM(profit)。金额单位 INR。
毛利仅扣商品成本，不代表企业净利润；不以产品当前成本替代交易成本。
各节均可独立运行；均为只读查询，不修改源表。
主线：整体经营 → 品类结构 → 头部与亏损SKU → 折扣核验 → 库存情景。
*/

/* ================================================================
1 商品整体经营情况
年度商品毛利率为汇总毛利除以汇总收入，不平均各明细毛利率。
================================================================ */

WITH delivered_items AS (
    SELECT
        YEAR(o.order_date) AS order_year,
        o.order_date,
        oi.order_item_id,
        oi.order_id,
        oi.product_id,
        p.product_name,
        p.category,
        oi.quantity,
        oi.unit_price,
        oi.discount_percentage,
        oi.item_revenue,
        oi.item_cost,
        oi.profit,
        oi.quantity * oi.unit_price AS original_revenue
    FROM orders o
    JOIN order_items oi
        ON o.order_id = oi.order_id
    JOIN products p
        ON oi.product_id = p.product_id
    WHERE o.order_status = 'Delivered'
        AND o.order_date >= '2024-01-01'
        AND o.order_date < '2026-01-01'
)
SELECT
    order_year,
    COUNT(DISTINCT product_id) AS sold_skus,
    SUM(quantity) AS quantity,
    SUM(item_revenue) AS revenue,
    SUM(item_cost) AS cost,
    SUM(profit) AS gross_profit,
    100.0 * SUM(profit) / NULLIF(SUM(item_revenue), 0) AS gross_margin_pct
FROM delivered_items
GROUP BY order_year
ORDER BY order_year;

/* ================================================================
2 品类收入与毛利结构
保留全部品类；年度净毛利贡献可为负。增量贡献以全企业对应年度增量为分母。
================================================================ */

WITH delivered_items AS (
    SELECT
        YEAR(o.order_date) AS order_year,
        o.order_date,
        oi.order_item_id,
        oi.order_id,
        oi.product_id,
        p.product_name,
        p.category,
        oi.quantity,
        oi.unit_price,
        oi.discount_percentage,
        oi.item_revenue,
        oi.item_cost,
        oi.profit,
        oi.quantity * oi.unit_price AS original_revenue
    FROM orders o
    JOIN order_items oi
        ON o.order_id = oi.order_id
    JOIN products p
        ON oi.product_id = p.product_id
    WHERE o.order_status = 'Delivered'
        AND o.order_date >= '2024-01-01'
        AND o.order_date < '2026-01-01'
),
category_metrics AS (
    SELECT
        order_year,
        category,
        COUNT(DISTINCT product_id) AS sold_skus,
        SUM(quantity) AS quantity,
        SUM(item_revenue) AS revenue,
        SUM(profit) AS gross_profit
    FROM delivered_items
    GROUP BY order_year, category
)
SELECT
    *,
    100.0 * gross_profit / NULLIF(revenue, 0) AS gross_margin_pct,
    100.0 * revenue / NULLIF(SUM(revenue) OVER (PARTITION BY order_year), 0) AS revenue_share_pct,
    100.0 * gross_profit / NULLIF(SUM(gross_profit) OVER (PARTITION BY order_year), 0) AS gross_profit_share_pct,
    revenue - LAG(revenue) OVER (PARTITION BY category ORDER BY order_year) AS revenue_change,
    gross_profit - LAG(gross_profit) OVER (PARTITION BY category ORDER BY order_year) AS gross_profit_change
FROM category_metrics
ORDER BY order_year, revenue DESC;

/* ================================================================
3A 全量SKU年度指标
用product_id打破金额并列；2024和2025不混合累计。
================================================================ */

WITH delivered_items AS (
    SELECT
        YEAR(o.order_date) AS order_year,
        o.order_date,
        oi.order_item_id,
        oi.order_id,
        oi.product_id,
        p.product_name,
        p.category,
        oi.quantity,
        oi.unit_price,
        oi.discount_percentage,
        oi.item_revenue,
        oi.item_cost,
        oi.profit,
        oi.quantity * oi.unit_price AS original_revenue
    FROM orders o
    JOIN order_items oi
        ON o.order_id = oi.order_id
    JOIN products p
        ON oi.product_id = p.product_id
    WHERE o.order_status = 'Delivered'
        AND o.order_date >= '2024-01-01'
        AND o.order_date < '2026-01-01'
),
sku_metrics AS (
    SELECT
        order_year,
        product_id,
        product_name,
        category,
        SUM(quantity) AS quantity,
        SUM(item_revenue) AS revenue,
        SUM(item_cost) AS cost,
        SUM(profit) AS gross_profit,
        SUM(original_revenue) AS original_revenue,
        SUM(CASE WHEN profit < 0 THEN -profit ELSE 0 END) AS negative_line_loss,
        COUNT(*) AS item_lines
    FROM delivered_items
    GROUP BY order_year, product_id, product_name, category
)
SELECT
    *,
    100.0 * gross_profit / NULLIF(revenue, 0) AS gross_margin_pct
FROM sku_metrics

ORDER BY order_year, revenue DESC, product_id;

/* ================================================================
3B 2025年收入前十SKU
用product_id打破金额并列；2024和2025不混合累计。
================================================================ */

WITH delivered_items AS (
    SELECT
        YEAR(o.order_date) AS order_year,
        o.order_date,
        oi.order_item_id,
        oi.order_id,
        oi.product_id,
        p.product_name,
        p.category,
        oi.quantity,
        oi.unit_price,
        oi.discount_percentage,
        oi.item_revenue,
        oi.item_cost,
        oi.profit,
        oi.quantity * oi.unit_price AS original_revenue
    FROM orders o
    JOIN order_items oi
        ON o.order_id = oi.order_id
    JOIN products p
        ON oi.product_id = p.product_id
    WHERE o.order_status = 'Delivered'
        AND o.order_date >= '2024-01-01'
        AND o.order_date < '2026-01-01'
),
sku_metrics AS (
    SELECT
        order_year,
        product_id,
        product_name,
        category,
        SUM(quantity) AS quantity,
        SUM(item_revenue) AS revenue,
        SUM(item_cost) AS cost,
        SUM(profit) AS gross_profit,
        SUM(original_revenue) AS original_revenue,
        SUM(CASE WHEN profit < 0 THEN -profit ELSE 0 END) AS negative_line_loss,
        COUNT(*) AS item_lines
    FROM delivered_items
    GROUP BY order_year, product_id, product_name, category
)
SELECT
    *,
    100.0 * gross_profit / NULLIF(revenue, 0) AS gross_margin_pct
FROM sku_metrics
WHERE order_year = 2025
ORDER BY revenue DESC, product_id LIMIT 10;

/* ================================================================
3C 2025年商品毛利前十SKU
用product_id打破金额并列；2024和2025不混合累计。
================================================================ */

WITH delivered_items AS (
    SELECT
        YEAR(o.order_date) AS order_year,
        o.order_date,
        oi.order_item_id,
        oi.order_id,
        oi.product_id,
        p.product_name,
        p.category,
        oi.quantity,
        oi.unit_price,
        oi.discount_percentage,
        oi.item_revenue,
        oi.item_cost,
        oi.profit,
        oi.quantity * oi.unit_price AS original_revenue
    FROM orders o
    JOIN order_items oi
        ON o.order_id = oi.order_id
    JOIN products p
        ON oi.product_id = p.product_id
    WHERE o.order_status = 'Delivered'
        AND o.order_date >= '2024-01-01'
        AND o.order_date < '2026-01-01'
),
sku_metrics AS (
    SELECT
        order_year,
        product_id,
        product_name,
        category,
        SUM(quantity) AS quantity,
        SUM(item_revenue) AS revenue,
        SUM(item_cost) AS cost,
        SUM(profit) AS gross_profit,
        SUM(original_revenue) AS original_revenue,
        SUM(CASE WHEN profit < 0 THEN -profit ELSE 0 END) AS negative_line_loss,
        COUNT(*) AS item_lines
    FROM delivered_items
    GROUP BY order_year, product_id, product_name, category
)
SELECT
    *,
    100.0 * gross_profit / NULLIF(revenue, 0) AS gross_margin_pct
FROM sku_metrics
WHERE order_year = 2025
ORDER BY gross_profit DESC, product_id LIMIT 10;

/* ================================================================
4A 2025年全量亏损SKU核验名单
年度净毛利<0才进入名单；按实际净亏损降序排核验顺序。不是仅筛存在亏损明细的SKU。
================================================================ */

WITH delivered_items AS (
    SELECT
        YEAR(o.order_date) AS order_year,
        o.order_date,
        oi.order_item_id,
        oi.order_id,
        oi.product_id,
        p.product_name,
        p.category,
        oi.quantity,
        oi.unit_price,
        oi.discount_percentage,
        oi.item_revenue,
        oi.item_cost,
        oi.profit,
        oi.quantity * oi.unit_price AS original_revenue
    FROM orders o
    JOIN order_items oi
        ON o.order_id = oi.order_id
    JOIN products p
        ON oi.product_id = p.product_id
    WHERE o.order_status = 'Delivered'
        AND o.order_date >= '2024-01-01'
        AND o.order_date < '2026-01-01'
),
sku_metrics AS (
    SELECT
        order_year,
        product_id,
        product_name,
        category,
        SUM(quantity) AS quantity,
        SUM(item_revenue) AS revenue,
        SUM(item_cost) AS cost,
        SUM(profit) AS gross_profit,
        SUM(original_revenue) AS original_revenue,
        SUM(CASE WHEN profit < 0 THEN -profit ELSE 0 END) AS negative_line_loss,
        COUNT(*) AS item_lines
    FROM delivered_items
    GROUP BY order_year, product_id, product_name, category
)
SELECT
    a.product_id,
    a.product_name,
    a.category,
    a.quantity,
    a.revenue,
    a.cost,
    a.gross_profit,
    100.0 * a.gross_profit / NULLIF(a.revenue, 0) AS gross_margin_pct,
    -a.gross_profit AS loss_amount,
    100.0 * (-a.gross_profit) / NULLIF(SUM(-a.gross_profit) OVER (), 0) AS loss_share_pct,
    100.0 * SUM(-a.gross_profit) OVER (
        ORDER BY a.gross_profit, a.product_id ROWS UNBOUNDED PRECEDING
    ) / NULLIF(SUM(-a.gross_profit) OVER (), 0) AS cumulative_loss_share_pct,
    b.gross_profit AS gross_profit_2024,
    CASE
        WHEN b.product_id IS NULL THEN '2024无成交记录'
        WHEN b.gross_profit < 0 THEN '连续两年净亏损'
        ELSE '2025转为净亏损'
    END AS loss_status,
    a.original_revenue,
    a.original_revenue - a.cost AS pre_discount_gross_profit,
    100.0 * (1 - a.revenue / NULLIF(a.original_revenue, 0)) AS weighted_discount_pct,
    100.0 * (1 - a.cost / NULLIF(a.original_revenue, 0)) AS goods_cost_break_even_discount_pct,
    a.negative_line_loss
FROM sku_metrics a
LEFT JOIN sku_metrics b
    ON a.product_id = b.product_id
    AND b.order_year = 2024
WHERE a.order_year = 2025
    AND a.gross_profit < 0
ORDER BY a.gross_profit, a.product_id;

/* ================================================================
4B 亏损SKU的年度与品类分布
损失金额是净亏损SKU毛利绝对值之和；不与负毛利明细金额相加。
================================================================ */

WITH delivered_items AS (
    SELECT
        YEAR(o.order_date) AS order_year,
        o.order_date,
        oi.order_item_id,
        oi.order_id,
        oi.product_id,
        p.product_name,
        p.category,
        oi.quantity,
        oi.unit_price,
        oi.discount_percentage,
        oi.item_revenue,
        oi.item_cost,
        oi.profit,
        oi.quantity * oi.unit_price AS original_revenue
    FROM orders o
    JOIN order_items oi
        ON o.order_id = oi.order_id
    JOIN products p
        ON oi.product_id = p.product_id
    WHERE o.order_status = 'Delivered'
        AND o.order_date >= '2024-01-01'
        AND o.order_date < '2026-01-01'
),
sku_metrics AS (
    SELECT
        order_year,
        product_id,
        product_name,
        category,
        SUM(quantity) AS quantity,
        SUM(item_revenue) AS revenue,
        SUM(item_cost) AS cost,
        SUM(profit) AS gross_profit,
        SUM(original_revenue) AS original_revenue,
        SUM(CASE WHEN profit < 0 THEN -profit ELSE 0 END) AS negative_line_loss,
        COUNT(*) AS item_lines
    FROM delivered_items
    GROUP BY order_year, product_id, product_name, category
)
SELECT
    order_year,
    category,
    COUNT(*) AS sold_skus,
    SUM(CASE WHEN gross_profit < 0 THEN 1 ELSE 0 END) AS loss_skus,
    SUM(CASE WHEN gross_profit < 0 THEN -gross_profit ELSE 0 END) AS net_sku_loss,
    SUM(negative_line_loss) AS negative_line_loss
FROM sku_metrics
GROUP BY order_year, category
ORDER BY order_year, net_sku_loss DESC;

/* ================================================================
5A Electronics折扣与毛利的金额核对
原价收入是保持实际数量和单价的计算基准，不是取消折扣后的销量或收入预测。
================================================================ */

WITH delivered_items AS (
    SELECT
        YEAR(o.order_date) AS order_year,
        o.order_date,
        oi.order_item_id,
        oi.order_id,
        oi.product_id,
        p.product_name,
        p.category,
        oi.quantity,
        oi.unit_price,
        oi.discount_percentage,
        oi.item_revenue,
        oi.item_cost,
        oi.profit,
        oi.quantity * oi.unit_price AS original_revenue
    FROM orders o
    JOIN order_items oi
        ON o.order_id = oi.order_id
    JOIN products p
        ON oi.product_id = p.product_id
    WHERE o.order_status = 'Delivered'
        AND o.order_date >= '2024-01-01'
        AND o.order_date < '2026-01-01'
)
SELECT
    order_year,
    SUM(original_revenue) AS original_revenue,
    SUM(original_revenue - item_revenue) AS discount_amount,
    SUM(item_revenue) AS revenue,
    SUM(item_cost) AS cost,
    SUM(original_revenue - item_cost) AS pre_discount_gross_profit,
    SUM(profit) AS gross_profit,
    100.0 * SUM(original_revenue - item_revenue) / NULLIF(SUM(original_revenue), 0) AS weighted_discount_pct,
    100.0 * SUM(original_revenue - item_cost) / NULLIF(SUM(original_revenue), 0) AS goods_cost_break_even_discount_pct
FROM delivered_items
WHERE category = 'Electronics'
GROUP BY order_year
ORDER BY order_year;

/* ================================================================
5B Electronics净亏损SKU的折扣核验
仅覆盖商品成本的盈亏平衡折扣；年度加权值不能直接用作每笔新交易折扣上限。超出百分点与亏损金额存在代数关系，不作为独立风险评分。
================================================================ */

WITH delivered_items AS (
    SELECT
        YEAR(o.order_date) AS order_year,
        o.order_date,
        oi.order_item_id,
        oi.order_id,
        oi.product_id,
        p.product_name,
        p.category,
        oi.quantity,
        oi.unit_price,
        oi.discount_percentage,
        oi.item_revenue,
        oi.item_cost,
        oi.profit,
        oi.quantity * oi.unit_price AS original_revenue
    FROM orders o
    JOIN order_items oi
        ON o.order_id = oi.order_id
    JOIN products p
        ON oi.product_id = p.product_id
    WHERE o.order_status = 'Delivered'
        AND o.order_date >= '2024-01-01'
        AND o.order_date < '2026-01-01'
),
sku_metrics AS (
    SELECT
        order_year,
        product_id,
        product_name,
        category,
        SUM(quantity) AS quantity,
        SUM(item_revenue) AS revenue,
        SUM(item_cost) AS cost,
        SUM(profit) AS gross_profit,
        SUM(original_revenue) AS original_revenue,
        SUM(CASE WHEN profit < 0 THEN -profit ELSE 0 END) AS negative_line_loss,
        COUNT(*) AS item_lines
    FROM delivered_items
    GROUP BY order_year, product_id, product_name, category
)
SELECT
    product_id,
    product_name,
    revenue,
    cost,
    gross_profit,
    original_revenue,
    original_revenue - cost AS pre_discount_gross_profit,
    original_revenue - revenue AS discount_amount,
    100.0 * (1 - revenue / NULLIF(original_revenue, 0)) AS weighted_discount_pct,
    100.0 * (1 - cost / NULLIF(original_revenue, 0)) AS goods_cost_break_even_discount_pct,
    100.0 * (cost - revenue) / NULLIF(original_revenue, 0) AS excess_discount_pp,
    CASE WHEN original_revenue <= cost
        THEN '先核对基础单价与成本'
        ELSE '成交折让超过商品成本空间'
    END AS accounting_check
FROM sku_metrics
WHERE order_year = 2025
    AND category = 'Electronics'
    AND gross_profit < 0
ORDER BY gross_profit, product_id;

/* ================================================================
5C Electronics负毛利明细核验
逐笔核对实际成交价与历史商品成本；候选优惠须另考虑其他费用和实际需求变化。
================================================================ */

WITH delivered_items AS (
    SELECT
        YEAR(o.order_date) AS order_year,
        o.order_date,
        oi.order_item_id,
        oi.order_id,
        oi.product_id,
        p.product_name,
        p.category,
        oi.quantity,
        oi.unit_price,
        oi.discount_percentage,
        oi.item_revenue,
        oi.item_cost,
        oi.profit,
        oi.quantity * oi.unit_price AS original_revenue
    FROM orders o
    JOIN order_items oi
        ON o.order_id = oi.order_id
    JOIN products p
        ON oi.product_id = p.product_id
    WHERE o.order_status = 'Delivered'
        AND o.order_date >= '2024-01-01'
        AND o.order_date < '2026-01-01'
)
SELECT
    order_item_id,
    order_id,
    product_id,
    quantity,
    unit_price,
    discount_percentage,
    item_revenue,
    item_cost,
    profit,
    100.0 * (1 - item_cost / NULLIF(original_revenue, 0)) AS goods_cost_break_even_discount_pct
FROM delivered_items
WHERE order_year = 2025
    AND category = 'Electronics'
    AND profit < 0
ORDER BY profit, order_item_id;

/* ================================================================
6 近30日与近90日库存覆盖情景
products库存是无日期快照。以下仅为快照库存除以历史日均销量的情景测算，不能认定历史积压或直接生成采购量。窗口包含截止日；无销量覆盖天数为NULL。
================================================================ */

WITH cutoff AS (
    SELECT MAX(order_date) AS as_of_date
    FROM orders
    WHERE order_status = 'Delivered'
        AND order_date < '2026-01-01'
),
recent_sales AS (
    SELECT
        oi.product_id,
        SUM(CASE WHEN o.order_date >= DATE_SUB(c.as_of_date, INTERVAL 29 DAY)
            THEN oi.quantity ELSE 0 END) AS quantity_30d,
        SUM(oi.quantity) AS quantity_90d
    FROM orders o
    JOIN order_items oi
        ON o.order_id = oi.order_id
    CROSS JOIN cutoff c
    WHERE o.order_status = 'Delivered'
        AND o.order_date >= DATE_SUB(c.as_of_date, INTERVAL 89 DAY)
        AND o.order_date <= c.as_of_date
    GROUP BY oi.product_id
)
SELECT
    p.product_id,
    p.product_name,
    p.category,
    p.stock_quantity AS snapshot_stock,
    c.as_of_date AS sales_cutoff,
    COALESCE(r.quantity_30d, 0) AS quantity_30d,
    COALESCE(r.quantity_90d, 0) AS quantity_90d,
    COALESCE(r.quantity_30d, 0) / 30.0 AS daily_quantity_30d,
    COALESCE(r.quantity_90d, 0) / 90.0 AS daily_quantity_90d,
    p.stock_quantity * 30.0 / NULLIF(r.quantity_30d, 0) AS coverage_30d,
    p.stock_quantity * 90.0 / NULLIF(r.quantity_90d, 0) AS coverage_90d
FROM products p
CROSS JOIN cutoff c
LEFT JOIN recent_sales r
    ON p.product_id = r.product_id
ORDER BY p.product_id;
