#!/usr/bin/env python3
"""Watch Flutter UI source and hot reload the three local preview sessions.

Run: python3 scripts/watch_ui_reload.py
Stop with Ctrl+C. Native code/dependency changes still require a new build.
"""
import os
from pathlib import Path
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
PID_FILES = [Path(f'/tmp/koofy-live-{name}.pid') for name in ('phone', 'fold', 'duo')]


def snapshot():
    result = {}
    for path in (ROOT / 'lib').rglob('*.dart'):
        try:
            result[str(path)] = (path.stat().st_mtime_ns, path.stat().st_size)
        except FileNotFoundError:
            pass
    return result


def reload_sessions():
    # The Duo uses an isolated preview because ML Kit has no arm64 simulator slice.
    preview = ROOT / 'work' / 'live-duo'
    if (preview / 'pubspec.yaml').is_file():
        subprocess.run(['rsync', '-a', '--delete', str(ROOT / 'lib') + '/',
                        str(preview / 'lib') + '/'], check=True)
    for path in PID_FILES:
        try:
            pid = int(path.read_text().strip())
            if pid <= 1:
                continue
            command = subprocess.check_output(['ps', '-p', str(pid), '-o', 'args='], text=True)
            if 'flutter_tools' not in command or str(path) not in command:
                continue
            os.kill(pid, signal.SIGUSR1)
            print(f'Hot reload: {path.stem}', flush=True)
        except (OSError, ValueError, subprocess.CalledProcessError):
            pass


if __name__ == '__main__':
    previous = snapshot()
    changed_at = None
    print('Watching lib/**/*.dart; Ctrl+C stops automatic reload.', flush=True)
    try:
        while True:
            time.sleep(.5)
            current = snapshot()
            if current != previous:
                previous, changed_at = current, time.monotonic()
            if changed_at is not None and time.monotonic() - changed_at >= 1:
                reload_sessions()
                changed_at = None
    except KeyboardInterrupt:
        print('Watcher stopped.', flush=True)
