# 数据来源与选表范围

## 来源

- 数据集：[Indian E-Commerce Sales & Customer Analytics](https://www.kaggle.com/datasets/shiyalkishan01/indian-e-commerce-sales-and-customer-analytics)
- 发布者：Shiyal Kishan，Kaggle账号`shiyalkishan01`
- 查看版本：Version 1
- 时间覆盖：2023-01-01至2025-12-31
- 数据性质：发布者明确说明为程序生成的100%合成数据，不代表真实公司、客户或交易。
- 页面许可：CC0 1.0 / Public Domain，见[许可页面](https://creativecommons.org/publicdomain/zero/1.0/)。该说明针对来源数据，不等于为本项目新增统一的代码或报告许可证。

推荐引用：Shiyal Kishan. *Indian E-Commerce Sales & Customer Analytics*. Kaggle, Version 1. 数据集链接见上。

## 本项目仅使用四表

| 表 | 附件实测行数 | 列数 | 用途 |
|---|---:|---:|---|
| customers.csv | 25,000 | 18 | 客户关联、属性与价值分层 |
| orders.csv | 100,000 | 16 | 订单状态、日期、金额与客户关系 |
| order_items.csv | 254,331 | 9 | 商品明细收入、成本、毛利和折让 |
| products.csv | 550 | 14 | 商品品类、属性与库存快照 |

以上是本项目使用的四张表规模，不代表原数据集只有四表。原数据集还包含payments、shipments、returns、customer_reviews、marketing_campaigns，以及数据字典、校验报告和生成脚本等。本项目的结论与数据限制以实际使用的四表为准。

## 来源匹配证据

根据Kaggle数据说明与在线文件预览核对，四表文件名、列数、预览字段和具体样本与上传CSV一致：

| 表 | 在线预览与本地一致的样本 |
|---|---|
| products | PROD10000，Sen Basic Staple，Grocery，价格220.0，成本173.88，评分4.4 |
| orders | ORD1000000，2025-08-16 22:35:23，Failed，Next-Day，Mumbai / Maharashtra，优惠码FEST20，折扣5.0 |
| order_items | OI10000000，ORD1000000，PROD10347，数量4，单价150.0，折扣6.5，收入561.0，成本515.92，毛利45.08 |
| customers | 首条记录注册日期2023-01-09，Male，年龄44.0，Madhya Pradesh / Indore，邮编前缀607，Regular，Mobile App |

数据卡所述25,000名客户、100,000个订单、550个商品、约254,000条明细及2023—2025时间范围与附件一致。核对范围为页面说明和预览样本，没有声称对Kaggle下载文件与附件完成全量逐字节比对。

## 获取与公开范围

从来源页面下载数据后，仅使用上列四张CSV。原始CSV未重复放入本仓库，便于保持作品包简洁并引导读者访问发布者页面。导入步骤见[SQL运行说明](../sql/README.md)。

公开成果包括SQL、数据字典、汇总CSV、三张Dashboard、Tableau工作簿、报告与商品核验Excel。合成客户名单未随包分发，分析逻辑及分层汇总已保留。该选择用于精简展示，不是因存在真实客户隐私或许可未明。

Tableau工作簿内嵌15份汇总CSV，作者与设备指纹已清理。

## 使用边界

本项目是独立Portfolio Project，结果只反映该合成数据中的关系。收入增长、亏损集中度和召回候选不能作为真实印度电商市场、真实消费者行为或实际业务实施收益的证据。
