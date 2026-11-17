-- =============================================================================
-- 工程问数 · Oracle 建表脚本（SPMS 前缀）
--
-- 命名规范（沿用中石化工程管理系统习惯）：
--   SPMS_META_*  元数据（表/字段/指标/关联/取值）
--   SPMS_DW_*     物理实体表（只存主键与属性，不冗余关联列）
--   SPMS_RELATION 实体关系表（所有表间关系的唯一来源，本质是关系图的边表）
--   SPMS_DIM_* / SPMS_FACT_* / SPMS_PROJECT_PLAN  语义视图（应用与模型只见这一层）
--
-- 两条硬性设计约束：
-- 1) 不使用外键，关系全部登记在 SPMS_RELATION（source_type/source_id/relation_type/target_type/target_id）。
--    好处：导入无顺序依赖、关系可扩展、血缘一次查询可见；
--    代价：JOIN 路径变长，用视图固化路径 + 复合索引兜住。
-- 2) 物理层与语义层分离：SPMS_DW_* 是实体表，SPMS_DIM_*/SPMS_FACT_* 是视图。
--    物理层怎么重构都不影响问数。
--
-- 业务域覆盖：进度 / 质量 / 设计 / 费用 / HSE / 材料
-- =============================================================================
SET SERVEROUTPUT ON
SET DEFINE OFF
ALTER SESSION SET CONTAINER = SPMSUAT;

