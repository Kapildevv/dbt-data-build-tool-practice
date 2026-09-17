# dbt + Databricks Practice Project

A hands-on **dbt learning project** that builds a small e-commerce analytics
warehouse on **Databricks** using the **medallion architecture**
(Source → Bronze → Silver / Gold), plus worked examples of dbt's core
features: sources, refs, seeds, snapshots, macros, Jinja, and tests.

> This is a study repository. The dbt project itself lives in
> [`dbt_practice/`](dbt_practice/) — all `dbt` commands must be run from inside
> that folder.

---

## Table of Contents

- [Stack](#stack)
- [Environment Setup](#environment-setup)
- [Configuring the Connection Profile](#configuring-the-connection-profile)
- [Project Structure](#project-structure)
- [Data Flow](#data-flow)
- [Models](#models)
- [Materializations & Custom Schemas](#materializations--custom-schemas)
- [Seeds](#seeds)
- [Snapshots](#snapshots)
- [Macros](#macros)
- [Tests](#tests)
- [Analyses & Jinja Examples](#analyses--jinja-examples)
- [dbt Command Reference](#dbt-command-reference)
- [Common Workflows](#common-workflows)
- [Security Notes](#security-notes)
- [Troubleshooting](#troubleshooting)
- [Resources](#resources)

---

## Stack

| Component       | Version / Value                               |
| --------------- | --------------------------------------------- |
| Python          | 3.12 (see [.python-version](.python-version)) |
| Package manager | [uv](https://docs.astral.sh/uv/)              |
| dbt-core        | 1.12.4                                        |
| dbt-databricks  | 1.10.9                                        |
| dbt-adapters    | 1.24.5                                        |
| Warehouse       | Databricks SQL Warehouse                      |
| Catalog         | `ecommerce_practice`                          |
| dbt project     | `dbt_practice`                                |

---

## Environment Setup

Build the Python environment and install dbt from the repository root:

```bash
# 1. Install uv (one time, globally)
pip install uv

# 2. Scaffold the project (already done in this repo)
uv init

# 3. Create the virtual environment and install locked dependencies
uv sync

# 4. Activate the virtual environment
.venv/Scripts/activate        # Windows (PowerShell / Git Bash)
source .venv/bin/activate     # macOS / Linux

# 5. Add the dbt packages (already recorded in pyproject.toml)
uv add dbt-core
uv add dbt-databricks
```

### Initializing a new dbt project

`dbt init` scaffolds the project folder. It prompts for:

1. **Project name** — e.g. `dbt_practice`
2. **Server hostname** — e.g. `dbc-xxxxxxxx-xxxx.cloud.databricks.com`
3. **HTTP path** — e.g. `/sql/1.0/warehouses/xxxxxxxxxxxxxxxx`

```bash
dbt init
```

> **Important:** after `dbt init`, `cd` into the project folder
> (`cd dbt_practice`) before running any other dbt command. dbt looks for
> `dbt_project.yml` in the current working directory.

### Verify the setup

```bash
cd dbt_practice
dbt debug        # checks config, dependencies and warehouse connection
```

---

## Configuring the Connection Profile

This project keeps `profiles.yml` **inside** the dbt project folder rather than
in `~/.dbt/`, so dbt picks it up automatically when run from `dbt_practice/`.

Copy the sample and fill in your own values:

```bash
cd dbt_practice
cp profiles_sample.yml profiles.yml
```

[`profiles_sample.yml`](dbt_practice/profiles_sample.yml) defines two targets
that share a catalog but let you separate development from production runs:

| Target | Purpose                         | Selected by             |
| ------ | ------------------------------- | ----------------------- |
| `dev`  | Default; day-to-day development | `dbt run` (default)     |
| `prod` | Production environment          | `dbt run --target prod` |

```yaml
dbt_practice:
  outputs:
    dev:
      type: databricks
      catalog: ecommerce_practice
      host: dbc-XXXXXXXX-XXXX.cloud.databricks.com
      http_path: /sql/1.0/warehouses/XXXXXXXXXXXXXXXX
      schema: default
      threads: 1
      token: dapiXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
    prod:
      # ...same keys, pointed at the production warehouse
  target: dev
```

`target.catalog` is referenced dynamically in
[`Source.yml`](dbt_practice/models/Source/Source.yml) and
[`gold_items.yml`](dbt_practice/snapshots/gold_items.yml), so switching targets
moves the whole build without editing model code.

> ⚠️ **Never commit a real `token`.** See [Security Notes](#security-notes).

---

## Project Structure

```
dbt-project/
├── pyproject.toml              # Python deps (dbt-core, dbt-databricks)
├── uv.lock                     # Locked dependency versions
├── .python-version             # Python 3.12
└── dbt_practice/               # ← the dbt project; run dbt commands here
    ├── dbt_project.yml         # Project config: paths, materializations, schemas
    ├── profiles_sample.yml     # Template connection profile (safe to commit)
    ├── profiles.yml            # Real credentials — MUST stay untracked
    ├── models/
    │   ├── Source/Source.yml   # Source table declarations (raw layer)
    │   ├── Bronze/             # 1:1 landing models over sources
    │   │   ├── bronze_transactions.sql
    │   │   ├── bronze_customers.sql
    │   │   ├── bronze_products.sql
    │   │   ├── bronze_pg_data.sql
    │   │   ├── bronze_cashback_rewards.sql
    │   │   └── properties.yml  # Model configs + column-level tests
    │   ├── Silver/             # Cleansed / joined business models
    │   │   ├── master_table.sql
    │   │   └── customer_monthly_txn.sql
    │   └── Gold/               # Consumption-ready models
    │       └── source_gold_transactions.sql
    ├── seeds/mapping.csv         # Static lookup loaded into the warehouse
    ├── snapshots/gold_items.yml  # SCD Type 2 history via YAML snapshot
    ├── macros/
    │   ├── multiply.sql        # Custom reusable SQL macro
    │   └── generate_schema.sql # Overrides dbt's schema-naming behaviour
    ├── tests/
    │   ├── generic/generic_non_negative.sql  # Reusable generic test
    │   └── txn_value_test.sql  # Singular (one-off) test
    └── analyses/               # Jinja + macro scratchpad (compiled, never run)
```

---

## Data Flow

```
Databricks catalog: ecommerce_practice / schema: default
│
├─ transactions ──────┐
├─ customers ─────────┤
├─ products ──────────┤   declared in models/Source/Source.yml
├─ pg_data ───────────┤
└─ cashback_rewards ──┘
          │
          ▼  source('default', <table>)
┌──────────────────────────────────────────────┐
│ BRONZE  (schema: bronze)                     │
│   bronze_transactions        (table)         │
│   bronze_products            (table)         │
│   bronze_pg_data             (table)         │
│   bronze_customers           (view)          │
│   bronze_cashback_rewards    (view)          │
│   mapping                    (seed → bronze) │
└──────────────────────────────────────────────┘
          │  ref(...)
          ├───────────────────────────┬──────────────────────────┐
          ▼                           ▼                          ▼
┌─────────────────────┐   ┌──────────────────────┐   ┌──────────────────────────┐
│ SILVER              │   │ SILVER               │   │ GOLD                     │
│ master_table        │   │ customer_monthly_txn │   │ source_gold_transactions │
│ (wide join of all   │   │ (month + previous    │   │ (latest order per        │
│  bronze + seed)     │   │  month per customer) │   │  customer)               │
└─────────────────────┘   └──────────────────────┘   └──────────────────────────┘
                                                                  │
                                                                  ▼
                                                     ┌──────────────────────────┐
                                                     │ SNAPSHOT (schema: gold)  │
                                                     │ gold_items — SCD Type 2  │
                                                     └──────────────────────────┘
```

---

## Models

### Source layer — [`models/Source/Source.yml`](dbt_practice/models/Source/Source.yml)

Declares five raw Databricks tables under the source name `default`. Using
`source()` instead of hard-coded table names gives dbt source freshness,
lineage in the docs, and a single place to repoint the raw layer.

The `database:` key is templated from `target.catalog`, so the source follows
whichever target you run.

### Bronze layer — [`models/Bronze/`](dbt_practice/models/Bronze/)

Straight `SELECT *` passthroughs over each source — the landing zone. No
business logic, which keeps the raw data reproducible and auditable.

| Model                     | Materialization | Configured in                                |
| ------------------------- | --------------- | -------------------------------------------- |
| `bronze_transactions`     | table           | `dbt_project.yml` (folder default)           |
| `bronze_products`         | table           | `dbt_project.yml` (folder default)           |
| `bronze_pg_data`          | table           | `dbt_project.yml` (folder default)           |
| `bronze_customers`        | view            | `properties.yml` (YAML config block)         |
| `bronze_cashback_rewards` | view            | in-file `config(materialized='view')` block  |

> The two views demonstrate the **three places a config can live** — project
> file, properties YAML, and an in-model `config()` block — with the most
> specific one winning.

### Silver layer — [`models/Silver/`](dbt_practice/models/Silver/)

**[`master_table.sql`](dbt_practice/models/Silver/master_table.sql)** — the
centrepiece join. It left-joins all five bronze models plus the `mapping` seed
onto `bronze_transactions` and demonstrates:

- `LEFT JOIN` fan-out across five refs and a seed
- The custom `multiply()` macro to derive `gst_amount` at 18%
- Semi-structured parsing with `get_json_object(...)` to flatten
  `product_specs`, `pg_metadata`, and `customer_metadata` JSON columns into
  ~15 flat fields (weight, warranty, device type, city, pincode, error codes…)
- Date cleaning with `date(substr(order_date, 1, 10))`
- Derived `unit_price` with an explicit `cast(quantity as double)` to avoid
  integer division

> **Note:** the final `SELECT` currently returns a **row-count summary**
> (`total_records`, `total_orders`, `total_customers`) rather than the wide CTE
> itself — a useful sanity check while developing. To materialize the full
> table, select from `raw_data` directly.

**[`customer_monthly_txn.sql`](dbt_practice/models/Silver/customer_monthly_txn.sql)**
— builds a distinct customer/month grain and uses a window function
(`LAG(...) OVER (PARTITION BY customer_id ORDER BY order_month)`) to attach
each customer's previous active month. Useful for churn / gap analysis.

### Gold layer — [`models/Gold/`](dbt_practice/models/Gold/)

**[`source_gold_transactions.sql`](dbt_practice/models/Gold/source_gold_transactions.sql)**
— deduplicates to the **latest order per customer** using
`ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date DESC)` and
filtering `row_num = 1`. This model is the input to the `gold_items` snapshot.

---

## Materializations & Custom Schemas

Folder-level defaults are set in
[`dbt_project.yml`](dbt_practice/dbt_project.yml):

```yaml
models:
  dbt_practice:
    Bronze:
      +materialized: table
      schema: bronze
    Silver:
      +materialized: table
      schema: silver
    Gold:
      +materialized: table
      schema: gold

seeds:
  dbt_practice:
    +schema: bronze
```

By default dbt would **concatenate** the target schema and the custom schema
(producing `default_bronze`). This project overrides that behaviour in
[`macros/generate_schema.sql`](dbt_practice/macros/generate_schema.sql) so the
custom name is used verbatim: if `custom_schema_name` is `none` it falls back
to `target.schema`, otherwise it returns the trimmed custom name.

Result: models land in clean `bronze` / `silver` / `gold` schemas.

> ⚠️ This override removes the per-developer namespacing that dbt's default
> provides. In a shared warehouse, two developers running `dev` will write to
> the **same** schemas. Fine for solo practice; prefix by `target.name` before
> using this pattern on a team.

---

## Seeds

[`seeds/mapping.csv`](dbt_practice/seeds/mapping.csv) is a small static lookup
mapping order status text to a numeric code:

| status_text | status |
| ----------- | ------ |
| Delivered   | 7      |
| Cancelled   | 18     |
| InTransit   | 5      |

Load it into the warehouse, then reference it like any other model with
`ref('mapping')`:

```bash
dbt seed
```

Seeds are for small, version-controlled reference data — not for loading
production volumes.

---

## Snapshots

[`snapshots/gold_items.yml`](dbt_practice/snapshots/gold_items.yml) captures
**slowly changing dimension (Type 2)** history over the gold model, using the
YAML snapshot syntax introduced in recent dbt versions:

```yaml
snapshots:
  - name: gold_items
    relation: ref('source_gold_transactions')
    config:
      schema: gold
      database: "{{ target.catalog }}"
      unique_key: customer_id
      strategy: timestamp
      updated_at: order_date
      dbt_valid_to_current: current_timestamp()
```

- **`strategy: timestamp`** — a row is treated as changed when `order_date`
  moves forward (the alternative is `check` with a column list).
- **`dbt_valid_to_current`** — sets the `dbt_valid_to` value for the *current*
  record instead of leaving it `NULL`, which makes `BETWEEN` range filters work
  without `COALESCE`.

```bash
dbt snapshot
```

---

## Macros

| Macro                  | File                                                                    | Purpose                                                       |
| ---------------------- | ----------------------------------------------------------------------- | ------------------------------------------------------------- |
| `multiply(x, y)`       | [`macros/multiply.sql`](dbt_practice/macros/multiply.sql)               | Emits `x * y`; used for the GST calculation in `master_table` |
| `generate_schema_name` | [`macros/generate_schema.sql`](dbt_practice/macros/generate_schema.sql) | Built-in override so custom schemas are used verbatim         |

Call a macro straight from a model or analysis, or run one standalone from the
CLI:

```bash
dbt run-operation multiply --args '{x: 2, y: 3}'
```

---

## Tests

dbt has two kinds of tests, and this project uses both.

### Generic tests — [`models/Bronze/properties.yml`](dbt_practice/models/Bronze/properties.yml)

| Column         | Test                   | Notes                                                       |
| -------------- | ---------------------- | ----------------------------------------------------------- |
| `order_id`     | `not_null`, `unique`   | Enforces the primary-key grain                              |
| `order_status` | `accepted_values`      | `['Delivered', 'Cancelled', 'InTransit']`, `severity: warn` |
| `total_amount` | `generic_non_negative` | Custom generic test (below)                                 |

Note the modern dbt 1.10+ test syntax, where test inputs are nested under
`arguments:` and behaviour under `config:`:

```yaml
- accepted_values:
    arguments:
      values: ['Delivered', 'Cancelled', 'InTransit']
    config:
      severity: warn
```

`severity: warn` lets the build continue on failure — the right choice for a
data-quality signal you want visibility on but that shouldn't block the DAG.

### Custom generic test — [`tests/generic/generic_non_negative.sql`](dbt_practice/tests/generic/generic_non_negative.sql)

A reusable `test` block taking `model` and `column_name`, selecting rows where
the column is negative. A test passes when it returns **zero rows**. Because
it's wrapped in a `test` block rather than written as a plain query, it can be
attached to any column in any model's YAML.

### Singular test — [`tests/txn_value_test.sql`](dbt_practice/tests/txn_value_test.sql)

A one-off assertion written as a plain query against a single model — no
parameters, no reuse. Good for bespoke business rules.

```bash
dbt test                                  # everything
dbt test --select bronze_transactions     # one model
dbt test --select test_type:generic       # only generic tests
dbt test --select test_type:singular      # only singular tests
```

---

## Analyses & Jinja Examples

Files in [`analyses/`](dbt_practice/analyses/) are **compiled but never
executed** against the warehouse — a scratchpad for learning Jinja and for
ad-hoc queries. Run `dbt compile` and read the rendered SQL under
`target/compiled/`.

| File                                                            | Demonstrates                                                            |
| --------------------------------------------------------------- | ----------------------------------------------------------------------- |
| [`jinja1.sql`](dbt_practice/analyses/jinja1.sql)                 | `set` variables and whitespace control (`{%- ... -%}`)                  |
| [`jinja2.sql`](dbt_practice/analyses/jinja2.sql)                 | `for` loops with `if` / `else` branching over a list                    |
| [`jinja3.sql`](dbt_practice/analyses/jinja3.sql)                 | Dynamic column lists with `loop.last` comma handling + conditional `WHERE` |
| [`query_marco.sql`](dbt_practice/analyses/query_marco.sql)       | Calling the custom `multiply` macro                                     |
| [`explore.sql`](dbt_practice/analyses/explore.sql)               | `ref()` against a seed                                                  |
| [`explore2.sql`](dbt_practice/analyses/explore2.sql)             | `ref()` against a bronze model                                          |

The `loop.last` pattern in `jinja3.sql` is the standard way to build a
comma-separated column list without a trailing comma.

---

## dbt Command Reference

Run all of these from inside `dbt_practice/`.

| Command         | Description                                                                |
| --------------- | -------------------------------------------------------------------------- |
| `build`         | Run all seeds, models, snapshots, and tests in DAG order                   |
| `clean`         | Delete all folders in the `clean-targets` list (`target/`, `dbt_packages/`) |
| `clone`         | Create clones of selected nodes based on their location                    |
| `compile`       | Generate executable SQL from source, model, test, and analysis files       |
| `debug`         | Show information on the current dbt environment and test the connection    |
| `deps`          | Install dbt packages specified in `packages.yml`                           |
| `docs`          | Generate or serve the documentation website for your project               |
| `init`          | Initialize a new dbt project                                               |
| `list`          | List the resources in your project                                         |
| `parse`         | Parse the project and provide information on performance                   |
| `retry`         | Retry the nodes that failed in the previous run                            |
| `run`           | Compile SQL and execute against the current target database                |
| `run-operation` | Run the named macro with any supplied arguments                            |
| `seed`          | Load data from CSV files into your data warehouse                          |
| `show`          | Generate and preview executable SQL for a named resource or inline query   |
| `snapshot`      | Execute snapshots defined in your project                                  |
| `source`        | Manage your project's sources (e.g. `dbt source freshness`)                |
| `test`          | Run tests on data in deployed models                                       |

---

## Common Workflows

```bash
cd dbt_practice
```

**Full build (seeds → models → snapshots → tests, in dependency order):**

```bash
dbt build
```

**Build a single layer:**

```bash
dbt run --select Bronze          # everything in the Bronze folder
dbt run --select Silver Gold     # multiple folders
```

**Build a model and everything downstream of it:**

```bash
dbt run --select bronze_transactions+
```

**Build a model and everything it depends on:**

```bash
dbt run --select +master_table
```

**Preview results without materializing:**

```bash
dbt show --select customer_monthly_txn --limit 10
```

**Inspect the SQL dbt actually sends to Databricks:**

```bash
dbt compile --select master_table
# → target/compiled/dbt_practice/models/Silver/master_table.sql
```

**Rerun only what failed last time:**

```bash
dbt retry
```

**Generate and browse lineage docs:**

```bash
dbt docs generate
dbt docs serve          # opens the DAG + catalog at http://localhost:8080
```

**Run against production:**

```bash
dbt build --target prod
```

**Start from a clean slate:**

```bash
dbt clean && dbt deps && dbt build
```



---

## Troubleshooting

| Symptom                                           | Likely cause / fix                                                              |
| ------------------------------------------------- | ------------------------------------------------------------------------------- |
| `Could not find dbt_project.yml`                  | You're in the repo root — `cd dbt_practice` first                               |
| `Runtime Error ... connection`                    | Run `dbt debug`; verify host, HTTP path, and that the SQL warehouse is **running** |
| `dbt: command not found`                          | Virtual environment not activated — `.venv/Scripts/activate`                    |
| Compilation error: `mapping` not found            | Run `dbt seed` before `dbt run`, or just use `dbt build`                        |
| Models land in `default_bronze` instead of `bronze` | The `generate_schema_name` macro isn't being picked up — confirm it sits in `macros/` |
| Snapshot rewrites every row                       | `updated_at` (`order_date`) is null or non-monotonic for those keys             |
| Stale results after editing a model               | `dbt clean` to clear `target/`, then rebuild                                    |

---

## Resources

- [dbt Documentation](https://docs.getdbt.com/docs/introduction)
- [dbt + Databricks setup](https://docs.getdbt.com/docs/core/connect-data-platform/databricks-setup)
- [Jinja & macros reference](https://docs.getdbt.com/docs/build/jinja-macros)
- [Node selection syntax](https://docs.getdbt.com/reference/node-selection/syntax)
- [Snapshots](https://docs.getdbt.com/docs/build/snapshots)
- [dbt Discourse](https://discourse.getdbt.com/) · [Community Slack](https://community.getdbt.com/) · [Blog](https://blog.getdbt.com/)
