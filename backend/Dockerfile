FROM python:3.11-slim-bookworm

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENV PYTHONUNBUFFERED=1

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=25s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')"

# Çok işçi: Python tek süreçte tek çekirdek kullanır. WEB_CONCURRENCY ile ayarlanır (2 çekirdek / 2-4 GB için 2;
# 4 çekirdek / 8 GB için 4). İşçiler arası paylaşılması gereken her şey (hız sınırı, kota, push imleci) Redis'te.
# --timeout-keep-alive nginx'in upstream keepalive süresinden (60 sn) uzun olmalı; kısa kalırsa nginx kapanmış
# bir bağlantıya istek yollar ve kullanıcı ara sıra 502 görür.
# --timeout-graceful-shutdown: deploy sırasında süren istekler (sohbet dahil) bitirilir, kesilmez.
CMD ["sh", "-c", "exec uvicorn main:app --host 0.0.0.0 --port 8000 --workers ${WEB_CONCURRENCY:-2} --timeout-keep-alive 75 --timeout-graceful-shutdown 25 --no-server-header"]