-- ---------------------------------------------------------------- 幂等清理
-- 重复执行时先删对象：视图依赖表，必须先删视图。
-- 用 ALL_VIEWS / ALL_TABLES + OWNER 过滤，而不是 USER_*：
-- USER_* 只反映"当前登录用户"（SYS），CURRENT_SCHEMA 不影响它。
BEGIN
    FOR v IN (SELECT owner, view_name FROM all_views
               WHERE owner = 'DW' AND view_name LIKE 'SPMS\_%' ESCAPE '\') LOOP
        EXECUTE IMMEDIATE 'DROP VIEW ' || v.owner || '.' || v.view_name;
    END LOOP;
END;
/

BEGIN
    FOR t IN (SELECT owner, table_name FROM all_tables
               WHERE owner IN ('DW', 'META') AND table_name LIKE 'SPMS\_%' ESCAPE '\') LOOP
        EXECUTE IMMEDIATE 'DROP TABLE ' || t.owner || '.' || t.table_name
                          || ' CASCADE CONSTRAINTS PURGE';
    END LOOP;
END;
/

-- #############################################################################
-- #  第一部分  元数据库 meta
-- #############################################################################
ALTER SESSION SET CURRENT_SCHEMA = meta;

CREATE TABLE spms_meta_table_info (
    id          VARCHAR2(64) PRIMARY KEY,
    name        VARCHAR2(128) NOT NULL,
    db_name     VARCHAR2(128),
    role        VARCHAR2(32),          -- fact / dim
    description VARCHAR2(512)
);

CREATE TABLE spms_meta_column_info (
    id               VARCHAR2(64) PRIMARY KEY,
    name             VARCHAR2(128) NOT NULL,
    type             VARCHAR2(64),
    role             VARCHAR2(32),     -- primary_key / relation_key / measure / dimension / time
    ordinal_position NUMBER(6),
    is_nullable      CHAR(1) DEFAULT 'Y',
    examples         VARCHAR2(2000),   -- JSON 数组
    description      VARCHAR2(512),
    alias            VARCHAR2(512),    -- JSON 数组，首元素为中文展示名
    table_id         VARCHAR2(64) NOT NULL
);
CREATE INDEX idx_spms_column_table ON spms_meta_column_info (table_id);

CREATE TABLE spms_meta_metric_info (
    id               VARCHAR2(64) PRIMARY KEY,
    name             VARCHAR2(128) NOT NULL,
    metric_type      VARCHAR2(32),     -- amount / ratio / count / duration
    unit             VARCHAR2(32),
    agg_func         VARCHAR2(32),     -- sum / avg / count / ratio
    formula          VARCHAR2(512),    -- 可执行 SQL 表达式，口径的唯一来源
    description      VARCHAR2(512),
    relevant_columns VARCHAR2(1000),   -- JSON 数组
    alias            VARCHAR2(512)
);

CREATE TABLE spms_meta_column_metric (
    column_id     VARCHAR2(64) NOT NULL,
    metric_id     VARCHAR2(64) NOT NULL,
    relation_type VARCHAR2(32),
    CONSTRAINT pk_spms_column_metric PRIMARY KEY (column_id, metric_id)
);

CREATE TABLE spms_meta_value_info (
    id           NUMBER(12) PRIMARY KEY,
    column_id    VARCHAR2(64) NOT NULL,
    column_value VARCHAR2(512) NOT NULL,
    frequency    NUMBER(10) DEFAULT 0
);
CREATE INDEX idx_spms_value_column ON spms_meta_value_info (column_id);

-- #############################################################################
-- #  第二部分  数据仓库 dw
-- #############################################################################
ALTER SESSION SET CURRENT_SCHEMA = dw;

-- ---------------------------------------------------------------- 实体关系表
-- 一行 = 一条有向边：source_type/source_id 指向 target_type/target_id，
-- relation_type 说明是什么关系（FACT_PROJECT / PLAN_PROJECT / INSPECTION_PROJECT ...）。
-- 不用外键：导入无顺序依赖，关系本身成为可插拔的数据。
CREATE TABLE spms_relation (
    source_type VARCHAR2(32) NOT NULL,
    source_id   VARCHAR2(64) NOT NULL,
    relation_type VARCHAR2(32) NOT NULL,
    target_type VARCHAR2(32) NOT NULL,
    target_id   VARCHAR2(64) NOT NULL
);
CREATE INDEX idx_spms_relation_source ON spms_relation (source_type, source_id, relation_type);
CREATE INDEX idx_spms_relation_target ON spms_relation (target_type, target_id, relation_type);

-- ---------------------------------------------------------------- 维度表
CREATE TABLE spms_dw_date (
    date_id  NUMBER(8) PRIMARY KEY,     -- yyyymmdd
    year_no  NUMBER(4),
    month_no NUMBER(2),
    quarter_no NUMBER(1),
    weekday  VARCHAR2(16)
);

CREATE TABLE spms_dw_project (
    project_id    VARCHAR2(32) PRIMARY KEY,
    project_name  VARCHAR2(128) NOT NULL,
    enterprise    VARCHAR2(64),
    project_type  VARCHAR2(32),
    manage_mode   VARCHAR2(32),
    budget_amount NUMBER(18, 2),        -- 批复概算（万元）
    plan_start    NUMBER(8),
    plan_finish   NUMBER(8)
);

CREATE TABLE spms_dw_wbs (
    wbs_id     VARCHAR2(32) PRIMARY KEY,
    wbs_name   VARCHAR2(128) NOT NULL,
    wbs_level  VARCHAR2(16),            -- 单位工程 / 分部工程 / 分项工程
    discipline VARCHAR2(32)             -- 土建/设备/管道/电气/仪表/防腐保温
);

CREATE TABLE spms_dw_contractor (
    contractor_id   VARCHAR2(32) PRIMARY KEY,
    contractor_name VARCHAR2(128) NOT NULL,
    contractor_type VARCHAR2(32)        -- EPC / 施工 / 监理 / 检测
);

-- ---------------------------------------------------------------- 进度域
CREATE TABLE spms_dw_fact_construction_daily (
    fact_id       VARCHAR2(32) PRIMARY KEY,
    date_id       NUMBER(8) NOT NULL,
    output_value  NUMBER(18, 2),        -- 当日完成产值（万元）
    invest_amount NUMBER(18, 2),        -- 当日实际投资额（万元）
    man_hours     NUMBER(12, 2)         -- 当日投入工时
);
CREATE INDEX idx_spms_dw_fact_date ON spms_dw_fact_construction_daily (date_id);

CREATE TABLE spms_dw_project_plan (
    plan_id     VARCHAR2(32) PRIMARY KEY,
    plan_level  VARCHAR2(8),            -- L1 里程碑 / L2 WBS 节点 / L3 详细作业
    plan_name   VARCHAR2(256) NOT NULL,
    plan_start  NUMBER(8),
    plan_finish NUMBER(8),
    plan_value  NUMBER(18, 2)           -- 计划完成产值（万元）
);

-- ---------------------------------------------------------------- 质量域
-- 焊口检验：一行是一次检验批，合格率只能在这里算，施工日报不重复存
CREATE TABLE spms_dw_quality_inspection (
    inspection_id VARCHAR2(32) PRIMARY KEY,
    date_id       NUMBER(8) NOT NULL,
    weld_total    NUMBER(10),
    weld_passed   NUMBER(10),
    ncr_count     NUMBER(6) DEFAULT 0
);
CREATE INDEX idx_spms_dw_inspection_date ON spms_dw_quality_inspection (date_id);

CREATE TABLE spms_dw_ncr (
    ncr_id     VARCHAR2(32) PRIMARY KEY,
    date_id    NUMBER(8) NOT NULL,
    severity   VARCHAR2(16),            -- 一般 / 严重 / 重大
    status     VARCHAR2(16),            -- OPEN / CLOSED
    close_date NUMBER(8)
);

-- ---------------------------------------------------------------- 设计域
CREATE TABLE spms_dw_design_delivery (
    delivery_id VARCHAR2(32) PRIMARY KEY,
    date_id     NUMBER(8) NOT NULL,
    doc_type    VARCHAR2(32),           -- 施工图 / 详图 / 竣工图
    doc_total   NUMBER(10),
    delivered_total NUMBER(10),
    plan_date   NUMBER(8),
    actual_date NUMBER(8)
);

CREATE TABLE spms_dw_design_change (
    change_id    VARCHAR2(32) PRIMARY KEY,
    date_id      NUMBER(8) NOT NULL,
    change_type  VARCHAR2(32),          -- 设计优化 / 现场签证 / 业主变更
    change_count NUMBER(6) DEFAULT 1
);

-- ---------------------------------------------------------------- 费用域
CREATE TABLE spms_dw_cost_monthly (
    cost_id         VARCHAR2(32) PRIMARY KEY,
    date_id         NUMBER(8) NOT NULL, -- 月度首日，如 20260801
    budget_amount   NUMBER(18, 2),      -- 当月预算（万元）
    actual_amount   NUMBER(18, 2),      -- 当月实际（万元）
    committed_amount NUMBER(18, 2)      -- 已承诺未发生（万元）
);

-- ---------------------------------------------------------------- HSE 域
CREATE TABLE spms_dw_hse_event (
    event_id   VARCHAR2(32) PRIMARY KEY,
    date_id    NUMBER(8) NOT NULL,
    event_type VARCHAR2(32),            -- 安全事故 / 未遂 / 违章 / 环保
    severity   VARCHAR2(16),            -- 轻微 / 一般 / 较大 / 重大
    lost_days  NUMBER(8) DEFAULT 0,     -- 损失工日
    man_hours  NUMBER(12, 2)            -- 当期总工时
);

-- ---------------------------------------------------------------- 材料域
CREATE TABLE spms_dw_material_delivery (
    delivery_id  VARCHAR2(32) PRIMARY KEY,
    date_id      NUMBER(8) NOT NULL,
    material_name VARCHAR2(128),        -- 管道 / 钢材 / 设备 / 电缆
    plan_qty     NUMBER(14, 2),
    actual_qty   NUMBER(14, 2),
    unit         VARCHAR2(16),
    plan_date    NUMBER(8),
    actual_date  NUMBER(8)
);

-- ---------------------------------------------------------------- 语义视图
-- 每个事实视图用 LEFT JOIN 把关系表还原成 project_id / contractor_id，
-- 不做标量子查询：数据量上来后标量子查询会退化成逐行扫描。
CREATE OR REPLACE VIEW spms_dim_date AS
SELECT date_id, year_no, month_no, quarter_no, weekday FROM spms_dw_date;

CREATE OR REPLACE VIEW spms_dim_project AS
SELECT project_id, project_name, enterprise, project_type, manage_mode,
       budget_amount, plan_start, plan_finish
  FROM spms_dw_project;

CREATE OR REPLACE VIEW spms_dim_wbs AS
SELECT w.wbs_id, w.wbs_name, w.wbs_level, w.discipline,
       r.target_id AS project_id
  FROM spms_dw_wbs w
  LEFT JOIN spms_relation r
    ON r.source_type = 'WBS' AND r.source_id = w.wbs_id AND r.relation_type = 'WBS_PROJECT';

CREATE OR REPLACE VIEW spms_dim_contractor AS
SELECT contractor_id, contractor_name, contractor_type FROM spms_dw_contractor;

CREATE OR REPLACE VIEW spms_fact_construction_daily AS
SELECT f.fact_id, f.date_id, f.output_value, f.invest_amount, f.man_hours,
       p.target_id AS project_id,
       c.target_id AS contractor_id
  FROM spms_dw_fact_construction_daily f
  LEFT JOIN spms_relation p
    ON p.source_type = 'FACT' AND p.source_id = f.fact_id AND p.relation_type = 'FACT_PROJECT'
  LEFT JOIN spms_relation c
    ON c.source_type = 'FACT' AND c.source_id = f.fact_id AND c.relation_type = 'FACT_CONTRACTOR';

CREATE OR REPLACE VIEW spms_project_plan AS
SELECT pl.plan_id, pl.plan_level, pl.plan_name, pl.plan_start, pl.plan_finish, pl.plan_value,
       p.target_id AS project_id
  FROM spms_dw_project_plan pl
  LEFT JOIN spms_relation p
    ON p.source_type = 'PLAN' AND p.source_id = pl.plan_id AND p.relation_type = 'PLAN_PROJECT';

CREATE OR REPLACE VIEW spms_fact_quality_inspection AS
SELECT i.inspection_id, i.date_id, i.weld_total, i.weld_passed, i.ncr_count,
       p.target_id AS project_id,
       c.target_id AS contractor_id
  FROM spms_dw_quality_inspection i
  LEFT JOIN spms_relation p
    ON p.source_type = 'INSPECTION' AND p.source_id = i.inspection_id
   AND p.relation_type = 'INSPECTION_PROJECT'
  LEFT JOIN spms_relation c
    ON c.source_type = 'INSPECTION' AND c.source_id = i.inspection_id
   AND c.relation_type = 'INSPECTION_CONTRACTOR';

CREATE OR REPLACE VIEW spms_fact_ncr AS
SELECT n.ncr_id, n.date_id, n.severity, n.status, n.close_date,
       p.target_id AS project_id
  FROM spms_dw_ncr n
  LEFT JOIN spms_relation p
    ON p.source_type = 'NCR' AND p.source_id = n.ncr_id AND p.relation_type = 'NCR_PROJECT';

CREATE OR REPLACE VIEW spms_fact_design_delivery AS
SELECT d.delivery_id, d.date_id, d.doc_type, d.doc_total, d.delivered_total,
       d.plan_date, d.actual_date,
       p.target_id AS project_id
  FROM spms_dw_design_delivery d
  LEFT JOIN spms_relation p
    ON p.source_type = 'DELIVERY' AND p.source_id = d.delivery_id
   AND p.relation_type = 'DELIVERY_PROJECT';

CREATE OR REPLACE VIEW spms_fact_design_change AS
SELECT ch.change_id, ch.date_id, ch.change_type, ch.change_count,
       p.target_id AS project_id
  FROM spms_dw_design_change ch
  LEFT JOIN spms_relation p
    ON p.source_type = 'CHANGE' AND p.source_id = ch.change_id AND p.relation_type = 'CHANGE_PROJECT';

CREATE OR REPLACE VIEW spms_fact_cost_monthly AS
SELECT c.cost_id, c.date_id, c.budget_amount, c.actual_amount, c.committed_amount,
       p.target_id AS project_id
  FROM spms_dw_cost_monthly c
  LEFT JOIN spms_relation p
    ON p.source_type = 'COST' AND p.source_id = c.cost_id AND p.relation_type = 'COST_PROJECT';

CREATE OR REPLACE VIEW spms_fact_hse_event AS
SELECT e.event_id, e.date_id, e.event_type, e.severity, e.lost_days, e.man_hours,
       p.target_id AS project_id,
       c.target_id AS contractor_id
  FROM spms_dw_hse_event e
  LEFT JOIN spms_relation p
    ON p.source_type = 'EVENT' AND p.source_id = e.event_id AND p.relation_type = 'EVENT_PROJECT'
  LEFT JOIN spms_relation c
    ON c.source_type = 'EVENT' AND c.source_id = e.event_id AND c.relation_type = 'EVENT_CONTRACTOR';

CREATE OR REPLACE VIEW spms_fact_material_delivery AS
SELECT m.delivery_id, m.date_id, m.material_name, m.plan_qty, m.actual_qty, m.unit,
       m.plan_date, m.actual_date,
       p.target_id AS project_id
  FROM spms_dw_material_delivery m
  LEFT JOIN spms_relation p
    ON p.source_type = 'MATERIAL' AND p.source_id = m.delivery_id
   AND p.relation_type = 'MATERIAL_PROJECT';

-- ---------------------------------------------------------------- 数据水位
-- 结果附带的"数据截至时间"：所有事实视图里最近的业务日期
CREATE OR REPLACE VIEW spms_v_data_watermark AS
SELECT MAX(date_id) AS data_as_of
  FROM (
        SELECT date_id FROM spms_dw_fact_construction_daily
        UNION ALL SELECT date_id FROM spms_dw_quality_inspection
        UNION ALL SELECT date_id FROM spms_dw_cost_monthly
       );
