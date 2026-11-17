-- =============================================================================
-- 工程问数 · 示例数据（六个业务域）
--
-- 可重入：先清空再插入，重复执行结果一致。
-- 数据是"造"的，但结构、量纲、口径与真实项目一致，用于演示与评测。
-- 执行：sqlplus meta/Spms123456@localhost:1521/SPMSUAT @02_dw_data.sql
-- 依赖：01_schema.sql 已执行
-- =============================================================================
SET SERVEROUTPUT ON
SET DEFINE OFF
ALTER SESSION SET CONTAINER = SPMSUAT;
ALTER SESSION SET CURRENT_SCHEMA = dw;

-- ---------------------------------------------------------------- 清空
DELETE FROM spms_relation;
DELETE FROM spms_dw_material_delivery;
DELETE FROM spms_dw_hse_event;
DELETE FROM spms_dw_cost_monthly;
DELETE FROM spms_dw_design_change;
DELETE FROM spms_dw_design_delivery;
DELETE FROM spms_dw_ncr;
DELETE FROM spms_dw_quality_inspection;
DELETE FROM spms_dw_project_plan;
DELETE FROM spms_dw_fact_construction_daily;
DELETE FROM spms_dw_wbs;
DELETE FROM spms_dw_contractor;
DELETE FROM spms_dw_project;
DELETE FROM spms_dw_date;
COMMIT;

-- ---------------------------------------------------------------- 日期维度
BEGIN
    FOR i IN 0 .. 364 LOOP
        INSERT INTO spms_dw_date (date_id, year_no, month_no, quarter_no, weekday)
        VALUES (
            TO_NUMBER(TO_CHAR(DATE '2026-01-01' + i, 'YYYYMMDD')),
            2026,
            TO_NUMBER(TO_CHAR(DATE '2026-01-01' + i, 'MM')),
            TO_NUMBER(TO_CHAR(DATE '2026-01-01' + i, 'Q')),
            TRIM(TO_CHAR(DATE '2026-01-01' + i, 'DAY', 'NLS_DATE_LANGUAGE=AMERICAN'))
        );
    END LOOP;
    COMMIT;
END;
/

-- ---------------------------------------------------------------- 项目 / 承包商 / WBS
INSERT INTO spms_dw_project (project_id, project_name, enterprise, project_type, manage_mode,
                            budget_amount, plan_start, plan_finish)
VALUES ('P2025-01', '镇海炼化乙烯项目', '镇海炼化', '炼化一体化', 'IPMT', 1280000, 20250101, 20271231);
INSERT INTO spms_dw_project (project_id, project_name, enterprise, project_type, manage_mode,
                            budget_amount, plan_start, plan_finish)
VALUES ('P2025-02', '中科炼化二期项目', '中科炼化', '炼化一体化', 'EPC', 860000, 20250301, 20270630);
INSERT INTO spms_dw_project (project_id, project_name, enterprise, project_type, manage_mode,
                            budget_amount, plan_start, plan_finish)
VALUES ('P2025-03', '海南炼化芳烃项目', '海南炼化', '化工', 'IPMT', 540000, 20250601, 20270930);

INSERT INTO spms_dw_contractor (contractor_id, contractor_name, contractor_type)
VALUES ('C001', '中石化第十建设公司', 'EPC');
INSERT INTO spms_dw_contractor (contractor_id, contractor_name, contractor_type)
VALUES ('C002', '中石化宁波工程公司', 'EPC');
INSERT INTO spms_dw_contractor (contractor_id, contractor_name, contractor_type)
VALUES ('C003', '浙江安装集团', '施工');
INSERT INTO spms_dw_contractor (contractor_id, contractor_name, contractor_type)
VALUES ('C004', '江苏华能建设', '施工');
INSERT INTO spms_dw_contractor (contractor_id, contractor_name, contractor_type)
VALUES ('C005', '齐鲁石化建安', '施工');
INSERT INTO spms_dw_contractor (contractor_id, contractor_name, contractor_type)
VALUES ('C006', '石化工程监理公司', '监理');

