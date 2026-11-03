-- BIG BROTHER | DAMAGE EXCHANGE PURCHASED COST CORRECTION | 03-Nov-2026
-- Cloud migration: vetted source transaction provenance; does NOT create stock, expenses or invoices.
-- Existing batch/warehouse quantities, purchase and sale amounts are unchanged.
-- Before-images: public.system_activity_log, migrationId=BB_DAMAGE_EXCHANGE_COST_20261103
BEGIN;
SET LOCAL lock_timeout='8s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtext('BB_STOCK_WRITE'));

DO $patch_future_exchange$
DECLARE
  original text;
  revised text;
  start_at integer;
  end_at integer;
  target text:='bb_stock_receive_damage_exchange';
  insert_cost text:=$cost$
    -- BB_DAMAGE_EXCHANGE_DOCUMENTED_COST_20261103: the original damaged purchased
    -- stock determines the replacement's carried inventory cost, not current AVG.
    SELECT CASE
      WHEN count(*)>0 AND
           abs(coalesce(sum(a.allocated_qty),0)-v_exchange.exchange_qty)<=0.000001
      THEN round(sum(a.allocated_qty*d.unit_cost)/
                 nullif(sum(a.allocated_qty),0),6)
      ELSE NULL END
      INTO v_documented_damage_cost
    FROM public.stock_damage_clear_allocations a
    JOIN public.stock_activity d ON d.transaction_id=a.damage_transaction_id
    WHERE a.clear_transaction_id=v_exchange.clearance_transaction_id
      AND a.product_code=v_exchange.product_code
      AND d.product_code=v_exchange.product_code
      AND coalesce(d.unit_cost,0)>=0;

    IF coalesce(v_documented_damage_cost,0)>0 THEN
      v_received_unit_cost:=v_documented_damage_cost;
    ELSIF coalesce(v_exchange.unit_cost,0)>0 THEN
      v_received_unit_cost:=v_exchange.unit_cost;
    ELSE
      RAISE EXCEPTION 'Damage Exchange %: original damaged purchased cost unavailable or zero; review stock source before receiving',
        v_exchange.exchange_item_id;
    END IF;

$cost$;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO STRICT original
  FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
  WHERE n.nspname='public' AND p.proname=target;
  IF position('BB_DAMAGE_EXCHANGE_DOCUMENTED_COST_20261103' IN original)>0 THEN
    RAISE NOTICE 'Damage exchange future-cost protection already installed';
    RETURN;
  END IF;
  IF position('v_received_unit_cost numeric;' IN original)=0 THEN
    RAISE EXCEPTION 'Damage Exchange receive function declaration changed; abort';
  END IF;
  start_at:=position('    v_received_unit_cost :=' IN original);
  IF start_at=0 THEN RAISE EXCEPTION 'Damage exchange current cost calculation missing'; END IF;
  end_at:=position('    v_line_value :=' IN original);
  IF end_at<=start_at THEN RAISE EXCEPTION 'Damage exchange cost calculation boundary changed'; END IF;
  IF position('public.bb_stock_average_cost_internal(' IN substring(original FROM start_at FOR end_at-start_at))=0 OR
     position('v_exchange.unit_cost' IN substring(original FROM start_at FOR end_at-start_at))=0 THEN
    RAISE EXCEPTION 'Unexpected current damage exchange cost strategy';
  END IF;
  revised:=substring(original FROM 1 FOR start_at-1)
           || insert_cost
           || substring(original FROM end_at);
  revised:=replace(revised,'v_received_unit_cost numeric;',
            E'v_received_unit_cost numeric;\n  v_documented_damage_cost numeric;');
  EXECUTE revised;
  RAISE NOTICE 'Damage exchange receiver now requires documented source cost';
END
$patch_future_exchange$;

CREATE TEMP TABLE bb_damage_exchange_cost_repair_20261103 ON COMMIT DROP AS
SELECT x.exchange_item_id,x.product_code,x.clearance_transaction_id,
       x.exchange_qty,x.received_qty,
       count(a.allocation_id) allocation_rows,
       coalesce(sum(a.allocated_qty),0) allocated_qty,
       round(coalesce(sum(a.allocated_qty*d.unit_cost),0),2) source_value,
       round(coalesce(sum(a.allocated_qty*d.unit_cost),0)/
         nullif(sum(a.allocated_qty),0),6) documented_cost
