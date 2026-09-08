# Paste into: Flocks → Agent Studio → Workflow → Create Workflow → Rex workbench (right panel)

> Paste everything **below the divider**.
> Rex generates `workflow.md` first (the requirements contract). Review it in the left
> **Process Description** panel and click Accept, then click **Generate Workflow** to produce
> `workflow.json`. **Do not skip human review.**

---

Help me create a workflow: `tdp_daily_watch` — TDP daily posture brief.

## Positioning (read this first — it drives every design trade-off below)

This is **not** a slimmed-down deep inspection. It is a **change detector**. Every morning it
answers one question: **"What changed on TDP yesterday that I need to look at?"**

So its headline content is the **delta against yesterday**, not a stock count.
"3 newly compromised hosts since yesterday" is useful. "47 hosts have alerts" is not —
it was 47 yesterday and 47 the day before, and the reader goes numb.

I already have a separate workflow, `tdp-inspection`, for manually triggered deep inspection
(it has a hard-stop human review node). The division of labour must stay clean, and
**this workflow must not duplicate it**:

| | `tdp_daily_watch` (this one) | `tdp-inspection` (existing) |
| --- | --- | --- |
| Trigger | Task Center schedule, unattended | Manual |
| Window | Last 24h + diff against yesterday's snapshot | User-specified (e.g. 30/90 days) |
| Human review | **No hard stop** — must never block | Hard stop, waits for adjudication |
| Answers | What changed yesterday | What is the overall state of this environment |
| Output | Short brief pushed to IM + snapshot | Full English report + snapshot |

## Inputs

| Parameter | Required | Purpose | Behaviour if missing |
| --- | --- | --- | --- |
| `device_name` | Yes | TDP device name in Flocks | **Stop and ask. Do not guess.** |
| `notify_session_id` | No | Flocks `session_id` to push the brief to | Skip push, write to disk only |
| `lookback_hours` | No | Lookback window | Default 24 |
| `assets_group` | No | Business group filter | No filter |

## Node flow

```
(1) collect_light   Python thread pool   Concurrently pull health + 24h threats + asset changes
(2) reduce          Python               Session dedup + never-fold extraction (deterministic)
(3) diff            Python               Compare against yesterday's snapshot -> new / gone / escalated
(4) enrich          Agent delegation     IOC enrichment for never-fold entries only (rate-limited)
(5) compose_brief   LLM                  Generate the brief
(6) dispatch        Python               Push to IM + write snapshot + escalation decision
```

Concurrency belongs only in (1). Nodes (2) and (3) need a global view — splitting them across
parallel branches produces wrong numbers.

## Node requirements

### (1) collect_light — lightweight collection

**Read-only tool whitelist** (strictly read-only, see Safety Red Lines below):

- Health layer: `tdp_system_status` (core services / hardware / DB / input sources / IOC update /
  cloud connectivity), `tdp_dashboard_status`
- Threat layer: `tdp_threat_alert_host` (`action=alert_host_list`),
  `tdp_threat_intelligent_aggregation`, `tdp_log_search`
  (`action=terms` for aggregation, `action=search` for samples)
- Asset layer (**changes only, not a full inventory**): `tdp_machine_asset_list`,
  `tdp_login_weakpwd_list`, `tdp_vulnerability_list` — used only to spot newly exposed assets.
  Full attack surface analysis belongs to the deep inspection workflow.

**Implementation requirements — every one of these comes from a real failure in the field and
must be hard-coded into the node:**

1. **List endpoints return only 20 records per page by default and do not auto-paginate.**
   Read `page.total_num` / `page.total_pages` from the response first, then loop until complete.
   If the collected count != `total_num`, mark that item `partial` and record it in `coverage_gaps`.
   Every asset figure in the brief must be `total_num`, never the number of records fetched.
2. **`tdp_log_search` defaults `size` to 10.** Raise it explicitly for aggregation (200–1000).
   This tool does **not** support a `page_size` parameter.
3. **Compute timestamps dynamically** (Unix seconds). Never hard-code them.
4. **Force `is_plaintext = false`** on the weak password endpoint.
5. TDP rate-limits each endpoint at 50/s, which is generous. Use concurrency 8–12.

