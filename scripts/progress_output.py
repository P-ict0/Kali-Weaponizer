#!/usr/bin/env python3
"""Stream command output and a transient task line through one terminal writer.

Never sets scrolling margins or addresses absolute screen rows. A partial output
line (including an input prompt) is shown immediately and suspends the spinner.
"""
import argparse
import codecs
import os
from pathlib import Path
import re
import select
import signal
import sys
import time

SGR = re.compile(r'\x1b\[[0-9;]*m')
FRAMES = '|/-\\'


class Display:
    def __init__(self, output, enabled, color):
        self.output = output
        self.enabled = enabled and output.isatty()
        self.color = color
        self.drawn = False
        self.drawn_length = 0
        self.line_start = True
        self.task = ''
        self.started = time.monotonic()
        self.frame = 0

    def clear(self):
        if self.drawn:
            self.output.write('\r\x1b[2K')
            # A narrower window can reflow the old status across several rows.
            # Clear only those status rows before displaying further output.
            try:
                width = max(1, os.get_terminal_size(self.output.fileno()).columns)
            except OSError:
                width = max(1, self.drawn_length)
            for _ in range(max(0, self.drawn_length - 1) // width):
                self.output.write('\x1b[1A\r\x1b[2K')
            self.drawn = False

    def write(self, text):
        self.clear()
        self.output.write(text)
        # Do not draw over partial lines/prompts, including bare carriage returns.
        if text:
            self.line_start = text.endswith('\n')
        self.output.flush()

    def refresh(self, state):
        if state != self.task:
            self.clear()
            self.task = state
            self.started = time.monotonic()
        if not self.enabled or not self.line_start or not self.task:
            self.output.flush()
            return
        try:
            width = os.get_terminal_size(self.output.fileno()).columns
        except OSError:
            return
        if width < 20:
            self.clear()
            self.output.flush()
            return
        number, title = self.task.split('\t', 1)
        elapsed = int(time.monotonic() - self.started)
        text = (f' [{FRAMES[self.frame % 4]}] Step {number} | {title} | '
                f'{elapsed // 60:02d}:{elapsed % 60:02d} elapsed')
        self.frame += 1
        self.clear()
        prefix, suffix = ('\x1b[1;36m', '\x1b[0m') if self.color else ('', '')
        text = text[:width - 1]
        self.output.write(prefix + text + suffix)
        self.drawn = True
        self.drawn_length = len(text)
        self.output.flush()


def read_state(path):
    try:
        state = path.read_text().strip()
    except OSError:
        return ''
    # Only installer-controlled, printable ASCII task labels reach the terminal.
    if '\t' not in state:
        return ''
    number, title = state.split('\t', 1)
    if not number.isdecimal() or not title.isascii() or not title.isprintable():
        return ''
    return state


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--log', type=Path, required=True)
    parser.add_argument('--state', type=Path, required=True)
    parser.add_argument('--progress', choices=('0', '1'), required=True)
    parser.add_argument('--color', choices=('0', '1'), required=True)
    args = parser.parse_args()
    # Bash owns cancellation and its exit status. Drain its pipe on interruption
    # so error messages and the final log aren't lost to SIGINT/SIGTERM.
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    display = Display(sys.stdout, args.progress == '1', args.color == '1')
    decoder = codecs.getincrementaldecoder('utf-8')(errors='replace')
    log_pending = ''
    with args.log.open('w', encoding='utf-8') as log:
        def emit(text, final=False):
            nonlocal log_pending
            display.write(text)
            log_pending += text
            # Keep split ANSI colour sequences together when stripping log text.
            if final:
                ready, log_pending = log_pending, ''
            elif '\n' in log_pending:
                ready, log_pending = log_pending.rsplit('\n', 1)
                ready += '\n'
            else:
                return
            log.write(SGR.sub('', ready))
            log.flush()

        try:
            while True:
                readable, _, _ = select.select([sys.stdin.fileno()], [], [], 0.2)
                if readable:
                    chunk = os.read(sys.stdin.fileno(), 65536)
                    if not chunk:
                        emit(decoder.decode(b'', final=True), final=True)
                        break
                    emit(decoder.decode(chunk))
                display.refresh(read_state(args.state))
        finally:
            display.clear()
            sys.stdout.flush()


if __name__ == '__main__':
    main()
