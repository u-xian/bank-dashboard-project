# Bank Transaction Dashboard — dbt + Airflow + Grafana

An end-to-end data engineering pipeline that extracts bank transaction data from PostgreSQL, transforms it with dbt, orchestrates the workflow with Apache Airflow, and visualizes it in Grafana.

Built as a personal portfolio project to demonstrate modern data engineering practices (dbt, Airflow) alongside traditional SQL/ETL skills (PL/pgSQL) from 18+ years of professional data engineering experience.

## Architecture

```
PostgreSQL (raw transactions)
        │
        ▼
PL/pgSQL stored procedure  ──►  extracts & loads raw data into a staging table
        │
        ▼
dbt  ──►  transforms staging data into analytics-ready models
        │
        ▼
Apache Airflow  ──►  orchestrates the extraction → dbt run → dbt test pipeline on a schedule
        │
        ▼
Grafana  ──►  visualizes transaction trends, loan/savings breakdowns, and category filters
```

## Dashboard preview

![Dashboard overview](screenshots/dashboard_overview.png)

The dashboard includes:

- **Transaction volume by type** — filterable by transaction category and year, showing trends over time
- **Loan Payment breakdown** — disbursement, capital repay, interest repay, fees, by share of total
- **Savings Accounts Payment breakdown** — capital return, capital deduct, and interest payment shares

## Tech stack

| Layer          | Tool                       |
| -------------- | -------------------------- |
| Database       | PostgreSQL                 |
| Extraction     | PL/pgSQL stored procedures |
| Transformation | dbt (dbt-postgres)         |
| Orchestration  | Apache Airflow             |
| Visualization  | Grafana                    |
| Language       | Python, SQL                |

## Project structure

```
bank-dashboard-project/
├── dbt/
│   ├── .dbt/                    # dbt profiles.yml (not committed — see .gitignore)
│   ├── dbt-env/                 # dbt virtualenv (not committed)
│   └── bank_dashboard/
│       ├── dbt_project.yml
│       ├── models/
│       │   ├── staging/
│       │   └── marts/
│       └── ...
├── airflow-project/
│   └── airflow_home/
│       ├── dags/
│       │   └── bank_dashboard_pipeline.py
│       └── ...                  # (not committed — see .gitignore)
├── sql/
│   ├── agent_commission_calculation.sql
│   └── generate_interac_transactions.sql
├── grafana/
├── screenshots/
└── README.md
```

## How the pipeline works

1. **Extraction** — An Airflow `PostgresOperator` task calls a PL/pgSQL stored procedure (`processed.refresh_daily_transactions()`) that pulls raw transaction records into a staging table.
2. **Transformation** — Airflow then runs `dbt run`, which transforms the staged data into clean, analytics-ready models (e.g. daily/monthly transaction summaries by type).
3. **Testing** — `dbt test` runs data quality checks (not-null, uniqueness, referential checks) on the transformed models before the pipeline completes.
4. **Visualization** — Grafana connects directly to the PostgreSQL models dbt produces, with dashboard variables for filtering by transaction type and year.

The DAG runs on a daily schedule (`0 2 * * *`) with `catchup=False`, so it always processes the latest data without backfilling historical runs.

## Setup

### Prerequisites

- PostgreSQL (with your own transaction data, or use a generator script — see `sql/`)
- Python 3.10+
- Grafana

### 1. Clone the repo

```bash
git clone https://github.com/<your-username>/bank-dashboard-project.git
cd bank-dashboard-project
```

### 2. Set up dbt

```bash
cd dbt
python3 -m venv dbt-env
source dbt-env/bin/activate
pip install dbt-postgres
deactivate
```

Create `dbt/.dbt/profiles.yml` with your own PostgreSQL connection details (see `dbt/bank_dashboard/dbt_project.yml` for the profile name it expects).

### 3. Set up Airflow

```bash
cd ../airflow-project
python3 -m venv airflow-env
source airflow-env/bin/activate
pip install apache-airflow apache-airflow-providers-postgres
```

Set the project root environment variable (this makes the DAG portable across machines/users — no hardcoded paths):

```bash
export BANK_DASHBOARD_PROJECT_ROOT=$HOME/bank-dashboard-project
```

Add that line to your `~/.bashrc` (or equivalent) to persist it.

### 4. Run it

```bash
cd ~/bank-dashboard-project
airflow standalone
```

Open `http://localhost:8080`, unpause the `bank_dashboard_pipeline` DAG, and trigger a run.

### 5. Connect Grafana

Add PostgreSQL as a data source in Grafana pointing at your database, then build panels against the dbt-generated models (or import a dashboard JSON if one is included under `grafana/`).

## Notes

- All SQL scripts under `sql/` use fictional data and business logic — no proprietary code or data from any employer is included in this repository.
- `dbt-env/`, `airflow-env/`, `.dbt/`, and Airflow's runtime files (database, logs, config) are excluded via `.gitignore` since they contain machine-specific paths and should never be committed.

## Author

Christian Uwakristu — Data Engineer / ETL Developer (PL/SQL, Oracle, PostgreSQL, dbt, Airflow)
