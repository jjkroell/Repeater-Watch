from __future__ import annotations

import logging
import threading
import urllib.request

import config

logger = logging.getLogger(__name__)


def send_notification(title: str, message: str, priority: str = "default") -> None:
    if not config.NTFY_URL:
        return

    def _post():
        try:
            req = urllib.request.Request(
                config.NTFY_URL,
                data=message.encode(),
                headers={
                    "Title": title,
                    "Priority": priority,
                    "Tags": "satellite_antenna",
                },
                method="POST",
            )
            urllib.request.urlopen(req, timeout=10)
            logger.info("ntfy notification sent: %s", title)
        except Exception as e:
            logger.warning("ntfy notification failed: %s", e)

    threading.Thread(target=_post, daemon=True).start()