-- 每个项目 3 个 WBS 节点（土建 / 管道 / 电气）
BEGIN
    FOR p IN (SELECT project_id FROM spms_dw_project ORDER BY project_id) LOOP
        INSERT INTO spms_dw_wbs VALUES (p.project_id || '-W1', '土建工程', '单位工程', '土建');
        INSERT INTO spms_relation VALUES ('WBS', p.project_id || '-W1', 'WBS_PROJECT', 'PROJECT', p.project_id);
        INSERT INTO spms_dw_wbs VALUES (p.project_id || '-W2', '管道安装', '单位工程', '管道');
        INSERT INTO spms_relation VALUES ('WBS', p.project_id || '-W2', 'WBS_PROJECT', 'PROJECT', p.project_id);
        INSERT INTO spms_dw_wbs VALUES (p.project_id || '-W3', '电气仪表', '单位工程', '电气');
        INSERT INTO spms_relation VALUES ('WBS', p.project_id || '-W3', 'WBS_PROJECT', 'PROJECT', p.project_id);
    END LOOP;
    COMMIT;
END;
/

-- ---------------------------------------------------------------- 进度：施工日报 2026-06-01 ~ 2026-09-30
BEGIN
    FOR d IN (SELECT date_id FROM spms_dw_date WHERE date_id BETWEEN 20260601 AND 20260930) LOOP
        FOR p IN (SELECT project_id, ROWNUM AS seq FROM spms_dw_project ORDER BY project_id) LOOP
            DECLARE
                v_id   VARCHAR2(32) := 'F' || TO_CHAR(d.date_id) || LPAD(p.seq, 2, '0');
                v_epc  VARCHAR2(32);
                v_out  NUMBER(18, 2) := 60 + MOD(d.date_id + p.seq * 7, 45);
                v_inv  NUMBER(18, 2) := 45 + MOD(d.date_id + p.seq * 5, 35);
            BEGIN
                SELECT MIN(contractor_id) INTO v_epc
                  FROM spms_dw_contractor WHERE contractor_type = 'EPC';
                INSERT INTO spms_dw_fact_construction_daily (fact_id, date_id, output_value, invest_amount, man_hours)
                VALUES (v_id, d.date_id, v_out, v_inv, 800 + MOD(d.date_id, 400));
                INSERT INTO spms_relation VALUES ('FACT', v_id, 'FACT_PROJECT', 'PROJECT', p.project_id);
                INSERT INTO spms_relation VALUES ('FACT', v_id, 'FACT_CONTRACTOR', 'CONTRACTOR', v_epc);
            END;
        END LOOP;
    END LOOP;
    COMMIT;
END;
/

-- ---------------------------------------------------------------- 进度：计划节点（L1 里程碑 / L2 / L3）
BEGIN
    FOR p IN (SELECT project_id, ROWNUM AS seq FROM spms_dw_project ORDER BY project_id) LOOP
        FOR lvl IN 1 .. 3 LOOP
            FOR k IN 1 .. (4 - lvl) LOOP
                DECLARE
                    v_id VARCHAR2(32) := 'PL' || p.seq || lvl || k;
                    v_lv VARCHAR2(8) := 'L' || lvl;
                BEGIN
                    INSERT INTO spms_dw_project_plan (plan_id, plan_level, plan_name, plan_start, plan_finish, plan_value)
                    VALUES (v_id, v_lv, v_lv || ' 节点 ' || k, 20260601 + k * 10, 20260801 + k * 10,
                            (5 - lvl) * 200 + k * 30);
                    INSERT INTO spms_relation VALUES ('PLAN', v_id, 'PLAN_PROJECT', 'PROJECT', p.project_id);
                END;
            END LOOP;
        END LOOP;
    END LOOP;
    COMMIT;
END;
/

-- ---------------------------------------------------------------- 质量：焊口检验 + NCR
BEGIN
    FOR p IN (SELECT project_id, ROWNUM AS seq FROM spms_dw_project ORDER BY project_id) LOOP
        FOR k IN 1 .. 12 LOOP
            DECLARE
                v_id    VARCHAR2(32) := 'QI' || p.seq || LPAD(k, 2, '0');
                v_total NUMBER(10) := 120 + MOD(k * 13 + p.seq, 80);
                v_pass  NUMBER(10) := 120 + MOD(k * 13 + p.seq, 80) - MOD(k * 7 + p.seq, 14);
                v_epc   VARCHAR2(32);
            BEGIN
                SELECT MIN(contractor_id) INTO v_epc
                  FROM spms_dw_contractor WHERE contractor_type = 'EPC';
                INSERT INTO spms_dw_quality_inspection (inspection_id, date_id, weld_total, weld_passed, ncr_count)
                VALUES (v_id, 20260605 + (k - 1) * 10, v_total, v_pass, MOD(k + p.seq, 3));
                INSERT INTO spms_relation VALUES ('INSPECTION', v_id, 'INSPECTION_PROJECT', 'PROJECT', p.project_id);
                INSERT INTO spms_relation VALUES ('INSPECTION', v_id, 'INSPECTION_CONTRACTOR', 'CONTRACTOR', v_epc);
            END;
        END LOOP;
    END LOOP;
    COMMIT;
