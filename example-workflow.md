# Example Workflow: What the AI Does Behind Each Request

This shows the exact tool calls the agent makes for a first week of operation, following `SKILL.md`. The owner only types the quoted lines; everything else is the agent's work. Assumes setup from `QUICKSTART.md` is complete (both MCP servers configured, `schema.sql` loaded, `SKILL.md` given as instructions).

IDs and responses are illustrative. ZenSched IDs are integers.

## Session start (every session)

```
sqlite_execute: PRAGMA foreign_keys = ON;
sqlite_query:   SELECT key, value FROM settings;
  → business_name = My Pet Care Co, timezone_offset = -05:00,
    default_worker_id = NULL, default_visit_minutes = 30,
    invoice_due_days = 14, invoice_prefix = INV,
    visit_report_form_id = NULL, event_window_days = 60
```

## "My business is Happy Paws Pet Care in Portland, Maine, Eastern time."

```
sqlite_execute: UPDATE settings SET value = 'Happy Paws Pet Care' WHERE key = 'business_name';
sqlite_execute: UPDATE settings SET value = '-04:00' WHERE key = 'timezone_offset';
```

> Saved. I'll schedule everything in Eastern time (-04:00). You don't have a Visit Report form yet; it's free to create and every walk will come back with photos, pee/poop, meds, and notes. Want me to set it up now?

Owner: *"yes"*

```
form_create:
  title: "Visit Report"
  idempotency_key: "form-visit-report"
  fields_json: "[
    {\"type\": \"section\", \"label\": \"Visit report\", \"text\": \"Fill this in before you leave. Owners love photos.\"},
    {\"type\": \"multi_select\", \"label\": \"Activities\", \"identifier\": \"activities\", \"required\": true,
     \"options\": [\"Walk\", \"Play\", \"Feed\", \"Water refreshed\", \"Litter/yard cleanup\", \"Meds given\"]},
    {\"type\": \"select\", \"label\": \"Peed\", \"identifier\": \"peed\", \"required\": true, \"options\": [\"Yes\", \"No\"]},
    {\"type\": \"select\", \"label\": \"Pooped\", \"identifier\": \"pooped\", \"required\": true, \"options\": [\"Yes\", \"No\", \"Unusual\"]},
    {\"type\": \"text\", \"label\": \"Meds given (name/dose)\", \"identifier\": \"meds_given\", \"placeholder\": \"e.g. Apoquel 16mg\",
     \"show_if\": {\"field\": \"activities\", \"op\": \"contains\", \"value\": \"meds_given\", \"action\": \"show\"}},
    {\"type\": \"textarea\", \"label\": \"Notes for owner\", \"identifier\": \"notes_for_owner\"},
    {\"type\": \"photo\", \"label\": \"Photos\", \"identifier\": \"photos\", \"max_images\": 3},
    {\"type\": \"select\", \"label\": \"Any concerns\", \"identifier\": \"any_concerns\", \"required\": true, \"options\": [\"None\", \"Minor\", \"Call me\"]},
    {\"type\": \"textarea\", \"label\": \"Describe the concern\", \"identifier\": \"concern_detail\",
     \"show_if\": {\"field\": \"any_concerns\", \"op\": \"not_equals\", \"value\": \"none\", \"action\": \"show\"}}
  ]"
  → form_id: 301, fields: [ ...9 fields echoed with identifiers... ]

sqlite_execute: UPDATE settings SET value = '301' WHERE key = 'visit_report_form_id';
```

> Visit Report form created. I'll attach it to every client automatically.

## "Add a client: Sarah Kim, sarah@example.com, 555-0101, 42 Birch Lane, Portland ME 04101. Dog Bella, yellow Lab, gets Apoquel 16mg with lunch. Lockbox on the gas meter, code 4471. 30-minute walk Mon–Fri at noon starting Monday 9/7."

