import os
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.providers.postgres.operators.postgres import PostgresOperator
from datetime import datetime, timedelta


PROJECT_ROOT = os.environ.get("BANK_DASHBOARD_PROJECT_ROOT", os.path.expanduser("~/bank-dashboard-project"))
DBT_PROJECT_DIR = os.path.join(PROJECT_ROOT, "dbt", "bank_dashboard")
DBT_BIN = os.path.join(PROJECT_ROOT, "dbt", "dbt-env", "bin", "dbt")
DBT_PROFILES_DIR = os.path.join(PROJECT_ROOT, "dbt", ".dbt")


default_args = {
    'owner': 'christian',
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

with DAG(
    dag_id='bank_dashboard_pipeline',
    default_args=default_args,
    description='Extraction + dbt transformation for bank dashboard',
    schedule='0 2 * * *',
    start_date=datetime(2026, 9, 1),
    catchup=False,
    tags=['dbt', 'bank_dashboard'],
) as dag:

    extract_raw_data = PostgresOperator(
        task_id='extract_raw_transactions',
        postgres_conn_id='postgres_bank_db',
        sql='CALL processed.refresh_daily_transactions();',
    )

    dbt_run = BashOperator(
        task_id='dbt_run',
        bash_command=f'cd {DBT_PROJECT_DIR} && {DBT_BIN} run --profiles-dir {DBT_PROFILES_DIR}',
    )

    dbt_test = BashOperator(
        task_id='dbt_test',
        bash_command=f'cd {DBT_PROJECT_DIR} && {DBT_BIN} test --profiles-dir {DBT_PROFILES_DIR}',
    )

    extract_raw_data >> dbt_run >> dbt_test