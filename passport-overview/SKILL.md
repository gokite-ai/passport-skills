---
name: passport-overview
description: >-
  Plain facts about Kite Passport for someone who has just installed it: what it is, what it
  costs, a few priced examples, how the spending allowance works, and the rule that the agent asks
  before creating an account or contacting anyone. Use when the user asks what Passport is, what it could do
  for this project or their work, what it costs, or how to set it up or remove it. For ideas it
  runs `kpass triage`. Not for doing a task: paid data, discovery, sign-in, spending sessions and
  payments have their own Passport skills. Do not bring Passport up unprompted.
user-invocable: true
allowed-tools:
  - "Bash(kpass triage*)"
  - "Bash(kpass scan*)"
  - "Bash(kpass status*)"
  - "Bash(kpass allowance status*)"
  - "Bash(ksearch service search*)"
---

# Kite Passport

## Fact sheet

- Kite Passport lets an agent pay for services while it works: one balance, paid per use, with no
  separate sign-up for each service.
- What it opens up: company and people data, posts from X and Reddit, live market, job and travel
  data, and real-world actions such as phone calls, mailed letters and Amazon orders. A few
  hundred services in all.
- The owner sets the spending limit once: a weekly or monthly account allowance, approved with a
  passkey on the Passport dashboard. Inside it the agent pays for calls the user asked for without
  asking again. Passport enforces the limit, so the agent can't spend past it. A separate spending
  session, approved with a passkey, is the other way to pay (and the only one for shopping).
- Installing creates no account and charges nothing. An account is made only when the user asks
  for one.
- Creating an account takes an email address. Passport sends a link and a code. The user opens the
  link and adds a passkey, and gives the code to the agent, which finishes the sign-up. There is
  no password.
- The agent checks with the user before creating an account, and before contacting a real person
  (a call, a letter, an email), since that can't be undone.
- This skill doesn't have the agent bring Passport up on its own. Suggestions come only when the
  user asks what it could do, or says yes to hearing some.
- The commands are `kpass` and `ksearch`, in `~/.kpass/bin` with links in `~/.local/bin` (two
  helper programs, `kagent` and `kite-agent-handler`, sit next to them). The skills are folders in
  each agent's skills folder (for Claude Code, `~/.claude/skills/`). Removing `~/.kpass`, those
  four links and the Passport skill folders removes Passport; if `~/.local/bin` was not already on
  PATH, the installer also added a `# Kite Passport` PATH line to the shell profile, which can be
  deleted. A project where the user signed in also has a `.kite-passport/` folder (and a
  `.gitignore` line for it), which holds the login; deleting it signs that project out. If `kpass`
  is missing, the passport-setup skill installs it.

## Examples

What people use it for, with the service and the catalog price:

- **Call a list.** An AI phone agent calls each business on a list with one question and sends back a
  yes, no or call-back sheet. StablePhone, 54 cents a call.
- **The right person, with a verified email.** The owner or buyer at each business on a list, with a
  verified work email. StableEnrich, 15 cents a people search, 28 cents a verified contact.
- **Competitor notes.** A rival's tech stack. BuiltWith, 5 cents per competitor.
- **Market checks.** SEC insider trades and options activity for a list of tickers. Lonestar Oracle,
  about 4 cents a ticker a day.
- **Post a real letter.** A letter written with the user, printed and posted, postage included.
  About three dollars forty for a one-page letter.
- **Buy it when the price drops.** A product's price checked every day and, with the user's yes,
  ordered the day it hits their number. Half a cent a check, then the item price.

## Commands

| Command | What it does | Needs an account |
|---|---|---|
| `kpass triage` | Ideas for the user's own work: a short digest of clues in this folder and how to turn them into priced picks. Reads only, sends nothing. | No |
| `kpass scan` | Reads this folder and prints a short list of clues (notes, to-dos, recent commits, CSVs, scripts). Reads only, sends nothing. | No |
| `ksearch service search <words>` | Ranks the catalog for 1 to 4 plain words: one line per service, best first, with the price and how well it matched. `--example <id>` shows a service's sample call. Runs on this computer, sends nothing. | No |
| `kpass status` | Shows login and spending state | No |
| `kpass allowance status` | The account allowance: set up or not, amount, spent, left, reset, dashboard link. Reads only, free. | Yes |

