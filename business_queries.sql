/* =============================================================================
Note: 
This file contains production-grade analytical query templates designed for the 
provided 3NF schema. While the current `dbdata.sql` primarily populates dimension 
tables (games, tags, mappers) for structural validation, these queries are built 
to execute against populated fact tables (`user`, `token`, `order`) in a live 
production environment to extract deep-funnel business metrics.
=============================================================================
*/

/* =============================================================================
业务场景 1：全链路设备端到端转化漏斗 (End-to-End Conversion Funnel)
分析目标：计算从 平台注册 -> 设备登录 -> 最终购买 的核心转化率与 ARPU
=============================================================================
*/
WITH RegisteredUsers AS (
    -- 步骤 1: 提取所有注册用户
    SELECT `id` AS uid, `ctime` AS reg_time 
    FROM `shop`.`user`
),
ActiveSessions AS (
    -- 步骤 2: 提取有过有效登录会话(Token)的活跃用户
    SELECT `uid`, 
           COUNT(DISTINCT `token`) AS session_count, 
           MAX(`device`) AS primary_device
    FROM `shop`.`token`
    GROUP BY `uid`
),
Purchasers AS (
    -- 步骤 3: 提取产生过实际购买行为的用户及消费总额
    SELECT o.`uid`, 
           COUNT(DISTINCT om.`item`) AS games_bought, 
           SUM(oi.`price`) AS total_spent
    FROM `shop`.`order` o
    -- 【注意】：order 是 SQL 保留字，作为字段名必须加反引号，体现严谨的工程素养
    JOIN `shop`.`ordermapper` om ON o.`id` = om.`order` 
    JOIN `shop`.`orderitem` oi ON om.`item` = oi.`id`
    GROUP BY o.`uid`
)
-- 组装漏斗并计算转化率
SELECT 
    COUNT(DISTINCT ru.uid) AS `Total Registered Users`,
    COUNT(DISTINCT asess.uid) AS `Active Logged-in Users`,
    COUNT(DISTINCT p.uid) AS `Converted Purchasers`,
    ROUND((COUNT(DISTINCT p.uid) / COUNT(DISTINCT asess.uid)) * 100, 2) AS `Login-to-Purchase Conv. Rate (%)`,
    ROUND(AVG(p.total_spent), 2) AS `ARPU (Avg Revenue Per User)`
FROM RegisteredUsers ru
LEFT JOIN ActiveSessions asess ON ru.uid = asess.uid
LEFT JOIN Purchasers p ON ru.uid = p.uid;


/* =============================================================================
业务场景 2：深层品类变现分析 (Revenue Contribution by Game Kind)
分析目标：打通 订单详情 -> 游戏元数据 -> 种类映射 -> 种类字典，计算各类游戏的收入占比
=============================================================================
*/
SELECT 
    k.`name` AS `Game Category`,
    COUNT(DISTINCT oi.`id`) AS `Total Copies Sold`,
    SUM(oi.`price`) AS `Total Revenue Generated`,
    ROUND(AVG(oi.`price`), 2) AS `Average Selling Price (ASP)`,
    -- 计算该品类占全盘收入的百分比 (利用窗口函数)
    ROUND(SUM(oi.`price`) / SUM(SUM(oi.`price`)) OVER() * 100, 2) AS `Revenue Contribution (%)`
FROM `shop`.`orderitem` oi
JOIN `shop`.`game` g ON oi.`gid` = g.`id`
JOIN `shop`.`kindmapper` km ON g.`id` = km.`game`
JOIN `shop`.`kind` k ON km.`kind` = k.`id`
GROUP BY k.`name`
ORDER BY `Total Revenue Generated` DESC;
