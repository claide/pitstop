## Step 0: Quota check (Pitstop)

Run this before any planning or code changes. Skip it only if the user says "skip quota check".

**Pitstop-not-installed handling (do this exactly once per conversation, not once per ticket):**
The first time in this conversation that `pitstop check` fails because the command isn't found,
tell the user in one line — e.g. "Pitstop isn't installed, skipping the quota check for this
ticket." — and continue Step 1 onward without Steps 3 and 4. For every ticket after that *in the
same conversation*, skip Steps 3 and 4 silently, with no message at all — don't repeat the
notice. If a new conversation starts, the once-per-conversation notice resets: mention it again
on the first ticket of that new conversation.

### 1. Read the ticket fields (Geekee Jira)
- Story Points: `customfield_10026`
- Technical Implementation: `customfield_10043`
- Story Point Criteria: `customfield_10284` (use only if its ratings are filled in)

Ignore QA Story Points (`customfield_10216`) and Story point estimate (`customfield_10016`).

### 2. Pick the size from Technical Implementation
Score +1 for each that applies:
- 5 or more implementation steps
- Payment provider or other third-party integration
- Must match a legacy brand's behavior exactly (legacy code has to be read)
- Behavior branches on a feature flag
- 2 or more API calls to wire up
- Database migration or backend schema change

Score −1 for each that applies:
- Explicitly reuses an existing component or flow

Total: 0–1 = `light`, 2–3 = `normal`, 4+ = `heavy`.

If Story Point Criteria is filled in, use it instead: mostly Low = `light`, mostly Medium = `normal`,
any High in Novelty or Dependency = `heavy`.

Missing data:
- No Technical Implementation → use `normal`, and say so.
- No Story Points → use `--points 3`, and say so.
- Neither → ask the user whether to proceed without a check.

### 3. Check
```bash
pitstop check --points <POINTS> --size <SIZE>
```
Pitstop turns points and size into the percentage needed (its table is calibrated from real
tickets over time), then prints one line and exits with:

- `0`: go. If the line says "tight", warn the user and ask before starting.
- `1`: wait. Show the line (it includes the reset time and any other account with room).
  Ask whether to wait, switch account, or start anyway.
- `2`: unknown (e.g. login expired). Show the line and ask whether to proceed.
- `3`: split. Recommend splitting the ticket and stop unless the user overrides.

Before the Pitstop line, print how the size was chosen, e.g.
`GEEK-11699: 3 pts, heavy (score 4: 5 steps, TrustPay, legacy parity, feature flag, API calls, −1 reuses iframe).`

### 4. Record actual usage
- Right before starting work: `pitstop mark start <KEY> --points <POINTS> --size <SIZE>`
- Right after the PR is opened: `pitstop mark end <KEY>`

After 10 finished tickets, remind the user once to run `pitstop calibrate` to review the real costs.