FROM public.stock_damage_exchange_items x
LEFT JOIN public.stock_damage_clear_allocations a ON a.clear_transaction_id=x.clearance_transaction_id
LEFT JOIN public.stock_activity d ON d.transaction_id=a.damage_transaction_id
WHERE x.exchange_item_id IN (14,16)
GROUP BY x.exchange_item_id,x.product_code,x.clearance_transaction_id,x.exchange_qty,x.received_qty;

DO $validate_cost_repair$
DECLARE
  checks bigint;
  downstream_count bigint;
BEGIN
  SELECT count(*) INTO checks FROM bb_damage_exchange_cost_repair_20261103 r
  JOIN public.stock_damage_exchange_items x ON x.exchange_item_id=r.exchange_item_id
  JOIN public.stock_activity clearance ON clearance.transaction_id=r.clearance_transaction_id
  JOIN public.stock_activity receipt ON receipt.source_id=r.exchange_item_id::text
        AND receipt.movement_type='DAMAGE_EXCHANGE_RECEIVE'
        AND receipt.product_code=r.product_code
  WHERE x.status='COMPLETED' AND x.exchange_qty=x.received_qty
    AND x.unit_cost=0 AND x.exchange_value=0
    AND r.exchange_qty=r.allocated_qty AND r.allocation_rows>0
    AND r.documented_cost=0.45 AND r.documented_cost>0
    AND receipt.qty=x.received_qty AND receipt.unit_cost=0 AND receipt.line_value=0
    AND clearance.movement_type='DAMAGE_CLEAR'
    AND clearance.damage_clearance_type='EXCHANGE_FOR_GOOD_PRODUCTS'
    AND clearance.unit_cost=0 AND clearance.line_value=0
    AND NOT EXISTS(SELECT 1 FROM public.stock_damage_inventory_writeoffs w WHERE w.clearance_transaction_id=x.clearance_transaction_id);
  IF checks<>2 THEN RAISE EXCEPTION 'Exchange source/expense provenance mismatched: % of 2',checks; END IF;
  IF (SELECT sum(source_value) FROM bb_damage_exchange_cost_repair_20261103)<>137.25 THEN
    RAISE EXCEPTION 'Original exchange values no longer match $137.25';
  END IF;
  SELECT count(*) INTO downstream_count FROM public.stock_activity a
  WHERE a.transaction_id=ANY(ARRAY[
   'TRX-007166','TRX-007186','TRX-007188','TRX-007206','TRX-007208',
   'TRX-007266','TRX-007388','TRX-007394','TRX-007396','TRX-007400',
   'TRX-007762','TRX-007766','TRX-007768','TRX-007780'])
   AND a.product_code IN ('CHM-220','CH-O220')
   AND a.unit_cost=0 AND a.line_value=0 AND a.qty>0
   AND (a.from_bucket IN ('WAREHOUSE_GOOD','BATCH_PENDING')
        OR a.to_bucket IN ('WAREHOUSE_GOOD','BATCH_PENDING'))
   AND a.movement_type IN ('BATCH_STOCK','BATCH_TRANSFER','BACK_SALE','BATCH_SALE','BATCH_EDIT');
  IF downstream_count<>14 THEN
    RAISE EXCEPTION 'Downstream affected movement set drifted: % of 14',downstream_count;
  END IF;
  IF (SELECT coalesce(sum(a.qty),0) FROM public.stock_activity a
       WHERE a.transaction_id IN ('TRX-007388','TRX-007394','TRX-007396')
         AND a.movement_type='BATCH_SALE' AND a.unit_cost=0)<>17
  THEN RAISE EXCEPTION 'Affected sold quantity changed'; END IF;
END
$validate_cost_repair$;

-- Full before images of both exchange records.
INSERT INTO public.system_activity_log(actor_name,module_key,action,entity_type,entity_id,summary,metadata)
SELECT 'BIG BROTHER Accounting Correction','Stock Management',
       'DAMAGE_EXCHANGE_COST_CORRECTION_20261103','stock_damage_exchange_items',
       x.exchange_item_id::text,'Restore original purchased cost: supplier damage exchange',
       jsonb_build_object('migrationId','BB_DAMAGE_EXCHANGE_COST_20261103',
                          'original',to_jsonb(x),'documentedUnitCost',r.documented_cost,
                          'documentedValue',r.source_value)
