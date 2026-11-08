# Login step counts

What the sign-in flow costs a person, before and after the browser sign-in change
(ATE-379 Wave 0). This is the reference for what `authenticate-user` promises: when
the skill changes, the CLI rows here must still describe what it does.

Today's emails, codes and tabs are the requester's counts at prod backend v3.4.5,
site v1.25.10 and kpass 6.8.9; today's redirects are derived from the same code read.

## Before and after

> Before and after counts (AC 1, as restated by goal-v2). E/C/R/T = emails / codes typed / redirects (page changes the person didn't choose) / tabs opened; the total adds them up. Today's emails, codes and tabs are from the requester's facts at prod backend v3.4.5, site v1.25.10, kpass 6.8.9; today's redirects are derived from the same code read. Release recounts every row in production.

| Flow | Today E/C/R/T (total) | After E/C/R/T (total) |
| -- | -- | -- |
| New user, web, same device | 1/0/1/2 (4) | 1/1/0/1 (3) |
| New user, web, email read on another device | 2/1/1/2 (6) | 1/1/0/1 (3) |
| New user, web, Google | none today | 0/0/2/1 (3) |
| Returning, web, back after 24 hours, within 30 days | 1/1/2/1 (5) | 0/0/0/1 (1) |
| Returning, web, back after 30 days | 1/1/2/1 (5) | 1/1/0/1 (3) |
| New user, CLI, browser on the machine, to first spending approval | 3/2/3/2 (10) | 1/1/1/2 (5) |
| New user, CLI, no browser on the machine, to first spending approval | 3/2/3/2 (10) | 2/2/0/1 (5) |
| Returning, CLI, dashboard signed in | 1/1/0/0 (2) per repo | 0/0/1/1 (2) per machine |
| Returning, CLI, dashboard not signed in | 1/1/0/0 (2) per repo | 1/1/1/1 (4) per machine |
| Returning, CLI, no browser on the machine | 1/1/0/0 (2) per repo | 1/1/0/0 (2) per machine |

> Counts that rise in a row: typed codes for a new web user on the same device (0 to 1, in place of the link's second tab; one way to verify, criterion 4); tabs and redirects for a CLI sign-in through the browser. The last three rows are the single-repo exception in criterion 1: level, or one tab and one redirect more when the dashboard isn't signed in (that sign-in also leaves the dashboard signed in); with two or more repos on the machine every CLI row is lower than today.

## Which rows the skill owns

The `authenticate-user` skill delivers the five CLI rows. The web rows are the
dashboard's, and are here so one table covers both surfaces.

| Row | What the skill runs |
| -- | -- |
| New user, CLI, browser on the machine | `kpass login`, then `kpass login status` until it says `signed_in`. The dashboard does the sign-up in the browser, and the first spending key is approved from the `user_message` link. |
| New user, CLI, no browser on the machine | `kpass login` exits `browser_unavailable`, so the skill runs `login init` then `login verify`. One email, one code, for a new address as much as an existing one. |
| Returning, CLI, dashboard signed in | `kpass login`, then `kpass login status`. No email, no code. |
| Returning, CLI, dashboard not signed in | The same two commands. The dashboard asks for the email and code itself, and that sign-in leaves it signed in for next time. |
| Returning, CLI, no browser on the machine | `login init` then `login verify`. One email, one code, no browser. |

The skill never runs `kpass signup`, and never asks for a second code. A new email
and a known email take the same path.

The CLI rows are counted per machine, not per repo. With a global install `kpass`
keeps one login in the home folder, so a second repo on the same machine needs no
sign-in at all; today's counts are per repo, which is why a person who works in two
or more repos is better off on every CLI row. A local (project) install still keeps
its login per project.

Release recounts every row in production; the "after" column is the target, not a
measurement.
