"""请求级上下文。"""
from contextvars import ContextVar

# 并发安全的 request_id；未进入请求时显示 "-"
request_id_ctx_var: ContextVar[str] = ContextVar("request_id", default="-")
