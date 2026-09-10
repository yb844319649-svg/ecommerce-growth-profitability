# 四张原始表：字段与数据模型

本项目从[来源数据集](data_source.md)中仅选取customers、orders、order_items、products四张表；以下仅描述本项目选表，不代表完整原数据集的全部表或总规模。本地检查基于完整原始CSV，未过滤、去重或填补。公开仓库不附原始CSV，以下记录数与字段描述为原附件数据的说明。字段类型为配套MySQL建表脚本的建议类型。

| 表 | 记录数 | 字段数 | 粒度 | 主键 |
|---|---:|---:|---|---|
| customers | 25,000 | 18 | 客户快照 | customer_id |
| orders | 100,000 | 16 | 订单当前记录 | order_id |
| order_items | 254,331 | 9 | 订单商品明细行 | order_item_id |
| products | 550 | 14 | 商品快照 | product_id |

关联结构：customers 1 → N orders 1 → N order_items N ← 1 products。

订单金额不可在关联明细后直接求和，否则会随明细行数重复。客户分析先将明细毛利汇总至订单，再关联订单与客户；商品分析保留明细粒度。

## customers

| 原始字段 | 建议类型 | 空值数 | 字段说明及使用方式 |
|---|---|---:|---|
| customer_id | VARCHAR(32) | 0 | 客户唯一标识；客户表主键，关联orders.customer_id。 |
| customer_signup_date | DATE | 0 | 客户注册日期；用于注册背景，不替代历史首购日期。 |
| gender | VARCHAR(255) | 0 | 性别分类。 |
| age | INT | 250 | 年龄；保留缺失，不自行补值。 |
| age_group | VARCHAR(255) | 0 | 数据集提供的年龄分组标签。 |
| state | VARCHAR(255) | 0 | 客户所属邦/州；与订单收货地区是不同字段。 |
| city | VARCHAR(255) | 0 | 客户所属城市。 |
| pincode_prefix | VARCHAR(12) | 0 | 邮编前缀；作为文本编码使用。 |
| customer_segment | VARCHAR(255) | 0 | 数据集提供的客户分层标签；不替代本项目重新计算的消费及盈利分组。 |
| preferred_device | VARCHAR(255) | 125 | 偏好设备；保留缺失。 |
| preferred_payment_method | VARCHAR(255) | 0 | 偏好支付方式；不是支付流水或实收证据。 |
| acquisition_channel | VARCHAR(255) | 0 | 客户获客渠道标签；不能单独据此计算投放ROI。 |
| total_orders | INT | 0 | 客户表预汇总订单数，未限定本项目年度和Delivered口径；本项目从orders重算。 |
| total_spend | DECIMAL(18,2) | 0 | 客户表预汇总消费金额，未限定本项目年度和Delivered口径；本项目从交易重算。 |
| last_order_date | DATE | 2,300 | 预汇总最近下单日期；未购时长使用Delivered历史重新计算。 |
| average_order_value | DECIMAL(18,2) | 0 | 预汇总平均订单金额；本项目按Revenue / Delivered Orders重算。 |
| customer_status | VARCHAR(255) | 0 | 数据集提供的客户状态快照；不替代本项目未购时长分组。 |
| loyalty_tier | VARCHAR(255) | 0 | 会员/忠诚度层级标签；只作属性说明。 |

## orders

| 原始字段 | 建议类型 | 空值数 | 字段说明及使用方式 |
|---|---|---:|---|
| order_id | VARCHAR(32) | 0 | 订单唯一标识；订单表主键。 |
| customer_id | VARCHAR(32) | 0 | 下单客户标识，关联customers。 |
| order_date | DATE | 0 | 下单日期；本项目收入、同比、首购和未购天数的时间归属字段。 |
| order_time | TIME | 0 | 下单时刻。 |
| order_status | VARCHAR(255) | 0 | 订单当前状态；Delivered用于经营口径，状态结构统计全部订单。 |
| shipping_method | VARCHAR(255) | 0 | 订单配送方式；四表项目没有实际签收时效。 |
| delivery_city | VARCHAR(255) | 0 | 订单收货城市。 |
| delivery_state | VARCHAR(255) | 0 | 订单收货邦/州；地区经营及取消治理使用此字段。 |
| coupon_code | VARCHAR(255) | 33,711 | 优惠码；空白保留为缺失，不编造优惠活动。 |
| discount_percentage | DECIMAL(10,6) | 0 | 订单层折扣百分数，10表示10%；商品分析优先使用明细层折扣和实际金额。 |
| marketing_channel | VARCHAR(255) | 0 | 订单营销渠道标签；与客户获客渠道不是同一粒度。 |
| subtotal | DECIMAL(18,2) | 0 | 订单商品金额，INR；等于对应明细item_revenue之和，Delivered订单的该字段汇总为Revenue。 |
| shipping_fee | DECIMAL(18,2) | 0 | 订单运费，INR；不计入本项目Revenue。 |
| tax_amount | DECIMAL(18,2) | 0 | 订单税费，INR；不计入Revenue。 |
| final_amount | DECIMAL(18,2) | 0 | 订单含税费和运费金额，INR；等于subtotal + shipping_fee + tax_amount，不视为已验证实收。 |
| campaign_id | VARCHAR(32) | 82,821 | 活动标识；当前项目不包含marketing_campaigns，保留字段但不做活动归因。 |

