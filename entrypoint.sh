#!/bin/sh
# Container entrypoint.
#
#   runserver (default)  start the API; refuses to start without a strong JWT_SECRET
#   init-data            build data/ruc.db unless it already exists (one-shot job)
#   build | download | token ...   pass-through to manage.py
#   anything else        executed as-is
set -eu

DATA_DIR="/code/data"
RUC_DB="$DATA_DIR/ruc.db"
MIN_SECRET_LENGTH=32
MIN_RUC_ROWS=1000000

runserver() {
    secret="${JWT_SECRET:-}"
    if [ -z "$secret" ]; then
        echo "ERROR: JWT_SECRET is not set. Refusing to start." >&2
        echo "Generate one with: openssl rand -hex 32" >&2
        exit 1
    fi
    if [ "${#secret}" -lt "$MIN_SECRET_LENGTH" ]; then
        echo "ERROR: JWT_SECRET must be at least $MIN_SECRET_LENGTH characters long. Refusing to start." >&2
        exit 1
    fi
    unset secret
    exec python manage.py runserver --host 0.0.0.0 --port "${PORT:-3000}"
}

init_data() {
    if [ -s "$RUC_DB" ]; then
        echo "ruc.db present, skipping build"
        exit 0
    fi

    echo "ruc.db missing or empty, building it from DNIT data (this can take several minutes)..."
    mkdir -p "$DATA_DIR/tmp"
    python manage.py build

    if [ ! -s "$RUC_DB" ]; then
        echo "ERROR: build finished but $RUC_DB was not created." >&2
        exit 1
    fi

    if ! python -c "
import sqlite3, sys
conn = sqlite3.connect('file:$RUC_DB?mode=ro', uri=True)
rows = conn.execute('SELECT COUNT(*) FROM ruc').fetchone()[0]
print('ruc rows: %d' % rows)
sys.exit(0 if rows > $MIN_RUC_ROWS else 1)
"; then
        echo "ERROR: ruc table is missing or has fewer than $MIN_RUC_ROWS rows." >&2
        exit 1
    fi
    echo "ruc.db built successfully"
}

if [ "$#" -eq 0 ]; then
    runserver
fi

case "$1" in
    runserver)
        runserver
        ;;
    init-data)
        init_data
        ;;
    build | download | token)
        exec python manage.py "$@"
        ;;
    *)
        exec "$@"
        ;;
esac
