# Tableau Dashboard

[经营](images/01_business_overview.png) · [客户](images/02_customer_analysis.png) · [商品](images/03_product_profitability.png)

[下载TWBX](ecommerce_2025.twbx)。原文件记录的创建版本为Tableau 2026.2.1，建议使用兼容版本打开。当前环境未在Tableau客户端验证打开与交互。

内嵌15个汇总CSV，连接路径为包内`Data/Data`，无实时MySQL连接。外部副本位于`../data/aggregated/`，保持原中文文件名和字段名，便于对应SQL与数据源。不要只改看板标题日期，应同时更新SQL结果和内嵌数据。

文件清理仅移除WorkbookFingerprinting中的设备与作者标识，分析、布局及内嵌CSV保持原内容。原始截图直接保留，未重绘或改动数字。
