FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# 先装依赖，利用层缓存：只有 requirements 变化时才重新装
COPY requirements.txt .
RUN pip install -r requirements.txt

COPY app ./app
COPY conf ./conf
COPY prompts ./prompts
COPY oracle ./oracle
COPY eval ./eval
COPY main.py ./

# 非 root 运行
RUN useradd -m -u 10001 projask && chown -R projask:projask /app
USER projask

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s --start-period=20s \
  CMD python -c "import urllib.request;urllib.request.urlopen('http://127.0.0.1:8000/api/health')"

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]