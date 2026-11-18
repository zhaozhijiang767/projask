"""Redis 连接、键规范、就绪探针。"""
from __future__ import annotations

import pytest

from app.core.errors import StateUnavailable
from app.core.readiness import Readiness
from app.state.redis import RedisState


def test_client_raises_before_connect():
    """未连接时必须显式报错，而不是返回 None 让调用方各自判断。"""
    with pytest.raises(StateUnavailable):
        _ = RedisState().client


def test_key_uses_configured_prefix():
    from app.core.config import settings

    state = RedisState()
    assert state.key("sess", "abc") == f"{settings.redis.key_prefix}:sess:abc"


async def test_ping_false_when_disconnected():
    assert await RedisState().ping() is False


async def test_connect_and_ping(monkeypatch):
    import fakeredis.aioredis

    fake = fakeredis.aioredis.FakeRedis(decode_responses=True)
    monkeypatch.setattr("app.state.redis.from_url", lambda *a, **k: fake)
    state = RedisState()
    await state.connect()
    assert await state.ping() is True
    await state.close()
    assert state.connected is False


async def test_readiness_reports_failure():
    readiness = Readiness()

    async def broken():
        raise RuntimeError("boom")

    async def ok():
        return True, "ok"

    readiness.register("redis", ok)
    readiness.register("oracle", broken)
    snapshot = await readiness.snapshot()
    assert snapshot["ready"] is False
    assert snapshot["dependencies"]["oracle"]["ok"] is False
    assert "boom" in snapshot["dependencies"]["oracle"]["detail"]


async def test_readiness_warning_does_not_block():
    readiness = Readiness()

    async def ok():
        return True, "ok"

    readiness.register("redis", ok)
    readiness.warn("MongoDB 不可用，历史不持久化")
    snapshot = await readiness.snapshot()
    assert snapshot["ready"] is True
    assert snapshot["warnings"] == ["MongoDB 不可用，历史不持久化"]