# SQL 运行说明

原项目面向MySQL 8.0+，保留原分析查询，仅统一文件命名。原始CSV从[来源数据集](https://www.kaggle.com/datasets/shiyalkishan01/indian-e-commerce-sales-and-customer-analytics)下载，本仓库不重复分发。

1. 在本地准备customers.csv、products.csv、orders.csv、order_items.csv，字段顺序见数据字典。
2. 在独立练习数据库环境执行`00_schema.sql`。脚本创建`ecommerce_analysis`及四表，采用IF NOT EXISTS，不会自动修复既有表结构。
3. 使用MySQL导入工具按customers、products、orders、order_items顺序导入，启用UTF-8，跳过表头，核对列映射。空白应按字段转为NULL，年龄原CSV可能以44.0形式表示，导入INT前确认转换结果。不要用导入错误忽略选项掩盖丢行。
4. 核对25,000 / 550 / 100,000 / 254,331行。先执行经营模块0A/0B及客户模块0节，检查主键、关联、金额和日期异常。
5. 分别执行01、02、03模块。01与02模块单独执行某一查询前，先运行文件顶部USE与SET参数。03模块包含固定年度过滤，改期需同步检查全部查询。
6. 导出结果时关闭客户端“仅返回1000行”等限制。百分比字段`_pct`已乘100，而Tableau汇总CSV比例为0—1，不可重复乘100。
7. 如刷新Dashboard，应按原CSV字段名、粒度和单位更新15份汇总文件，再在Tableau更新数据并重新打包。这里未提供一键导入或自动导出脚本。

模块入口：
- `01_business_performance.sql`：年度/月度经营、季度贡献、Shapley增长分解、地区与订单状态。
- `02_customer_value_retention.sql`：消费分层、毛利、未购回看、固定窗口二购、行动分层和客户名单查询。
- `03_product_profitability.sql`：品类结构、亏损SKU、折让桥接、库存覆盖情景。

原`99_全部分析SQL.sql`为三个模块的合并版，公开版省略，避免重复维护。建表脚本另列。分析代码包含输出客户级结果的查询，公开代码不意味着应把查询产生的客户名单上传。

本次已独立复算关键结果，但未在MySQL服务器逐条执行全部语句。
