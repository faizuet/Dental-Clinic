#!/bin/sh
set -e

if [ "${SKIP_DB_SETUP:-0}" != "1" ]; then
  alembic upgrade head
  python -m app.db.seed
fi

if [ "$#" -gt 0 ]; then
  exec "$@"
fi

exec uvicorn app.main:app --host 0.0.0.0 --port "${PORT:-8000}"