END;
/

BEGIN
    FOR p IN (SELECT project_id, ROWNUM AS seq FROM spms_dw_project ORDER BY project_id) LOOP
        FOR k IN 1 .. 6 LOOP
            DECLARE
                v_id VARCHAR2(32) := 'NCR' || p.seq || LPAD(k, 2, '0');
                v_status VARCHAR2(16) := CASE WHEN MOD(k, 3) = 0 THEN 'OPEN' ELSE 'CLOSED' END;
            BEGIN
                INSERT INTO spms_dw_ncr (ncr_id, date_id, severity, status, close_date)
                VALUES (v_id, 20260701 + k * 5,
                        CASE WHEN MOD(k, 4) = 0 THEN '重大' WHEN MOD(k, 2) = 0 THEN '严重' ELSE '一般' END,
                        v_status,
                        CASE WHEN v_status = 'CLOSED' THEN 20260710 + k * 5 END);
                INSERT INTO spms_relation VALUES ('NCR', v_id, 'NCR_PROJECT', 'PROJECT', p.project_id);
            END;
        END LOOP;
    END LOOP;
    COMMIT;
END;
/

-- ---------------------------------------------------------------- 设计：图纸交付 + 设计变更
BEGIN
    FOR p IN (SELECT project_id, ROWNUM AS seq FROM spms_dw_project ORDER BY project_id) LOOP
        FOR k IN 1 .. 4 LOOP
            DECLARE
                v_id VARCHAR2(32) := 'DD' || p.seq || k;
                v_plan NUMBER(8) := 20260701 + k * 15;
                v_actual NUMBER(8) := 20260701 + k * 15 + CASE WHEN MOD(k + p.seq, 3) = 0 THEN 7 ELSE -2 END;
                v_doc VARCHAR2(32) := CASE k WHEN 1 THEN '施工图' WHEN 2 THEN '详图' WHEN 3 THEN '竣工图' ELSE '施工图' END;
            BEGIN
                INSERT INTO spms_dw_design_delivery (delivery_id, date_id, doc_type, doc_total, delivered_total,
                                                    plan_date, actual_date)
                VALUES (v_id, v_plan, v_doc, 40 + k * 5, 40 + k * 5, v_plan, v_actual);
                INSERT INTO spms_relation VALUES ('DELIVERY', v_id, 'DELIVERY_PROJECT', 'PROJECT', p.project_id);
            END;
        END LOOP;
        FOR k IN 1 .. 4 LOOP
            DECLARE
                v_id VARCHAR2(32) := 'DC' || p.seq || k;
            BEGIN
                INSERT INTO spms_dw_design_change (change_id, date_id, change_type, change_count)
                VALUES (v_id, 20260710 + k * 12,
                        CASE MOD(k, 3) WHEN 0 THEN '设计优化' WHEN 1 THEN '现场签证' ELSE '业主变更' END,
                        1 + MOD(k, 3));
                INSERT INTO spms_relation VALUES ('CHANGE', v_id, 'CHANGE_PROJECT', 'PROJECT', p.project_id);
            END;
        END LOOP;
    END LOOP;
    COMMIT;
END;
/

-- ---------------------------------------------------------------- 费用：月度（2026-07 ~ 2026-09）
BEGIN
    FOR p IN (SELECT project_id, ROWNUM AS seq FROM spms_dw_project ORDER BY project_id) LOOP
        FOR m IN 7 .. 9 LOOP
            DECLARE
                v_id VARCHAR2(32) := 'COST' || p.seq || m;
                v_budget NUMBER(18, 2) := 3000 + p.seq * 500;
                v_actual NUMBER(18, 2) := 3000 + p.seq * 500 + MOD(m * 37 + p.seq, 400) - 150;
            BEGIN
                INSERT INTO spms_dw_cost_monthly (cost_id, date_id, budget_amount, actual_amount, committed_amount)
                VALUES (v_id, 20260000 + m * 100 + 1, v_budget, v_actual, ROUND(v_budget * 0.15, 2));
                INSERT INTO spms_relation VALUES ('COST', v_id, 'COST_PROJECT', 'PROJECT', p.project_id);
            END;
        END LOOP;
    END LOOP;
    COMMIT;