```
sqlite_execute:
  INSERT INTO clients (client_name, contact_email, contact_phone)
  VALUES ('Sarah Kim', 'sarah@example.com', '555-0101');
  → lastInsertRowid = 1

sqlite_execute:
  INSERT INTO addresses (client_id, address, city, state, zip, access_notes)
  VALUES (1, '42 Birch Lane', 'Portland', 'ME', '04101', 'Lockbox on gas meter, code 4471');
  → lastInsertRowid = 1

sqlite_execute:
  INSERT INTO pets (client_id, pet_name, species, breed, meds)
  VALUES (1, 'Bella', 'dog', 'Labrador (yellow)', 'Apoquel 16mg with lunch');
  → lastInsertRowid = 1

sqlite_query:   SELECT service_id, price FROM services WHERE code = 'walk30';   → 1, 25.00

sqlite_execute:
  INSERT INTO visit_schedule (client_id, address_id, service_id, weekdays, preferred_start, start_date)
  VALUES (1, 1, 1, '1111100', '12:00', '2026-09-07');
  → lastInsertRowid = 1
```

Agent (first metered call this session, rule 9):

> Creating Sarah's address on ZenSched costs $0.03 for geocoding. If your account isn't funded yet you'll get a prompt for the $5 activation deposit. Go ahead?

Owner: *"yes"*

```
location_create:
  name: "Sarah Kim - 42 Birch Lane"
  street_address: "42 Birch Lane, Portland, ME 04101"
  checkin_radius_m: 75
  idempotency_key: "loc-address-1"
  → location_id: 9001, lat: 43.6615, lng: -70.2553, pin_quality: "street"
    billing: { meter: "geocode", units: 1, price: 0.03 }
```

The lockbox code is **not** in `notes`. It lives only in `addresses.access_notes`.

```
event_create:
  location_id: 9001
  title: "Pet care - 42 Birch Lane (Bella)"
  start_date: "2026-09-07"
  end_date:   "2026-11-05"          ← start + 59 days (60-day cap)
  idempotency_key: "event-address-1-20260907"
  → event_id: 7001

form_assign:
  form_id: 301
  event_id: 7001
  idempotency_key: "assign-visit-report-7001"
  → status: "assigned", form_id: 301, event_id: 7001, policy_id: 0

sqlite_execute:
  UPDATE addresses SET zensched_location_id = 9001, zensched_event_id = 7001, event_valid_until = '2026-11-05'
  WHERE address_id = 1;
```

> Added Sarah Kim, 42 Birch Lane. Bella (yellow Lab, Apoquel 16mg at lunch). Mon–Fri 12:00 30-minute walk at $25. The lockbox code is saved on your computer only; give it to your walker directly. Her ZenSched event runs through Nov 5; I'll renew it automatically when scheduling gets that far.

## "Add Dan Alvarez, dan@example.com, 555-0202, 8 Harbor Street, Portland ME 04101. Two cats, Mochi and Tofu. Drop-in visits Mon, Wed, Fri at 12:45 and Saturday at 9. Key under the blue planter. Tofu hides; don't chase him."

Same pattern. The agent does not re-ask about the $0.03 (owner already approved geocoding this session).