**Aggregation source with fallbacks** — `action=terms` has been observed to be entirely
unavailable in the field. That is a missing server-side capability, not a parameter problem:

| Priority | Source |
| --- | --- |
| Primary | `tdp_log_search action=terms` (has `global_total` / `global_percent`; most accurate) |
| Fallback 1 | `tdp_threat_intelligent_aggregation` (device already aggregated once) |
| Fallback 2 | `tdp_threat_alert_host action=alert_host_list` (host-level aggregation) |

When falling back, the brief **must state the changed basis**, and any percentage becomes
an estimate rather than an exact figure.

**Fault tolerance**: if any tool fails, times out, or is not subscribed, record it in
`coverage_gaps` and **continue**. Never abort the whole workflow. A scheduled job that
aborts on a single failure means there was no inspection that day.

### (2) reduce — noise reduction (deterministic; makes no judgements)

- **Session dedup**: same `id`, or same `(net.src_ip, net.src_port, net.dest_ip, net.dest_port,
  threat.name)` within a close time window, merges into one event. One session matching multiple
  rules is **one behaviour**, not multiple attacks.
- **Direction correction**: if `net.real_src_ip` exists and differs from `net.src_ip`, take
  `real_src_ip` as the true source and re-label `direction` as `in`. Reverse proxies and NAT
  systematically record Inbound Attacks as Lateral Movement.
- **Triple aggregation**: `(real_src, dst, threat.name)` -> `count` / `first_seen` / `last_seen` /
  `result` distribution.

**Never-fold list — reported individually and unconditionally, exempt from all folding:**

| Condition | Rationale |
| --- | --- |
| `threat.is_connected = 1` | C&C connection established — the hardest signal |
| `threat.characters` contains `is_compromised` | Already compromised |
| `threat.result = 'success'` | Attack succeeded |
| `threat.is_apt = 1` | APT attribution |
| `severity = 4` (critical) | Device's highest severity |
| `threat.type` in {trojan, rat, shell, dc, tunneling} | Backdoor / RAT / webshell / C2 / tunnel |

The last row matters most: **these alerts are inherently low-volume.** Ranking purely by alert
count buries them in the long tail — and they are exactly what a daily brief exists to surface.

Everything else folds into statistical buckets by alert volume. **Folding must be reversible**
(retain count, time span, representative `alert_id`).

### (3) diff — compare against yesterday (the core output of this workflow)

Read the previous run's snapshot and emit four categories:

| Category | Definition | Position in the brief |
| --- | --- | --- |
| `new` | Absent from yesterday's snapshot | **Headline** |
| `escalated` | Existed, but severity rose / gained a success flag / gained a C&C connection | **Headline** |
| `ongoing` | Present and unchanged | Folded to a single count line |
| `resolved` | Present yesterday, gone today | One line |

**`ongoing` must be folded.** The most common way a daily brief becomes noise is re-expanding
the same backlog every morning; readers stop opening it within two weeks. Give ongoing items one
line — "Ongoing: N items, M of them high severity" — expandable on demand.

**First run**: there is nothing to compare against, so mark everything `baseline` (**not** `new`)
and state in the brief that this run is the baseline.

### (4) enrich — IOC enrichment (rate-limited)

- **Enrich never-fold entries only.** This workflow runs every day; enriching everything will
  exhaust the intelligence quota.
- Use only `threatbook_io_ip_query` / `threatbook_io_domain_query` / `threatbook_io_file_query`.
- **Prohibited**: VirusTotal, AbuseIPDB, or any third-party source for IOC judgement. These tools
  may be enabled in the environment — do not use them even if you can see them.
- Mark anything unenriched or failed as `not_enriched`. **Never fabricate a source, link, or
  conclusion.**

### (5) compose_brief — generate the brief

Load the Skill `tdp-inspection-methodology` as the judgement basis. The brief structure is fixed,
**in this order**:

```
1. [Confidence]      One line. Green / Amber / Red + one-sentence reason
2. [Look now]        New + escalated high severity, itemised:
                     host / threat / hard signal / recommended action
3. [Changes]         new / escalated / resolved summary
4. [Ongoing]         One count line, not expanded
5. [To confirm]      Items with uncertain classification, with evidence — non-blocking
6. [Escalate to deep inspection?]   Yes/No + reason + suggested window
```

