# Skill setup installer advisory

Every release in the list below shipped a skill setup script that could be made to run code the user did not choose. This advisory covers the `attach-session`, `authenticate-user` and `request-session` skills. An outside security researcher reported the problem, and we thank them for the report.

## What was wrong

Three skill-bundled copies of the bootstrap script had the same defects.

- `attach-session/scripts/setup.sh`
- `authenticate-user/scripts/setup.sh`
- `request-session/scripts/setup.sh`

Each copy had these problems.

- It piped the downloaded installer straight into `bash`, so whatever the server returned ran at once.
- It interpolated `$SKILLS_JSON` into the code argument of `node -p` and `python3 -c`. A crafted path to `skills.json` became part of the code. The fixed copies pass the path as a separate argument.
- From `v3.5.3` onward, it read `KPASS_BASE_URL` and used the value as the installer host with no check on it. Anyone who could set that variable could make the script download and run an installer from any host. Earlier releases did not read the variable and always used `https://cli.gokite.ai`.

The fixed copies of these three scripts accept only `https://cli.gokite.ai` and `https://cli.staging.gokite.ai`. They download the installer to a file, refuse redirects, and run the file only when it starts with `#!`.

## Who is affected

Agents that run the `attach-session`, `authenticate-user`, or `request-session` skill from a release in the list below.

## Not covered by this fix

The `kite-discovery` skill bundles its own `kite-discovery/scripts/setup-ksearch.sh`, which has the same pattern of an unchecked `KPASS_BASE_URL` and curl piped into bash. That script is outside this fix and is being handled separately, so it is still unfixed in the release that fixes the three scripts above. Until it is fixed, leave `KPASS_BASE_URL` unset when running `kite-discovery`, or set it only to `https://cli.gokite.ai`.

## Affected releases

These tags shipped at least one vulnerable copy of the three scripts above. That is every release cut so far. A script generates the list from the git tags, so do not edit it by hand.

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

<!-- affected-releases:end -->

## How the list is computed

`scripts/list-affected-releases.sh` reads the three copies at each `v*` tag. It marks a copy vulnerable when any one of these rules matches.

1. The copy reads `KPASS_BASE_URL` and does not contain the allowlist test `^https://cli(\.staging)?\.gokite\.ai$`.
2. A command pipes `curl` output into a shell. `| sh` counts the same as `| bash`, as do an absolute path to the shell, a prefix such as `sudo` or a variable assignment, a pipeline split over backslash continuations, and a pipeline inside a command substitution. The same text printed by an `echo`, or sitting inside the JSON error message, does not count.
3. `$SKILLS_JSON` appears inside the quoted code argument of `node -p`, `node -e`, or `python3 -c`.

A release is `affected` when any copy that exists is vulnerable. It is `not-shipped` when none of the three paths exists. Otherwise it is `fixed`.

The rules are a text scan, not a shell parser. They are tuned to the shapes these scripts actually used, and they are deliberately conservative about what counts as executing a download, so `eval "$(curl ...)"` and `bash <(curl ...)` are not matched. A reader checking a new shape should read the copy rather than trust the verdict alone.

Run the script from a full clone with tags.

```bash
bash scripts/list-affected-releases.sh
bash scripts/list-affected-releases.sh --ref <tag>
bash scripts/list-affected-releases.sh --check
```

The first command prints the affected tags in version order. The second prints one verdict for a single ref. The third compares the list above with the tags and exits 1 when they differ. The script also exits 1 when the clone has no `v*` tags, so run `git fetch --tags` first in a shallow clone.

## Fix

The fix is the hardened copies of the three scripts above, which land on `main` ahead of this advisory. They ship in the first tagged release cut after that. Release names that release in the #security post.

## What to do

Install the fixed release. Until then, leave `KPASS_BASE_URL` unset, or set it only to `https://cli.gokite.ai`. That removes the attacker-chosen host, which is the only one of the three defects a user can mitigate. On an affected release the installer is still piped into bash and `$SKILLS_JSON` is still interpolated into interpreter code, so upgrading is the fix.