```
sqlite_execute: INSERT INTO clients (client_name, contact_email, contact_phone) VALUES ('Dan Alvarez', 'dan@example.com', '555-0202');   → 2
sqlite_execute: INSERT INTO addresses (client_id, address, city, state, zip, access_notes) VALUES (2, '8 Harbor Street', 'Portland', 'ME', '04101', 'Key under the blue planter by the door');   → 2
sqlite_execute: INSERT INTO pets (client_id, pet_name, species) VALUES (2, 'Mochi', 'cat');   → 2
sqlite_execute: INSERT INTO pets (client_id, pet_name, species, behaviour_flags) VALUES (2, 'Tofu', 'cat', 'Shy, hides. Do not chase.');   → 3
sqlite_query:   SELECT service_id FROM services WHERE code = 'dropin';   → 3
sqlite_execute: INSERT INTO visit_schedule (client_id, address_id, service_id, weekdays, preferred_start, start_date) VALUES (2, 2, 3, '1010100', '12:45', '2026-09-07');   → 2
sqlite_execute: INSERT INTO visit_schedule (client_id, address_id, service_id, weekdays, preferred_start, start_date) VALUES (2, 2, 3, '0000010', '09:00', '2026-09-07');   → 3

location_create: name "Dan Alvarez - 8 Harbor Street", street_address "8 Harbor Street, Portland, ME 04101", checkin_radius_m 75, idempotency_key "loc-address-2"  → location_id 9002
event_create:    location_id 9002, title "Pet care - 8 Harbor Street (Mochi, Tofu)", start_date "2026-09-07", end_date "2026-11-05", idempotency_key "event-address-2-20260907"  → event_id 7002
form_assign:     form_id 301, event_id 7002, idempotency_key "assign-visit-report-7002"
sqlite_execute:  UPDATE addresses SET zensched_location_id = 9002, zensched_event_id = 7002, event_valid_until = '2026-11-05' WHERE address_id = 2;
```

Two `visit_schedule` rows because the Saturday visit is at a different time than the weekday ones.

## "Invite my walker Maya Patel, maya@example.com, and make her the default."

> Inviting a walker costs $0.25. OK?

Owner: *"yes"*

```
worker_invite:
  email: "maya@example.com"
  first_name: "Maya"
  last_name: "Patel"
  idempotency_key: "worker-maya@example.com"
  → worker_id: 501, status: "invited", invitation_sent: true
    billing: { meter: "worker_invite", units: 1, price: 0.25 }

sqlite_execute: UPDATE settings SET value = '501' WHERE key = 'default_worker_id';
```

> Invited Maya. She'll get an email with the app link and an activation code. She's the default walker now. Remember to give her the lockbox code and where Dan's key is; I keep those off ZenSched on purpose.

## "Schedule next week for Maya."

```
sqlite_query: SELECT * FROM visits_due_this_week;
  → 2026-09-07 | sched 1 | Sarah Kim   | addr 1 | evt 7001 | event_needs_roll 0 | walk30 | 12:00 | worker 501
               | start_iso 2026-09-07T12:00:00-04:00 | end_iso 2026-09-07T12:30:00-04:00 | shift-address-1-20260907-1200 | pets Bella
    2026-09-07 | sched 2 | Dan Alvarez | addr 2 | evt 7002 | event_needs_roll 0 | dropin | 12:45 | worker 501
               | start_iso 2026-09-07T12:45:00-04:00 | end_iso 2026-09-07T13:15:00-04:00 | shift-address-2-20260907-1245 | pets Mochi, Tofu
    2026-09-08 | sched 1 | Sarah Kim ... 12:00
    2026-09-09 | sched 1 | Sarah Kim ... 12:00
    2026-09-09 | sched 2 | Dan Alvarez ... 12:45
    2026-09-10 | sched 1 | Sarah Kim ... 12:00
    2026-09-11 | sched 1 | Sarah Kim ... 12:00
    2026-09-11 | sched 2 | Dan Alvarez ... 12:45
    2026-09-12 | sched 3 | Dan Alvarez ... 09:00 | shift-address-2-20260912-0900
  (9 rows)

shift_create:
  event_id: 7001
  worker_id: 501
  start: "2026-09-07T12:00:00-04:00"
  end:   "2026-09-07T12:30:00-04:00"
  idempotency_key: "shift-address-1-20260907-1200"
  → shift_id: 88001, status: "scheduled", forms_installed: [301]

shift_create:
  event_id: 7002
  worker_id: 501
  start: "2026-09-07T12:45:00-04:00"
  end:   "2026-09-07T13:15:00-04:00"
  idempotency_key: "shift-address-2-20260907-1245"
  → shift_id: 88002, status: "scheduled", forms_installed: [301]

(... seven more shift_create calls, one per remaining row → 88003 ... 88009)
```

