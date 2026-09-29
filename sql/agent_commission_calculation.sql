-- =====================================================================
-- agent_commission_calculation.sql
--
-- Fictional / demonstration script.
-- Portfolio sample showing PL/SQL patterns for a mobile-money style
-- agent commission engine: tiered commission lookup, monthly commission
-- calculation, and a simple structuring / fraud-pattern flag.
--
-- All schema names, table names, business rules, and thresholds below
-- are invented for demonstration purposes only. No proprietary code,
-- data, or business logic from any employer is reproduced here.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Schema objects
-- ---------------------------------------------------------------------

CREATE TABLE agent_commission_tier (
    tier_id             NUMBER          PRIMARY KEY,
    tier_name           VARCHAR2(50)    NOT NULL,
    min_volume_amount   NUMBER(18,2)    NOT NULL,
    max_volume_amount   NUMBER(18,2),          -- NULL = no upper bound
    commission_rate_pct NUMBER(5,3)     NOT NULL,   -- e.g. 0.750 = 0.75%
    flat_bonus_amount   NUMBER(18,2)    DEFAULT 0 NOT NULL
);

INSERT INTO agent_commission_tier VALUES (1, 'Bronze',   0,          500000,     0.400, 0);
INSERT INTO agent_commission_tier VALUES (2, 'Silver',   500000.01,  2000000,    0.550, 15000);
INSERT INTO agent_commission_tier VALUES (3, 'Gold',     2000000.01, 5000000,    0.700, 40000);
INSERT INTO agent_commission_tier VALUES (4, 'Platinum', 5000000.01, NULL,       0.850, 90000);
COMMIT;

CREATE TABLE agent_transaction (
    transaction_id      NUMBER          PRIMARY KEY,
    agent_id            NUMBER          NOT NULL,
    transaction_date    DATE            NOT NULL,
    transaction_type    VARCHAR2(20)    NOT NULL,   -- CASH_IN, CASH_OUT, TRANSFER
    amount               NUMBER(18,2)   NOT NULL
);

CREATE TABLE agent_monthly_commission (
    agent_id             NUMBER          NOT NULL,
    commission_month     DATE            NOT NULL,   -- first day of month
    total_volume         NUMBER(18,2)    NOT NULL,
    tier_id              NUMBER          NOT NULL,
    commission_amount    NUMBER(18,2)    NOT NULL,
    calculated_on        DATE            DEFAULT SYSDATE,
    CONSTRAINT pk_agent_monthly_commission PRIMARY KEY (agent_id, commission_month)
);

CREATE TABLE agent_fraud_flag (
    flag_id              NUMBER          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    agent_id             NUMBER          NOT NULL,
    flag_date            DATE            DEFAULT SYSDATE,
    flag_type            VARCHAR2(50)    NOT NULL,
    detail               VARCHAR2(4000)
);

-- ---------------------------------------------------------------------
-- 2. Package specification
-- ---------------------------------------------------------------------

CREATE OR REPLACE PACKAGE agent_commission_pkg AS

    -- Calculates and stores commission for a single agent for a given month.
    PROCEDURE calculate_monthly_commission (
        p_agent_id   IN NUMBER,
        p_month_date IN DATE
    );

    -- Runs the monthly calculation for every active agent.
    PROCEDURE calculate_all_agents (
        p_month_date IN DATE
    );

    -- Looks for a simple "structuring" pattern: several transactions kept
    -- just under a reporting threshold within a short window.
    PROCEDURE flag_structuring_pattern (
        p_agent_id     IN NUMBER,
        p_window_days  IN NUMBER DEFAULT 3,
        p_threshold    IN NUMBER DEFAULT 10000
    );

END agent_commission_pkg;
/

-- ---------------------------------------------------------------------
-- 3. Package body
-- ---------------------------------------------------------------------

