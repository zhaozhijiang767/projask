-- 问数执行账号：只有语义层视图的 SELECT 权限。
-- 即使 SQL 校验被绕过，数据库侧也拿不到写权限与物理表。
ALTER SESSION SET CONTAINER = SPMSUAT;

-- 幂等：先删用户再建
BEGIN
    FOR u IN (SELECT username FROM all_users WHERE username = 'DW_READER') LOOP
        EXECUTE IMMEDIATE 'DROP USER ' || u.username || ' CASCADE';
    END LOOP;
END;
/

CREATE USER dw_reader IDENTIFIED BY "Spms123456";
GRANT CREATE SESSION TO dw_reader;

GRANT SELECT ON dw.spms_dim_date              TO dw_reader;
GRANT SELECT ON dw.spms_dim_project           TO dw_reader;
GRANT SELECT ON dw.spms_dim_wbs               TO dw_reader;
GRANT SELECT ON dw.spms_dim_contractor        TO dw_reader;

GRANT SELECT ON dw.spms_fact_construction_daily TO dw_reader;
GRANT SELECT ON dw.spms_project_plan            TO dw_reader;
GRANT SELECT ON dw.spms_fact_quality_inspection TO dw_reader;
GRANT SELECT ON dw.spms_fact_ncr                TO dw_reader;
GRANT SELECT ON dw.spms_fact_design_delivery    TO dw_reader;
GRANT SELECT ON dw.spms_fact_design_change      TO dw_reader;
GRANT SELECT ON dw.spms_fact_cost_monthly       TO dw_reader;
GRANT SELECT ON dw.spms_fact_hse_event          TO dw_reader;
GRANT SELECT ON dw.spms_fact_material_delivery  TO dw_reader;

GRANT SELECT ON dw.spms_v_data_watermark      TO dw_reader;

-- 私有同义词（归属 dw_reader）：应用以 dw_reader 连接，生成的 SQL 用不带 schema
-- 前缀的视图名。没有同义词时 Oracle 会把名字解析到 dw_reader 自己的 schema，
-- 报 ORA-00942。用私有而不是公共同义词，避免污染全局命名空间。
CREATE OR REPLACE SYNONYM dw_reader.spms_dim_date              FOR dw.spms_dim_date;
CREATE OR REPLACE SYNONYM dw_reader.spms_dim_project           FOR dw.spms_dim_project;
CREATE OR REPLACE SYNONYM dw_reader.spms_dim_wbs               FOR dw.spms_dim_wbs;
CREATE OR REPLACE SYNONYM dw_reader.spms_dim_contractor        FOR dw.spms_dim_contractor;

CREATE OR REPLACE SYNONYM dw_reader.spms_fact_construction_daily FOR dw.spms_fact_construction_daily;
CREATE OR REPLACE SYNONYM dw_reader.spms_project_plan            FOR dw.spms_project_plan;
CREATE OR REPLACE SYNONYM dw_reader.spms_fact_quality_inspection FOR dw.spms_fact_quality_inspection;
CREATE OR REPLACE SYNONYM dw_reader.spms_fact_ncr                FOR dw.spms_fact_ncr;
CREATE OR REPLACE SYNONYM dw_reader.spms_fact_design_delivery    FOR dw.spms_fact_design_delivery;
CREATE OR REPLACE SYNONYM dw_reader.spms_fact_design_change      FOR dw.spms_fact_design_change;
CREATE OR REPLACE SYNONYM dw_reader.spms_fact_cost_monthly       FOR dw.spms_fact_cost_monthly;
CREATE OR REPLACE SYNONYM dw_reader.spms_fact_hse_event          FOR dw.spms_fact_hse_event;
CREATE OR REPLACE SYNONYM dw_reader.spms_fact_material_delivery  FOR dw.spms_fact_material_delivery;

CREATE OR REPLACE SYNONYM dw_reader.spms_v_data_watermark        FOR dw.spms_v_data_watermark;