> Scheduled 9 visits for Maya the week of Sep 7:
> - Bella, 42 Birch Ln: Mon–Fri 12:00–12:30 walk
> - Mochi & Tofu, 8 Harbor St: Mon, Wed, Fri 12:45–13:15 drop-in; Sat 9:00–9:30 drop-in
>
> Maya's been notified in the app and every visit has the Visit Report attached.

Nothing is written to SQLite here. If the owner asks "schedule next week" again, the identical idempotency keys make ZenSched return the same nine shifts instead of creating duplicates.

## Maya does the work

Monday 11:58, at 42 Birch Lane, in the ZenSched app: **Check in** (GPS: 14 m from the pin, verified, $0.10). Walks Bella, gives the Apoquel. Opens **Visit Report**: Activities = Walk, Meds given; Peed = Yes; Pooped = Yes; Meds given = "Apoquel 16mg"; Notes = "Great walk, pulled toward the park"; two photos; Any concerns = None. Submits. **Check out** 12:31.

Then 8 Harbor Street at 12:44: check in, scoops litter, refreshes water, photo of Mochi on the windowsill (Tofu under the bed as advertised), report, check out.

Tuesday: Bella again. This time Any concerns = **Call me**, "Favoring back left leg on the way home, no yelping, ate fine."

## "Record what Maya did this week."

```
shift_list:
  date_from: "2026-09-07"
  date_to:   "2026-09-13"
  status:    "checked_out"
  → shifts: [
      { shift_id: 88001, event_id: 7001, worker_id: 501, date: "2026-09-07", start: "12:00", end: "12:30", status: "checked_out" },
      { shift_id: 88002, event_id: 7002, worker_id: 501, date: "2026-09-07", start: "12:45", end: "13:15", status: "checked_out" },
      ... 7 more ...
    ], count: 9

sqlite_query: SELECT zensched_shift_id FROM visits WHERE zensched_shift_id IN (88001, 88002, ...);
  → (none; not yet recorded)

sqlite_query: SELECT a.address_id, a.client_id, s.schedule_id, s.service_id, sv.price
              FROM addresses a JOIN visit_schedule s ON s.address_id = a.address_id JOIN services sv USING (service_id)
              WHERE a.zensched_event_id = 7001 AND s.preferred_start = '12:00';
  → 1, 1, 1, 1, 25.00
```

Agent (metered read, rule 9):

> There are 9 visit reports to pull. Reading them costs $0.05 each, or $0.15 when they have photos; all nine have photos, so about $1.35. I'll read them once and keep the summaries locally. OK?

Owner: *"go"*