CREATE OR REPLACE PACKAGE BODY agent_commission_pkg AS

    PROCEDURE calculate_monthly_commission (
        p_agent_id   IN NUMBER,
        p_month_date IN DATE
    ) IS
        v_month_start   DATE := TRUNC(p_month_date, 'MM');
        v_month_end     DATE := ADD_MONTHS(v_month_start, 1) - 1/86400;
        v_total_volume  NUMBER(18,2);
        v_tier_id       NUMBER;
        v_rate_pct      NUMBER(5,3);
        v_bonus         NUMBER(18,2);
        v_commission    NUMBER(18,2);
    BEGIN
        -- 1) Total eligible volume for the month (cash-in + cash-out only)
        SELECT NVL(SUM(amount), 0)
          INTO v_total_volume
          FROM agent_transaction
         WHERE agent_id = p_agent_id
           AND transaction_date BETWEEN v_month_start AND v_month_end
           AND transaction_type IN ('CASH_IN', 'CASH_OUT');

        -- 2) Resolve the commission tier for that volume
        SELECT tier_id, commission_rate_pct, flat_bonus_amount
          INTO v_tier_id, v_rate_pct, v_bonus
          FROM agent_commission_tier
         WHERE v_total_volume >= min_volume_amount
           AND (max_volume_amount IS NULL OR v_total_volume <= max_volume_amount);

        -- 3) Commission = (volume * rate%) + flat bonus for the tier
        v_commission := ROUND(v_total_volume * (v_rate_pct / 100), 2) + v_bonus;

        -- 4) Upsert into the monthly commission table
        MERGE INTO agent_monthly_commission tgt
        USING (SELECT p_agent_id AS agent_id, v_month_start AS commission_month FROM dual) src
           ON (tgt.agent_id = src.agent_id AND tgt.commission_month = src.commission_month)
        WHEN MATCHED THEN
            UPDATE SET total_volume      = v_total_volume,
                       tier_id           = v_tier_id,
                       commission_amount = v_commission,
                       calculated_on     = SYSDATE
        WHEN NOT MATCHED THEN
            INSERT (agent_id, commission_month, total_volume, tier_id, commission_amount)
            VALUES (p_agent_id, v_month_start, v_total_volume, v_tier_id, v_commission);

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            -- No matching tier (e.g. zero volume) — log a zero-commission row instead of failing
            MERGE INTO agent_monthly_commission tgt
            USING (SELECT p_agent_id AS agent_id, v_month_start AS commission_month FROM dual) src
               ON (tgt.agent_id = src.agent_id AND tgt.commission_month = src.commission_month)
            WHEN MATCHED THEN
                UPDATE SET total_volume = v_total_volume, tier_id = 1, commission_amount = 0, calculated_on = SYSDATE
            WHEN NOT MATCHED THEN
                INSERT (agent_id, commission_month, total_volume, tier_id, commission_amount)
                VALUES (p_agent_id, v_month_start, v_total_volume, 1, 0);
    END calculate_monthly_commission;


    PROCEDURE calculate_all_agents (
        p_month_date IN DATE
    ) IS
    BEGIN
        FOR rec IN (SELECT DISTINCT agent_id FROM agent_transaction) LOOP
            calculate_monthly_commission(rec.agent_id, p_month_date);
        END LOOP;

        COMMIT;
    END calculate_all_agents;


    PROCEDURE flag_structuring_pattern (
        p_agent_id     IN NUMBER,
        p_window_days  IN NUMBER DEFAULT 3,
        p_threshold    IN NUMBER DEFAULT 10000
    ) IS
        v_count NUMBER;
    BEGIN
        -- Heuristic only: count transactions in the last N days that sit
        -- just under the threshold (80-99.9% of it) — a classic
        -- "structuring" red flag when it happens repeatedly.
        SELECT COUNT(*)
          INTO v_count
          FROM agent_transaction
         WHERE agent_id = p_agent_id
           AND transaction_date >= SYSDATE - p_window_days
           AND amount BETWEEN (p_threshold * 0.8) AND (p_threshold * 0.999);

        IF v_count >= 3 THEN
            INSERT INTO agent_fraud_flag (agent_id, flag_type, detail)
            VALUES (
                p_agent_id,
                'POSSIBLE_STRUCTURING',
                'Agent had ' || v_count || ' transactions between ' ||
                ROUND(p_threshold * 0.8, 2) || ' and ' || ROUND(p_threshold * 0.999, 2) ||
                ' within the last ' || p_window_days || ' day(s).'
            );
        END IF;
    END flag_structuring_pattern;

END agent_commission_pkg;
/

-- ---------------------------------------------------------------------
-- 4. Example usage
-- ---------------------------------------------------------------------

-- Run commission calculation for all agents for the current month
-- EXEC agent_commission_pkg.calculate_all_agents(SYSDATE);

-- Check a single agent for structuring patterns
-- EXEC agent_commission_pkg.flag_structuring_pattern(p_agent_id => 1042);
