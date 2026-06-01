---
description: Open-source administration console for Aidbox FHIR server with Resource Browser, REST Console, SQL Console, FHIR packages, Audit Events, and Settings.
---

# Aidbox UI

**Aidbox UI** is an open-source administration console for the Aidbox FHIR server. It is built with React and TypeScript and ships as part of every Aidbox instance. The source code is available on [GitHub](https://github.com/HealthSamurai/aidbox-ui). Contributions, bug reports, and feature requests are welcome.

Aidbox UI is built on top of the [Aidbox TypeScript SDK](https://github.com/HealthSamurai/aidbox-ts-sdk) and the [Health Samurai React Components](https://github.com/HealthSamurai/aidbox-ts-sdk/tree/master/packages/react-components) library — a set of reusable UI components for building healthcare applications with Aidbox. You can use the same libraries to build your own custom UIs.

## Key components

### Resource Browser

Browse, search, create, and edit FHIR resources stored in Aidbox. The Resource Browser supports search parameters, sorting, and inline JSON editing.

Some resource types have specialized views:

* **AccessPolicy** — includes a built-in dev tool for testing policies. Send a request directly from the editor and see which policies matched, the evaluation result, and the generated SQL — all without leaving the page.
* **ViewDefinition** — a visual builder for [SQL on FHIR](../../modules/sql-on-fhir/README.md) ViewDefinitions. Edit columns, preview the generated SQL, run the query, and inspect results side by side with a FHIRPath editor and schema browser.

<video src="../../../assets/overview/aidbox-ui/vd.mp4" autoplay loop muted playsinline controls class="w-full rounded-lg" loading="lazy"></video>

### REST Console

An interactive HTTP client built into Aidbox. Use it to execute REST API requests, inspect responses, and build collections of saved queries.

<video src="../../../assets/overview/aidbox-ui/rest-4k.mp4" autoplay loop muted playsinline controls class="w-full rounded-lg" loading="lazy"></video>

### SQL Console

Run SQL queries directly against the Aidbox database. Useful for debugging, analytics, and working with [SQL on FHIR](../../modules/sql-on-fhir/README.md) ViewDefinitions.

Per-tab settings:

* **Transaction mode** — `Autocommit` (each statement commits immediately; required for `VACUUM`, `CREATE INDEX CONCURRENTLY`) or `Transaction` (whole script wrapped in a single transaction).
* **Timeout** — per-query `statement_timeout`, default 1 minute.
* **Limit** — JDBC fetch size cap.
* **Execution** — `Foreground` (synchronous, results returned to the UI) or `Background` (fire-and-forget; the server runs the query, the UI does not retain results).

Stop button cancels the running query via [`$psql-cancel`](../../api/rest-api/other/sql-endpoints.md#usdpsql-cancel). The `Tab` key indents inside the editor; `EXPLAIN` plans render as a monospace block. Each tab keeps its own settings, query text, and running state. Backed by the [`$psql` endpoint](../../api/rest-api/other/sql-endpoints.md#usdpsql).

<video src="../../../assets/overview/aidbox-ui/db.mp4" autoplay loop muted playsinline controls class="w-full rounded-lg" loading="lazy"></video>

### Database

A DBA-focused page at `/u/database` with three subpages:

* **Schema Explorer** — every table across all user schemas, grouped into per-schema tabs. Per-table size, row count, index/toast share, and time since last (auto)vacuum/(auto)analyze. Expand a row to inspect its indexes (with their `CREATE INDEX` DDL on hover) and run `VACUUM`, `ANALYZE`, or `REINDEX`. Destructive operations like `TRUNCATE` are available only via the [`aidbox.pg/*` RPCs](../../database/database-maintenance-rpcs.md).

<figure><img src="../../../assets/database/schema-explorer.avif" alt="Database → Schema Explorer — per-schema tabs over a fuzzy search; one row per table with size, row count, index/toast share, and recency of vacuum/analyze"><figcaption><p>Database → Schema Explorer.</p></figcaption></figure>

* **Running Queries** — `pg_stat_activity` snapshot of active queries, refreshed every 5 seconds. Cancel a statement (`pg_cancel_backend`) or terminate the whole connection (`pg_terminate_backend`) from the row.

<figure><img src="../../../assets/database/running-queries.avif" alt="Database → Running Queries — live table of pg_stat_activity backends with PID, user, duration, wait event, app, query, and Cancel / Terminate buttons"><figcaption><p>Database → Running Queries.</p></figcaption></figure>

* **Search Params Stats** — paginated, sortable view of `aidbox_stat.search_param_stats`. Pick a resource type from the dropdown, filter by search-param substring, drop stats for the selected rows, or reset everything. See [Search Parameters Usage Statistics](../../deployment-and-maintenance/indexes/search-parameter-usage-stats.md) for the underlying data model.

<figure><img src="../../../assets/database/search-params-stats.avif" alt="Database → Search Params Stats — sortable table of per-SP call counts, mean/min/max/total time, last-used timestamp, and an Index column; per-row checkboxes drive bulk drop"><figcaption><p>Database → Search Params Stats.</p></figcaption></figure>

Backed by the [`aidbox.pg/*`](../../database/database-maintenance-rpcs.md) and [`aidbox.index/*`](../../deployment-and-maintenance/indexes/search-parameter-usage-stats.md) RPCs.

### FHIR Packages

Browse, install, and manage FHIR Implementation Guides and NPM packages loaded into Aidbox via the [FHIR Artifact Registry](../../artifact-registry/artifact-registry-overview.md). Inspect individual resources within each package.

<video src="../../../assets/overview/aidbox-ui/far.mp4" autoplay loop muted playsinline controls class="w-full rounded-lg" loading="lazy"></video>

### Audit Events

View and search [AuditEvent](../../access-control/audit-and-logging.md) resources generated by Aidbox, with filtering by date, type, and agent.

### Settings

Configure Aidbox instance settings from the UI.
