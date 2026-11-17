-- 执行身份：SYS，连到 PDB
-- sqlplus sys/Spms123456@localhost:1521/SPMSUAT as sysdba
ALTER SESSION SET CONTAINER = SPMSUAT;

-- 幂等：先删用户再建（CASCADE 会一并删掉其下的表和视图），
-- 这样重复执行 init_db.sh 不会报 ORA-01920。
-- 注意：有活跃连接时删用户会报 ORA-01940，先停应用再执行。
BEGIN
    FOR u IN (SELECT username FROM all_users
               WHERE username IN ('META', 'DW', 'DW_READER')) LOOP
        EXECUTE IMMEDIATE 'DROP USER ' || u.username || ' CASCADE';
    END LOOP;
END;
/

-- meta：元数据（表/字段/指标/关联/取值）
CREATE USER meta IDENTIFIED BY "Spms123456" DEFAULT TABLESPACE users QUOTA UNLIMITED ON users;
-- dw：数仓（物理表 + 语义视图）
CREATE USER dw IDENTIFIED BY "Spms123456" DEFAULT TABLESPACE users QUOTA UNLIMITED ON users;

GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW TO meta;
GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW TO dw;
