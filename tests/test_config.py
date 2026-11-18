"""配置层测试：覆盖顺序、类型转换、生产校验。"""
from __future__ import annotations

import pytest
import yaml
from dotenv import load_dotenv

from app.core.config import Settings, _ENV_FIELDS, apply_env_overrides


@pytest.fixture(autouse=True)
def clear_config_env(monkeypatch):
    for env_name in _ENV_FIELDS.values():
        monkeypatch.delenv(env_name, raising=False)


def _raw() -> dict:
    return {
        "app": {"environment": "development"},
        "auth": {"cookie_secure": False, "scope": {"mode": "none"}},
        "llm": {"api_key": ""},
        "db_meta": {"password": ""},
        "db_dw": {"password": ""},
        "redis": {"host": "localhost"},
    }


def test_env_overrides_string_field(monkeypatch):
    monkeypatch.setenv("PROJASK_REDIS_HOST", "redis-prod")
    raw = _raw()
    apply_env_overrides(raw)
    assert raw["redis"]["host"] == "redis-prod"


def test_env_overrides_bool_by_default_type(monkeypatch):
    """字符串 "true" 必须转成布尔，而不是留下字符串。"""
    monkeypatch.setenv("PROJASK_COOKIE_SECURE", "true")
    raw = _raw()
    apply_env_overrides(raw)
    assert raw["auth"]["cookie_secure"] is True


def test_env_does_not_cast_password_to_number(monkeypatch):
    """纯数字口令必须保持字符串，否则会丢前导零、破坏登录。"""
    monkeypatch.setenv("PROJASK_DB_META_PASSWORD", "00123456")
    raw = _raw()
    apply_env_overrides(raw)
    assert raw["db_meta"]["password"] == "00123456"


def test_empty_env_is_ignored(monkeypatch):
    """空环境变量不应覆盖 YAML 里的默认值。"""
    monkeypatch.setenv("PROJASK_REDIS_HOST", "")
    raw = _raw()
    apply_env_overrides(raw)
    assert raw["redis"]["host"] == "localhost"


def test_production_rejects_insecure_defaults():
    settings = Settings.model_validate({
        "app": {"environment": "production"},
        "auth": {"mode": "none", "cookie_secure": False, "scope": {"mode": "none"}},
        "llm": {"api_key": "sk-dev-placeholder"},
        "db_meta": {"password": ""},
        "db_dw": {"password": ""},
    })
    with pytest.raises(SystemExit) as exc:
        settings.validate_production()
    message = str(exc.value)
    assert "auth.mode" in message
    assert "db_dw_reader" in message


def test_development_skips_production_guard():
    settings = Settings.model_validate({"app": {"environment": "development"}})
    settings.validate_production()  # 不抛异常即通过


@pytest.mark.parametrize("prefer_system", [False, True])
@pytest.mark.parametrize("section, field, env_name, value", [
    ("db_meta", "user", "PROJASK_DB_META_USER", "meta-local"),
    ("db_meta", "password", "PROJASK_DB_META_PASSWORD", "00123456"),
    ("db_dw", "user", "PROJASK_DB_DW_USER", "dw-local"),
    ("db_dw", "password", "PROJASK_DB_DW_PASSWORD", "00123457"),
    ("db_dw_reader", "user", "PROJASK_DB_DW_READER_USER", "reader-local"),
    ("db_dw_reader", "password", "PROJASK_DB_DW_READER_PASSWORD", "00123458"),
    ("llm", "api_key", "PROJASK_LLM_API_KEY", "test-key"),
    ("llm", "base_url", "PROJASK_LLM_BASE_URL", "http://localhost:8080/v1"),
    ("llm", "model_name", "PROJASK_LLM_MODEL_NAME", "test-main-model"),
    ("llm", "fast_model_name", "PROJASK_LLM_FAST_MODEL_NAME", "test-fast-model"),
])
def test_dotenv_credentials_and_system_priority(
    tmp_path, monkeypatch, section, field, env_name, value, prefer_system,
):
    raw = _raw()
    raw.setdefault(section, {})[field] = "yaml-value"
    config_path = tmp_path / "app.yaml"
    config_path.write_text(yaml.safe_dump(raw), encoding="utf-8")
    env_path = tmp_path / ".env"
    env_path.write_text(f'{env_name}="{value}"\n', encoding="utf-8")
    monkeypatch.setenv(env_name, "system-value")
    if not prefer_system:
        monkeypatch.delenv(env_name)

    load_dotenv(env_path, override=False)
    settings = Settings.load(config_path)

    expected = "system-value" if prefer_system else value
    assert getattr(getattr(settings, section), field) == expected
