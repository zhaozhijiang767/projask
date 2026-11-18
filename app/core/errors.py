"""错误码契约。全系统只在这里定义一次。"""
from __future__ import annotations


class AppError(Exception):
    """所有可预期业务异常的基类：带稳定的 code，前端据此展示文案。"""

    code = "APP_ERROR"

    def __init__(self, message: str, code: str | None = None) -> None:
        self.message = message
        if code:
            self.code = code
        super().__init__(message)


class StateUnavailable(AppError):
    """共享状态存储不可用（未连接 / 连接中断）。"""
    code = "STATE_UNAVAILABLE"


class QueryRejected(AppError):
    """输入闸门拒绝：注入、写操作、预测、过于笼统。"""
    code = "QUERY_REJECTED"


class ScopeDenied(AppError):
    """数据范围无法安全注入：失败关闭，绝不放行。"""
    code = "SCOPE_DENIED"


class SQLRejected(AppError):
    """SQL 未通过只读 / 白名单 / 语法校验。"""
    code = "SQL_INVALID"