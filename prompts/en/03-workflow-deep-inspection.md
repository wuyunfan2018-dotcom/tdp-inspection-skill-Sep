# Paste into: Flocks → Agent Studio → Workflow → Create Workflow → Rex workbench (right panel)

> This is the **deep inspection** (manually triggered, with a hard-stop human review).
> See 02 for how it divides labour with the daily `tdp_daily_watch`.
> Paste everything **below the divider**. Review the generated `workflow.md` in the left
> **Process Description** panel and Accept, then click **Generate Workflow**.
> **Do not skip human review.**

---

Help me create a workflow: `tdp-inspection`.

Generation requirements:
- Every node needs explicit input and output schemas
- After generation, run single-node tests, then full integration tests
- Test data and artifacts land in the Workspace outputs directory
- Node 6 `human_review` is a **hard stop** — it must genuinely pause and wait for user input,
  never auto-skip

## 1. Goal

Perform one **read-only** security inspection of a ThreatBook TDP (NDR) device already onboarded
via API, producing:

- An **English Markdown inspection report** (action-first structure)
- A **structured JSON snapshot** for diffing against the next inspection

This is for **manual triggering** (PoV wrap-up, periodic security review, pulling data before a
customer meeting). It is not a continuous alerting job — hourly silent health monitoring belongs
to the separate daily workflow, and this one must not overlap with it.

### How this differs from TDP's own inspection report

TDP's built-in exported report lists alerts and assets, but its **`Security Recommendations`
chapter is empty** (the literal text is `(Input by inspectors, ...)`), and it performs no triage,
no noise reduction, and no cross-dimension correlation. Those three gaps are exactly what this
workflow fills.

## 2. Inputs

| Parameter | Required | Purpose | Behaviour if missing |
| --- | --- | --- | --- |
| `device_name` | Yes | TDP device name in Flocks | **Stop and ask. Do not guess.** |
| `customer` | Yes | Customer identifier, for output path and report header | Stop and ask |
| `threat_window_days` | Yes | Threat layer window in days, e.g. 30 | Stop and ask |
| `asset_window_days` | No | Asset layer window in days | Default 90 |
| `pov_mode` | Yes | `A` = we ran simulated attacks / dropped samples during the PoV; `B` = pure passive monitoring of real traffic | **Stop and ask. Never default.** |
| `assets_group` | No | Business group filter | No filter |
| `attack_list` | No | Attack list for PoV reconciliation (time window / source and target IP / attack name) | Skip the reconciliation section |

> **Why `pov_mode` must be asked**: it decides whether a tidy batch of failed exploits is
> "detection capability validation" or "external scanning in the customer's real environment".
> Getting it wrong skews the entire report's classification systematically.

## 3. Dual time windows

All TDP asset endpoints require `time_from` / `time_to`, which means the assets you retrieve are
really **"assets that appeared on the network during that window"**. Open the window too narrowly
and low-frequency assets (quarterly batch jobs, standby systems, cold spares) vanish entirely.

| Layer | Window | Rationale |
| --- | --- | --- |
| 0 Confidence | Now + last 7 days trend | Health is a present-tense state |
| 1 Assets | `asset_window_days` (long, default 90) | The goal is a complete inventory |
| 2 Threats | `threat_window_days` (short, user-specified) | The goal is what happened this period |
| 3 Correlation | **Short-window threats x long-window asset attributes** | "Is this alerting host an exposed asset?" — judge asset attributes with the fullest possible knowledge |

**Both windows must be printed in the report**, and every asset figure must be labelled with its
window.

### "Newly discovered" has two meanings — never mix them

| Field | Meaning | Source |
| --- | --- | --- |
| `tdp_flagged_new` | TDP's own Newly Discovered flag | Device basis |
| `new_since_last_inspection` | Derived by diffing against the last inspection snapshot | This workflow's snapshot |

On a first inspection, mark all `new_since_last_inspection` as `baseline` (**not** `new`), and state
in the report that this run is the baseline with nothing to compare against.

## 4. Node overview

```
[Start]
  |
(1) collect        Python + thread pool   Concurrently pull read-only tools -> raw data
  |
(2) denoise        Python                 Session dedup / triple aggregation / direction correction / classification / folding
  |
(3) profile        Python                 Asset three-facet statistics + efficacy metrics + operational metrics
  |
(4) correlate      Python                 Join assets with threats -> remediation priority queue
  |
(5) triage         Agent delegation       Load the methodology Skill; classify events + IOC enrichment
  |
(6) human_review   Human confirmation     HARD STOP: two-column findings list, wait for adjudication
  |
(7) compose        LLM                    Generate the English report + JSON snapshot -> Workspace
```

