-- BIG BROTHER Local Brain V5/V6 | Damage Exchange read-only verification
-- Does not create/change invoices, stock, cost, expenses, or functions.
-- Run ONLY as the approved controller SQL verification step after the migration.

WITH affected AS (
  SELECT x.exchange_item_id,x.product_code,x.exchange_qty,x.received_qty,
         x.unit_cost,x.exchange_value,
         CASE WHEN x.exchange_item_id=14 THEN 116.55
              WHEN x.exchange_item_id=16 THEN 20.70 END AS expected_value
  FROM public.stock_damage_exchange_items x
  WHERE x.exchange_item_id IN (14,16)
), summary AS (
 SELECT
   (SELECT count(*) FROM affected) AS exchange_items_present,
   (SELECT count(*) FROM affected WHERE unit_cost=.45
          AND exchange_value=expected_value AND exchange_qty=received_qty) AS exchange_items_correct,
   (SELECT count(*) FROM public.stock_activity a
     WHERE a.transaction_id IN (
       'TRX-007126','TRX-007128','TRX-007134','TRX-007136',
       'TRX-007166','TRX-007186','TRX-007188','TRX-007206','TRX-007208',
       'TRX-007266','TRX-007388','TRX-007394','TRX-007396','TRX-007400',
       'TRX-007762','TRX-007766','TRX-007768','TRX-007780')
     AND a.unit_cost=.45 AND a.line_value=round(a.qty*.45,2)) AS corrected_stock_rows,
   (SELECT coalesce(sum(a.line_value),0) FROM public.stock_activity a
     WHERE a.transaction_id IN ('TRX-007388','TRX-007394','TRX-007396')
       AND a.movement_type='BATCH_SALE') AS corrected_sales_cogs,
   (SELECT count(*) FROM public.stock_activity a
      WHERE a.product_code IN ('CHM-220','CH-O220')
        AND a.created_at>='2026-10-31 06:55:00+00'::timestamptz
        AND coalesce(a.unit_cost,0)<=0
        AND (a.from_bucket IN ('WAREHOUSE_GOOD','BATCH_PENDING')
          OR a.to_bucket IN ('WAREHOUSE_GOOD','BATCH_PENDING'))) AS other_zero_cost_purchased_movements,
   (SELECT count(*) FROM public.stock_damage_inventory_writeoffs w
     WHERE w.clearance_transaction_id IN ('TRX-007126','TRX-007128')) AS duplicate_writeoff_entries,
   (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
     WHERE ns.nspname='public' AND p.proname='bb_stock_receive_damage_exchange'
       AND position('BB_DAMAGE_EXCHANGE_DOCUMENTED_COST_20261103'
            IN pg_get_functiondef(p.oid))>0
       AND position('BB_DAMAGE_EXCHANGE_HEADER_VALUE_20261103'
            IN pg_get_functiondef(p.oid))>0) AS future_receive_guards_installed
)
SELECT *,
 CASE WHEN exchange_items_present=2 AND exchange_items_correct=2
       AND corrected_stock_rows=18 AND corrected_sales_cogs=7.65
       AND other_zero_cost_purchased_movements=0
       AND duplicate_writeoff_entries=0
       AND future_receive_guards_installed=1
      THEN 'PASS' ELSE 'BLOCK' END AS local_damage_exchange_valuation_status
FROM summary;

SELECT p.product_code,p.product_name,p.warehouse_good,p.batch_pending,
       p.warehouse_zero_cost,p.batch_zero_cost,p.average_cost,
       p.warehouse_value,p.total_value
FROM public.bb_stock_product_rows_zero_cost_v1_internal() p
WHERE p.product_code IN ('CHM-220','CH-O220')
ORDER BY p.product_code;

SELECT a.product_code,a.activity_date,a.movement_type,
       a.reference_no,a.qty,a.unit_cost,a.line_value,a.from_bucket,a.to_bucket
FROM public.stock_activity a
WHERE a.transaction_id IN ('TRX-007388','TRX-007394','TRX-007396')
ORDER BY a.product_code,a.transaction_id;

SELECT action,entity_type,count(*) AS audited_before_images
FROM public.system_activity_log
WHERE metadata->>'migrationId'='BB_DAMAGE_EXCHANGE_COST_20261103'
GROUP BY action,entity_type
ORDER BY entity_type;
