# ZenSched Pet-Care Reference Kit

A copy-pasteable setup for a 1–5 person dog walking or pet sitting business that wants an AI assistant to run scheduling, GPS-verified visit reports, client and pet records, and invoicing. ZenSched handles the live schedule, the walker's phone app, GPS check-ins at the client's door, and the photo-plus-checklist Visit Report. A small local database on your computer holds your clients, pets, prices, recurring schedule, and invoices.

**You do not need to know how to program or write SQL to use this.** You type plain English to your AI assistant ("schedule next week for Maya", "add a new client", "what happened with Bella this week?", "who owes me money?") and the AI does the work using two tools you set up once. Setup takes about 15 minutes and is the only technical part.

If you *are* a developer, skip to [For developers](#for-developers).

## What lives where

**ZenSched (source of truth for what happened, when, and where):**

- Locations (client homes with GPS coordinates and a check-in radius)
- Workers (walkers and sitters with the mobile app)
- Events (one "Pet care" job per home, renewed every 60 days)
- Shifts (each scheduled visit, with push notifications to the walker)
- GPS punches (check-in/check-out with distance-from-the-door verification)
- The Visit Report form (activities, peed/pooped, meds, notes, up to 3 photos, concerns) and every submission
- Timesheets (verified hours worked)

**Local SQLite database (`petcare-ops.db`, on your computer):**

- Client contact info and billing notes
- Addresses, including access notes (lockbox code, alarm word, where the key is) that **never leave your computer**
- Pets: species, breed, meds, feeding notes, vet, behaviour flags
- Your price list (30-min walk, 60-min walk, drop-in, overnight, puppy visit)
- The recurring schedule (which weekdays, what time, which service) per client
- Completed visits with a summary of each Visit Report, and invoices
- Your settings (timezone, default walker, invoice prefix, Visit Report form id)

**Never duplicated:** the live schedule, punches, timesheets, and report photos stay in ZenSched. The local database only stores *references* to them plus a short per-visit summary so you can answer "how was Bella this week" without paying to re-read reports.

### Privacy note

Lockbox codes, alarm words, garage codes, and key hiding spots are stored only in `addresses.access_notes` in the local database. `SKILL.md` forbids the AI from putting them into any ZenSched field. Give them to your walker yourself, by whatever channel you trust. ZenSched only ever sees the street address and the GPS pin.

## How it works day to day

Your AI assistant has two sets of tools:

1. **ZenSched tools** (`location_create`, `shift_create`, `form_submissions`, `shift_list`, ...) that talk to ZenSched over the internet.
2. **A SQLite tool** (`sqlite_query`, `sqlite_execute`) that reads and writes `petcare-ops.db` on your computer.

When you say "schedule next week," the AI expands your recurring schedule for the next 7 days from the local database, creates one shift per visit on ZenSched, and tells you what it did. Your walker sees the visits in the app, checks in at the door (GPS-verified), fills in the Visit Report with photos, and checks out. Later you say "record this week's visits" and the AI pulls the completed shifts and reports, saves a summary locally, and flags anything the walker marked as a concern. You never run SQL yourself. `SKILL.md` in this repo is the instruction sheet that teaches the AI how to do all of this; you paste it into your AI tool once.

## Setup

### 0. What you need

- **An AI tool that supports MCP.** These instructions use Claude Desktop (Windows or Mac). Cursor works too.
- **Node.js 20 or newer.** The SQLite tool runs on it. Download the LTS installer from [nodejs.org](https://nodejs.org/) and run it with the defaults. This is the only software install.
- You do **not** need the `sqlite3` command-line program, Python, or Git.

### 1. Make a folder for your data

Create a folder where the database will live and write down its full path. Examples:

- Windows: `C:\Users\YourName\petcare-ops`
- Mac: `/Users/yourname/petcare-ops`

The database file will be created automatically inside this folder the first time the AI uses it.

### 2. Add both tools to your AI's config file

Open the MCP configuration file for your AI tool:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json` (paste that into the File Explorer address bar)
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json` (in Claude Desktop: Settings → Developer → Edit Config)
- **Cursor:** Settings → MCP → Add new global MCP server

Paste in the contents of `mcp.json.example` from this repo, then change one line, the `SQLITE_PATH`, to point at your folder from step 1 plus `\petcare-ops.db` (Windows) or `/petcare-ops.db` (Mac):

```json
{
  "mcpServers": {
    "zensched": {
      "url": "https://mcp.zensched.com/mcp",
      "headers": { "Authorization": "Bearer zsc_your_key_here" }
    },
    "petcare-ops-db": {
      "command": "npx",
      "args": ["-y", "easy-sqlite-mcp"],
      "env": { "SQLITE_PATH": "/Users/yourname/petcare-ops/petcare-ops.db" }
    }
  }
}
```

**Windows path gotcha:** inside a JSON file every backslash must be doubled. Write `"C:\\Users\\YourName\\petcare-ops\\petcare-ops.db"`, not `"C:\Users\..."`. A single backslash will silently break the config.

**Leave `zsc_your_key_here` exactly as it is for now.** You do not have a key yet. The ZenSched tools that create your account work without one, and you will fill this in during step 3.

Save the file and **fully quit and reopen** your AI tool (on Mac, Cmd-Q; on Windows, right-click the tray icon → Quit). It only reads this file on startup.

### 3. Create your ZenSched account

In a new chat, type:

> Call `zensched_guide`, then call `account_create` with org_name "My Pet Care Co" (use my real business name if I told you one). Show me the `zsc_` key it returns.

Copy the `zsc_` key. Go back to the config file from step 2, replace `zsc_your_key_here` with your real key, save, and fully quit and reopen the AI tool again.

Some clients can adopt the key mid-session with `account_use_key`; you can ask the AI to try that to keep going immediately, but still update the config file so the key survives restarts. Keep the key private; it is the password to your account.

### 4. Create the database tables

Open `schema.sql` from this repo in any text editor, copy the whole thing, and paste it into the chat with this message in front of it:

> Create these tables in my petcare-ops database. Run each statement one at a time using the SQLite tool, then list the tables to confirm.

The AI will run about 43 statements and confirm the tables exist. The `petcare-ops.db` file now exists in your folder, pre-loaded with a starter price list you can change.

If you happen to have the `sqlite3` command-line tool, `sqlite3 petcare-ops.db < schema.sql` does the same thing, but it is not required.

### 5. Teach the AI the workflow

Paste the contents of `SKILL.md` into your AI tool as standing instructions. In Claude Desktop, create a Project and put it in the project instructions; in Cursor, save it as a rule. Then tell it your basics once:

> My business is Happy Paws Pet Care in Portland, Maine (Eastern time). Save that in settings, and set up the Visit Report form.

It writes those to the `settings` table, creates the Visit Report form on ZenSched (free), and saves the form id so every client's visits get it automatically.

### 6. Funding (only when asked)

The first 200 ZenSched tool calls per day are free. Some things are metered: creating a location (geocoding, $0.03), inviting a walker ($0.25), each GPS-verified check-in or check-out ($0.10), and reading a Visit Report ($0.05, or $0.15 when it has photos). When a metered call happens without funds, the AI will get a `payment_required` response and tell you how to add the $5 activation deposit, which is credited to your balance. You will not be charged without seeing this first.

For a typical client on five walks a week that is about $1.75 in GPS verification plus $0.75 in report reads per week; the AI states the cost before it spends.

## Using it

Everything after setup is plain English. Examples:

- "Add a client: Sarah Kim, sarah@example.com, 42 Birch Lane, Portland ME 04101. Dog Bella, yellow Lab, Apoquel 16mg at lunch. Lockbox code 4471 on the gas meter. Mon–Fri noon 30-minute walk starting Monday."
- "Add Dan Alvarez at 8 Harbor Street, two cats Mochi and Tofu, drop-ins Mon/Wed/Fri 12:45 and Saturday 9."
- "Invite my walker Maya Patel, maya@example.com, and make her the default."
- "Schedule next week for Maya."
- "Record what Maya did this week."
- "What happened with Bella this week? I want to send Sarah a summary."
- "Draft invoices for everyone with uninvoiced work."
- "Who still owes me money?"
- "Dan's away the 21st to the 25th, skip the cats that week."
- "Add an extra drop-in for Mochi Saturday at 3."

See `QUICKSTART.md` for the first-week walkthrough and `example-workflow.md` for exactly which tools the AI calls behind each of these.

### What "invoice" means here

"Draft an invoice" records the invoice in your database (number, date, due date, amount, which visits) and the AI writes out a plain-text invoice you can paste into an email or text message, with a line per visit and a note that the visits were GPS-verified. It does **not** generate a PDF, email it for you, or collect payment. When the client pays, tell the AI ("Sarah paid INV-2026-0003") and it marks it paid. If you outgrow this, the invoice records are simple enough to import into any accounting tool.

## Mobile app for walkers

- **Android:** [Google Play](https://play.google.com/store/apps/details?id=com.zensched.app)
- **iOS:** [TestFlight](https://testflight.apple.com/join/Wp51m5Yq)

When you invite a walker, they get an email, install the app, and can immediately see their visits, check in and out with GPS verification, and fill in the Visit Report with photos. The report is attached to each visit automatically.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| AI says it has no ZenSched tools | Config file not saved, or the app was not fully restarted | Check the JSON is valid (paste it into [jsonlint.com](https://jsonlint.com)), then quit and reopen the app |
| AI says it has no SQLite / `petcare-ops-db` tools | Node.js not installed, or bad `SQLITE_PATH` | Install Node.js LTS; on Windows check every backslash is doubled |
| `SQLITE_PATH` points nowhere / "unable to open database" | Folder from step 1 does not exist | Create the folder; the file is created automatically but the folder is not |
| ZenSched tools return an auth error | Key still says `zsc_your_key_here`, or was pasted with a space | Re-paste the key, restart |
| `payment_required` | Metered call with no balance | Follow the instructions in the response; $5 deposit |
| AI creates shifts at the wrong hour | Timezone not set | "Set my timezone offset to -04:00 in settings" (use your own offset) |
| Shift creation fails for dates a couple of months out | The client's 60-day ZenSched event has expired | Say "renew the events"; the AI runs the roll-over in `SKILL.md` and retries |
| Walker's check-in not GPS-verified at a house | Geocoded pin is at the mailbox, walker parked far away | Ask the AI to widen `checkin_radius_m` on that location or run `location_refine` ($0.10) |
| Walker does not see the Visit Report | Form not assigned to that client's event | "Attach the Visit Report to Sarah's event" (`form_assign`) |
| "What happened with Bella" comes back empty | Visits not recorded yet | "Record this week's visits" first; reading reports is metered, so the AI asks before doing it |
| AI asks you to run SQL yourself | It does not have `SKILL.md` loaded | Re-paste `SKILL.md` as project instructions |

If something is confusing or broken in ZenSched itself, ask the AI to call `feedback_submit` with a description. It is free, needs no account, and a human reads every submission.

## For developers

**Architecture.** Two MCP servers, no application code. The agent is the integration layer; `SKILL.md` is the spec it follows. ZenSched is authoritative for operations (schedule, punches, forms); SQLite is authoritative for CRM, pet records, recurrence, and billing; each side stores only the other's IDs, plus a per-visit report summary cached locally because submission reads are metered.

**Data model decisions.**

- One ZenSched **location** per address, permanent, stored on `addresses.zensched_location_id`. Created with `location_create(name, street_address=..., checkin_radius_m=75, idempotency_key=...)`.
- **Events are capped at 60 days by ZenSched**, so an event cannot be a permanent job template the way it is in the lawn kit. Instead each address holds its *current* event in `addresses.zensched_event_id` and its last covered date in `addresses.event_valid_until`. The agent creates a new event (`event_create(location_id, title, start_date, end_date=start+59 days, idempotency_key="event-address-{address_id}-{YYYYMMDD}")`) whenever a shift date is later than `event_valid_until`, calls `form_assign(form_id, event_id=...)` on it, and updates the row. The `visits_due_this_week` view exposes `event_needs_roll` per row and `events_expiring` lists addresses due for renewal within 14 days. Shifts already created on the old event remain valid. When recording a completed visit whose `event_id` no longer matches an address (because it rolled), the agent falls back to `event_get(event_id).location_id` against `addresses.zensched_location_id`; no local event history table is needed.
- **Recurrence is per weekday.** `visit_schedule.weekdays` is a 7-character `0/1` mask, Monday first, `CHECK`-constrained to exactly seven `0`/`1` characters; `preferred_start` is `CHECK`-constrained to `HH:MM`. A client with two visits a day has two rows. The view does the expansion with a recursive CTE over the next seven days, joins to the mask with `strftime('%w')` (remapping Sunday from `0` to position 7), honours `start_date`/`end_date`, drops rows whose date already exists in `visits` for that `schedule_id`, and emits ready-to-use `start_iso`, `end_iso` (via `datetime(... '+N minutes')`, so overnights cross midnight correctly), `worker_id` (row override or `settings.default_worker_id`), and the shift `idempotency_key`.
- `visits.zensched_shift_id` is `UNIQUE` so a shift cannot be recorded twice. `visits.report_dc_id` holds the form `submission_id`. `peed`, `pooped`, and `concerns` are `CHECK`-constrained to the form's option labels so the local summary cannot drift from the form.
- `invoices.invoice_number` is auto-assigned by trigger as `{prefix}-{YYYY}-{0001}`.
- `pets.species` (`dog | cat | rabbit | bird | reptile | fish | small_mammal | other`) and `services.service_type` (`walk | drop_in | overnight | puppy | other`) are `CHECK`-constrained.
- `addresses.access_notes` and `parking_notes` are the only columns that must never be sent to ZenSched; `SKILL.md` rule 5 enforces it.
- `PRAGMA foreign_keys = ON` is in `schema.sql` and `SKILL.md` tells the agent to run it per session; SQLite does not persist it.
- Views `visits_due_this_week`, `events_expiring`, `pets_with_meds`, `visits_to_invoice`, `invoices_outstanding` exist so the agent's routine queries are one-liners it cannot get wrong.

**Visit Report form.** Created once with `form_create(title, fields_json, idempotency_key="form-visit-report")`; the exact `fields_json` is in `SKILL.md`. Every field carries an explicit `identifier` so submission `data` keys are stable (`activities`, `peed`, `pooped`, `meds_given`, `notes_for_owner`, `photos`, `any_concerns`, `concern_detail`). Two `show_if` conditionals reference earlier `select`/`multi_select` fields by identifier and option key (`meds_given`, `none`). ZenSched documents conditionals as web-only; the phone may show those two fields unconditionally, which is harmless. Attaching is `form_assign(form_id, event_id=...)`, which resolves event → brand → policy and installs the form on the phone for every subsequent `shift_create`. Because a single-brand account shares policy 0, one assignment effectively covers all events, but the kit re-assigns per new event anyway (idempotent) so the behaviour holds if the owner later adds brands.

**Idempotency keys.** Deterministic, derived from local IDs so a retried or re-run agent turn cannot duplicate:

- location: `loc-address-{address_id}`
- event: `event-address-{address_id}-{YYYYMMDD window start}`
- shift: `shift-address-{address_id}-{YYYYMMDD}-{HHMM}` (date and start time, because two visits a day is normal)
- worker: `worker-{email}`
- form: `form-visit-report`; assignment: `assign-visit-report-{event_id}`

ZenSched caches idempotent responses for 24 hours.

**Timestamps.** `shift_create` takes `start` and `end` in ISO 8601 with an explicit offset. Always use the business's local offset from `settings.timezone_offset` (e.g. `2026-09-07T12:00:00-04:00`), never `Z`. The view builds these strings so the agent does not have to.

**Metered reads.** `form_submissions` and `form_export` bill $0.05 per submission read ($0.15 with media); `form_export` is preferred for a week or month at a time (one call, one payload). The kit stores the summary and media URLs in `visits` on first read so later questions are answered from SQLite. `shift_list`, `shift_status`, `event_get`, and `timesheet_export(mode="hours"|"raw")` are free; `mode="processed"` is $0.10 and needs a payroll period configured.

**SQLite MCP server.** `mcp.json.example` uses [`easy-sqlite-mcp`](https://github.com/chenkumi/easy-sqlite-mcp) (Node, `better-sqlite3`, `SQLITE_PATH` env var). Its `sqlite_execute` calls `prepare()`, so it accepts **one statement per call**; `schema.sql` is written so every statement stands alone and is idempotent. Any SQLite MCP server with read and write tools will work; adjust the tool names in `SKILL.md`.

**Schema test.** The schema was verified by splitting the file into its 43 statements and executing each individually (as the MCP server does) twice for idempotency, then exercising: the recursive-CTE view against a daily and a Mon–Fri schedule (7 and 5 rows), `event_needs_roll` flipping after `event_valid_until`, exclusion of already-recorded dates, overnight `end_iso` crossing midnight, the `UNIQUE` on `zensched_shift_id`, every `CHECK` (species, service type, weekday mask, start time, peed/pooped/concerns), foreign keys and cascade, the `updated_at` triggers, the invoice numbering trigger, and all five views on an empty database.

## Support

- ZenSched docs: <https://www.zensched.com/docs/>
- Tool reference: <https://www.zensched.com/docs/tools/>
- Feedback: ask your AI to call `feedback_submit` (categories: `bug`, `friction`, `missing_capability`, `docs`, `billing`, `feature`, `other`)

## License

MIT. See `LICENSE`.
