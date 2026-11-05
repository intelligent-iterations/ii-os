"""Persistent JSON result cache for the headless ACE-Step API.

The pinned upstream patch uses this small cache interface instead of a
pickle-backed cache. Corrupt data raises an error; it is never deserialized
as Python objects. SQLite serializes writers across threads and processes.
"""
from __future__ import annotations

import json
from pathlib import Path
import sqlite3
from threading import RLock
import time
from typing import Any, Callable, Iterator


class JsonCache:
    def __init__(self, directory: str | Path, *, clock: Callable[[], float] = time.time):
        directory = Path(directory)
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        self._clock = clock
        self._lock = RLock()
        self._db = sqlite3.connect(directory / 'results.sqlite3', timeout=10,
                                   check_same_thread=False, isolation_level=None)
        self._db.execute('PRAGMA journal_mode=WAL')
        self._db.execute('CREATE TABLE IF NOT EXISTS entries '
                         '(key TEXT PRIMARY KEY, value TEXT NOT NULL, expires REAL)')

    def set(self, key: str, value: Any, expire: float | None = None) -> bool:
        if not isinstance(key, str):
            raise TypeError('cache keys must be strings')
        encoded = json.dumps(value, ensure_ascii=False, allow_nan=False)
        expires = None if expire is None else self._clock() + expire
        with self._lock:
            self._db.execute('INSERT INTO entries(key,value,expires) VALUES(?,?,?) '
                             'ON CONFLICT(key) DO UPDATE SET value=excluded.value, expires=excluded.expires',
                             (key, encoded, expires))
        return True

    def _row(self, key: str):
        # Conditional deletion cannot remove a concurrent writer's fresh value.
        now = self._clock()
        self._db.execute('DELETE FROM entries WHERE key=? AND expires<=?', (key, now))
        return self._db.execute('SELECT value FROM entries WHERE key=? '
                                'AND (expires IS NULL OR expires>?)', (key, now)).fetchone()

    def get(self, key: str, default: Any = None) -> Any:
        with self._lock:
            row = self._row(key)
            return default if row is None else json.loads(row[0])

    def __contains__(self, key: str) -> bool:
        with self._lock:
            return self._row(key) is not None

    def delete(self, key: str) -> bool:
        with self._lock:
            return self._db.execute('DELETE FROM entries WHERE key=?', (key,)).rowcount > 0

    def iterkeys(self) -> Iterator[str]:
        with self._lock:
            now = self._clock()
            self._db.execute('DELETE FROM entries WHERE expires<=?', (now,))
            keys = [row[0] for row in self._db.execute(
                'SELECT key FROM entries WHERE expires IS NULL OR expires>? ORDER BY key', (now,))]
        return iter(keys)

    def close(self) -> None:
        with self._lock:
            if self._db is not None:
                self._db.close()
                self._db = None