**Concurrency strategy**: concurrency belongs only in (1). Nodes (2), (3) and (4) need a **global
view** (relative baselines, Pareto, two-table joins) — splitting them across parallel branches
produces wrong numbers. Node (5) is bounded by the run-level LLM concurrency budget (1–5), so
reduce work through leader/follower grouping rather than by adding concurrency.

## 5. Node definitions

### (1) collect

**Responsibility**: concurrently call read-only device tools and retrieve raw layer 0/1/2 data.
**This node makes no judgements.**

**Read-only whitelist (20 tools, hard constraint)**

| Layer | Tool | Purpose |
| --- | --- | --- |
| 0 | `tdp_system_status` | All sub-status (core / DB / hardware / services / input / IOC update / cloud connectivity / timezone) |
| 0·1 | `tdp_dashboard_status` | Overview, blocking info, security statistics, attacking assets, file detection, stage statistics |
| 1 | `tdp_machine_asset_list` | `service_list` / `host_asset_list` / `web_app_frameworks` |
| 1 | `tdp_assets_domain_list` | Domain assets |
| 1 | `tdp_login_api_list` | Login portals `summary` / `category` / `list` |
| 1 | `tdp_login_weakpwd_list` | Weak Passwords |
| 1 | `tdp_interface_list` | API interface inventory |
| 1 | `tdp_interface_risk_list` | API risks |
| 1 | `tdp_asset_upload_api` | Upload interfaces `summary` / `host_list` / `interface_list` |
| 1 | `tdp_cloud_facilities` | Cloud service access sources and instances |
| 1 | `tdp_privacy_diagram` | Plaintext sensitive information topology |
| 1 | `tdp_vulnerability_list` | Vulnerabilities |
| 2 | `tdp_threat_alert_host` | `alert_host_list` -> `host_threat_list` |
| 2 | `tdp_threat_intelligent_aggregation` | Aggregated incidents + attack success / timeline / attacker |
| 2 | `tdp_threat_external_attack` | Inbound Attack severity distribution |
| 2·4 | `tdp_log_search` | `action=search` for evidence, `action=terms` for aggregation |
| Evidence | `tdp_pcap_download` | Packets by `alert_id` + `occ_time` (**high-value events only**) |
| Evidence | `tdp_file_download` | Malicious file by hash (**matched samples only**) |
| Reference | `tdp_mdr_alert_list` | MDR triage results (if the customer subscribes) |

**Explicitly prohibited**: `tdp_policy_settings` and `tdp_platform_config`. These can add blocklist
entries, trigger linked blocking, change alert Resolution Status, add/modify/delete assets, and
change custom rules. **An inspection tool does not modify the thing it inspects**, and write
operations would poison the next inspection's diff baseline. They are not on the whitelist and must
not appear in any node.

**Not used**: `tdp_threat_monitor_list` — its query range is hard-limited to <= 24 hours, and
inspection needs cross-period data.

**Implementation notes**

- Use a `ThreadPoolExecutor`. TDP rate-limits each endpoint at 50/s, which is generous; use
  concurrency 8–12.
- Compute timestamps **dynamically** (Unix seconds). Never hard-code them.
- `tdp_log_search` defaults `size` to **10** — raise it explicitly for aggregation (200–1000).
  This tool does **not** support `page_size`.
- **Force `is_plaintext = false`** on Weak Passwords (see §9).

**Pagination rule (observed in the field — must be hard-coded into the node)**

List endpoints **return only 20 records per page by default and do not auto-paginate.** Observed:
`service_list` returned 20 records while `page.total_num` was 445 — 4.5% of the data. Treating that
20 as the asset total would invalidate the entire attack surface analysis.

The node must:
1. Read `page.total_num` and `page.total_pages` from every list response first
2. **Loop until complete** (or until a configured cap)
3. **Self-check**: when `len(collected) != total_num`, mark the item `partial` and record both the
   retrieved count and the total in `coverage_gaps`
4. Ensure every asset figure in the report is `total_num`, not the number of records retrieved

**Aggregation source with fallbacks (terms has been observed entirely unavailable)**

| Priority | Source | Note |
| --- | --- | --- |
| Primary | `tdp_log_search action=terms` | Has `global_total` / `global_percent` / `distinct`; most accurate |
| **Fallback 1** | `tdp_threat_intelligent_aggregation` | The device has already aggregated once |
| **Fallback 2** | `tdp_threat_alert_host action=alert_host_list` | Host-level threat list and counts; supports a host-dimension relative baseline |
| Fallback 3 | `tdp_log_search action=search` + client-side aggregation in the node | Bounded by `size`; head of the distribution only |

