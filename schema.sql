-- ZenSched Pet-Care Local Database Schema
-- SQLite database for CRM, pet records, recurring schedule templates, and billing.
-- DO NOT duplicate live schedule data from ZenSched (shifts, punches, timesheets).
--
-- HOW TO LOAD THIS FILE
--   Normal path: paste this whole file into your AI chat and say
--   "Create these tables in my petcare-ops database. Run each statement one at a time."
--   The AI runs each statement through the SQLite MCP tool (sqlite_execute).
--   Most SQLite MCP tools accept ONE statement per call, so every statement
--   below ends with a semicolon and stands alone.
--
--   Alternative (if you have the sqlite3 command-line tool):
--     sqlite3 petcare-ops.db < schema.sql
--
-- Every statement is idempotent (IF NOT EXISTS / INSERT OR IGNORE), so it is
-- safe to run this file again on an existing database.
--
-- PRIVACY: addresses.access_notes (lockbox codes, alarm words, garage codes,
-- where the spare key is) lives ONLY in this file on your computer. It is never
-- sent to ZenSched. SKILL.md forbids the agent from putting it in any ZenSched
-- notes field.

-- Foreign keys are OFF by default in SQLite. This must be run once per
-- connection for ON DELETE CASCADE to work. SKILL.md tells the agent to run it
-- at the start of each session.
PRAGMA foreign_keys = ON;

-- Settings: small key/value store so the agent does not have to be re-told the
-- basics every session (timezone, default walker, business name, form id).
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT
);

INSERT OR IGNORE INTO settings (key, value) VALUES ('business_name', 'My Pet Care Co');
INSERT OR IGNORE INTO settings (key, value) VALUES ('timezone_offset', '-05:00');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_worker_id', NULL);
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_visit_minutes', '30');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_due_days', '14');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_prefix', 'INV');
INSERT OR IGNORE INTO settings (key, value) VALUES ('visit_report_form_id', NULL);
INSERT OR IGNORE INTO settings (key, value) VALUES ('event_window_days', '60');

