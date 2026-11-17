"""全局测试夹具。

三条约定：
1. 所有 Redis 相关测试走 fakeredis，不依赖本机服务；
2. 外部存储（Oracle / Qdrant / ES / Mongo）一律用替身，单测不连网；
3. 夹具内部惰性导入：conftest 在第 2 步创建，此时业务模块还不存在，
   顶层 import 会让 `pytest` 在早期步骤直接收集失败。
"""
from __future__ import annotations

import pytest


@pytest.fixture
async def fake_redis(monkeypatch):
    """把全局 Redis 客户端替换成 fakeredis。"""
    import fakeredis.aioredis

    from app.state import redis as redis_state

    client = fakeredis.aioredis.FakeRedis(decode_responses=True)
    monkeypatch.setattr(redis_state.redis_state, "_client", client, raising=False)
    yield client
    await client.flushall()
    await client.aclose()


@pytest.fixture
def scope_all():
    """不受限的数据范围（本地调试 / 管理员）。"""
    from app.core.scope import DataScope

    return DataScope(unrestricted=True)


@pytest.fixture
def scope_p2025():
    """只可见一个项目的数据范围，用于验证 scope 注入。"""
    from app.core.scope import DataScope

    return DataScope(user_id="u1", user_name="张三", project_ids=("P2025-01",))