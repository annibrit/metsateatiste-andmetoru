FROM python:3.13-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends cron postgresql-client \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY scripts/requirements.txt /tmp/scripts-requirements.txt
COPY dashboard/requirements.txt /tmp/dashboard-requirements.txt

RUN pip install --no-cache-dir -r /tmp/scripts-requirements.txt \
    && pip install --no-cache-dir -r /tmp/dashboard-requirements.txt

CMD ["sleep", "infinity"]