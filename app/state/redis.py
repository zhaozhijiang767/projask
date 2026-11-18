"""Redis 连接与键规范。

设计取舍：**不做进程内降级**。
v1 每个组件都写"先试 Redis，失败回退内存"，结果是同一份语义两套实现、
两套测试、故障时行为不确定。v2 只保留一条路径：
- 启动期连不上 → 进程退出；
- 运行期断开 → 请求返回 STATE_UNAVAILABLE，就绪探针转 503。
"""
from __future__ import annotations

from redis.asyncio import Redis, from_url

from app.core.config import settings
from app.core.errors import StateUnavailable


class RedisState:
    def __init__(self) -> None:
        self._client: Redis | None = None

    async def connect(self) -> None:
        """启动期调用一次；失败直接抛出，由 lifespan 决定退出。"""
        client = from_url(
            settings.redis.url,
            decode_responses=True,
            health_check_interval=30,
            socket_connect_timeout=3,
            socket_timeout=3,
        )
        await client.ping()
        self._client = client

    @property
    def client(self) -> Redis:
        if self._client is None:
            raise StateUnavailable("Redis 未连接")
        return self._client

    @property
    def connected(self) -> bool:
        return self._client is not None

    def key(self, *parts: str) -> str:
        """所有键只在这里生成，组件禁止自己拼字符串。"""
        prefix = settings.redis.key_prefix
        return ":".join([prefix, *(str(part) for part in parts)])

    async def ping(self) -> bool:
        if self._client is None:
            return False
        try:
            return bool(await self._client.ping())
        except Exception:
            return False

    async def close(self) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None


redis_state = RedisState()