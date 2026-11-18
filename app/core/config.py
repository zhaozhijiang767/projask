"""配置：一份 YAML + 显式环境变量覆盖 + 生产启动校验。

三条约束：
1. YAML 是唯一默认值来源，代码里不写死任何业务参数；
2. 环境变量只覆盖"机器相关"的字段（主机、口令、开关），清单显式列出；
3. 覆盖时按默认值的类型转换，避免把 "12345678" 这样的口令转成整数。
"""
from __future__ import annotations

import os
from pathlib import Path
from typing import Any, Literal

import yaml
from dotenv import load_dotenv
from pydantic import BaseModel, Field, ValidationError

PROJECT_ROOT = Path(__file__).resolve().parents[2]
CONFIG_PATH = PROJECT_ROOT / "conf" / "app.yaml"

# 本地开发从 .env 读密钥；已存在的系统环境变量优先
load_dotenv(PROJECT_ROOT / ".env", override=False)


class AppInfo(BaseModel):
    name: str = "工程问数"
    version: str = "2.0.0"
    environment: Literal["development", "production"] = "development"
    cors_origins: list[str] = Field(default_factory=list)


class FileLog(BaseModel):
    enable: bool = True
    level: str = "INFO"
    path: str = "logs"
    rotation: str = "10 MB"
    retention: str = "7 days"


class ConsoleLog(BaseModel):
    enable: bool = True
    level: str = "INFO"


class LoggingConfig(BaseModel):
    file: FileLog = Field(default_factory=FileLog)
    console: ConsoleLog = Field(default_factory=ConsoleLog)


class DBConfig(BaseModel):
    host: str = "localhost"
    port: int = 1521
    user: str = ""
    password: str = ""
    service_name: str = "SPMSUAT"

    def dsn(self) -> str:
        """SQLAlchemy 异步 DSN。

        注意：口令若含 @ : / 等字符必须先 URL 编码，否则会被当成 DSN 分隔符。
        生产建议用纯字母数字口令，或改用 `create_async_engine(..., connect_args=...)`。
        """
        return f"oracle+oracledb://{self.user}:{self.password}@{self.host}:{self.port}/?service_name={self.service_name}"


class QdrantConfig(BaseModel):
    host: str = "localhost"
    port: int = 6333
    embedding_size: int = 1024
    column_collection: str = "projask_column"
    metric_collection: str = "projask_metric"


class EmbeddingConfig(BaseModel):
    host: str = "localhost"
    port: int = 8081
    model: str = "BAAI/bge-large-zh-v1.5"

    @property
    def base_url(self) -> str:
        return f"http://{self.host}:{self.port}"


class ESConfig(BaseModel):
    host: str = "localhost"
    port: int = 9200
    index_name: str = "projask_value"

    @property
    def url(self) -> str:
        return f"http://{self.host}:{self.port}"


class MongoConfig(BaseModel):
    host: str = "localhost"
    port: int = 27017
    username: str = ""
    password: str = ""
    database: str = "projask"
    session_collection: str = "session_history"
    audit_collection: str = "audit_log"

    @property
    def url(self) -> str:
        auth = f"{self.username}:{self.password}@" if self.username else ""
        return f"mongodb://{auth}{self.host}:{self.port}"


class RedisConfig(BaseModel):
    """共享状态存储。没有 enabled 开关：连不上就是没就绪。"""
    host: str = "localhost"
    port: int = 6379
    db: int = 0
    password: str = ""
    key_prefix: str = "projask"

    @property
    def url(self) -> str:
        auth = f":{self.password}@" if self.password else ""
        return f"redis://{auth}{self.host}:{self.port}/{self.db}"


class LLMConfig(BaseModel):
    model_name: str = ""
    fast_model_name: str = ""
    api_key: str = ""
    base_url: str = ""
    temperature: float = 0.0
    seed: int = 42
    request_timeout: float = 40.0
    max_retries: int = 0
    thinking_budget: int = 1024
    fast_thinking_budget: int = 512
    context_token_budget: int = 8000


