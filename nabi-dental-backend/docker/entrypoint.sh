#!/bin/sh
set -e

mkdir -p /app/uploads/xrays /app/uploads/avatars
if [ "$(id -u)" = "0" ]; then
  chown -R app:app /app/uploads 2>/dev/null || true
fi

if [ "${SKIP_DB_SETUP:-0}" != "1" ]; then
  python -c "from app.core.config import database_target, settings; print('entrypoint db', database_target(settings.DATABASE_URL), flush=True)"
  alembic upgrade head
  python -m app.db.seed
fi

if [ "$#" -gt 0 ]; then
  exec "$@"
fi

exec uvicorn app.main:app --host 0.0.0.0 --port "${PORT:-8000}"
