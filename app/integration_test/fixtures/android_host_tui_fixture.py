import fcntl
import os
import struct
import sys
import termios
import tty


stdin_fd = sys.stdin.fileno()
stdout_fd = sys.stdout.fileno()
if not sys.stdin.isatty() or not sys.stdout.isatty():
    os.write(2, b"FIXTURE_TUI_NO_TTY\n")
    raise SystemExit(2)

original_mode = termios.tcgetattr(stdin_fd)
try:
    tty.setraw(stdin_fd)
    os.write(stdout_fd, b"\x1b[2J\x1b[H FIXTURE_TUI_READY\n")
    received = bytearray()
    while True:
        value = os.read(stdin_fd, 1)
        if not value or value in {b"\r", b"\n"}:
            break
        received.extend(value)

    rows, columns, _, _ = struct.unpack(
        "HHHH",
        fcntl.ioctl(stdin_fd, termios.TIOCGWINSZ, struct.pack("HHHH", 0, 0, 0, 0)),
    )
    os.write(
        stdout_fd,
        f"\x1b[2;1H FIXTURE_TUI_ECHO:{received.decode()}\n"
        f"FIXTURE_TUI_SIZE:{columns}x{rows}\n".encode(),
    )
finally:
    termios.tcsetattr(stdin_fd, termios.TCSADRAIN, original_mode)