class ExpansionConfig(BaseModel):
    enable: bool = True
    max_keywords: int = 30
    embedding_batch_size: int = 32


class RecallConfig(BaseModel):
    score_threshold: float = 0.6
    limit: int = 5
    concurrency: int = 8


class FilterConfig(BaseModel):
    mode: Literal["auto", "always", "never"] = "auto"
    max_tables: int = 4
    max_columns: int = 60
    on_error: Literal["keep", "raise"] = "keep"


class AgentConfig(BaseModel):
    expansion: ExpansionConfig = Field(default_factory=ExpansionConfig)
    recall: RecallConfig = Field(default_factory=RecallConfig)
    filter: FilterConfig = Field(default_factory=FilterConfig)


class CacheTTL(BaseModel):
    keyword: int = 21600
    embedding: int = 86400
    db_info: int = 3600
    query_sql: int = 300
    negative: int = 60
    watermark: int = 900


class CacheConfig(BaseModel):
    ttl: CacheTTL = Field(default_factory=CacheTTL)


class ScopeConfig(BaseModel):
    mode: Literal["none", "unit", "project"] = "none"
    unit_projects: dict[str, list[str]] = Field(default_factory=dict)


class OIDCConfig(BaseModel):
    authorization_endpoint: str = ""
    token_endpoint: str = ""
    userinfo_endpoint: str = ""
    client_id: str = ""
    client_secret: str = ""
    scope: str = "openid profile email"
    redirect_uri: str = ""
    user_field: str = "preferred_username"
    name_field: str = "name"
    unit_field: str = "unit"


class CASConfig(BaseModel):
    login_url: str = ""
    validate_url: str = ""
    service_url: str = ""


class AuthConfig(BaseModel):
    mode: Literal["none", "local", "oidc", "cas"] = "none"
    cookie_secure: bool = False
    session_cookie: str = "projask_session"
    session_ttl_seconds: int = 28800
    admin_users: list[str] = Field(default_factory=list)
    scope: ScopeConfig = Field(default_factory=ScopeConfig)
    oidc: OIDCConfig = Field(default_factory=OIDCConfig)
    cas: CASConfig = Field(default_factory=CASConfig)


class RateLimitConfig(BaseModel):
    requests_per_minute: int = 30
    window_seconds: int = 60


class QueryConfig(BaseModel):
    timeout_seconds: float = 240.0
    history_limit: int = 6
    max_corrections: int = 1
    require_where_for_detail: bool = True
    max_question_chars: int = 2000


class Settings(BaseModel):
    app: AppInfo = Field(default_factory=AppInfo)
    logging: LoggingConfig = Field(default_factory=LoggingConfig)
    db_meta: DBConfig = Field(default_factory=DBConfig)
    db_dw: DBConfig = Field(default_factory=DBConfig)
    db_dw_reader: DBConfig | None = None
    qdrant: QdrantConfig = Field(default_factory=QdrantConfig)
    embedding: EmbeddingConfig = Field(default_factory=EmbeddingConfig)
    es: ESConfig = Field(default_factory=ESConfig)
    mongo: MongoConfig = Field(default_factory=MongoConfig)
    redis: RedisConfig = Field(default_factory=RedisConfig)
    llm: LLMConfig = Field(default_factory=LLMConfig)
    agent: AgentConfig = Field(default_factory=AgentConfig)
    cache: CacheConfig = Field(default_factory=CacheConfig)
    auth: AuthConfig = Field(default_factory=AuthConfig)
    rate_limit: RateLimitConfig = Field(default_factory=RateLimitConfig)
    query: QueryConfig = Field(default_factory=QueryConfig)

    # ------------------------------------------------------------------ 加载
    @classmethod
    def load(cls, path: Path | None = None) -> "Settings":
        raw = yaml.safe_load((path or CONFIG_PATH).read_text(encoding="utf-8")) or {}
        apply_env_overrides(raw)
        try:
            return cls.model_validate(raw)
        except ValidationError as exc:
            raise SystemExit(f"配置校验失败：\n{exc}") from exc

    # ------------------------------------------------------------------ 生产校验
    def validate_production(self) -> None:
        """生产环境的安全底线。缺一条就拒绝启动，而不是带病上线。"""
        if self.app.environment != "production":
            return

        problems: list[str] = []
        if self.auth.mode not in {"oidc", "cas"}:
            problems.append(
                "auth.mode 必须是 oidc 或 cas：local 模式按用户名直接建会话，"
                "任何人都能冒充 admin_users 里的账号"
            )
        if not self.auth.cookie_secure:
            problems.append("auth.cookie_secure 必须为 true（Cookie 只走 HTTPS）")
        if not self.llm.api_key or self.llm.api_key.startswith("sk-dev-"):
            problems.append("llm.api_key 未配置")
        if not self.db_meta.password or not self.db_dw.password:
            problems.append("数据库口令未配置")
        if self.db_dw_reader is None or not self.db_dw_reader.password:
            problems.append("db_dw_reader 未配置（问数必须走只读账号）")
        if self.auth.scope.mode == "none":
            problems.append("auth.scope.mode 不能是 none（否则所有用户可见全部项目）")
        if problems:
            raise SystemExit("生产环境配置不安全：\n  - " + "\n  - ".join(problems))


