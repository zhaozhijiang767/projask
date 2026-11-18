from __future__ import annotations

import sys
from pathlib import Path
from time import perf_counter

import oracledb

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.core.config import settings


class DatabaseConnectionTest:
    def run(self) -> bool:
        targets = (
            ("元数据库", settings.db_meta),
            ("数仓", settings.db_dw),
            ("数仓只读账号", settings.db_dw_reader),
        )
        passed = 0
        sql = "SELECT 1, USER, SYS_CONTEXT('USERENV', 'SERVICE_NAME') FROM DUAL"

        for name, config in targets:
            print(f"\n--- {name} ---", flush=True)
            if config is None or not config.user or not config.password:
                print("[失败] 账号或密码未配置，请检查项目根目录的 .env。")
                continue

            print(f"地址：{config.host}:{config.port}，服务：{config.service_name}，用户：{config.user}")
            started = perf_counter()
            try:
                with oracledb.connect(
                    user=config.user,
                    password=config.password,
                    host=config.host,
                    port=config.port,
                    service_name=config.service_name,
                    tcp_connect_timeout=5,
                    retry_count=0,
                ) as connection:
                    connection.call_timeout = 8000
                    with connection.cursor() as cursor:
                        cursor.execute(sql)
                        row = cursor.fetchone()

                print(f"[成功] 登录及查询通过，耗时 {perf_counter() - started:.2f} 秒")
                print(f"SQL：{sql}")
                print(f"结果：{row[0]}，当前用户：{row[1]}，当前服务：{row[2]}")
                passed += 1
            except Exception as exc:
                error = str(exc).replace(config.password, "[已隐藏]")
                print(f"[失败] {type(exc).__name__}：{error}")

        print(f"\n数据库测试结果：{passed}/{len(targets)} 通过")
        return passed == len(targets)


def main() -> None:
    success = DatabaseConnectionTest().run()
    raise SystemExit(0 if success else 1)


if __name__ == "__main__":
    main()
