{{ config(materialized='table') }}

SELECT
    transaction_date::DATE AS summary_date,
    transaction_type,
    COUNT(*) AS txn_count,
    SUM(amount) AS total_amount
FROM {{ source('processed', 'daily_transaction') }}
GROUP BY transaction_date::DATE, transaction_type