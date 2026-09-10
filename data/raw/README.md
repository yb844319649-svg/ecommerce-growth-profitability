# 原始数据获取

下载来源：[Indian E-Commerce Sales & Customer Analytics](https://www.kaggle.com/datasets/shiyalkishan01/indian-e-commerce-sales-and-customer-analytics)，发布者Shiyal Kishan，页面标注CC0 1.0。

本项目仅使用customers.csv、products.csv、orders.csv、order_items.csv，订单日期覆盖2023—2025年。原数据集包含更多表，不必全部导入。

请将需要的四表保存在本地，按[运行说明](../../sql/README.md)导入MySQL。字段结构见[数据字典](../../docs/data_dictionary.md)，来源及比对范围见[数据来源](../../docs/data_source.md)。

仓库不重复附带原始CSV。`.gitignore`已将该目录中的本地数据排除，仅跟踪本说明文件。
