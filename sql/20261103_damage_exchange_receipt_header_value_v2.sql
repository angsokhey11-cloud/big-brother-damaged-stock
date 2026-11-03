-- BIG BROTHER Cloud | Damage Exchange Cost Continuity V2 | 03-Nov-2026
-- Synchronize Exchange item header valuation with the documented stock receipt cost.
-- Applies to future receives; historical 2 Champei exchanges were already corrected by V1.
-- Idempotent and fail-closed; does not change existing stock, amounts or invoices.
BEGIN;
SET LOCAL lock_timeout='8s';
SET LOCAL statement_timeout='120s';
DO $bb_damage_exchange_header$
DECLARE
 v_definition text;
 v_updated text;
 v_needle text := '      received_qty =';
 v_added text := E'      /* BB_DAMAGE_EXCHANGE_HEADER_VALUE_20261103 */\n      unit_cost = v_received_unit_cost,\n      exchange_value = round(v_exchange.exchange_qty * v_received_unit_cost, 2),\n\n      received_qty =';
 v_hits integer;
BEGIN
 SELECT pg_get_functiondef(p.oid) INTO STRICT v_definition
 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
 WHERE n.nspname='public' AND p.proname='bb_stock_receive_damage_exchange';

 IF position('BB_DAMAGE_EXCHANGE_HEADER_VALUE_20261103' IN v_definition)>0 THEN
   RAISE NOTICE 'Damage Exchange header valuation already matches future received cost';
   RETURN;
 END IF;
 IF position('BB_DAMAGE_EXCHANGE_DOCUMENTED_COST_20261103' IN v_definition)=0 THEN
   RAISE EXCEPTION 'Requires the documented original damaged-stock cost guard (V1)';
 END IF;
 v_hits:=(length(v_definition)-length(replace(v_definition,v_needle,'')))/length(v_needle);
 IF v_hits<>1 OR position('v_exchange.exchange_qty' IN v_definition)=0 THEN
   RAISE EXCEPTION 'Damage Exchange UPDATE statement drifted (% matching anchors)',v_hits;
 END IF;
 v_updated:=replace(v_definition,v_needle,v_added);
 EXECUTE v_updated;
 IF NOT EXISTS(
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
    WHERE n.nspname='public' AND p.proname='bb_stock_receive_damage_exchange'
      AND position('BB_DAMAGE_EXCHANGE_HEADER_VALUE_20261103' IN pg_get_functiondef(p.oid))>0
 ) THEN
   RAISE EXCEPTION 'Header cost continuity patch not installed';
 END IF;
 RAISE NOTICE 'Future Damage Exchange items record documented received unit cost and full exchange value';
END
$bb_damage_exchange_header$;
COMMIT;
