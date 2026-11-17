#!/usr/bin/env bash
# 一次性初始化数据库：建用户 → 建表 → 导示例数据 → 建只读账号
#
# 用法（在项目根目录）：
#   bash oracle/init_db.sh
#
# 为什么需要它：gvenzl 镜像的 /opt/oracle/scripts/setup 自动执行并不可靠
# （本机实测：全新卷初始化时日志里没有 Executing 记录，脚本根本没跑）。
# 与其赌它，不如显式执行一次——脚本本身都是幂等的。
set -euo pipefail
cd "$(dirname "$0")/.."

# 等数据库真的可连接再动手。
# 踩过的坑：容器刚起、healthcheck 已经 green，但 PDB 还在建，
# 这时执行脚本会写进一个随后被重建的库，白忙一场。
echo "==> 等待数据库就绪"
ready=0
for _ in $(seq 1 60); do
    # 用镜像自带的 healthcheck.sh：它内部会真正连一次库，
    # 比自己拼 sqlplus 探针可靠（v$instance 里的 $ 容易被内层 shell 吃掉）
    if docker compose exec -T oracle healthcheck.sh >/dev/null 2>&1; then
        ready=1
        echo "    就绪"
        break
    fi
    sleep 5
done
if [ "$ready" != "1" ]; then
    echo "数据库 5 分钟内未就绪，检查：docker compose logs oracle" >&2
    exit 1
fi

for f in 00_users.sql 01_schema.sql 02_dw_data.sql 04_readonly_user.sql; do
    echo "==> $f"
    docker compose exec -T oracle bash -lc "sqlplus -s / as sysdba <<SQL
@/opt/oracle/scripts/setup/${f}
exit
SQL"
done

echo "==> 校验"
docker compose exec -T oracle bash -lc 'sqlplus -s / as sysdba <<SQL
set heading off feedback off pagesize 0
alter session set container=SPMSUAT;
select count(*) from dw.spms_dim_project;
select count(*) from dw.spms_fact_construction_daily;
select count(*) from dw.spms_relation;
exit
SQL'
echo "==> 期望：3 / 366 / 912"