-- Clients: the pet owners. Contact and billing information only.
CREATE TABLE IF NOT EXISTS clients (
  client_id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_name TEXT NOT NULL,
  contact_email TEXT,
  contact_phone TEXT,
  emergency_contact TEXT,                           -- name + phone of a backup person
  billing_notes TEXT,                               -- 'pays by Venmo', 'invoice monthly', ...
  is_active INTEGER DEFAULT 1,                      -- 0 = paused (vacation, cancelled)
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Addresses: where the pets live, with ZenSched references.
-- One ZenSched LOCATION per address, created once and kept forever.
-- One ZenSched EVENT per address per rolling window of at most 60 days
-- (ZenSched caps event length). zensched_event_id is the CURRENT event and
-- event_valid_until is its last valid date. When a visit date is later than
-- event_valid_until, the agent creates a new event and updates both columns.
CREATE TABLE IF NOT EXISTS addresses (
  address_id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_id INTEGER NOT NULL,
  label TEXT,                                       -- 'Home', 'Lake house'
  address TEXT NOT NULL,
  address_line2 TEXT,
  city TEXT,
  state TEXT,
  zip TEXT,
  access_notes TEXT,                                -- LOCAL ONLY: lockbox code, alarm word, key location
  parking_notes TEXT,                               -- LOCAL ONLY: 'street parking, no permit needed'
  zensched_location_id INTEGER,                     -- from location_create (permanent)
  zensched_event_id INTEGER,                        -- from event_create (current <=60-day window)
  event_valid_until TEXT,                           -- ISO date: last day the current event covers
  is_active INTEGER DEFAULT 1,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (client_id) REFERENCES clients(client_id) ON DELETE CASCADE
);

-- Pets: one row per animal. Care details the walker needs to know.
CREATE TABLE IF NOT EXISTS pets (
  pet_id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_id INTEGER NOT NULL,
  pet_name TEXT NOT NULL,
  species TEXT NOT NULL
    CHECK (species IN ('dog', 'cat', 'rabbit', 'bird', 'reptile', 'fish', 'small_mammal', 'other')),
  breed TEXT,
  sex TEXT CHECK (sex IS NULL OR sex IN ('M', 'F')),
  birth_year INTEGER,
  weight_lbs REAL,
  meds TEXT,                                        -- 'Apoquel 16mg with breakfast', NULL if none
  feeding_notes TEXT,                               -- '1 cup kibble AM/PM, bowl under sink'
  vet_name TEXT,
  vet_phone TEXT,
  behaviour_flags TEXT,                             -- 'leash reactive', 'escape artist', 'hides under bed'
  notes TEXT,
  is_active INTEGER DEFAULT 1,                      -- 0 = deceased / rehomed / no longer in care
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (client_id) REFERENCES clients(client_id) ON DELETE CASCADE
);

-- Services: your price list. Seeded with common items; edit prices freely.
CREATE TABLE IF NOT EXISTS services (
  service_id INTEGER PRIMARY KEY AUTOINCREMENT,
  code TEXT NOT NULL UNIQUE,                        -- short handle: 'walk30'
  service_name TEXT NOT NULL,                       -- shown on invoices
  service_type TEXT NOT NULL
    CHECK (service_type IN ('walk', 'drop_in', 'overnight', 'puppy', 'other')),
  default_minutes INTEGER NOT NULL,                 -- shift length on ZenSched
  price REAL NOT NULL,                              -- per visit, in dollars
  is_active INTEGER DEFAULT 1,
  notes TEXT
);

INSERT OR IGNORE INTO services (code, service_name, service_type, default_minutes, price) VALUES ('walk30', '30-minute walk', 'walk', 30, 25.00);
INSERT OR IGNORE INTO services (code, service_name, service_type, default_minutes, price) VALUES ('walk60', '60-minute walk', 'walk', 60, 40.00);
INSERT OR IGNORE INTO services (code, service_name, service_type, default_minutes, price) VALUES ('dropin', 'Drop-in visit (30 min)', 'drop_in', 30, 25.00);
INSERT OR IGNORE INTO services (code, service_name, service_type, default_minutes, price) VALUES ('overnight', 'Overnight stay', 'overnight', 720, 90.00);
INSERT OR IGNORE INTO services (code, service_name, service_type, default_minutes, price) VALUES ('puppy', 'Puppy visit (20 min)', 'puppy', 20, 20.00);

-- Visit schedule: the recurring template ("Bella: Mon-Fri 12:00, 30-min walk").
-- weekdays is a 7-character mask, Monday first: '1111100' = Mon-Fri.
-- A client with a morning AND an evening visit gets two rows.
-- This table is the cadence; it is expanded into real ZenSched shifts by the
-- agent once a week using the visits_due_this_week view.
CREATE TABLE IF NOT EXISTS visit_schedule (
  schedule_id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_id INTEGER NOT NULL,
  address_id INTEGER NOT NULL,
  service_id INTEGER NOT NULL,
  weekdays TEXT NOT NULL
    CHECK (length(weekdays) = 7 AND weekdays NOT GLOB '*[^01]*'),
  preferred_start TEXT NOT NULL                     -- 'HH:MM' 24-hour local time
    CHECK (preferred_start GLOB '[0-2][0-9]:[0-5][0-9]'),
  zensched_worker_id INTEGER,                       -- NULL = use settings.default_worker_id
  start_date TEXT,                                  -- first date this applies (NULL = already running)
  end_date TEXT,                                    -- last date (NULL = open-ended)
  is_active INTEGER DEFAULT 1,
  notes TEXT,                                       -- 'skip if raining hard', 'use back door'
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (client_id) REFERENCES clients(client_id) ON DELETE CASCADE,
  FOREIGN KEY (address_id) REFERENCES addresses(address_id) ON DELETE CASCADE,
  FOREIGN KEY (service_id) REFERENCES services(service_id)
);

-- Visits: one row per COMPLETED visit, linked to the ZenSched shift and the
-- Visit Report form submission. This is the billing record plus a small
-- summary of the report so "what happened with Bella this week" is a local query.
CREATE TABLE IF NOT EXISTS visits (
  visit_id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_id INTEGER NOT NULL,
  address_id INTEGER NOT NULL,
  schedule_id INTEGER,                              -- NULL for one-off visits
  service_id INTEGER NOT NULL,
  visit_date TEXT NOT NULL,                         -- ISO date: '2026-09-08'
  scheduled_start TEXT,                             -- 'HH:MM' as scheduled
  amount REAL NOT NULL,
  zensched_shift_id INTEGER UNIQUE,                 -- prevents recording the same shift twice
  zensched_event_id INTEGER,
  zensched_worker_id INTEGER,
  actual_in TEXT,                                   -- from shift_status / timesheet_export
  actual_out TEXT,
  duration_minutes INTEGER,
  gps_verified INTEGER,                             -- 1 if the check-in punch was on site
  report_dc_id INTEGER,                             -- Visit Report submission_id from form_submissions
  activities TEXT,                                  -- JSON array copied from the report, e.g. ["walk","peed"]
  peed TEXT CHECK (peed IS NULL OR peed IN ('Yes', 'No')),
  pooped TEXT CHECK (pooped IS NULL OR pooped IN ('Yes', 'No', 'Unusual')),
  meds_given TEXT,
  concerns TEXT CHECK (concerns IS NULL OR concerns IN ('None', 'Minor', 'Call me')),
  concern_detail TEXT,
  report_notes TEXT,                                -- "Notes for owner" from the report
  photo_urls TEXT,                                  -- JSON array of media URLs from the report
  invoiced INTEGER DEFAULT 0,                       -- 1 = included in an invoice
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (client_id) REFERENCES clients(client_id) ON DELETE CASCADE,
  FOREIGN KEY (address_id) REFERENCES addresses(address_id) ON DELETE CASCADE,
  FOREIGN KEY (schedule_id) REFERENCES visit_schedule(schedule_id) ON DELETE SET NULL,
  FOREIGN KEY (service_id) REFERENCES services(service_id)
);

-- Invoices: billing records.
-- invoice_number is filled in automatically by a trigger if left NULL.
CREATE TABLE IF NOT EXISTS invoices (
  invoice_id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_id INTEGER NOT NULL,
  invoice_number TEXT UNIQUE,                       -- human-readable: 'INV-2026-0001'
  invoice_date TEXT NOT NULL,
  due_date TEXT,
  total_amount REAL NOT NULL,
  paid INTEGER DEFAULT 0,                           -- 1 = paid, 0 = unpaid
  paid_date TEXT,
  sent_date TEXT,                                   -- when you actually emailed/texted it
  line_items TEXT,                                  -- JSON array of visit references
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (client_id) REFERENCES clients(client_id) ON DELETE CASCADE
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_addresses_client ON addresses(client_id);
CREATE INDEX IF NOT EXISTS idx_addresses_zensched_event ON addresses(zensched_event_id);
CREATE INDEX IF NOT EXISTS idx_addresses_zensched_location ON addresses(zensched_location_id);
CREATE INDEX IF NOT EXISTS idx_pets_client ON pets(client_id);
CREATE INDEX IF NOT EXISTS idx_schedule_client ON visit_schedule(client_id, is_active);
CREATE INDEX IF NOT EXISTS idx_schedule_address ON visit_schedule(address_id);
CREATE INDEX IF NOT EXISTS idx_visits_client_date ON visits(client_id, visit_date);
CREATE INDEX IF NOT EXISTS idx_visits_schedule_date ON visits(schedule_id, visit_date);
CREATE INDEX IF NOT EXISTS idx_visits_invoiced ON visits(invoiced);
CREATE INDEX IF NOT EXISTS idx_invoices_client ON invoices(client_id);
CREATE INDEX IF NOT EXISTS idx_invoices_paid ON invoices(paid);

-- Keep updated_at current
CREATE TRIGGER IF NOT EXISTS update_client_timestamp
AFTER UPDATE ON clients
BEGIN
  UPDATE clients SET updated_at = datetime('now') WHERE client_id = NEW.client_id;
END;

CREATE TRIGGER IF NOT EXISTS update_address_timestamp
AFTER UPDATE ON addresses
BEGIN
  UPDATE addresses SET updated_at = datetime('now') WHERE address_id = NEW.address_id;
END;

CREATE TRIGGER IF NOT EXISTS update_pet_timestamp
AFTER UPDATE ON pets
BEGIN
  UPDATE pets SET updated_at = datetime('now') WHERE pet_id = NEW.pet_id;
END;

CREATE TRIGGER IF NOT EXISTS update_schedule_timestamp
AFTER UPDATE ON visit_schedule
BEGIN
  UPDATE visit_schedule SET updated_at = datetime('now') WHERE schedule_id = NEW.schedule_id;
END;

-- Auto-number invoices: INV-2026-0001, INV-2026-0002, ...
CREATE TRIGGER IF NOT EXISTS number_invoice
AFTER INSERT ON invoices
WHEN NEW.invoice_number IS NULL
BEGIN
  UPDATE invoices
  SET invoice_number = (SELECT COALESCE(value, 'INV') FROM settings WHERE key = 'invoice_prefix')
                       || '-' || strftime('%Y', NEW.invoice_date)
                       || '-' || printf('%04d', NEW.invoice_id)
  WHERE invoice_id = NEW.invoice_id;
END;

-- Every visit that should happen in the next 7 days (today + 6), expanded from
-- visit_schedule, minus dates already recorded in visits. The agent's weekly
-- scheduling query. One row = one shift_create call. Columns ending in _iso
-- are ready to pass as shift_create start/end; idempotency_key is ready too.
-- event_needs_roll = 1 means create a new ZenSched event first (see SKILL.md).
CREATE VIEW IF NOT EXISTS visits_due_this_week AS
WITH RECURSIVE days(d) AS (
  SELECT date('now')
  UNION ALL
  SELECT date(d, '+1 day') FROM days WHERE d < date('now', '+6 days')
)
SELECT
  days.d                                     AS visit_date,
  s.schedule_id,
  c.client_id,
  c.client_name,
  a.address_id,
  a.address,
  a.city,
  a.zensched_location_id,
  a.zensched_event_id,
  a.event_valid_until,
  CASE WHEN a.event_valid_until IS NULL OR a.event_valid_until < days.d THEN 1 ELSE 0 END AS event_needs_roll,
  sv.service_id,
  sv.code                                    AS service_code,
  sv.service_name,
  sv.default_minutes,
  sv.price,
  s.preferred_start,
  COALESCE(s.zensched_worker_id, (SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'default_worker_id')) AS worker_id,
  days.d || 'T' || s.preferred_start || ':00' || (SELECT value FROM settings WHERE key = 'timezone_offset') AS start_iso,
  strftime('%Y-%m-%dT%H:%M:%S', datetime(days.d || ' ' || s.preferred_start || ':00', '+' || sv.default_minutes || ' minutes'))
    || (SELECT value FROM settings WHERE key = 'timezone_offset') AS end_iso,
  'shift-address-' || a.address_id || '-' || strftime('%Y%m%d', days.d) || '-' || replace(s.preferred_start, ':', '') AS idempotency_key,
  (SELECT group_concat(p.pet_name, ', ') FROM pets p WHERE p.client_id = c.client_id AND p.is_active = 1) AS pets,
  s.notes                                    AS schedule_notes
FROM days
JOIN visit_schedule s
  ON s.is_active = 1
 AND substr(s.weekdays, CASE strftime('%w', days.d) WHEN '0' THEN 7 ELSE CAST(strftime('%w', days.d) AS INTEGER) END, 1) = '1'
 AND (s.start_date IS NULL OR s.start_date <= days.d)
 AND (s.end_date IS NULL OR s.end_date >= days.d)
JOIN clients c ON c.client_id = s.client_id AND c.is_active = 1
JOIN addresses a ON a.address_id = s.address_id AND a.is_active = 1
JOIN services sv ON sv.service_id = s.service_id
WHERE NOT EXISTS (
  SELECT 1 FROM visits v WHERE v.schedule_id = s.schedule_id AND v.visit_date = days.d
)
ORDER BY days.d, s.preferred_start, c.client_name;

-- Addresses whose current ZenSched event expires within 14 days (or has none)
-- and that still have an active recurring schedule. Roll these proactively.
CREATE VIEW IF NOT EXISTS events_expiring AS
SELECT
  a.address_id,
  c.client_name,
  a.address,
  a.zensched_location_id,
  a.zensched_event_id,
  a.event_valid_until
FROM addresses a
JOIN clients c ON c.client_id = a.client_id AND c.is_active = 1
WHERE a.is_active = 1
  AND EXISTS (SELECT 1 FROM visit_schedule s WHERE s.address_id = a.address_id AND s.is_active = 1)
  AND (a.event_valid_until IS NULL OR a.event_valid_until <= date('now', '+14 days'))
ORDER BY a.event_valid_until;

-- Pets that get medication, with the client and schedule context the walker needs.
CREATE VIEW IF NOT EXISTS pets_with_meds AS
SELECT
  p.pet_id,
  p.pet_name,
  p.species,
  p.meds,
  p.feeding_notes,
  p.behaviour_flags,
  c.client_id,
  c.client_name,
  c.contact_phone,
  p.vet_name,
  p.vet_phone
FROM pets p
JOIN clients c ON c.client_id = p.client_id
WHERE p.is_active = 1
  AND c.is_active = 1
  AND p.meds IS NOT NULL
  AND trim(p.meds) <> ''
ORDER BY c.client_name, p.pet_name;

-- Completed visits that have not been invoiced yet, grouped by client.
CREATE VIEW IF NOT EXISTS visits_to_invoice AS
SELECT
  c.client_id,
  c.client_name,
  c.contact_email,
  c.billing_notes,
  COUNT(v.visit_id)     AS visit_count,
  SUM(v.amount)         AS total_amount,
  MIN(v.visit_date)     AS first_visit_date,
  MAX(v.visit_date)     AS last_visit_date
FROM visits v
JOIN clients c ON c.client_id = v.client_id
WHERE v.invoiced = 0
GROUP BY c.client_id
ORDER BY c.client_name;

-- Unpaid invoices, oldest first.
CREATE VIEW IF NOT EXISTS invoices_outstanding AS
SELECT
  i.invoice_id,
  i.invoice_number,
  c.client_name,
  c.contact_email,
  i.invoice_date,
  i.due_date,
  i.total_amount,
  i.sent_date,
  CASE WHEN i.due_date < date('now') THEN 1 ELSE 0 END AS overdue
FROM invoices i
JOIN clients c ON c.client_id = i.client_id
WHERE i.paid = 0
ORDER BY i.due_date;