```
form_export:
  form_id: 301
  since: "2026-09-07"
  until: "2026-09-13"
  format: "json"
  → row_count: 9, rows (inline for small exports, otherwise a download_url): [
      { submission_id: 3301, worker_id: 501, event_id: 7001, submitted_at: "2026-09-07 12:29:40",
        data: { activities: ["walk", "meds_given"], peed: "yes", pooped: "yes", meds_given: "Apoquel 16mg",
                notes_for_owner: "Great walk, pulled toward the park", any_concerns: "none" },
        media: [ { cdn_url: "https://cdn.zensched.com/m/.../a1.jpg" }, { cdn_url: "https://cdn.zensched.com/m/.../a2.jpg" } ] },
      { submission_id: 3302, worker_id: 501, event_id: 7002, submitted_at: "2026-09-07 13:12:05",
        data: { activities: ["feed", "water_refreshed", "litter_yard_cleanup"], peed: "yes", pooped: "yes",
                notes_for_owner: "Mochi supervised from the windowsill, Tofu under the bed as promised", any_concerns: "none" },
        media: [ { cdn_url: "https://cdn.zensched.com/m/.../b1.jpg" } ] },
      { submission_id: 3303, worker_id: 501, event_id: 7001, submitted_at: "2026-09-08 12:30:12",
        data: { activities: ["walk", "meds_given"], peed: "yes", pooped: "no", meds_given: "Apoquel 16mg",
                notes_for_owner: "Shorter loop today", any_concerns: "call_me",
                concern_detail: "Favoring back left leg on the way home, no yelping, ate fine" },
        media: [ ... ] },
      ...
    ]
    billing: { meter: "form_media", units: 9, price: 1.35 }

shift_status: shift_id 88001
  → status "checked_out", actual_in "2026-09-07T11:58:20-04:00", actual_out "2026-09-07T12:31:02-04:00",
    punches: [ { type: "in", gps_verified: true, distance_from_site_m: 14 }, { type: "out", gps_verified: true, distance_from_site_m: 9 } ]
(free; repeated per shift, or skipped if the owner only wants billing)

sqlite_execute:
  INSERT INTO visits (client_id, address_id, schedule_id, service_id, visit_date, scheduled_start, amount,
                      zensched_shift_id, zensched_event_id, zensched_worker_id, actual_in, actual_out, duration_minutes, gps_verified,
                      report_dc_id, activities, peed, pooped, meds_given, concerns, report_notes, photo_urls)
  VALUES (1, 1, 1, 1, '2026-09-07', '12:00', 25.00,
          88001, 7001, 501, '2026-09-07T11:58:20-04:00', '2026-09-07T12:31:02-04:00', 33, 1,
          3301, '["walk","meds_given"]', 'Yes', 'Yes', 'Apoquel 16mg', 'None', 'Great walk, pulled toward the park',
          '["https://cdn.zensched.com/m/.../a1.jpg","https://cdn.zensched.com/m/.../a2.jpg"]');

sqlite_execute:
  INSERT INTO visits (...) VALUES (2, 2, 2, 3, '2026-09-07', '12:45', 25.00, 88002, 7002, 501, ..., 3302,
          '["feed","water_refreshed","litter_yard_cleanup"]', 'Yes', 'Yes', NULL, 'None',
          'Mochi supervised from the windowsill, Tofu under the bed as promised', '["https://cdn.zensched.com/m/.../b1.jpg"]');

sqlite_execute:
  INSERT INTO visits (...) VALUES (1, 1, 1, 1, '2026-09-08', '12:00', 25.00, 88003, 7001, 501, ..., 3303,
          '["walk","meds_given"]', 'Yes', 'No', 'Apoquel 16mg', 'Call me',
          'Favoring back left leg on the way home, no yelping, ate fine', ...);

(... six more inserts)
```

> Recorded 9 visits for the week, all GPS-verified at the door.
>
> **One flag — Tuesday, Bella:** Maya marked "Call me": *"Favoring back left leg on the way home, no yelping, ate fine."* Wednesday's and later reports say she walked normally. Worth mentioning to Sarah.
>
> Everything else routine: Bella got her Apoquel every day; Mochi & Tofu fed, watered, litter done each visit (Tofu stayed under the bed on Monday, came out Wednesday).

## "What happened with Bella this week? I want to send Sarah a summary."

```
sqlite_query:
  SELECT v.visit_date, v.scheduled_start, s.service_name, v.actual_in, v.actual_out, v.gps_verified,
         v.activities, v.peed, v.pooped, v.meds_given, v.concerns, v.concern_detail, v.report_notes, v.photo_urls
  FROM visits v JOIN services s USING (service_id) JOIN pets p ON p.client_id = v.client_id
  WHERE p.pet_name = 'Bella' AND v.visit_date BETWEEN '2026-09-07' AND '2026-09-13'
  ORDER BY v.visit_date, v.scheduled_start;
  → 5 rows
```

No ZenSched call, no cost; the reports were already stored.

