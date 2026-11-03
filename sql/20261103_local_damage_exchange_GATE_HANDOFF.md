# BIG BROTHER V3.4 Local Brain V5/V6 - Damage Exchange Cost / COGS

**State:** PREPARED; NOT APPLIED TO LOCAL BRAIN; CONTROLLER REGISTRATION PENDING.

**Migration ID:** `20261103_local_damage_exchange_source_cogs_v1`

**Migration (single atomic transaction):** [20261103_local_damage_exchange_source_cogs_v1.sql](./20261103_local_damage_exchange_source_cogs_v1.sql)

**Migration SHA-256 (UTF-8):** `d09f0c632bc46fe98025be35e41f0e4fe88b951cb71205813487118458cddf6e`

**Read-only verifier:** [20261103_local_damage_exchange_read_only_verify.sql](./20261103_local_damage_exchange_read_only_verify.sql)

**Verifier SHA-256:** `0a105a893380a571fa1fed8b3ee2b4c6510d303f8064e6c24447e96d97657266`

## Accounting and compatibility rules

- Future damaged-stock exchanges must inherit the documented *original purchased stock* unit cost from `stock_damage_clear_allocations` + `stock_activity`, not the current available-stock average if it is zero. If the documented cost is unavailable, **block receiving** rather than silently recognizing purchased inventory at $0.
- The same received cost updates the exchange-summary `unit_cost` and `exchange_value`, including partial receipt workflows.
- The targeted past Champei Melon (CHM-220) and Original (CH-O220) corrections use their actual damaged-stock transaction costs ($0.45). No new stock, invoices, purchases or expenses are created.
- On pre-correction Local data, correct exactly two exchange summary records plus 18 ledger movements (2 clearances, 2 receipts, 14 downstream movements), recording each full original row in `system_activity_log` first.
- If the same rows are **already corrected** because Cloud -> Local merged them, do not duplicate the cost corrections or audit rows. Still install/check both future safeguards.
- If source IDs, cost evidence, movement counts, other purchased-stock zero-cost movements, or DB schema are inconsistent, abort and roll back the entire transaction. Do not fabricate costs or merge unrelated data.
- Do not alter any quantity, batch, warehouse bucket, zero-cost protected bucket, invoice, COGS row identity, paid expense, or staff earning.
- For the 17 affected historical sold units, purchased-stock COGS is $7.65. Remaining 288 units represent $129.60 at the documented $0.45 original purchase cost (when Local data matches Cloud).

## Approved V3.4 deployment sequence

1. **This is NOT yet integrated into the installed Control Center.** The controller ZIP file could not be accessed as editable bytes from the current Project/Library surface; therefore the Approved SQL Gate manifest was not modified.
2. In the actual V3.4 Controller, register the exact migration ID/path and above SHA-256 under the allowlisted `V34-LOCAL-APPROVED-SQL-CODE-GATE.ps1` used by **Code Sync**. Keep the existing preflight, schema guards, permission checks and local backup. Do not add raw SQL execution to Cloud -> Local business-data merge.
3. Code Sync should verify exact file checksum, existing Local function definitions, migration status and backup. It must run an isolated transactional rehearsal (ROLLBACK) and only then commit the verified migration. If it detects drift, **STOP** instead of adapting SQL unreviewed.
4. After a verified migration, run the read-only verification file and require `local_damage_exchange_valuation_status = PASS`. Confirm Stock Adjustment shows Champei Melon purchased warehouse qty independently of batch qty and current average cost $0.45.
5. V5/8081 and V6/8083 share the same local DB functions; keep their separate Start buttons.

## Cloud verification / proof

Cloud migration V1 [original documented cost + historical fix](./20261103_damage_exchange_original_cost_and_cogs_v1.sql) was applied and checked. Cloud migration V2 [exchange-header value continuity](./20261103_damage_exchange_receipt_header_value_v2.sql) is also applied and verified. The Local combined SQL was tested against the current Cloud database using a full transaction ending in ROLLBACK; its already-corrected replay path succeeded. The uncorrected historical path is based on the V1 correction that previously passed rollback rehearsal and was then committed to Cloud. This does **not** constitute a live Local installation test.

## Other staged fix still pending

The earlier Direct Sale warehouse source patch is separate:
[`big-brother-invoice-generator/sql/20261103_direct_sale_warehouse_source_local_v1.sql`](https://github.com/angsokhey11-cloud/big-brother-invoice-generator/blob/main/sql/20261103_direct_sale_warehouse_source_local_v1.sql).
Do not assume either fix is present on Local Brain merely because GitHub Code Sync downloads frontend files. They need individually approved database code migrations.
