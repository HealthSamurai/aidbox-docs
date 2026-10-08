---
description: How to upgrade the PostgreSQL database behind Aidbox to a new major version, for example from 14 to 18, using dump and restore or pg_upgrade.
---

# Upgrade PostgreSQL major version

PostgreSQL stores data in a format that changes between major versions. A PostgreSQL 18 server can't start on a data directory created by PostgreSQL 14, so changing the image tag in your deployment is not enough. You need to migrate the data to a new cluster.

Aidbox supports [recent PostgreSQL versions](postgresql-requirements.md) and doesn't need any changes on its side: once the data is in the new cluster, point Aidbox to it.

## Choose a method

* **Dump and restore** with `pg_dump` and `pg_restore`. The method is simple and works across any versions and hosts. Downtime grows with database size: expect minutes for a few GB and hours for hundreds of GB.
* **[pg\_upgrade](https://www.postgresql.org/docs/current/pgupgrade.html)** converts the data directory in place. It takes minutes regardless of size, but needs the binaries of both PostgreSQL versions on one host, which makes it harder to run with Docker images.
* **Managed PostgreSQL** (AWS RDS, Google Cloud SQL, Azure Database): use the provider's major version upgrade feature.

Use dump and restore unless the database is large and your downtime window is short. The rest of this page describes it.

## Before you start

Check the database size and the installed extensions on the current server:

```sql
SELECT pg_size_pretty(pg_database_size(current_database()));
```

```sql
SELECT extname, extversion FROM pg_extension;
```

Every extension in the list must be available in the target PostgreSQL. Standard `postgres` images include the extensions Aidbox requires. See [PostgreSQL Extensions](postgresql-extensions.md) for the full list.

### jsonknife

AidboxDB images before version 16 shipped the `jsonknife` extension. Newer AidboxDB images and the official `postgres` images don't include it. If your database has indexes that use `jsonknife` functions, the restore fails on those indexes. Find them with:

```sql
SELECT indexname, indexdef
  FROM pg_indexes
 WHERE indexdef ILIKE '%knife%';
```

If the query returns rows, run the shims below on the new cluster before you restore the dump. They define the `jsonknife` functions in plain SQL.

{% file src="../../assets/jsonknife-function-shims.sql" %}
jsonknife function shims
{% endfile %}

## Upgrade with dump and restore

The example uses Docker Compose. Adapt the container names, user, and database name to your setup.

{% stepper %}
{% step %}
**Stop Aidbox**

Stop Aidbox so it doesn't write to the database during the migration. Keep the old PostgreSQL running.

```bash
docker compose stop aidbox
```
{% endstep %}

{% step %}
**Dump the database**

Create a dump in the custom format. It's compressed and lets `pg_restore` work in parallel.

```bash
docker compose exec -T aidbox-db pg_dump -U aidbox -Fc -d aidbox > aidbox.dump
```
{% endstep %}

{% step %}
**Start the new PostgreSQL with an empty volume**

Change the image and use a new volume. Keep the old volume: you need it for rollback.

{% code title="docker-compose.yaml" %}
```yaml
services:
  aidbox-db:
    image: postgres:18
    volumes:
      - pgdata18:/var/lib/postgresql
    environment:
      POSTGRES_USER: aidbox
      POSTGRES_PASSWORD: <password>
      POSTGRES_DB: aidbox

volumes:
  pgdata18: {}
```
{% endcode %}

{% hint style="warning" %}
Starting with `postgres:18`, the official image keeps data in `/var/lib/postgresql/18/docker` and expects the volume at `/var/lib/postgresql`. A volume mounted at `/var/lib/postgresql/data`, as in older setups, doesn't work.
{% endhint %}

```bash
docker compose up -d aidbox-db
```

If you found `jsonknife` indexes, run the shims on the new database now.
{% endstep %}

{% step %}
**Restore the dump**

Copy the dump into the container and restore it. `-j` sets the number of parallel jobs, which only works with a file path.

```bash
docker compose cp aidbox.dump aidbox-db:/tmp/aidbox.dump
docker compose exec aidbox-db pg_restore -U aidbox -d aidbox --no-owner -j 4 /tmp/aidbox.dump
```

`pg_restore` doesn't transfer planner statistics. Collect them before you start Aidbox, or the first queries run slow:

```bash
docker compose exec aidbox-db vacuumdb -U aidbox -d aidbox --analyze-in-stages
```
{% endstep %}

{% step %}
**Start Aidbox and verify**

```bash
docker compose up -d aidbox
```

Check the Aidbox logs for database errors and compare approximate row counts with the old database. Run this query on both servers:

```sql
SELECT relname, n_live_tup
  FROM pg_stat_user_tables
 ORDER BY n_live_tup DESC
 LIMIT 20;
```
{% endstep %}
{% endstepper %}

## Roll back

If something goes wrong, switch the `aidbox-db` service back to the old image and volume and start Aidbox again. Delete the old volume only after you've confirmed the new database works.

## See also

* [pg\_dump](../deployment-and-maintenance/backup-and-restore/pg-dump.md)
* [PostgreSQL Requirements](postgresql-requirements.md)
* [Upgrading a PostgreSQL cluster](https://www.postgresql.org/docs/current/upgrading.html) in the PostgreSQL documentation