## order_items

| 原始字段 | 建议类型 | 空值数 | 字段说明及使用方式 |
|---|---|---:|---|
| order_item_id | VARCHAR(32) | 0 | 订单商品明细行唯一标识；主键。 |
| order_id | VARCHAR(32) | 0 | 所属订单，关联orders。 |
| product_id | VARCHAR(32) | 0 | 商品标识，关联products；同一订单同一商品可能多行，不能以order_id + product_id去重。 |
| quantity | INT | 0 | 该明细购买数量。 |
| unit_price | DECIMAL(18,2) | 0 | 该明细交易单价，INR；与quantity相乘形成折前金额基准。 |
| discount_percentage | DECIMAL(10,6) | 0 | 明细折扣百分数，10表示10%。 |
| item_revenue | DECIMAL(18,2) | 0 | 该行折后商品收入，INR；等于quantity × unit_price扣减该行折让后的金额。 |
| item_cost | DECIMAL(18,2) | 0 | 该行商品成本总额，INR；已覆盖该行数量，不能再次乘quantity。 |
| profit | DECIMAL(18,2) | 0 | 该行商品毛利，INR；等于item_revenue − item_cost，未扣经营费用。 |

## products

| 原始字段 | 建议类型 | 空值数 | 字段说明及使用方式 |
|---|---|---:|---|
| product_id | VARCHAR(32) | 0 | 商品唯一标识；商品表主键。 |
| product_name | VARCHAR(255) | 0 | 商品名称，保留原始英文。 |
| category | VARCHAR(255) | 0 | 商品品类，保留Electronics、Fashion等原字段值。 |
| subcategory | VARCHAR(255) | 0 | 商品子品类。 |
| brand | VARCHAR(255) | 0 | 品牌。 |
| price | DECIMAL(18,2) | 0 | 商品表价格快照，INR；历史折前金额使用order_items.unit_price。 |
| cost_price | DECIMAL(18,2) | 0 | 商品表单位成本快照，INR；历史毛利使用order_items.item_cost，不用快照回填。 |
| discount_range | VARCHAR(255) | 0 | 数据集提供的折扣区间标签；实际成交折让按明细金额核算。 |
| rating_average | DECIMAL(10,6) | 4 | 商品平均评分快照；不是特定年度或特定订单评价。 |
| rating_count | INT | 0 | 累计评分数量快照。 |
| stock_quantity | INT | 0 | 库存数量快照；无明确快照日期和历史库存流，覆盖天数仅用于情景测算。 |
| product_launch_date | DATE | 0 | 商品上市日期字段；部分早期订单与其先后关系异常，不用于新品生命周期结论。 |
| product_type | VARCHAR(255) | 0 | 商品类型标签。 |
| return_rate_baseline | DECIMAL(10,6) | 0 | 数据集提供的退货率基准字段，原始比例值；不作为本项目实测退货率。 |

## 使用前已核对的关系

- 四表主键均唯一：通过。
- 订单客户外键完整：通过。
- 明细订单与商品外键完整：通过。
- 逐行毛利恒等式成立：通过。
- 订单金额与明细收入一致：通过。
- 订单日期覆盖2023年至2025年：通过。
- order_id + product_id存在2,019条额外重复组合记录；它不是明细主键，全部保留。
- 日期范围：2023-01-01至2025-12-31；2023年保留用于历史首购和最近成交计算。
