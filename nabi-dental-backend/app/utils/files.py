import re

_UNSAFE = re.compile(r"[^A-Za-z0-9._-]+")


def safe_filename(name: str) -> str:
    cleaned = _UNSAFE.sub("_", name.strip().lower()).strip("._")
    return cleaned or "download"
