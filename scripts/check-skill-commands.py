#!/usr/bin/env python3
"""Check that every kpass / ksearch command and flag a skill names exists.

Usage: check-skill-commands.py <path-to-kpass> <path-to-ksearch> [skill-root]

Why: in the prod e2e (2026-10-23, Q07) an agent ran `kpass whoami`, a command
no skill names and the CLI does not have, and read the error as "not logged
in". Skills must name only real commands, so this script asks the CLI itself
(`<cmd> --help`) about every command path and `--flag` in the SKILL.md and
references/*.md files. Lines in a "Commands That DO NOT Exist" section, and
lines that say a command does not exist, are skipped: they name fake commands
on purpose.

Exit 0 when every command resolves; exit 1 with one line per miss.
"""
import os
import re
import subprocess
import sys
from functools import lru_cache

CMD_RE = re.compile(r"\b(kpass|ksearch)((?:[ \t]+[A-Za-z][A-Za-z0-9:_-]*)*)([^`\n|'\"]*)")
FLAG_RE = re.compile(r"(?<![\w-])--([a-z][a-z0-9-]*)")
SKIP_LINE_RE = re.compile(r"does not exist|doesn't exist|do not exist|no such|not a command|never guess|there is no `", re.I)
SKIP_SECTION_RE = re.compile(r"^#+ .*(DO NOT Exist|Do Not Exist|do not exist)", re.I)
# CLI output text that starts with the binary's name but is not a command.
NOT_COMMANDS = ("kpass bundle ",)
# Only code is checked: fenced blocks, and `inline code` elsewhere. Prose such
# as "kpass gives you a link" names the program, not a command.
INLINE_RE = re.compile(r"`([^`]+)`")
FENCE_CMD_RE = re.compile(r"^\s*(\$\s*)?([A-Z_][A-Z0-9_]*=\S*\s+)*(kpass|ksearch)\s")
# Words that end a command path in prose ("run kpass triage and follow").
STOP_WORDS = {"and", "or", "to", "with", "then", "for", "first", "again", "on", "in", "is", "the", "a", "an",
              "it", "that", "this", "as", "if", "when", "once", "only", "before", "after", "from", "by", "command",
              "commands", "output", "call", "calls", "returns", "pays", "binds", "prints", "shows", "uses", "itself",
              "flag", "flags", "cli", "binary", "skill", "skills", "itself", "your", "here", "now", "every", "each"}


def help_text(binary, path):
    env = dict(os.environ, KPASS_NO_UPDATE_CHECK="1", CI="1", KPASS_NO_BROWSER="1")
    try:
        out = subprocess.run([binary, *path, "--help"], capture_output=True, text=True, timeout=20, env=env)
    except subprocess.TimeoutExpired:
        return ""
    return out.stdout + out.stderr


@lru_cache(maxsize=None)
def resolve(binary, path):
    """Return (resolved_path_tuple, help_text) for the deepest real command."""
    text = help_text(binary, list(path))
    if "unknown command" in text or "Usage:" not in text:
        return None, text
    usage = text.split("Usage:", 1)[1].strip().splitlines()[0].strip()
    words = [w for w in usage.split() if re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]*", w)]
    return tuple(words[1:]), text


@lru_cache(maxsize=None)
def flag_known(binary, path, flag):
    """Ask the parser, so hidden flags count too: `--flag=1 --help` never runs
    the command; an unknown flag fails with "unknown flag"."""
    env = dict(os.environ, KPASS_NO_UPDATE_CHECK="1", CI="1", KPASS_NO_BROWSER="1")
    try:
        out = subprocess.run([binary, *path, f"--{flag}=1", "--help"], capture_output=True, text=True, timeout=20, env=env)
    except subprocess.TimeoutExpired:
        return True
    return "unknown flag" not in (out.stdout + out.stderr)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    bins = {"kpass": sys.argv[1], "ksearch": sys.argv[2]}
    root = sys.argv[3] if len(sys.argv) > 3 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    files = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in (".git", "node_modules", "evals", "docs", "scripts")]
        for f in filenames:
            if f == "SKILL.md" or (f.endswith(".md") and os.path.basename(dirpath) == "references"):
                files.append(os.path.join(dirpath, f))
    misses, checked = [], 0
    for path in sorted(files):
        in_skip, in_fence = False, False
        for n, line in enumerate(open(path, encoding="utf-8"), 1):
            if line.lstrip().startswith("```"):
                in_fence = not in_fence
                continue
            if line.startswith("#") and not in_fence:
                in_skip = bool(SKIP_SECTION_RE.match(line))
            if in_skip or SKIP_LINE_RE.search(line):
                continue
            # In a fenced block only a line that runs the command counts (not
            # JSON output or a flowchart that mentions kpass).
            if in_fence:
                code = line if FENCE_CMD_RE.match(line) else ""
            else:
                code = "\n".join(INLINE_RE.findall(line))
            for nc in NOT_COMMANDS:
                code = code.replace(nc, "")
            for m in CMD_RE.finditer(code):
                tool, words, rest = m.group(1), m.group(2).split(), m.group(3)
                cmd_words = []
                for w in words:
                    if w.lower() in STOP_WORDS or w.endswith(":") and ":" not in w[:-1]:
                        break
                    cmd_words.extend(w.split(":"))
                binary = bins[tool]
                # Find the longest prefix that is a real command path.
                resolved, text, used = None, "", 0
                for k in range(len(cmd_words), -1, -1):
                    r, t = resolve(binary, tuple(cmd_words[:k]))
                    if r is not None and len(r) >= 1 and r[-1] == (cmd_words[k - 1] if k else r[-1]):
                        resolved, text, used = r, t, k
                        break
                    if r is not None and k == 0:
                        resolved, text, used = r, t, 0
                checked += 1
                where = f"{os.path.relpath(path, root)}:{n}"
                shown = f"{tool} {' '.join(cmd_words)}".strip()
                if resolved is None:
                    misses.append(f"{where}: `{shown}`: not a command")
                    continue
                extra = cmd_words[used:]
                if extra and "unknown command" in help_text(binary, cmd_words[:used + 1]):
                    misses.append(f"{where}: `{shown}`: `{extra[0]}` is not a command under `{tool} {' '.join(cmd_words[:used])}`".replace("  ", " "))
                    continue
                if extra and "Available Commands:" in text:
                    misses.append(f"{where}: `{shown}`: `{extra[0]}` is not a subcommand of `{tool} {' '.join(cmd_words[:used])}`")
                    continue
                if "Available Commands:" in text and not extra and used == 0 and cmd_words:
                    misses.append(f"{where}: `{shown}`: not a command")
                    continue
                for flag in FLAG_RE.findall(rest):
                    if flag in ("help",):
                        continue
                    if not flag_known(binary, tuple(cmd_words[:used]), flag):
                        misses.append(f"{where}: `{shown} --{flag}`: no such flag")
    for line in misses:
        print(line)
    print(f"checked {checked} command mentions in {len(files)} files: {len(misses)} problem(s)")
    return 1 if misses else 0


if __name__ == "__main__":
    sys.exit(main())
