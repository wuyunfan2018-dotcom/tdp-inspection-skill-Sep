# Skill: tdp-inspection-methodology

Both workflows (daily `tdp_daily_watch` + deep `tdp-inspection`) **share this one skill**.
Install it first, then build the workflows.

---

## Path A (recommended): copy the files, lose nothing

The skill is already written, at `~/work/TDP-Inspection-Flocks/skills/tdp-inspection-methodology/`.
It contains SKILL.md plus 4 references (triage rules, TDP tool/field reference, data quirks,
report template) — roughly 34KB.

**Having Rex regenerate it can only lose information** — those 4 references are field-tested
gotchas that Rex cannot invent. So copy the files whenever you can:

```bash
cp -r ~/work/TDP-Inspection-Flocks/skills/tdp-inspection-methodology ~/.flocks/plugins/skills/
```

Verify in a Flocks session:

```text
/skills refresh
/skills
```

If `tdp-inspection-methodology` shows up, you are done.

> ⚠️ **Do not use `flocks skills install /local/path`, and do not put a local path into the page's
> Install Skill dialog.** The documentation states plainly that the local-path installer
> **only reads and saves `SKILL.md` — it does not copy `references/`, `scripts/`, or `templates/`**
> from the same directory. Everything valuable in this skill lives in the 4 references, so that
> route installs an empty shell. Only two routes deliver the complete directory:
> **`cp -r` the folder**, or **push it to a private GitHub repo and install with a `github:` source**.
>
> Also, "local path" means a path on **the machine running the Flocks service**, not the computer
> where your browser is. **Priority: user-level `~/.flocks/plugins/skills/` > project-level.**
> Same names override — avoid duplicates.

---

## Path B (fallback): if Flocks cannot reach the files, paste this and let Rex build it

> Paste everything below the divider into a Flocks session.
> Note: this produces the trunk methodology only — **without the field-tested detail in the 4
> references**. You will have to rebuild that from real engagements.

---

Help me create a Skill: `tdp-inspection-methodology`.

**Purpose**: the **triage methodology** for inspecting ThreatBook TDP (an NDR product). Load it
when judging the nature of TDP alerts, deciding whether a host is a scanner or genuine Lateral
Movement, deciding whether a behaviour is a threat or the customer's own activity, grading
inspection findings, or writing a TDP inspection report.

**Boundary**: this skill only covers **how to judge**. Collection, noise reduction, statistics, and
correlation are deterministic computation handled by the companion workflows. The skill contains
no collection steps and does not replace a workflow.

The reason for that split: precise counting, deduplication, aggregation, and joining two tables are
where an LLM is least reliable — give those to the workflow. Classification, family attribution,
and narrative are where an LLM is strong — give those to the skill.

## Methodology

### 0. One thing to establish before starting

**During the PoV or test period, did we run simulated attacks or drop samples? Do not assume.
Do not default.**

| Mode | Meaning | Classification framework |
| --- | --- | --- |
| A | We ran simulated attacks / dropped samples | Our traffic is "detection capability validation"; customer traffic is "live-network findings". **The two must be written separately.** |
| B | Pure passive monitoring of real traffic (more common) | **There is no "our test" bucket.** Every alert is real traffic from the customer's real environment. |

Getting this wrong skews the classification of the entire report systematically. The classic
mistake in Mode B is reporting the customer's own security tooling (vulnerability scanners, BAS,
red team), IT operations behaviour (admin tunnels, bulk push), or employee behaviour (remote access
software) as attacks. **Only the customer can claim that bucket** — give a leaning and the evidence,
never decide on their behalf.

### 1. The six-layer framework (inspection is a funnel — each layer is meaningless if the one above fails)

| Layer | Answers | Key output |
| --- | --- | --- |
| 0 Confidence | Can this data be trusted? | Confidence rating + downgrade statement |
| 1 Asset reality | What is actually on the network? | Attack surface inventory (three facets) |
| 2 Threat reality | What is happening on the network? | Classified event list |
| 3 Correlation | Which assets appear on both sides? | **Remediation priority queue** |
| 4 Detection efficacy | How is the device performing? | Signal-to-noise ratio + tuning list |
| 5 Operational maturity | How well is the customer responding? | Management-level recommendations |

**Layer 0 is the gate**: when engines are stale, cloud intelligence is unreachable, the mirror port
is abnormal, or collection has gaps, every downstream "no threats found" conclusion **may be a miss
rather than a clean result**. State the downgrade on page 1.

**Layer 3 is the core**: layers 1 and 2 in isolation are available from the device's own report.
But no off-the-shelf report joins the two — and the genuinely high-severity findings appear only at
the intersection.

### 2. The three-way traffic classification (the one mandatory human review point)

Every event entering triage must land in one of four buckets. No skipping, no defaults:

| Classification | Characteristics | Response posture |
| --- | --- | --- |
| `real_threat` | Intelligence hit, `is_connected=1`, `result=success`, real data egress | Act now |
| `customer_own_behavior` | Customer's own security tooling / IT ops / employee behaviour — real but not an attack | Governance decision. **Only the customer can claim it** |
| `tdp_artifact` | Statistical artefact or mechanism by-product | Exclude, but explain why |
| `pending_review` | Evidence insufficient | List the evidence, hand to a human |

**Hard rule**: treating a real threat as a drill, or treating the customer's own scanner as a
compromise, are the two most dangerous inspection errors. **If in doubt, mark it in doubt.** Never
adjudicate production traffic on the customer's behalf.

### 3. Compromise determination priority

1. `threat.is_connected = 1` (C&C connection established) — **the hardest signal, ranking above
   "attack succeeded"**
2. `threat.characters` contains `is_compromised`
3. `threat.result = success`

For a compromised host, always check **secondary behaviour**: is it now moving laterally or
attacking outbound? Compromise + spread raises the grade.

`result = unknown` does **not** mean unsuccessful. When passive detection cannot confirm the
outcome, judge it together with the target's patch state and subsequent behaviour. Do not wave it
through as "did not succeed".

### 4. Scanner vs genuine Lateral Movement (all three must hold, all measured relatively)

1. The **number of targets** hit by a single source is far above the network-wide median
2. **Threat variety explodes** — one host generating many unrelated vulnerability families
3. Results are **predominantly failed or unknown**

All three together strongly suggest a scanner or attack simulator. But in Mode B, **whether that is
the customer's security tool or a controlled host sweeping the network is something only the
customer can claim** — it must go to adjudication.

**Never use absolute thresholds** ("hit 100 targets", "over 5000 alerts"). They break the moment you
change customer environments. Always use a relative baseline.

### 5. Tunnels get called out separately

`threat.type = tunneling` gets reported on its own even at low volume: it bypasses perimeter
controls, is encrypted and unauditable, and gives the outside a direct path into the internal
network as long as the process is running. Classify it as a **governance problem, not a malware
problem** — either bring it under formal management or remove it. "Nobody knew it was there" is not
an acceptable end state.

### 6. Grading self-consistency check

The device's overall posture grade must be consistent with the itemised findings. When the posture
grade is low but there is confirmed compromise or successful backdoor communication: **state the
contradiction explicitly** in the report and recommend action (e.g. review the posture threshold
configuration). **Do not follow the device's grade blindly, and do not silently overwrite it** —
present the contradiction, give a recommendation, let the customer decide.

### 7. Per-layer triage notes

**Layer 1 assets**: run every asset class through three facets (Internet-facing / newly discovered /
carrying risk). "Newly discovered" has two different meanings (device-flagged vs diff against the
last inspection) — **they must not be mixed**; print them separately. EOL middleware is structural
risk and outranks ordinary vulnerabilities. Unidentified services are a blind spot, not "no risk".
For Weak Passwords, look at the login result: a weak password **with a successful login is already
being exploited**, not merely a latent risk. Every asset figure must be labelled with its time
window — what NDR sees is "assets that spoke during the window".

**Layer 4 efficacy**: compute signal-to-noise against the **device's full-population base** from the
aggregation endpoint, never against a paginated, truncated detail list. Suspected false positives
need an **actionable tuning step** (add an ignore rule / reclassify the alert / add X-Forwarded-For /
register the reverse proxy asset), not just "this is a false positive". A completely empty attack
stage usually means a deployment position or collection configuration problem, not a genuine absence.

**Layer 5 operations**: a high unhandled ratio means missing process or missing people, not a device
problem. Mostly default asset names means no asset register exists. Write this layer's
recommendations for management, not as technical actions.

### 8. Red lines

1. **Read-only.** No blocking, no changing resolution status, no configuration changes, no rule
   additions. An inspection tool does not modify the thing it inspects.
2. **ThreatBook intelligence only for IOC enrichment.** VirusTotal, AbuseIPDB, and any third-party
   source are prohibited from IOC judgement — these tools may be enabled in the environment; do not
   use them even if you can see them.
3. **Report only what was actually retrieved.** Mark anything unretrieved as "not enriched — pending
   manual review". Never fabricate a source, link, or conclusion, and do not write unauthorised
   source comparisons such as "not found in public sources".
4. **No plaintext passwords.** Record only username, password length and strength characteristics,
   and the matched rule.
5. **No exaggeration, no adjudication.** List the evidence for uncertain items and hand them to the
   customer.
6. **Terminology follows the product's English UI — do not invent translations**: Inbound Attack /
   Lateral Movement / Compromised / alert / incident / TCP reset / Attack Surface / Weak Passwords /
   Resolution Status.

## Output requirement

Once the skill is created, reserve four files under `references/` to be filled in from real
engagements: `triage-rules.md` (detailed triage rules), `field-reference.md` (TDP tool and field
reference), `quirks.md` (data-basis traps and statistical artefacts), `report-template.md` (report
skeleton and wording).
