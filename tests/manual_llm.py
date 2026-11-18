from __future__ import annotations

import sys
from pathlib import Path
from time import perf_counter

from openai import OpenAI

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.core.config import settings


class LLMConnectionTest:
    def run(self) -> bool:
        config = settings.llm
        if not config.api_key or not config.base_url or not config.model_name:
            print("[失败] 请检查项目根目录 .env 中的 LLM Key、接口地址和主模型名称。")
            return False

        targets = [("主模型", config.model_name)]
        if config.fast_model_name and config.fast_model_name != config.model_name:
            targets.append(("快速模型", config.fast_model_name))

        question = "请只回复：连接成功"
        passed = 0
        print(f"接口地址：{config.base_url}")
        print(f"测试问题：{question}")

        with OpenAI(
            api_key=config.api_key,
            base_url=config.base_url,
            timeout=config.request_timeout,
            max_retries=0,
        ) as client:
            for name, model in targets:
                print(f"\n--- {name}：{model} ---", flush=True)
                started = perf_counter()
                try:
                    response = client.chat.completions.create(
                        model=model,
                        messages=[{"role": "user", "content": question}],
                        temperature=config.temperature,
                        max_tokens=256,
                    )
                    choice = response.choices[0] if response.choices else None
                    content = choice.message.content if choice else None
                    if not content or not content.strip():
                        reason = choice.finish_reason if choice else "无候选回复"
                        print(f"[失败] 请求已返回，但没有文本输出，结束原因：{reason}")
                        continue

                    print(f"[成功] 收到实际回复，耗时 {perf_counter() - started:.2f} 秒")
                    print(f"模型输出：{content.strip()}")
                    if response.usage:
                        print(f"消耗 token：{response.usage.total_tokens}")
                    passed += 1
                except Exception as exc:
                    error = str(exc).replace(config.api_key, "[已隐藏]")
                    print(f"[失败] {type(exc).__name__}：{error}")

        print(f"\n大模型测试结果：{passed}/{len(targets)} 通过")
        return passed == len(targets)


def main() -> None:
    success = LLMConnectionTest().run()
    raise SystemExit(0 if success else 1)


if __name__ == "__main__":
    main()
