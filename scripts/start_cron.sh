#!/usr/bin/env bash
# Scheduler: seab cron-ajastuse ja käivitab metsateatiste töövoo.
# Käivitatakse compose.yml 'scheduler' teenusest: command: ["bash", "scripts/start_cron.sh"]
set -euo pipefail

CRON_EXPR="${PIPELINE_CRON:-0 6 * * *}"
RUN_ON_STARTUP="${RUN_ON_STARTUP:-true}"
ENV_FILE="/tmp/metsateatis_pipeline_env.sh"
CRON_FILE="/etc/cron.d/metsateatis-pipeline"

# Eemalda võimalikud ümbritsevad jutumärgid (nt kui .env-is on PIPELINE_CRON="0 6 * * *"),
# muidu jääb cron.d rida vigaseks ja töö ei käivitu.
CRON_EXPR="${CRON_EXPR%\"}"
CRON_EXPR="${CRON_EXPR#\"}"
CRON_EXPR="${CRON_EXPR%\'}"
CRON_EXPR="${CRON_EXPR#\'}"

# Kirjuta keskkonnamuutujad faili, mille cron-töö saab source'ida.
# Cron käivitab tööd minimaalse keskkonnaga, seega anname muutujad ise edasi.
write_export() {
    local name="$1"
    local value="${!name-}"
    printf "export %s=%q\n" "$name" "$value" >> "$ENV_FILE"
}

rm -f "$ENV_FILE"
for name in DB_HOST DB_PORT DB_USER DB_PASSWORD DB_NAME WFS_BASE_URL MAA_WFS_BASE_URL; do
    write_export "$name"
done

# Cron-töö väljund suunatakse PID 1 (cron -f) voogudesse, et see ilmuks 'docker logs'-i.
cat > "$CRON_FILE" <<EOF
SHELL=/bin/bash
$CRON_EXPR root . $ENV_FILE; cd /app && /usr/local/bin/python scripts/run_pipeline.py run-all >> /proc/1/fd/1 2>> /proc/1/fd/2
EOF

chmod 0644 "$CRON_FILE"
echo "Scheduler kasutab croni ajastust: $CRON_EXPR"

# Valikuline esmakäivitus. Kui see ebaõnnestub (nt WFS pole saadaval, DB veel valmis ei ole),
# logime vea, AGA ei katkesta skripti — cron peab ikkagi käima minema ja järgmisel korral uuesti proovima.
if [ "$RUN_ON_STARTUP" = "true" ]; then
    echo "Käivitan töövoo scheduler'i stardil."
    . "$ENV_FILE"
    cd /app
    if /usr/local/bin/python scripts/run_pipeline.py run-all; then
        echo "Esmakäivitus õnnestus."
    else
        echo "Esmakäivitus ebaõnnestus (väljumiskood $?). Cron jätkab ajakava järgi." >&2
    fi
fi

exec cron -f