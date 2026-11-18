"""可观测性埋点：节点耗时 + LLM 耗时与 token。

事件通过 LangGraph 的 stream_writer 直接进入 SSE 流，前端"执行详情"面板
消费的就是这些事件。埋点失败绝不影响主流程，因此所有写入都吞异常并记 debug。
"""
from __future__ import annotations

import time
from contextvars import ContextVar
from functools import wraps
from typing import Any, Callable

from langchain_core.callbacks import AsyncCallbackHandler

from app.core.log import logger

# 当前节点的 writer；ainvoke_llm 通过它把 LLM 事件写进同一条 SSE 流
_writer_ctx: ContextVar[Callable[[dict], Any] | None] = ContextVar(
    "trace_writer", default=None
)


def _emit(payload: dict) -> None:
    writer = _writer_ctx.get()
    if writer is None:
        return
    try:
        writer(payload)
    except Exception as exc:  # 埋点不能反向影响业务
        logger.debug(f"trace 事件写入失败：{exc}")


class _TokenUsage(AsyncCallbackHandler):
    """从回调里收集 token 用量，兼容 llm_output 与 usage_metadata 两种挂载位置。"""

    def __init__(self) -> None:
        self.input_tokens = 0
        self.output_tokens = 0
        self.total_tokens = 0
        self.model: str | None = None

    def _record(self, response: Any) -> None:
        output = getattr(response, "llm_output", None) or {}
        usage = output.get("token_usage") or output.get("usage") or {}
        self.model = output.get("model_name") or output.get("model") or self.model

        prompt = usage.get("prompt_tokens") or usage.get("input_tokens") or 0
        completion = usage.get("completion_tokens") or usage.get("output_tokens") or 0
        total = usage.get("total_tokens") or 0

        if not (prompt or completion or total):
            for group in getattr(response, "generations", []) or []:
                for generation in group:
                    meta = getattr(getattr(generation, "message", None), "usage_metadata", None) or {}
                    prompt = prompt or meta.get("input_tokens") or 0
                    completion = completion or meta.get("output_tokens") or 0
                    total = total or meta.get("total_tokens") or 0

        self.input_tokens += int(prompt or 0)
        self.output_tokens += int(completion or 0)
        self.total_tokens += int(total or (prompt or 0) + (completion or 0))

    async def on_chat_model_end(self, response: Any, **_: Any) -> None:
        self._record(response)

    async def on_llm_end(self, response: Any, **_: Any) -> None:
        self._record(response)


async def ainvoke_llm(chain, inputs: dict, name: str) -> Any:
    """统一模型调用入口：一次调用 = 一条 trace 事件。"""
    usage = _TokenUsage()
    started = time.perf_counter()
    try:
        result = await chain.ainvoke(inputs, config={"callbacks": [usage]})
    except Exception as exc:
        _emit({
            "type": "trace", "scope": "llm", "name": name, "status": "error",
            "elapsed_ms": round((time.perf_counter() - started) * 1000, 2),
            "error": str(exc)[:300],
        })
        raise

    elapsed_ms = round((time.perf_counter() - started) * 1000, 2)
    _emit({
        "type": "trace", "scope": "llm", "name": name, "status": "success",
        "elapsed_ms": elapsed_ms, "model": usage.model,
        "input_tokens": usage.input_tokens, "output_tokens": usage.output_tokens,
        "total_tokens": usage.total_tokens,
    })
    logger.info(
        f"LLM[{name}] {elapsed_ms}ms，token 入 {usage.input_tokens} / 出 {usage.output_tokens}"
    )
    return result


def traced_node(node: Callable) -> Callable:
    """节点耗时埋点：不改变节点签名，只多写一条 trace。"""

    @wraps(node)
    async def wrapper(state, runtime):
        token = _writer_ctx.set(runtime.stream_writer)
        started = time.perf_counter()
        try:
            result = await node(state, runtime)
        except Exception:
            _emit({
                "type": "trace", "scope": "node", "name": node.__name__,
                "status": "error",
                "elapsed_ms": round((time.perf_counter() - started) * 1000, 2),
            })
            raise
        else:
            _emit({
                "type": "trace", "scope": "node", "name": node.__name__,
                "status": "success",
                "elapsed_ms": round((time.perf_counter() - started) * 1000, 2),
            })
            return result
        finally:
            _writer_ctx.reset(token)

    return wrapper