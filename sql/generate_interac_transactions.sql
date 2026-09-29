-- =====================================================================
-- generate_interac_transactions.sql
--
-- PostgreSQL script that generates a large, realistic-looking set of
-- synthetic Interac e-Transfer transactions plus their settlement
-- records, with a controlled number of injected anomalies:
--   - missing settlements (transaction never settled)
--   - amount mismatches (settlement amount != transaction amount)
--   - orphan settlements (settlement with no matching transaction)
--
-- Intended for a personal portfolio project (reconciliation dashboard
-- demo). All data is fictional / randomly generated.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Schema
-- ---------------------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS public;

DROP TABLE IF EXISTS interac_settlement;
DROP TABLE IF EXISTS transactions;

CREATE TABLE transactions (
    transaction_id      BIGSERIAL PRIMARY KEY,
    transaction_date    TIMESTAMP NOT NULL,
    transaction_type    TEXT NOT NULL,       -- 'Interac Send', 'Interac Receive'
    amount               NUMERIC(12,2) NOT NULL,
    sender_account       TEXT NOT NULL,
    receiver_account     TEXT NOT NULL,
    status               TEXT NOT NULL DEFAULT 'Completed'
);

CREATE TABLE interac_settlement (
    settlement_id        BIGSERIAL PRIMARY KEY,
    transaction_id        BIGINT REFERENCES transactions(transaction_id),
    settlement_date       TIMESTAMP NOT NULL,
    settled_amount        NUMERIC(12,2) NOT NULL,
    settlement_status     TEXT NOT NULL DEFAULT 'Settled'
);

-- ---------------------------------------------------------------------
-- 2. Generate ~50,000 base transactions over the last 12 months
-- ---------------------------------------------------------------------

INSERT INTO transactions (transaction_date, transaction_type, amount, sender_account, receiver_account, status)
SELECT
    -- random timestamp within the last 365 days
    NOW() - (random() * INTERVAL '365 days') - (random() * INTERVAL '24 hours') AS transaction_date,
    (ARRAY['Interac Send', 'Interac Receive'])[FLOOR(random() * 2 + 1)] AS transaction_type,
    ROUND((random() * 2980 + 20)::NUMERIC, 2) AS amount,               -- $20 - $3000
    'ACCT' || LPAD((FLOOR(random() * 90000) + 10000)::TEXT, 5, '0') AS sender_account,
    'ACCT' || LPAD((FLOOR(random() * 90000) + 10000)::TEXT, 5, '0') AS receiver_account,
    'Completed' AS status
FROM generate_series(1, 50000);

-- ---------------------------------------------------------------------
-- 3. Generate matching settlements for most transactions
--    (settlement usually posts 0-2 days after the transaction)
-- ---------------------------------------------------------------------

INSERT INTO interac_settlement (transaction_id, settlement_date, settled_amount, settlement_status)
SELECT
    t.transaction_id,
    t.transaction_date + (random() * INTERVAL '2 days'),
    t.amount,
    'Settled'
FROM transactions t
WHERE random() < 0.97;   -- ~97% settle normally; the rest are handled below

-- ---------------------------------------------------------------------
-- 4. Inject anomaly type 1: missing settlements
--    (transactions with status 'Completed' but no settlement row —
--     already produced naturally by the ~3% skipped above; tag them
--     explicitly so they're easy to find in the dashboard)
-- ---------------------------------------------------------------------

UPDATE transactions t
SET status = 'Pending Settlement'
WHERE NOT EXISTS (
    SELECT 1 FROM interac_settlement s WHERE s.transaction_id = t.transaction_id
);

-- ---------------------------------------------------------------------
-- 5. Inject anomaly type 2: amount mismatches
--    Take a small random sample of settled transactions and shift the
--    settled amount slightly (simulates FX rounding / partial capture)
-- ---------------------------------------------------------------------

WITH mismatched AS (
    SELECT settlement_id
    FROM interac_settlement
    ORDER BY random()
    LIMIT 150
)
UPDATE interac_settlement s
SET settled_amount = ROUND((s.settled_amount + (random() * 10 - 5))::NUMERIC, 2),
    settlement_status = 'Settled - Amount Mismatch'
FROM mismatched m
WHERE s.settlement_id = m.settlement_id;

-- ---------------------------------------------------------------------
-- 6. Inject anomaly type 3: orphan settlements
--    Settlement rows with no corresponding transaction (e.g. a
--    duplicate feed record, or a transaction that was later reversed
--    and deleted upstream)
-- ---------------------------------------------------------------------

INSERT INTO interac_settlement (transaction_id, settlement_date, settled_amount, settlement_status)
SELECT
    NULL,
    NOW() - (random() * INTERVAL '365 days'),
    ROUND((random() * 500 + 20)::NUMERIC, 2),
    'Orphan - No Matching Transaction'
FROM generate_series(1, 40);

-- ---------------------------------------------------------------------
-- 7. Quick sanity checks
-- ---------------------------------------------------------------------

-- Total transactions vs settlements
-- SELECT COUNT(*) FROM transactions;
-- SELECT COUNT(*) FROM interac_settlement;

-- Reconciliation summary (mirrors the dashboard's "Interac Reconciliation" panel)
-- SELECT
--     COUNT(*) FILTER (WHERE t.status = 'Completed')          AS reconciled,
--     COUNT(*) FILTER (WHERE t.status = 'Pending Settlement') AS missing_settlement,
--     (SELECT COUNT(*) FROM interac_settlement WHERE settlement_status = 'Settled - Amount Mismatch') AS amount_mismatches,
--     (SELECT COUNT(*) FROM interac_settlement WHERE transaction_id IS NULL) AS orphan_settlements
-- FROM transactions t;