When `terms` is unavailable the workflow **must degrade and state the changed basis in the report**:
the denominator for signal-to-noise is no longer an exact full-population value, so present it as
"an estimate based on host-level aggregation", never as an exact proportion.

**Fault tolerance (critical)**

If any tool fails, times out, or the module is not subscribed by the customer, record it as
`unavailable` and **continue**. **Never abort the whole workflow.** All `unavailable` items roll up
into `coverage_gaps`, feed directly into the layer 0 confidence statement, and the report must state
plainly which areas were not covered.

**Output schema (outline)**

```
{
  "meta": { device, customer, threat_window, asset_window, pov_mode, collected_at },
  "coverage_gaps": [ {tool, action, reason} ],
  "layer0_health": { ... },
  "layer1_assets": { services, hosts, domains, web_apps, login_portals, weak_passwords,
                     apis, api_risks, upload_interfaces, cloud, sensitive_data, vulnerabilities },
  "layer2_threats": { alert_hosts, host_threats, aggregated_incidents, severity_distribution,
                      terms_aggregations, raw_samples }
}
```

### (2) denoise

**Responsibility**: turn "rule hit counts" back into "events worth triaging". **Fold, never delete.**

Full rules in §6. Core principle: **always use a relative baseline, never an absolute threshold**.
Every folded bucket can be expanded back to its original alerts.

**Output schema (outline)**

```
{
  "events": [ {
      event_key, real_src, dst, threat_name, threat_type, severity,
      count, first_seen, last_seen, result_distribution,
      classification,        // scanner_like | background_scan | suspected_business | normal
      keep_reason,           // never_fold:<reason> | pareto_head | null
      is_folded, folded_count, sample_alert_ids[], evidence_pointer
  } ],
  "folded_buckets": [ ... ],
  "denoise_stats": { raw_alert_total, event_total, fold_ratio, never_fold_count }
}
```

### (3) profile

**Responsibility**: pure statistics, no judgements.

**Asset three facets** (compute for every asset class):

| Facet | Definition |
| --- | --- |
| Internet-facing | The `Internet-facing` flag |
| Newly discovered | `tdp_flagged_new` and `new_since_last_inspection` computed separately |
| Carrying risk | Weak Passwords / vulnerabilities / sensitive data / high-risk ports / unidentified services |

**Layer 4 detection efficacy metrics**

- Signal-to-noise: (`never_fold` + Pareto head event count) / total raw alerts (use `global_total`
  from `tdp_log_search action=terms`)
- Top N noise sources: `global_percent` aggregated by `threat.name`
- Suspected false positive candidates: buckets classified `suspected_business`
- Coverage blind spots: `coverage_gaps` + whether every attack stage has data

**Layer 5 operational maturity metrics**

- Resolution Status distribution: proportions of `disposal_status` 1/2/3 (the unhandled proportion
  is the key metric)
- Asset register completeness: proportion of hosts whose asset name is `Preset asset`
- Blocking policy usage: from `tdp_dashboard_status` blocking info (**read-only statistics, no
  changes**)

### (4) correlate

**Responsibility**: join layers 1 and 2 to produce the **remediation priority queue**. This is the
single most valuable output of the inspection.

Full rules in §7. **This node must run as a single unit** — it needs the global view of both layers,
and splitting it produces wrong results.

**Output**: a priority queue where each entry carries **two dimensions of evidence** (asset-side +
threat-side), sorted P0/P1/P2.

### (5) triage

**Responsibility**: delegate to an expert Agent, load the `tdp-inspection-methodology` Skill, and
classify the denoised events.

**Input**: `events` (`never_fold` + Pareto head only) + `correlation_queue` + `pov_mode` +
`coverage_gaps`

**Three jobs**

1. **Three-way traffic classification** — every event must land in `real_threat` /
   `customer_own_behavior` / `tdp_artifact` / `pending_review`
2. **IOC enrichment** — using only `threatbook_io_ip_query` / `threatbook_io_domain_query` /
   `threatbook_io_file_query`
3. **Family and attribution** — extract family characteristics from `threat.name`, `threat.type`,
   and log metadata

**Implementation notes**

- **Leader/follower grouping**: group by `event_key`, triage only the leader, reuse the conclusion
  for followers. Bounded by the run-level LLM concurrency budget of 1–5, reducing work beats adding
  concurrency.
- Anything uncertain is marked `pending_review`. **Never adjudicate production traffic on the
  customer's behalf.**

