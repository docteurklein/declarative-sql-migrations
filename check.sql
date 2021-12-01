\pset pager off
\x

select
    (pcf).functionid::regprocedure, (pcf).lineno, (pcf).statement,
    (pcf).sqlstate, (pcf).message, (pcf).detail, (pcf).hint, (pcf).level,
    (pcf)."position", (pcf).query, (pcf).context
from
(
    select
        plpgsql_check_function_tb(pg_proc.oid, coalesce(pg_trigger.tgrelid, 0)) as pcf
    from pg_proc
    left join pg_trigger
        on (pg_trigger.tgfoid = pg_proc.oid)
    where
        prolang = (select lang.oid from pg_language lang where lang.lanname = 'plpgsql') and
        pronamespace <> (select nsp.oid from pg_namespace nsp where nsp.nspname = 'pg_catalog') and
        -- ignore unused triggers
        (pg_proc.prorettype <> (select typ.oid from pg_type typ where typ.typname = 'trigger') or
         pg_trigger.tgfoid is not null)
    offset 0
) ss
order by (pcf).functionid::regprocedure::text, (pcf).lineno
