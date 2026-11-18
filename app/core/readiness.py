"""就绪状态聚合。

/health 只证明"进程活着"，/ready 才决定"能不能接流量"。两者必须分开：
进程活着但 Redis 断了，继续接流量只会把错误放大。
"""
from __future__ import annotations

import asyncio
from typing import Awaitable, Callable

Check = Callable[[], Awaitable[tuple[bool, str]]]


class Readiness:
    def __init__(self) -> None:
        self._checks: dict[str, Check] = {}
        self._warnings: list[str] = []

    def register(self, name: str, check: Check) -> None:
        self._checks[name] = check

    def warn(self, message: str) -> None:
        """非致命问题（例如 MongoDB 不可用导致历史不持久化）。"""
        self._warnings.append(message)

    def clear_warnings(self) -> None:
        self._warnings.clear()

    async def snapshot(self) -> dict:
        names = list(self._checks)
        results = await asyncio.gather(
            *(self._checks[name]() for name in names), return_exceptions=True
        )
        dependencies: dict[str, dict] = {}
        ready = True
        for name, result in zip(names, results):
            if isinstance(result, Exception):
                ok, detail = False, f"{type(result).__name__}: {result}"
            else:
                ok, detail = result
            dependencies[name] = {"ok": ok, "detail": detail}
            ready = ready and ok
        return {
            "ready": ready,
            "dependencies": dependencies,
            "warnings": list(self._warnings),
        }


readiness = Readiness()


async def check_redis() -> tuple[bool, str]:
    from app.state.redis import redis_state

    ok = await redis_state.ping()
    return ok, "ok" if ok else "ping 失败"