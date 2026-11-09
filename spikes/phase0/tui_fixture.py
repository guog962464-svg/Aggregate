"""Interactive CLI fixture for macOS PTY verification."""

import shutil
import signal
import sys


def show_size(_signal=None, _frame=None):
    size = shutil.get_terminal_size()
    print(f"SIZE {size.columns}x{size.lines}", flush=True)


signal.signal(signal.SIGWINCH, show_size)
print("\x1b[2JREADY", flush=True)
show_size()
for line in sys.stdin:
    print(f"INPUT {line.strip()}", flush=True)
    if line.strip() == "quit":
        break
