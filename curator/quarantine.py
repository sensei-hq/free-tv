"""Quarantine state: grace repeated failures, quarantine, auto-restore."""
import json
import os
from dataclasses import dataclass, field
from datetime import datetime, timezone


def _now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


@dataclass
class StateEntry:
    fails: int = 0
    reason: str = ""
    last_ok: str = ""
    last_check: str = ""
    extra: dict = field(default_factory=dict)

    @property
    def quarantined(self):
        return self._quarantined

    _quarantined: bool = False

    def to_dict(self):
        return {
            "fails": self.fails,
            "reason": self.reason,
            "last_ok": self.last_ok,
            "last_check": self.last_check,
            "quarantined": self._quarantined,
            **self.extra,
        }


class Tracker:
    def __init__(self, max_fails=2, entries=None):
        self.max_fails = max_fails
        self.entries = entries or {}

    @classmethod
    def load(cls, path, max_fails=2):
        try:
            with open(path, encoding="utf-8") as fh:
                raw = json.load(fh)
        except (OSError, ValueError):
            return cls(max_fails=max_fails)
        entries = {}
        for url, data in raw.items():
            entries[url] = StateEntry(
                fails=data.get("fails", 0),
                reason=data.get("reason", ""),
                last_ok=data.get("last_ok", ""),
                last_check=data.get("last_check", ""),
                extra={"name": data["name"]} if "name" in data else {},
            )
            entries[url]._quarantined = bool(data.get("quarantined", False))
        return cls(max_fails=max_fails, entries=entries)

    def save(self, path):
        directory = os.path.dirname(path)
        if directory:
            os.makedirs(directory, exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(
                {u: e.to_dict() for u, e in self.entries.items()},
                fh, indent=2, sort_keys=True,
            )
            fh.write("\n")

    def update(self, url, status, reason, name=""):
        entry = self.entries.get(url, StateEntry())
        entry.last_check = _now()
        if name:
            entry.extra["name"] = name
        if status == "online":
            entry.fails = 0
            entry.reason = ""
            entry.last_ok = entry.last_check
            entry._quarantined = False
        else:
            entry.fails += 1
            entry.reason = f"{status}: {reason}" if reason else status
            entry._quarantined = entry.fails >= self.max_fails
        self.entries[url] = entry
        return entry