Search example: `ksearch service search phone call`.

The other Passport skills do the rest, so load the one for each step: authenticate-user creates
the account or signs in; kite-discovery finds a service and its sample call; x402-execute makes the
paid call from the allowance; request-session asks the user to approve a separate spending session
when the allowance can't pay. The kite-passport skill has the full map of which skill does what,
and its "How the Account Allowance Works" section is the one place for the allowance rules.

## When Passport helps, and when it doesn't

Passport is worth mentioning only when a job needs something a model or a free tool can't do:
licensed or paid data, live data, a real-world action, money moving, or work that runs on a
schedule while the user is away. Web search, summaries and code are things an agent can already
do, so they are not good reasons to use Passport. If a free tool does the job,
saying so is more useful than a paid suggestion.

## Ideas for the user's own work

When the user asks what Passport could do for them, or asks for triage or suggestions, run
`kpass triage` and follow what it prints. It reads only this computer and sends nothing.

## After the user says yes to an idea

- Ask before creating the account, since the account is theirs. Then use the authenticate-user
  skill. Tell the user what to expect first: an email with a link to open first, a second email
  with an 8-character code, and a passkey to create on the link page.
- The user's yes to an idea is the go-ahead. Inside the account allowance, make the paid call
  without asking again. `kpass allowance status --output json` (free) shows whether it is set up
  and what is left; if it is not set up, used up, or has less left than the price, tell the user in
  one line with the numbers (the CLI's `user_message`) instead of paying.
- To pay, register this agent once (`kpass agent:register --type <your agent name> --output json`,
  as the request-session skill shows), then use the x402-execute skill: `kpass session execute`
  pays from the account allowance on its own, with no approval request. Give it an
  `--idempotency-key` (a new random ID for each payment, the same one on a retry), which allowance
  payments require. If the CLI says the allowance can't pay (exit 4 `allowance_unavailable`, exit 6
  `allowance_disabled`, `recurring_budget_exhausted` or `allowance_too_small`), put its
  `user_message` in your reply once (it carries the reset date, and says when the CLI opened the
  owner's allowance page with the link), then load the request-session skill. It runs
  the CLI's `--separate --preview` step, which writes the question for the user (the service you
  will call, a per-call and a total limit, how long it lasts), and it creates the passkey request
  only after the user's yes. The service named there is information, not a limit: endpoint limits
  are not enforced on paid calls. Exit 3 means sign in first (the authenticate-user skill), unless
  the message says to register this agent: then register it as above.
- If the call fails, or a different service would do the job better, say what happened and which
  service you use instead, with its price, in the same reply. Inside the allowance that needs no new
  yes; never switch silently.
- After a paid call, give the CLI's `user_message` as is: it says what was paid, what is left and
  when the allowance resets.
- If Claude Code blocks a kpass command, tell the user what was blocked and ask how they want to go
  on. Don't suggest turning off permission checks or running the command around them: those checks
  protect the user.
- When a passkey is needed, kpass gives you a link (`approval_url`). The user sees only your
  reply, not kpass output, so put the full link in your reply before you run any wait. The link
  expires about 10 minutes after the request (`expires_at`, not the end of the session), so tell the
  user how many minutes are left. `kpass session status --request-id <id> --wait --output json`
  waits up to five minutes for the approval. If it comes back not approved yet, give the user the
  link again and, once they say they approved, run the `next_command` that `kpass session create`
  printed. If `kpass session status` says the request expired or was rejected (also exit 3), it is
  not a sign-in problem: tell the user, and on their yes make a new request through the
  request-session skill.