> Here's Bella's week, ready to forward:
>
> ```
> Bella — week of Sep 7 (Happy Paws Pet Care)
>
> Mon 9/7   11:58–12:31  Walk, Apoquel 16mg given. Peed/pooped. "Great walk, pulled toward the park." 2 photos
> Tue 9/8   12:01–12:28  Walk, Apoquel given. Peed, no poop. Maya noticed her favoring the back left leg on the way home — no yelping, ate fine. 1 photo
> Wed 9/9   11:57–12:30  Walk, Apoquel given. Peed/pooped. "Back to normal, no limp." 2 photos
> Thu 9/10  12:00–12:32  Walk, Apoquel given. Peed/pooped. 1 photo
> Fri 9/11  12:02–12:33  Walk, Apoquel given. Peed/pooped. "Made a friend (beagle) at the corner." 3 photos
>
> All five visits GPS-verified at your door.
> Photos: https://cdn.zensched.com/m/.../a1.jpg  https://cdn.zensched.com/m/.../a2.jpg  ...
> ```

## "Draft invoices for everyone with uninvoiced work."

```
sqlite_query: SELECT * FROM visits_to_invoice;
  → Dan Alvarez | 4 visits | 100.00 | 2026-09-07 .. 2026-09-12
    Sarah Kim   | 5 visits | 125.00 | 2026-09-07 .. 2026-09-11

sqlite_execute:
  INSERT INTO invoices (client_id, invoice_date, due_date, total_amount, line_items)
  SELECT v.client_id, date('now'),
         date('now', '+' || (SELECT value FROM settings WHERE key = 'invoice_due_days') || ' days'),
         SUM(v.amount),
         json_group_array(json_object('visit_id', v.visit_id, 'date', v.visit_date, 'service', s.service_name,
                                      'amount', v.amount, 'shift_id', v.zensched_shift_id))
  FROM visits v JOIN services s ON s.service_id = v.service_id
  WHERE v.invoiced = 0 AND v.client_id = 1 GROUP BY v.client_id;

sqlite_execute: UPDATE visits SET invoiced = 1 WHERE invoiced = 0 AND client_id = 1;
sqlite_query:   SELECT invoice_number, invoice_date, due_date, total_amount FROM invoices WHERE invoice_id = last_insert_rowid();
  → INV-2026-0001 | 2026-09-13 | 2026-09-27 | 125.00     (number assigned by trigger)

(same three statements for client 2 → INV-2026-0002, 100.00)
```

The agent then writes the invoices out as text:

> Here are your two invoices. Paste each into an email or text.
>
> ```
> Happy Paws Pet Care
> Invoice INV-2026-0001
> To: Sarah Kim (sarah@example.com)
> Date: Sep 13, 2026    Due: Sep 27, 2026
>
>   Sep 7    30-minute walk, Bella        $25.00
>   Sep 8    30-minute walk, Bella        $25.00
>   Sep 9    30-minute walk, Bella        $25.00
>   Sep 10   30-minute walk, Bella        $25.00
>   Sep 11   30-minute walk, Bella        $25.00
>
> Total due: $125.00
> All visits GPS-verified at 42 Birch Lane.
> ```
>
> ```
> Happy Paws Pet Care
> Invoice INV-2026-0002
> To: Dan Alvarez (dan@example.com)
> Date: Sep 13, 2026    Due: Sep 27, 2026
>
>   Sep 7    Drop-in visit (30 min), Mochi & Tofu    $25.00
>   Sep 9    Drop-in visit (30 min), Mochi & Tofu    $25.00
>   Sep 11   Drop-in visit (30 min), Mochi & Tofu    $25.00
>   Sep 12   Drop-in visit (30 min), Mochi & Tofu    $25.00
>
> Total due: $100.00
> All visits GPS-verified at 8 Harbor Street.
> ```
>
> Say "sent" when they're out and I'll note the date.

## "Sent. Sarah already paid."