FROM public.stock_damage_exchange_items x
JOIN bb_damage_exchange_cost_repair_20261103 r ON r.exchange_item_id=x.exchange_item_id;

-- Full before-images for all 18 stock activity movements (2 clearance, 2 receipt, 14 downstream).
INSERT INTO public.system_activity_log(actor_name,module_key,action,entity_type,entity_id,summary,metadata)
SELECT 'BIG BROTHER Accounting Correction','Stock Management',
       'DAMAGE_EXCHANGE_COST_CORRECTION_20261103','stock_activity',
       a.transaction_id,'Restore original purchased cost: exchange and linked stock flows',
       jsonb_build_object('migrationId','BB_DAMAGE_EXCHANGE_COST_20261103',
                          'original',to_jsonb(a),'documentedUnitCost',r.documented_cost)
FROM public.stock_activity a
JOIN bb_damage_exchange_cost_repair_20261103 r
  ON r.product_code=a.product_code
WHERE a.transaction_id=ANY(ARRAY[
 'TRX-007126','TRX-007128','TRX-007134','TRX-007136',
 'TRX-007166','TRX-007186','TRX-007188','TRX-007206','TRX-007208',
 'TRX-007266','TRX-007388','TRX-007394','TRX-007396','TRX-007400',
 'TRX-007762','TRX-007766','TRX-007768','TRX-007780']);

DO $repair_champei_exchange$
DECLARE n bigint;
BEGIN
  SELECT count(*) INTO n FROM public.system_activity_log
  WHERE action='DAMAGE_EXCHANGE_COST_CORRECTION_20261103'
    AND metadata->>'migrationId'='BB_DAMAGE_EXCHANGE_COST_20261103';
  IF n<>20 THEN RAISE EXCEPTION 'Incorrect audit before-image count: %',n; END IF;

  UPDATE public.stock_damage_exchange_items x
    SET unit_cost=r.documented_cost,
        exchange_value=r.source_value,
        updated_at=now()
  FROM bb_damage_exchange_cost_repair_20261103 r
  WHERE x.exchange_item_id=r.exchange_item_id;
  GET DIAGNOSTICS n=ROW_COUNT;
  IF n<>2 THEN RAISE EXCEPTION 'Exchange update count: %',n; END IF;

  UPDATE public.stock_activity a
    SET unit_cost=r.documented_cost,
        line_value=round(a.qty*r.documented_cost,2),
        updated_at=now()
  FROM bb_damage_exchange_cost_repair_20261103 r
  WHERE a.product_code=r.product_code
    AND a.transaction_id IN (
        'TRX-007126','TRX-007128','TRX-007134','TRX-007136',
        'TRX-007166','TRX-007186','TRX-007188','TRX-007206','TRX-007208',
        'TRX-007266','TRX-007388','TRX-007394','TRX-007396','TRX-007400',
        'TRX-007762','TRX-007766','TRX-007768','TRX-007780')
    AND a.unit_cost=0 AND a.line_value=0;
  GET DIAGNOSTICS n=ROW_COUNT;
  IF n<>18 THEN RAISE EXCEPTION 'Stock cost update count: % of 18',n; END IF;

  IF abs(public.bb_stock_average_cost_internal('CHM-220')-0.45)>0.000001 OR
     abs(public.bb_stock_average_cost_internal('CH-O220')-0.45)>0.000001 THEN
    RAISE EXCEPTION 'Recomputed average cost did not restore $0.45';
  END IF;
  IF (SELECT coalesce(sum(line_value),0) FROM public.stock_activity
      WHERE transaction_id IN ('TRX-007388','TRX-007394','TRX-007396'))<>7.65 THEN
    RAISE EXCEPTION 'Corrected affected sale COGS did not total $7.65';
  END IF;
  IF (SELECT coalesce(sum(warehouse_good+batch_pending),0)
      FROM public.bb_stock_product_rows_zero_cost_v1_internal()
      WHERE product_code IN ('CHM-220','CH-O220'))<>288 THEN
    RAISE EXCEPTION 'Current purchased good inventory quantity changed unexpectedly';
  END IF;
  PERFORM public.bb_stock_touch_revision_internal();
  RAISE NOTICE 'PASS: 2 exchanges, 18 ledger movements repriced; inventory quantities unchanged';
END
$repair_champei_exchange$;
COMMIT;
