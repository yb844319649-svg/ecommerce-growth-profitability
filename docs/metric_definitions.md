# 指标口径与看板数据来源

## 统一经营口径

| 指标 | 口径 |
|---|---|
| 分析期 / 对比期 | 2025-01-01至2025-12-31 / 2024-01-01至2024-12-31，按order_date归属。 |
| Revenue | 当前Delivered订单对应SUM(order_items.item_revenue)，与SUM(orders.subtotal)核对一致，不含税和运费。 |
| Gross Profit | 当前Delivered明细SUM(profit)，仅扣商品成本。 |
| Gross Margin | SUM(profit) / SUM(item_revenue)，不平均明细毛利率。 |
| Buyers | 同期间Delivered订单去重customer_id。 |
| Purchase Frequency | 同期间Delivered Orders / Buyers。 |
| AOV | 同期间Revenue / Delivered Orders。 |
| 收入增长拆解 | Revenue = Buyers × Purchase Frequency × AOV；使用全部六种替代顺序平均的Shapley贡献，三因素增量之和等于总增量。 |
| Cancelled Share | 当期当前Cancelled订单 / 当期全部下单订单；不同于取消原因发生率。 |
| 高消费前20% | 按年度Revenue降序、customer_id升序，NTILE(5)=1；2025年2,387人。 |
| 固定窗口二购率 | 各年1月1日至10月2日数据内首次Delivered客户中，在首次订单后30/60/90天内有另一order_id者的比例；三个窗口使用同一完整90天样本。2024年4,124人，2025年5,222人。 |
| 未购时长 | 2025-12-31减数据内最近Delivered订单日期。 |
| 召回 / 交易处理 | 高消费前20%且91—180天未购者346人；年度毛利>0为260人召回候选，其余86人先处理非正毛利交易。 |
| 年度净亏损SKU | 先按SKU汇总2025年Delivered商品毛利，汇总结果<0者33个。 |
| 净亏损额 | 33个SKU的年度负毛利取绝对值合计5,210,827.01 INR；不等于全量负毛利明细损失之和。 |
| 折前毛利基准 | SUM(quantity × unit_price − item_cost)。 |
| 成交折让 | SUM(quantity × unit_price − item_revenue)；折前毛利减成交折让等于实际商品毛利，属于金额恒等式。 |
| 库存覆盖情景 | 商品库存快照 / 最近30或90日Delivered日均销量。截止日取数据最后Delivered下单日；缺少明确库存快照日，不直接作为补货指令。 |

金额均为INR。看板中“百万INR”表示原始金额除以1,000,000。SQL的_pct字段已乘100；Tableau数据中比例以0—1存储，显示时转为百分比。同比百分比与百分点变化分开标注。

## 看板与SQL的对应

| Dashboard | 核心内容 | 对应模块及段落 |
|---|---|---|
| 企业经营 | 年度KPI、月度收入、增长来源、季度增量、取消地区 | 企业经营：年度经营表现、月度趋势、季度增长贡献、Shapley增长分解、取消订单地区分布；按SQL中文标题定位。 |
| 用户分析 | 客户数、90天二购、高消费盈利、未购回看、分层行动 | 用户分析：1B年度、5高消费贡献、6B回看、6C二购、9分层行动。盈利对比由第2节客户明细按spend_rank=1 / 其他分组汇总。 |
| 商品分析 | 品类毛利率、收入与毛利贡献、前五亏损SKU、Electronics折让 | 商品分析：2品类结构、4A亏损SKU、5A Electronics折让桥接。 |

工作簿使用与当前SQL结果一致的本地汇总CSV，15个数据源已嵌入TWBX。它是本次2025分析的固定数据版本，不自动连接MySQL。修改SQL后需重新导出相应CSV并更新看板；不要只改标题日期。

四表没有访问流量、获客费用、实际支付流水、历史库存和状态流转日志，因此本项目不计算访问转化率、CAC、净利润、实际签收时效或自动补货量。历史首次购买与未购回看以数据内记录和当前Delivered状态为基础。
