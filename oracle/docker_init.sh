#!/usr/bin/env bash
# 容器内执行：首次初始化数据库；已初始化则跳过（避免每次 up 都清空数据）
set -eu

DSN="sys/${ORACLE_PASSWORD}@oracle:1521/${ORACLE_DATABASE}"

run_sql() {
    sqlplus -s "$DSN" as sysdba <<SQL
set heading off feedback off pagesize 0
$1
exit
SQL
}

# 用 [:space:] 一次清掉空格/TAB/CR/LF：sqlplus 的输出带制表符，
# 只删空格和换行会得到 "\t0"，判断永远不等于 "0"。
existing=$(run_sql "select count(*) from dba_users where username='DW';" | tr -d '[:space:]')

if [ "$existing" = "1" ]; then
    echo "==> 已初始化（DW 用户存在），跳过"
    exit 0
fi
if [ "$existing" != "0" ]; then
    echo "==> 探测失败，sqlplus 输出：[$existing]" >&2
    exit 1
fi

for f in 00_users 01_schema 02_dw_data 04_readonly_user; do
    echo "==> ${f}.sql"
    sqlplus -s "$DSN" as sysdba @"/scripts/${f}.sql"
done
echo "==> 初始化完成"