**Section 1 must come first and must never be omitted.** This is the single biggest risk in a
daily inspection: if TDP itself is unhealthy (detection engines stale, cloud intelligence
unreachable, mirror port abnormal, traffic near interface capacity), then "no high-severity
findings yesterday" does **not** mean clean — it may mean blind. Reporting "all normal" every
morning while the sensor is blind is worse than running no inspection at all, because it
manufactures false assurance.

Health assessment: the three engines (TI / AI / Signature) **must be checked separately — they can
be out of sync**. Any one significantly stale downgrades confidence. Cloud intelligence
unreachable means IOC enrichment is dead. An approaching license expiry must appear in the brief,
or nobody will act on it.

**Anything with uncertain classification goes to section 5 and does not block sending.** This is
the key structural difference from the deep inspection workflow: the deep version can stop and
wait for adjudication; a daily brief cannot. But **uncertainty must not disappear because of
that** — it goes to section 5 with its evidence and the consequences of each reading, so the duty
analyst can decide whether to follow up.

Tone: no exaggeration, and never adjudicate the nature of production traffic on the customer's
behalf.

### (6) dispatch — distribution

1. Write the snapshot to the Workspace: `daily_watch/<device>/<YYYY-MM-DD>/snapshot.json` —
   this feeds tomorrow's diff.
2. Write the brief to `brief.md` in the same directory.
3. If `notify_session_id` is set, push the brief to that session.
4. **Send on quiet days too.** "Nothing happened yesterday" is information. Without a message the
   duty analyst cannot tell "genuinely quiet" from "the job died" — and the second is far more
   dangerous. On a quiet day send one line: confidence status + "no new high severity" + ongoing count.

**Escalation decision**: if any of the following holds, recommend a deep inspection in section 6
and give a suggested time window:

- A new `is_compromised` or `is_connected=1`
- Confidence is Red (device health is materially broken)
- `escalated` count exceeds 2x the trailing 7-day average
- The same `pending_review` items appear 3 days running (something is going unclaimed)

## Safety red lines (non-negotiable)

1. **Strictly read-only.** `tdp_policy_settings` and `tdp_platform_config` **must not appear in any
   node** — they can add blocklist entries, trigger linked blocking, change alert resolution status,
   and change configuration. An inspection tool does not modify the thing it inspects, and write
   operations would poison the next day's diff baseline.
2. **No plaintext passwords.** Force `is_plaintext=false`; record only username, password length
   and strength characteristics, and the matched rule.
3. **ThreatBook intelligence only for IOC enrichment**; third-party sources prohibited (see (4)).
4. **Report only what was actually retrieved.** Mark unenriched items `not_enriched`. Do not
   fabricate sources, links, or conclusions, and do not write unauthorised source comparisons such
   as "not found in public sources".
5. **Customer data stays local.** Internal IPs, hostnames, accounts, and asset topology are written
   only to the local Workspace.
6. **Never adjudicate for the customer.** Uncertain items stay `pending_review`.

## Acceptance criteria

- [ ] Node test: (1) completes with some tools unavailable and populates `coverage_gaps` correctly
- [ ] Node test: (1) for every list endpoint, records fetched == `page.total_num`; any mismatch
      appears in `coverage_gaps`
- [ ] Node test: (2) never-fold entries survive at any folding ratio
- [ ] Node test: (3) the first run marks everything `baseline`, not `new`
- [ ] Integration test: a missing `device_name` stops and asks rather than using a default
- [ ] Integration test: with `action=terms` artificially blocked, the run still completes, falls
      back automatically, and the brief states the changed basis
- [ ] Integration test: the brief is **still sent** when there are no new high-severity findings
- [ ] Artifact check: `snapshot.json` can be read by the next day's run to produce a diff
- [ ] Red line check: no write operation anywhere; grep the brief for plaintext passwords — zero hits

## Generation requirements

- Every node needs explicit input and output schemas
- After generation, run single-node tests, then full integration tests
- Test data and artifacts land in the Workspace outputs directory