```
sqlite_execute: UPDATE invoices SET sent_date = date('now') WHERE invoice_number IN ('INV-2026-0001', 'INV-2026-0002');
sqlite_execute: UPDATE invoices SET paid = 1, paid_date = date('now') WHERE invoice_number = 'INV-2026-0001';
```

> Marked both sent and INV-2026-0001 paid. Dan's $100 (INV-2026-0002) is outstanding, due Sep 27.

## "Dan's away Sep 21–25, skip the cats that week."

```
sqlite_execute: UPDATE visit_schedule SET end_date = '2026-09-20' WHERE schedule_id IN (2, 3);
sqlite_execute: INSERT INTO visit_schedule (client_id, address_id, service_id, weekdays, preferred_start, start_date) VALUES (2, 2, 3, '1010100', '12:45', '2026-09-26');
sqlite_execute: INSERT INTO visit_schedule (client_id, address_id, service_id, weekdays, preferred_start, start_date) VALUES (2, 2, 3, '0000010', '09:00', '2026-09-26');

shift_list: event_id 7002, date_from "2026-09-21", date_to "2026-09-25"
  → (none yet scheduled that far ahead; nothing to cancel)
```

> Done. No cat visits Sep 21–25; they resume Saturday Sep 26. Nothing was on the schedule for that week yet, so nothing needed cancelling.

## Eight weeks later: "Schedule next week."

```
sqlite_query: SELECT * FROM visits_due_this_week;
  → 2026-11-02 ... event_needs_roll 0
    ...
    2026-11-06 | sched 1 | Sarah Kim | addr 1 | evt 7001 | event_valid_until 2026-11-05 | event_needs_roll 1 | ...
    2026-11-06 | sched 2 | Dan Alvarez | addr 2 | evt 7002 | event_valid_until 2026-11-05 | event_needs_roll 1 | ...

event_create:
  location_id: 9001
  title: "Pet care - 42 Birch Lane (Bella)"
  start_date: "2026-11-06"
  end_date:   "2027-01-04"
  idempotency_key: "event-address-1-20261106"
  → event_id: 7150

form_assign: form_id 301, event_id 7150, idempotency_key "assign-visit-report-7150"
sqlite_execute: UPDATE addresses SET zensched_event_id = 7150, event_valid_until = '2027-01-04' WHERE address_id = 1;

(same for address 2 → event 7151)

shift_create: event_id 7001 for the Nov 2–5 visits (old event still valid for those dates)
shift_create: event_id 7150 for the Nov 6 visit, key "shift-address-1-20261106-1200"
...
```

> Scheduled the week. Bella's and the cats' ZenSched events were about to expire (Nov 5), so I renewed both through Jan 4. Nothing changes for Maya.

## Summary of who stored what

| Thing | Where | Why |
|---|---|---|
| Sarah's contact, Bella's meds and vet, the Mon–Fri noon cadence, prices | SQLite | CRM; ZenSched does not model pets, pricing, or recurrence |
| Lockbox code, where Dan's key is | SQLite **only** | Privacy; never sent to ZenSched |
| Each home's GPS location | ZenSched (ID in `addresses`) | Needed for geofenced check-in |
| Each home's current ≤60-day event and its end date | ZenSched (ID + `event_valid_until` in `addresses`) | Shifts hang off events; renewed by the agent |
| The Visit Report form | ZenSched (ID in `settings`) | Installed on the walker's phone per shift |
| Maya, her invite, her app | ZenSched (ID in `settings`) | Workforce and notifications |
| The week's nine shifts | ZenSched only | Live schedule; never copied |
| GPS punches, actual times | ZenSched only | Verified record; queried via `shift_status` / `timesheet_export` |
| Nine visit reports with photos | ZenSched (originals); summary + photo URLs in `visits` | Read once (metered), then answered from SQLite for free |
| Nine `visits` rows referencing shift and submission IDs | SQLite | Billing needs a durable "this visit is billable" record |
| Two invoices, one paid | SQLite | Billing |
