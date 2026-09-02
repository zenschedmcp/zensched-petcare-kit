# Quickstart

Setup is about 15 minutes, once. After that everything is plain English to your AI. Each step below tells you what to do and, where relevant, exactly what to type to the AI.

You need: Claude Desktop (or Cursor) and [Node.js LTS](https://nodejs.org/) installed. Nothing else.

## 1. Make a data folder

Create a folder such as `C:\Users\YourName\petcare-ops` (Windows) or `/Users/yourname/petcare-ops` (Mac). Note the full path.

## 2. Add the two tools to your AI's config

Open the config file:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json`
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Cursor:** Settings → MCP → Add new global MCP server

Paste this in and fix only the `SQLITE_PATH` line to match your folder from step 1:

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

- On Windows, double every backslash: `"C:\\Users\\YourName\\petcare-ops\\petcare-ops.db"`.
- Leave `zsc_your_key_here` as it is. You get the real key in the next step.

Save, then **fully quit and reopen** the AI app.

## 3. Create your ZenSched account

Type to the AI:

> Call zensched_guide, then account_create with org_name "My Pet Care Co". Show me the zsc_ key.

Copy the key into the config file in place of `zsc_your_key_here`. Save. Quit and reopen the app once more. (You can also ask the AI to call `account_use_key` with the key to continue right away, but update the file anyway so it sticks.)

## 4. Create the database tables

Copy the full contents of `schema.sql` and paste it into the chat with this line above it:

> Create these tables in my petcare-ops database. Run each statement one at a time with the SQLite tool, then list the tables to confirm.

## 5. Give the AI its instructions

Paste `SKILL.md` into the AI as standing instructions (Claude Desktop: a Project's instructions; Cursor: a rule). Then:

> My business is Happy Paws Pet Care in Portland, Maine, Eastern time. Save that to settings and create the Visit Report form.

The AI saves your settings and calls `form_create` once (free) to build the Visit Report your walkers fill in: activities, peed/pooped, meds given, notes, up to 3 photos, and a "Call me" flag. It stores the form id so every client gets it.

## 6. Add your first client

> Add a client: Sarah Kim, sarah@example.com, 555-0101, 42 Birch Lane, Portland ME 04101. Dog Bella, yellow Lab, Apoquel 16mg at lunch. Lockbox on the gas meter, code 4471. 30-minute walk Mon–Fri at noon starting Monday 2026-09-07.

Behind the scenes the AI inserts the client, address, pet, and recurring schedule, calls `location_create` (geocode, $0.03, may trigger the $5 activation deposit the first time), creates a 60-day `event_create` for the home, attaches the Visit Report with `form_assign`, and saves the IDs. The lockbox code goes only into the local database. You just see a confirmation.

## 7. Invite your walker

> Invite Maya Patel at maya@example.com as a walker and make her my default.

Maya gets an email ($0.25), installs the app ([Android](https://play.google.com/store/apps/details?id=com.zensched.app) / [App Store](https://apps.apple.com/us/app/zensched/id6800081657)), and activates. Give her the lockbox code yourself; the AI will not put it in ZenSched.

## 8. Schedule the week

> Schedule next week for Maya.

The AI expands the recurring schedule for the next 7 days, creates one shift per visit on ZenSched, and summarizes by day. Maya gets a push notification for each, with the Visit Report attached.

## 9. After the work is done

> Record what Maya did this week, then draft invoices for anyone with uninvoiced work.

The AI pulls the completed, GPS-verified shifts and the Visit Reports from ZenSched (reading reports is metered, so it tells you the cost first), saves a per-visit summary, flags any "Call me" concerns, creates invoice records, and writes out each invoice as text you can paste into an email.

> What happened with Bella this week?

Answered from the local summaries, free: one line per visit with pee/poop, meds, notes, and photo links, ready to forward to the client.

> Sarah paid INV-2026-0001.

Marks it paid.

## What next

- `README.md` for the full explanation, troubleshooting table, and developer notes
- `example-workflow.md` to see the exact tool calls behind each step above