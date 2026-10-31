#!/usr/bin/env python3
"""Clipboard History Manager.

Monitor the clipboard and log new entries with timestamps to a file.
Press Ctrl+C to stop.

Usage:
    python clipboard_history_manager.py --log-file clipboard_log.txt
"""
import argparse
import time
from datetime import datetime
from pathlib import Path

import pyperclip


def run_clipboard_history(log_file="clipboard_log.txt", poll_interval=1.0):
    """Monitor clipboard and log new entries with timestamps."""
    log_path = Path(log_file)
    previous = ""
    entry_count = 0
    print("Clipboard monitor running. Press Ctrl+C to stop.\n")
    try:
        while True:
            current = pyperclip.paste()
            if current != previous and current.strip():
                previous = current
                entry_count += 1
                timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                entry = f"[{timestamp}] Entry #{entry_count}\n{current}\n{'=' * 50}\n"
                with open(log_path, "a", encoding="utf-8") as f:
                    f.write(entry)
                # Show a preview (first 80 chars)
                preview = current[:80].replace("\n", " ")
                print(f"  #{entry_count} [{timestamp}] {preview}...")
            time.sleep(poll_interval)
    except KeyboardInterrupt:
        print(f"\nStopped. Logged {entry_count} entries to {log_path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--log-file", default="clipboard_log.txt",
                        help="Log file path (default: clipboard_log.txt)")
    parser.add_argument("--interval", type=float, default=1.0,
                        help="Poll interval in seconds (default: 1.0)")
    args = parser.parse_args()

    run_clipboard_history(log_file=args.log_file, poll_interval=args.interval)


if __name__ == "__main__":
    main()
