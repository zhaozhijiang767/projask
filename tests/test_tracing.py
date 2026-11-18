"""trace 事件：结构正确、异常路径不吞错、埋点失败不影响主流程。"""
from __future__ import annotations

import pytest

from app.core import tracing


class _FakeChain:
    def __init__(self, result=None, error: Exception | None = None):
        self._result = result
        self._error = error

    async def ainvoke(self, inputs, config=None):
        if self._error:
            raise self._error
        return self._result


async def test_llm_trace_emits_success(monkeypatch):
    events: list[dict] = []
    token = tracing._writer_ctx.set(events.append)
    try:
        await tracing.ainvoke_llm(_FakeChain("ok"), {}, "generate_sql")
    finally:
        tracing._writer_ctx.reset(token)

    assert len(events) == 1
    event = events[0]
    assert event["scope"] == "llm"
    assert event["name"] == "generate_sql"
    assert event["status"] == "success"
    assert event["elapsed_ms"] >= 0


async def test_llm_trace_emits_error_and_reraises():
    events: list[dict] = []
    token = tracing._writer_ctx.set(events.append)
    try:
        with pytest.raises(RuntimeError):
            await tracing.ainvoke_llm(_FakeChain(error=RuntimeError("boom")), {}, "generate_sql")
    finally:
        tracing._writer_ctx.reset(token)

    assert events[0]["status"] == "error"
    assert "boom" in events[0]["error"]


async def test_emit_without_writer_is_silent():
    """没有 writer（例如离线脚本）时埋点不能抛异常。"""
    tracing._emit({"type": "trace"})


async def test_traced_node_wraps_and_emits():
    events: list[dict] = []

    class _Runtime:
        stream_writer = staticmethod(events.append)

    @tracing.traced_node
    async def sample_node(state, runtime):
        return {"ok": True}

    result = await sample_node({}, _Runtime())
    assert result == {"ok": True}
    assert events[0]["scope"] == "node"
    assert events[0]["name"] == "sample_node"