### (6) human_review — HARD STOP

**Responsibility**: pause, present the findings list, and wait for the user's adjudication before
continuing.

**The list must have two columns**

| Column | Content |
| --- | --- |
| **Needs adjudication** | Items with uncertain classification only. Each carries: leaning / evidence pointer / the consequence of each reading |
| **Objective items** | Hard signals and statistics, listed for cross-checking, non-blocking |

**What goes into "Needs adjudication"** (only two classes genuinely need a human):

1. **Scanner / drill vs genuine Lateral Movement** — `scanner_like` involving an internal source
2. **Is this the customer's own tool or behaviour** — `suspected_business`, suspected customer-owned
   scanners, admin tunnels, employee software

**What does not** (objective hard signals, finalised directly): device health, license expiry,
`threat.is_connected=1`, `threat.result=success`, `threat.characters` containing `is_compromised`,
Weak Passwords with `result=success`.

After the user confirms or corrects, write the classifications back to the events and proceed to (7).

### (7) compose

**Responsibility**: produce two artifacts in the Workspace.

```
inspection/<customer>/<YYYY-MM-DD>/
  |- report.md        English inspection report (structure in §8)
  |- snapshot.json    Structured snapshot for the next diff
```

The report body is **English**. When `coverage_gaps` is non-empty, **a confidence statement must
appear on page 1**.

## 6. Noise reduction rules (full)

### Stage 1 · Normalize

| Rule | Implementation |
| --- | --- |
| Session dedup | Same `id`; or same `(net.src_ip, net.src_port, net.dest_ip, net.dest_port, threat.name)` within a close time window -> merge into one event. One session matching multiple rules is **one behaviour**, not multiple attacks |
| **Direction correction** | If `net.real_src_ip` exists and differs from `net.src_ip` -> take `real_src_ip` as the true source and re-label `direction` as `in`. Reverse proxies and NAT systematically record Inbound Attacks as Lateral Movement |
| Asset attribution | Join `src` / `dst` against the layer 1 asset table, tag internal/external, and **override** `src_tag` / `dest_tag`. If the customer uses public address ranges internally, the device will place them abroad using the public IP database |
| Hairpin detection | Source and target both being the customer's own public addresses -> tag `hairpin` (NAT hairpin), excluded from Inbound Attack counts |

### Stage 2 · Aggregate

- Triple buckets: `(real_src, dst, threat.name)` -> `count` / `first_seen` / `last_seen` / `result`
  distribution
- Temporal regularity: when the coefficient of variation (CV) of intervals within a bucket falls
  below a threshold, tag it `periodic` — the shared signature of scheduled jobs, business polling,
  and timed worm behaviour

### Stage 3 · Classify (all relative)

| Class | Criteria |
| --- | --- |
| `scanner_like` | Single source `distinct(dst)` > network-wide median `distinct(dst)` x K **and** `distinct(threat.name)` > M **and** `result` predominantly `failed`/`unknown` |
| `background_scan` | External source + low frequency + `result=failed` + no subsequent attack stage |
| `suspected_business` | `periodic` + `result != success` + target is an owned asset + normal HTTP response codes |
| `normal` | Everything else |

> Expose K and M as tunable workflow parameters, defaulting to K=5, M=10.
> **Never hard-code absolutes** like "hit 100 targets" or "over 5000 alerts" — they break the moment
> you change customer environments.

**Degradation path for the relative baseline**: `distinct(dst)` comes from `terms` aggregation by
preference. When that endpoint is unavailable, switch to `alert_host_list` host-level data and
compute "target hosts associated with each source host", taking the median from that distribution.
Both bases are valid, but **they must not be mixed**, and the report must state which was used.

### Stage 4 · Split

**Never-fold list (unconditionally triaged individually, exempt from Pareto splitting)**

| Condition | Rationale |
| --- | --- |
| `threat.characters` contains `is_compromised` | Already compromised |
| `threat.is_connected = 1` | C&C connection established — the hardest signal |
| `threat.result = 'success'` | Attack succeeded |
| `threat.is_apt = 1` | APT attribution |
| `severity = 4` (critical) | Device's highest severity |
| `threat.type` in {trojan, rat, shell, dc, tunneling} | Backdoor / RAT / webshell / C2 / tunnel |

> The last row matters most: **these alerts are inherently low-volume.** A pure alert-count Pareto
> will always fold them into the long tail — and they are precisely what the inspection exists to find.

