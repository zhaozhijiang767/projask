# 工程问数（ProjAsk）

工程建设项目管理领域的自然语言问数平台：把中文问句翻译成受控 SQL，跑在 Oracle 语义层视图上，以 SSE 流式返回进度、思考与结果。

> 构建过程见 `D:\项目文档\工程问数-从0到1构建全过程.md`（共 21 步）。本 README 只记录**动手时会踩的坑**，不重复文档内容。

## 环境

| 项 | 值 |
|---|---|
| Python | 3.12（`.python-version`） |
| 虚拟环境 | `.venv/`（已在项目内，勿提交） |
| 依赖唯一来源 | `requirements.txt` |

本机 `python` 命令指向 3.13，**重建环境必须显式指定版本**：

```bash
py -3.12 -m venv .venv
```

## 安装依赖

```bash
uv pip install -r requirements.txt
```

### 三条硬约定

1. **不要 `uv sync`**。`pyproject.toml` 的 `dependencies` 是空的（依赖唯一来源是 `requirements.txt`），`uv sync` 会按空依赖同步，把已装好的包全部卸掉。
2. **不要 `uv run`**。它会先做一次隐式 sync，后果同上。装包只走 `uv pip install`，运行只走激活后的 `python`。
3. **`uv pip` 只是更快的 pip**。它不读 `pyproject.toml`、不读锁文件，写进 venv 的结果和 `pip install` 等价。生产路径（Dockerfile、CI）用的就是 `pip install -r requirements.txt`，两边装的是同一份清单。

> 项目里刻意**没有** `uv.lock`。这个仓库不使用 uv 的项目模式，锁文件只会让 `uv run` 有机可乘。

## 运行测试

```bash
.venv/Scripts/python.exe -m pytest
```

- 第 2 步阶段：`no tests ran`，**退出码 5 是正常的**（表示配置与依赖装配无错，只是还没有用例）。
- `pytest.ini` 已设 `pythonpath = .`，测试文件里不要再写 `sys.path.append`。
- 所有 Redis 相关测试走 `fakeredis`，外部存储一律用替身，单测不连网。

Git Bash 下激活环境用 `source .venv/Scripts/activate`（文档里的 `Activate.ps1` 是 PowerShell 写法）。

## 目录

```text
app/      api / services / agent / core / state / store / prompt / scripts
conf/     业务域配置（app.yaml、meta_<域>.yaml、domain_<域>.yaml）
prompts/  提示词模板
oracle/   语义层 DDL 与数仓初始化脚本
eval/     评测集与跑批
tests/    与构建步骤一一对应的测试
web/      Vue 3 + Vite 前端
```

分层规则：`api → services → agent → store/state` 单向依赖，反向 import 视为缺陷。各包使用命名空间包，**不需要 `__init__.py`**。

## 进度

- [x] 第 2 步 项目初始化（依赖、pytest 配置、密钥模板、测试夹具）
- [ ] 第 3 步 配置层 —— 下一步