# ---------------------------------------------------------------------- 环境变量覆盖
# 只列"每台机器不同"的字段；业务参数一律走 YAML，避免环境变量成为第二套配置。
_ENV_FIELDS: dict[str, str] = {
    "app.environment": "PROJASK_ENV",
    "db_meta.host": "PROJASK_DB_META_HOST",
    "db_meta.user": "PROJASK_DB_META_USER",
    "db_meta.password": "PROJASK_DB_META_PASSWORD",
    "db_dw.host": "PROJASK_DB_DW_HOST",
    "db_dw.user": "PROJASK_DB_DW_USER",
    "db_dw.password": "PROJASK_DB_DW_PASSWORD",
    "db_dw_reader.host": "PROJASK_DB_DW_READER_HOST",
    "db_dw_reader.user": "PROJASK_DB_DW_READER_USER",
    "db_dw_reader.password": "PROJASK_DB_DW_READER_PASSWORD",
    "qdrant.host": "PROJASK_QDRANT_HOST",
    "embedding.host": "PROJASK_EMBEDDING_HOST",
    "es.host": "PROJASK_ES_HOST",
    "mongo.host": "PROJASK_MONGO_HOST",
    "redis.host": "PROJASK_REDIS_HOST",
    "redis.password": "PROJASK_REDIS_PASSWORD",
    "llm.api_key": "PROJASK_LLM_API_KEY",
    "llm.base_url": "PROJASK_LLM_BASE_URL",
    "llm.model_name": "PROJASK_LLM_MODEL_NAME",
    "llm.fast_model_name": "PROJASK_LLM_FAST_MODEL_NAME",
    "auth.mode": "PROJASK_AUTH_MODE",
    "auth.cookie_secure": "PROJASK_COOKIE_SECURE",
    "auth.scope.mode": "PROJASK_SCOPE_MODE",
}


def _coerce(current: Any, value: str) -> Any:
    """按默认值的类型转换，不靠字符串猜。"""
    if isinstance(current, bool):
        return value.strip().lower() in {"1", "true", "yes", "on"}
    if isinstance(current, int) and not isinstance(current, bool):
        return int(value)
    if isinstance(current, float):
        return float(value)
    return value


def apply_env_overrides(raw: dict) -> None:
    """就地覆盖 raw，缺失的中间层自动补齐。"""
    for dotted, env_name in _ENV_FIELDS.items():
        value = os.getenv(env_name)
        if value is None or value == "":
            continue
        keys = dotted.split(".")
        node = raw
        for key in keys[:-1]:
            node = node.setdefault(key, {})
        if not isinstance(node, dict):
            continue
        node[keys[-1]] = _coerce(node.get(keys[-1]), value)


settings = Settings.load()