"""日志装配。

三类输出：
1. 控制台：开发时看；
2. app.log：全量运行日志；
3. audit.log：只收 logger.bind(audit=True) 的记录，一行一个 JSON，供审计归档。
"""
from __future__ import annotations

import sys

from loguru import logger

from app.core.config import PROJECT_ROOT, settings
from app.core.context import request_id_ctx_var

FORMAT = (
    "<green>{time:YYYY-MM-DD HH:mm:ss.SSS}</green> | "
    "<level>{level: <8}</level> | "
    "<magenta>rid={extra[request_id]}</magenta> | "
    "<cyan>{name}</cyan>:<cyan>{line}</cyan> - <level>{message}</level>"
)


def _inject_request_id(record: dict) -> None:
    record["extra"]["request_id"] = request_id_ctx_var.get()


logger.remove()
logger = logger.patch(_inject_request_id)

if settings.logging.console.enable:
    logger.add(sys.stdout, level=settings.logging.console.level, format=FORMAT)

if settings.logging.file.enable:
    log_dir = PROJECT_ROOT / settings.logging.file.path
    log_dir.mkdir(parents=True, exist_ok=True)
    common = {
        "rotation": settings.logging.file.rotation,
        "retention": settings.logging.file.retention,
        "encoding": "utf-8",
    }
    logger.add(log_dir / "app.log",
               level=settings.logging.file.level, format=FORMAT, **common)
    logger.add(
        log_dir / "audit.log",
        level="INFO",
        format="{time:YYYY-MM-DD HH:mm:ss.SSS} | {message}",
        filter=lambda record: bool(record["extra"].get("audit")),
        **common,
    )