END;
/

-- ---------------------------------------------------------------- HSE 事件
BEGIN
    FOR p IN (SELECT project_id, ROWNUM AS seq FROM spms_dw_project ORDER BY project_id) LOOP
        FOR k IN 1 .. 3 LOOP
            DECLARE
                v_id VARCHAR2(32) := 'HSE' || p.seq || k;
                v_epc VARCHAR2(32);
            BEGIN
                SELECT MIN(contractor_id) INTO v_epc
                  FROM spms_dw_contractor WHERE contractor_type = '施工';
                INSERT INTO spms_dw_hse_event (event_id, date_id, event_type, severity, lost_days, man_hours)
                VALUES (v_id, 20260705 + k * 20,
                        CASE MOD(k, 3) WHEN 0 THEN '安全事故' WHEN 1 THEN '违章' ELSE '未遂' END,
                        CASE MOD(k, 3) WHEN 0 THEN '一般' WHEN 1 THEN '轻微' ELSE '轻微' END,
                        CASE MOD(k, 3) WHEN 0 THEN 3 ELSE 0 END,
                        24000 + k * 1000);
                INSERT INTO spms_relation VALUES ('EVENT', v_id, 'EVENT_PROJECT', 'PROJECT', p.project_id);
                INSERT INTO spms_relation VALUES ('EVENT', v_id, 'EVENT_CONTRACTOR', 'CONTRACTOR', v_epc);
            END;
        END LOOP;
    END LOOP;
    COMMIT;
END;
/

-- ---------------------------------------------------------------- 材料到货
BEGIN
    FOR p IN (SELECT project_id, ROWNUM AS seq FROM spms_dw_project ORDER BY project_id) LOOP
        FOR k IN 1 .. 4 LOOP
            DECLARE
                v_id VARCHAR2(32) := 'MD' || p.seq || k;
                v_plan NUMBER(8) := 20260710 + k * 15;
                v_actual NUMBER(8) := 20260710 + k * 15 + CASE WHEN MOD(k + p.seq, 2) = 0 THEN 5 ELSE -3 END;
            BEGIN
                INSERT INTO spms_dw_material_delivery (delivery_id, date_id, material_name, plan_qty, actual_qty,
                                                      unit, plan_date, actual_date)
                VALUES (v_id, v_plan,
                        CASE k WHEN 1 THEN '管道' WHEN 2 THEN '钢材' WHEN 3 THEN '设备' ELSE '电缆' END,
                        100 + k * 20, 100 + k * 20 - MOD(k, 2) * 5,
                        CASE k WHEN 1 THEN '吨' WHEN 2 THEN '吨' WHEN 3 THEN '台' ELSE '米' END,
                        v_plan, v_actual);
                INSERT INTO spms_relation VALUES ('MATERIAL', v_id, 'MATERIAL_PROJECT', 'PROJECT', p.project_id);
            END;
        END LOOP;
    END LOOP;
    COMMIT;
END;
/

-- ---------------------------------------------------------------- 校验
SELECT 'project' AS obj, COUNT(*) AS cnt FROM spms_dw_project
UNION ALL SELECT 'contractor', COUNT(*) FROM spms_dw_contractor
UNION ALL SELECT 'date', COUNT(*) FROM spms_dw_date
UNION ALL SELECT 'construction_daily', COUNT(*) FROM spms_dw_fact_construction_daily
UNION ALL SELECT 'project_plan', COUNT(*) FROM spms_dw_project_plan
UNION ALL SELECT 'quality_inspection', COUNT(*) FROM spms_dw_quality_inspection
UNION ALL SELECT 'ncr', COUNT(*) FROM spms_dw_ncr
UNION ALL SELECT 'design_delivery', COUNT(*) FROM spms_dw_design_delivery
UNION ALL SELECT 'design_change', COUNT(*) FROM spms_dw_design_change
UNION ALL SELECT 'cost_monthly', COUNT(*) FROM spms_dw_cost_monthly
UNION ALL SELECT 'hse_event', COUNT(*) FROM spms_dw_hse_event
UNION ALL SELECT 'material_delivery', COUNT(*) FROM spms_dw_material_delivery
UNION ALL SELECT 'relation', COUNT(*) FROM spms_relation;
