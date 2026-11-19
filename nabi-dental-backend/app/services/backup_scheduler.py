from __future__ import annotations

import logging
import os
import threading
import time

from app.core.config import settings
from app.core.exceptions import AppError
from app.services.backup_service import BackupService, _public_backup_message

logger = logging.getLogger("nabi.backup")


def start_backup_scheduler() -> None:
    if os.environ.get("DISABLE_BACKUP_SCHEDULER") == "1":
        return
    if settings.APP_ENV == "test":
        return
    database = settings.DATABASE_URL
    if "nabi_dental_test" in database or "nabi_backup_drill" in database:
        return
    thread = threading.Thread(target=_loop, name="nabi-backup", daemon=True)
    thread.start()


def _loop() -> None:
    time.sleep(45)
    while True:
        wait = 3600
        try:
            service = BackupService()
            if service.needs_scheduled_backup():
                service.create_archive()
                logger.info("Automatic clinic backup saved")
            wait = service.seconds_until_due()
        except AppError as exc:
            logger.warning("Automatic clinic backup failed: %s", exc.message)
            _remember_failure(exc.message)
            wait = 3600
        except Exception as exc:
            logger.exception("Automatic clinic backup failed")
            _remember_failure(str(exc))
            wait = 3600
        time.sleep(max(60, wait))


def _remember_failure(message: str) -> None:
    try:
        BackupService().record_failure(_public_backup_message(message))
    except Exception:
        logger.exception("Could not record the backup failure")
