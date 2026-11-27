# Skill setup installer advisory

Every release in the list below shipped a skill setup script that could be made to run code the user did not choose. This advisory covers the `attach-session`, `authenticate-user`, `request-session` and `kite-discovery` skills. An outside security researcher reported the problem, and we thank them for the report.

## What was wrong

Four skill-bundled bootstrap scripts had the defects below. Three are copies of `setup.sh`, which installs `kpass`.

- `attach-session/scripts/setup.sh`
- `authenticate-user/scripts/setup.sh`
- `request-session/scripts/setup.sh`

The fourth is `kite-discovery`'s copy of `setup-ksearch.sh`, which installs the same bundle to get `ksearch`.

- `kite-discovery/scripts/setup-ksearch.sh`

Each of the four copies had these problems.

- It piped the downloaded installer straight into `bash`, so whatever the server returned ran at once.
- From `v3.5.3` onward, it read `KPASS_BASE_URL` and used the value as the installer host with no check on it. Anyone who could set that variable could make the script download and run an installer from any host. Earlier releases did not read the variable and always used `https://cli.gokite.ai`.

The three `setup.sh` copies had one further problem, which `kite-discovery`'s copy never had because it reads no `skills.json`.

- It interpolated `$SKILLS_JSON` into the code argument of `node -p` and `python3 -c`. A crafted path to `skills.json` became part of the code. The fixed copies pass the path as a separate argument.

The fixed copies of all four scripts accept only `https://cli.gokite.ai` and `https://cli.staging.gokite.ai`. They download the installer to a file, refuse redirects, and run the file only when it starts with `#!`.

## Who is affected

Agents that run the `attach-session`, `authenticate-user`, `request-session` or `kite-discovery` skill from a release in the list below.

## Affected releases

These tags shipped at least one vulnerable copy of the four scripts above. That is every `v*` tag in the repository, so every release cut so far is affected. The `bot-release/*` tags are dispatch markers rather than releases and are not listed. The list comes from `scripts/list-affected-releases.sh`, and `--check` fails when the two disagree. To update it, paste that script's output rather than editing entries by hand.

<!-- affected-releases:start -->

- `v1.7.0`
- `v1.7.1`
- `v1.7.2`
- `v1.8.0`
- `v1.8.1`
- `v1.9.0`
- `v1.9.1`
- `v1.9.2`
- `v1.10.0`
- `v1.11.0`
- `v1.12.0`
- `v1.12.1`
- `v1.12.2`
- `v1.13.0`
- `v2.0.0`
- `v2.0.1`
- `v3.0.0`
- `v3.0.1`
- `v3.0.2`
- `v3.1.0`
- `v3.1.1`
- `v3.1.2`
- `v3.1.3`
- `v3.2.0`
- `v3.3.0`
- `v3.4.0`
- `v3.4.1`
- `v3.5.0`
- `v3.5.1`
- `v3.5.2`
- `v3.5.3`
- `v3.5.4`
- `v3.5.5`
- `v3.5.6`
- `v3.5.7`
- `v3.5.8`
- `v3.5.9`
- `v3.5.10`
- `v3.5.11`
- `v3.5.12`
- `v3.6.0`
- `v3.6.1`
- `v3.6.2`
- `v3.6.3`
- `v3.6.4`
- `v3.6.5`
- `v3.6.6`
- `v3.6.7`
- `v3.6.8`
- `v3.6.9`
- `v3.6.10`
- `v3.6.11`
- `v3.6.12`
- `v3.6.13`
- `v3.6.14`
- `v3.6.15`

<!-- affected-releases:end -->

## How the list is computed

`scripts/list-affected-releases.sh` reads the four copies at each `v*` tag. It marks a copy vulnerable when any one of these rules matches.

1. The copy reads `KPASS_BASE_URL` and does not contain the allowlist test `^https://cli(\.staging)?\.gokite\.ai$`.
2. A command pipes `curl` output into a shell. `| sh` counts the same as `| bash`, as do a path to either command, a wrapper such as `sudo` or `env` or a variable assignment on either side of the pipe, a pipeline split over a continuation (a trailing `\`, `|` or `|&`), and a pipeline inside a command substitution or backticks. The pipeline has to start where a command can start, which is what keeps the `curl ... | bash` text in these scripts' own `--help` output and JSON error message from counting. A wrapper option that takes a value, as in `sudo -u kite curl`, is not covered, because the rule cannot tell such an option from the command name after it.
3. `$SKILLS_JSON` is spliced into the code argument of `node` or `python`, rather than passed as a separate argument. This covers `-p`, `-e`, `-pe`, `--eval` and `--print` for a `node` or `nodejs` name and `-c` for a `python`, `python3` or `python3.12` name, each reachable by a path and each allowed other options first, with the code attached by a space, by `=` or by nothing at all. It covers a braced `${SKILLS_JSON}`, escaped quotes, and both splicing forms, `'...'"$X"'...'` and the unquoted `'...'$X'...'`.

A release is `affected` when any copy that exists is vulnerable. It is `not-shipped` when none of the four paths exists. Otherwise it is `fixed`.

The rules are a text scan, not a shell parser, so each can be wrong in either direction. What follows is a set of examples, not a closed list.

The scan can over-report. It reads only the text bash would run, so a comment is dropped and a comment that quotes the old command does not count, but a pipeline written inside other quoted text, such as a here-document of usage instructions, is still counted even though nothing runs it.

It can also under-report, and rule 1 is the case worth knowing. It asks whether the allowlist pattern appears in the copy, not whether the copy enforces it, so a copy that loses the check in a refactor while keeping the pattern in a help message reads as fixed. Rule 2 misses shells it cannot see as shells, among them `eval "$(curl ...)"`, `bash <(curl ...)`, a quoted or indirect name as in `| "bash"` or `| $SHELL`, a wrapper outside the handful it knows as in `nice curl ... | bash`, a wrapper option that takes a value as in `sudo -u kite curl`, and a pipeline fed by a group as in `{ curl ...; } | bash`.

No release used any of those shapes, which is why they are limitations rather than corrections. Widening a rule changes what this advisory publishes, so that is a decision for Engineering rather than for this script, and a reader checking a new shape should read the copy rather than trust the verdict alone.

Run the script from a full clone with tags.

```bash
bash scripts/list-affected-releases.sh
bash scripts/list-affected-releases.sh --ref <tag>
bash scripts/list-affected-releases.sh --check
```

The first command prints the affected tags in version order. The second prints one verdict for a single ref. The third compares the list above with the tags and exits 1 when they differ. The script refuses to answer from a shallow clone or from one with no `v*` tags, because a partial tag list reads exactly like a complete one, so run `git fetch --tags --unshallow` first.

## Fix

The fix is the hardened copies of the four scripts above. They ship in the first tagged release cut after those copies reach `main`. The #security post names that release. No tagged release carries them yet, which is why every tag in the list above is affected.

## What to do

Leave `KPASS_BASE_URL` unset, or set it only to `https://cli.gokite.ai`. That removes the attacker-chosen host, which is the only defect a user can mitigate. Install the fixed release once it is cut. On an affected release the installer is still piped into bash, and in the three `setup.sh` copies `$SKILLS_JSON` is still interpolated into interpreter code, so upgrading is the fix.
