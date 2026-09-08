# Session prompts + scheduled task

## First, a correction: a Session is not something you "create"

In the Flocks documentation a Session is **your task conversation space with Rex** — not a
configurable persistent object. There is no "create an inspection session template" operation.
So "set up the session" is really two things:

1. **A paste-ready prompt to start an inspection** (§1, §2 below)
2. **Promoting it to a Task Center scheduled task** so the daily run goes unattended (§3 below)

Incidentally: Rex conversations opened from other entry points (the Agent page, the Workflow page)
are also collected under Session Management — so a debugging conversation you started on the
Workflow page can be found again in the session list.

---

## §1 Daily watch — manual re-run

When the scheduled task is healthy you do not need this. Use it only to backfill after a failed
run, to check one device ad hoc, or to verify a workflow change.

```text
Run tdp_daily_watch for <device name>, lookback window 24 hours.
Push the result to session_id: <your duty group session_id>.
```

Backfill a specific period:

```text
Run tdp_daily_watch for <device name>, lookback window 48 hours.
Do not push it — I will review it first.
```

## §2 Deep inspection — on demand

For PoV wrap-up, periodic security reviews, or pulling data before a customer meeting.
**It has a hard stop**: at node 6 it pauses for your adjudication, so do not start it when you
are pressed for time.

```text
Run a deep inspection on <device name> using the tdp-inspection workflow.

Customer: <customer name>
Threat window: 30 days
Asset window: 90 days
pov_mode: B
```

**Always state `pov_mode` explicitly — never let it guess:**

- `A` = we ran simulated attacks / dropped samples during the PoV
- `B` = pure passive monitoring of real traffic

Getting it wrong skews the whole report's classification systematically. In Mode B there is no
"our test" bucket, so a tidy batch of failed exploits has to be classified as external scanning in
the customer's environment rather than as our own traffic.

At the hard stop Rex gives you a two-column list (**Needs your adjudication** holds only items with
uncertain classification; **Objective items** are listed for cross-checking and do not block).
It writes the report only after you adjudicate.

## §3 Create the scheduled task (where the daily watch actually lands)

Run `tdp_daily_watch` manually once first and confirm the artifacts look right, then schedule it:

```text
Configure tdp_daily_watch as a scheduled task:
- Run daily at 08:00
- Device: <device name>
- Lookback window 24 hours
- Push results to session_id: <duty group session_id>
- A single tool failure must not abort the task — record it in coverage_gaps and continue
```

**Do not drop that last line.** A scheduled job that aborts on one failure means there was no
inspection that day, and usually nobody notices.

## §4 Get the session_id (prerequisite for pushing)

Pushing uses `session_id` to locate the target IM conversation. Ask **in the target group**
(WeCom / Feishu / DingTalk, with the bot already in the group):

```text
What is your session_id?
```

Rex returns it. Alternatively send `/status` in that IM conversation to see the bound Session,
Agent, model, and channel.

Put the value into the scheduled task description so the unattended run knows who to send to.

**Two gotchas:**

- Once the target IM conversation runs `/new`, it binds a **new** Session and the **old
  `session_id` stops working**. Check this first when pushes silently stop.
- `session_id` is a routing identifier. Confirm it is the group you intend before sending —
  inspection briefs contain internal IPs and hostnames.

## §5 Useful `/` commands

| Command | Purpose |
| --- | --- |
| `/skills` | Confirm `tdp-inspection-methodology` is recognised |
| `/skills refresh` | Refresh after installing the skill |
| `/workflows` | Confirm both workflows are present |
| `/tasks` | Check scheduled task status |
| `/status` | See the Session / Agent / model / channel bound to this conversation |
| `/compact` | Compress context in a long conversation |
| `/help` | All commands supported at this entry point (they vary slightly) |

## §6 Let Rex read the methodology directly (without running a workflow)

Sometimes you just want Rex to look at a batch of already-exported TDP data without the full
workflow:

```text
Load the Skill tdp-inspection-methodology and help me triage this batch of TDP alerts.
pov_mode is B (pure real traffic — we ran no simulated attacks).
Mark anything uncertain as pending_review. Do not adjudicate on the customer's behalf.
```

Do not drop that last line. Without it an LLM tends to hand every item a confident verdict, and a
wrong classification is the most dangerous inspection error.