**Everything else**: sort by `global_percent` of `threat.name` descending, take the head accumulating
to **P%** (default 80%) into triage, fold the long tail into statistical buckets. **All folding is
reversible** — retain `count`, time span, representative `alert_id`, and evidence pointer.

> When `global_percent` is unavailable, normalise proportions from the fallback source's event
> counts. The splitting logic is unchanged, but **the denominator is an estimate** and the report's
> basis note must say so.

## 7. Correlation rules (full)

| Priority | Rule | Condition (all from collected fields) |
| --- | --- | --- |
| **P0** | Near-compromise | Weak Password `result=success` **and** the asset is `Internet-facing` |
| **P0** | Compromised and able to spread | `is_compromised` **and** the host itself serves externally |
| **P0** | Exposed surface breached | Asset is `Internet-facing` **and** an alert exists with `threat.result=success` |
| **P1** | Shadow IT / attacked on arrival | `new_since_last_inspection` **and** has alerts |
| **P1** | **Monitoring blind spot** | An alerting IP that is **absent** from the layer 1 asset table -> the asset register is incomplete |
| **P1** | Internal pivot | A `direction=lateral` source host **that** also serves externally |
| **P2** | Latent, unexploited | Asset exposed + Weak Password/vulnerability, **but no** related alerts |

Every entry must carry **two dimensions of evidence**: asset-side (exposure state / service / port /
Weak Password) and threat-side (threat name / result / count / time). Entries with only one
dimension do not enter the queue.

## 8. Report structure (action-first)

```
1. Executive Summary
   - One-sentence conclusion
   - [Confidence statement] mandatory when coverage_gaps is non-empty; state plainly which
     conclusions must be downgraded
   - Observation windows (print both)

2. Remediation Priority Queue        <- layer 3 output, the most valuable section
   P0 / P1 / P2, each with two dimensions of evidence + recommended action

3. Threat Findings                   <- layer 2
   Grouped by classification: confirmed threats / customer's own behaviour /
   statistical artefacts / pending confirmation

4. Assets & Attack Surface           <- layer 1
   Overview + three facets (Internet-facing / newly discovered / carrying risk)

5. Detection Efficacy & Tuning       <- layer 4
   Signal-to-noise, top N noise sources, suspected false positives, coverage blind spots,
   tuning recommendations

6. Operational Maturity              <- layer 5
   Resolution Status distribution, asset register completeness, blocking policy usage

7. Items for Customer Confirmation
   Only things the customer can claim, each with evidence and our leaning

Appendix: folded bucket statistics / IOC list / data basis notes
```

## 9. Safety red lines (non-negotiable)

1. **Strictly read-only.** The whitelist contains only the 20 read tools;
   `tdp_policy_settings` / `tdp_platform_config` must not appear in any node.
2. **No plaintext passwords.** Force `is_plaintext = false`; the report records only username,
   password length and strength characteristics, and the matched rule — **never the password itself**.
3. **ThreatBook intelligence only for IOC enrichment** (`threatbook_io_*`). VirusTotal, AbuseIPDB,
   and any third-party source are **prohibited** from IOC judgement — these tools may be enabled in
   the environment, so the node prompt must disable them explicitly.
4. **Report only what was actually retrieved.** Mark unenriched items `not_enriched`; never fabricate
   a source, link, or conclusion.
5. **Customer data stays local.** Internal IPs, hostnames, accounts, and asset topology go only to
   the local Workspace and never into an external query.
6. **Never adjudicate for the customer.** Uncertain classifications of production traffic stay
   `pending_review` for human adjudication.

## 10. Acceptance criteria

- [ ] Node test: (1) completes with some tools unavailable and populates `coverage_gaps` correctly
- [ ] Node test: (2) folded buckets expand back to original alerts; never-fold entries survive at any
      folding ratio
- [ ] Node test: (4) every queue entry carries two dimensions of evidence
- [ ] Integration test: a missing `pov_mode` stops and asks rather than using a default
- [ ] Integration test: (6) genuinely pauses and does not reach (7) without confirmation
- [ ] Artifact check: `report.md` page 1 carries a confidence statement when `coverage_gaps` is
      non-empty
- [ ] Artifact check: `snapshot.json` can be read by the next run to compute
      `new_since_last_inspection`
- [ ] **Pagination completeness**: for every list endpoint, records retrieved == `page.total_num`;
      any mismatch must appear in `coverage_gaps`
- [ ] **Aggregation degradation**: with `action=terms` artificially blocked, the workflow still
      completes, switches to a fallback automatically, and the report states the changed basis
- [ ] Red line check: no write operation anywhere in the run; grep the whole report for plaintext
      passwords — zero hits
