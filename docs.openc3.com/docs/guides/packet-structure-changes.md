---
title: Packet Structure Changes
description: How COSMOS migrates QuestDB tables when command and telemetry definitions change
sidebar_custom_props:
  myEmoji: 🔀
---

Command and telemetry definitions are rarely static. Items get added as a target matures, an item's type changes from an integer to a float, an item gets renamed, or an item is removed entirely. Because COSMOS 7 stores all decommutated data in the [QuestDB](https://questdb.io/) time-series database (TSDB), a change to a packet definition implies a change to a database table that may already hold months of data.

COSMOS reconciles the table schema automatically. This guide describes what it does, what happens to data already stored, and where manual intervention is required.

## Background

Each command and telemetry packet gets its own QuestDB table named `SCOPE__CMD__TARGET__PACKET` or `SCOPE__TLM__TARGET__PACKET`. Each packet item becomes one or more columns:

| Column    | Contents                                                              |
| --------- | --------------------------------------------------------------------- |
| `ITEM`    | The `RAW` value                                                       |
| `ITEM__C` | The `CONVERTED` value (only if the item has states or a conversion)   |
| `ITEM__F` | The `FORMATTED` value (only if the item has a format string or units) |

Tables are always `PARTITION BY DAY` with `PACKET_TIMESECONDS` as the designated timestamp. See [QuestDB](/docs/getting-started/architecture#questdb) in the Architecture document for the full COSMOS-to-QuestDB type mapping.

## When Reconciliation Happens

The schema is reconciled by the `tsdb` microservice when it starts up. There is one `tsdb` microservice per target (split into multiple instances for high rate targets), and the operator restarts it whenever the target's configuration changes. In practice this means the schema is reconciled when you:

- Install or reinstall a plugin
- Restart COSMOS

Reconciliation is not triggered by editing a definition file in [Local Mode](/docs/guides/local-mode) alone -- the plugin must be reinstalled (or the microservice restarted) for COSMOS to pick up the new definition and apply it to the table.

:::note[Dynamic packets]
Packets created at runtime with [Dynamic Packets](/docs/guides/dynamic-packets) do not go through startup reconciliation. Their topic is pushed to the already running `tsdb` microservice, so the table is created on the first write via the missing table recovery path described in [Recovering a Dropped Table](#recovering-a-dropped-table). Modifying an existing dynamic packet's items does not reconcile its table until the microservice restarts.
:::

For each packet, COSMOS builds the set of desired columns from the current definition, issues `SHOW COLUMNS` against the existing table, and then compares:

| Situation                             | Action                                  |
| ------------------------------------- | --------------------------------------- |
| Table does not exist                  | `CREATE TABLE`                          |
| Column missing                        | `ALTER TABLE ... ADD COLUMN`            |
| Column exists with a different type   | `ALTER TABLE ... ALTER COLUMN ... TYPE` |
| Column exists with the expected type  | Nothing                                 |
| Column exists but item no longer does | Nothing -- the column is left in place  |

A failure on one column is logged and reconciliation continues with the remaining columns, so a single problematic item does not block the rest of the packet. If any change was applied, COSMOS waits briefly for QuestDB to apply the (asynchronous) `ALTER` and reconnects the ILP ingest sender so it drops its cached schema.

## Adding an Item

A new item produces `ALTER TABLE ... ADD COLUMN`. Existing rows get `NULL` for the new column, and rows written from that point forward carry the value. Queries that span the change return `NULL` for the older rows.

Adding an item is the safest change and requires no manual action.

:::note[Adding items changes offsets]
Appending an item with `APPEND_ITEM` only adds a column. Inserting an item with `ITEM` at a bit offset that shifts other items changes the _meaning_ of the existing data in those columns -- the column type may be unchanged while the historical values now correspond to a different field. COSMOS cannot detect this.
:::

## Changing an Item's Type or Size

Changing `data_type` or `bit_size`, or adding/removing a conversion, changes the desired column type. COSMOS issues `ALTER TABLE ... ALTER COLUMN ... TYPE <new_type>` and QuestDB rewrites the existing data in place.

QuestDB converts existing values on a best-effort basis and **does not fail on unconvertible data** -- it writes `NULL` instead. Understand the conversion before you make the change:

| Change                                         | Effect on existing data                                                         |
| ---------------------------------------------- | ------------------------------------------------------------------------------- |
| Widening (`INT` → `FLOAT`, `int` → `long`)     | Preserved                                                                       |
| Numeric → string                               | Preserved as the string representation (`42` becomes `"42"`)                    |
| String → numeric                               | Numeric strings parse; non-numeric strings become `NULL` **(data loss)**        |
| Narrowing (`long` → `int`, `double` → `float`) | Values outside the target range become `NULL` or lose precision **(data loss)** |

Because a lossy `ALTER` is silent, take a [backup](/docs/guides/backups) before reinstalling a plugin that changes an item's type on a table holding data you care about.

:::warning[Type changes are not reversible]
`ALTER COLUMN TYPE` rewrites the column. Reverting the definition and reinstalling issues a second `ALTER` back to the original type, but any values that were NULLed or truncated by the first `ALTER` are gone. Restore from a backup instead.
:::

## Removing an Item

COSMOS never drops columns. If you remove an item from a packet definition, its column stays in the table with all its historical data and simply stops receiving new values. New rows have `NULL` for that column.

This is deliberate -- dropping the column would silently destroy historical data that is still valid for the time range in which the item existed. If you genuinely want the column gone, do it manually:

```sql
ALTER TABLE "DEFAULT__TLM__INST__HEALTH_STATUS" DROP COLUMN "OLD_ITEM";
```

**Warning:** This permanently deletes all historical values for that item. Take a backup first. Also remove the item from the packet definition and reinstall the plugin, otherwise the next reconciliation adds the column straight back.

Orphaned columns are harmless apart from a small amount of storage. Note that COSMOS tools driven by the [Streaming API](/docs/development/streaming-api) query by item name from the current definition, so a removed item disappears from the tools even though the column still exists.

## Renaming an Item

There is no rename path. A rename is seen as one item removed and one item added:

- The old column remains, holding all data written under the old name
- A new column is added, `NULL` for everything before the rename

Queries in COSMOS tools only see the new name, so historical data effectively becomes invisible even though it is still on disk. If you need continuity, migrate the data manually before or after reinstalling:

```sql
-- After the new column has been created by reconciliation
UPDATE "DEFAULT__TLM__INST__HEALTH_STATUS" SET "NEW_NAME" = "OLD_NAME" WHERE "NEW_NAME" IS NULL;
```

Prefer avoiding renames on packets with long-lived data.

## Name Sanitization

QuestDB rejects certain characters in table and column names, so COSMOS replaces them with an underscore:

- Table names: `? , ' " \ / : ) ( + * % ~`
- Column names: `? . , ' " \ / : ) ( + = - * % ~ ; ! @ # $ ^ &`

A warning is logged when a table name is changed this way. Two item names that differ only in sanitized characters (`A-B` and `A_B`) collapse to the same column, so avoid them. Item names are also limited to 127 characters because they are used as column names. See [Telemetry](/docs/configuration/telemetry) for the full naming rules.

## Recovering a Dropped Table

If a table is dropped out from under a running system, the next ILP write fails. COSMOS detects the "table does not exist" error, recreates the table from the current packet definition with the correct designated timestamp and partitioning, and replays the buffered rows. ILP auto-creation is deliberately disabled so QuestDB cannot create a schema-less table with the wrong timestamp column.

The recreated table only has the rows that were still buffered. Everything the dropped table held is gone unless you restore it from a [backup](/docs/guides/backups) or reingest it from the binary log files.

## Ingest-Time Type Mismatches

Reconciliation happens at startup, so a type mismatch during ingest means the incoming data does not match the definition (for example a conversion returning a string for an item declared as a float). COSMOS handles these at ingest rather than altering the schema:

- **Scalar mismatch** -- the value is cast to the column type. If it cannot be cast, the value is dropped and stored as `NULL`.
- **Array data into a scalar column** -- the value is serialized to a JSON string.

Either way a warning is logged naming the table, column, expected type, and received type, and COSMOS remembers the fix so subsequent rows are converted without another round-trip. Treat these warnings as a signal that a definition needs correcting -- the cast is a safety net, not a substitute for a correct definition.

## Backfilling and Reingest

Changing a definition does not retroactively change data already stored. To rebuild historical data under a new definition, reingest it from the raw binary packet logs, which are unaffected by definition changes and are always decommutated with whatever definition is current at reingest time.

COSMOS provides a [migration plugin](https://store.openc3.com/cosmos_plugins/21) that reads `.bin` and `.bin.gz` packet log files from bucket storage and batch-ingests the decommutated data into QuestDB. During reingest, `DEDUP` is enabled on the affected tables (`UPSERT KEYS(PACKET_TIMESECONDS)`) so replayed rows overwrite existing rows at the same timestamp rather than duplicating them, and disabled again once ingestion is complete.

This makes reingest the recommended recovery path after a lossy type change: fix the definition, reinstall the plugin so the schema reconciles, then reingest the affected time range.

## Retention Changes

[`TLM_DECOM_RETAIN_TIME`](/docs/configuration/plugins#tlm_decom_retain_time) and [`CMD_DECOM_RETAIN_TIME`](/docs/configuration/plugins#cmd_decom_retain_time) map to the QuestDB table TTL. TTL can only be declared at `CREATE TABLE` time, so COSMOS reads the current TTL on every reconciliation and issues `ALTER TABLE ... SET TTL` when it differs. Removing the keyword removes the TTL. Retention is applied as whole day partitions -- see [`TLM_DECOM_RETAIN_TIME`](/docs/configuration/plugins#tlm_decom_retain_time) for the rounding rules.

## Detached Partitions

Partitions detached for long-term archival keep the schema they had at detach time. If columns were added, removed, or retyped since then, reattaching may fail or attach only a subset of columns. See [Removing and Restoring Partitions](/docs/guides/backups#removing-and-restoring-partitions).

## Checklist

Before reinstalling a plugin that changes a packet on a system with data you care about:

1. Identify which changes are additions (safe) and which are type changes, removals, or renames (potentially lossy).
2. [Back up](/docs/guides/backups) QuestDB, or detach and archive the partitions for the affected time range.
3. Reinstall the plugin and check the `tsdb` microservice log for `Added column`, `Altered column type`, and any column reconciliation errors.
4. Spot-check a query spanning the change in [Data Extractor](/docs/tools/data-extractor) or [Telemetry Grapher](/docs/tools/tlm-grapher).
5. Reingest the affected time range if historical values were lost.
