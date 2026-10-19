-- Include application tasks when present, while keeping old standalone labs valid.
CREATE OR REPLACE FUNCTION pg_temp.app_tasks_snapshot() RETURNS text LANGUAGE plpgsql AS $$
DECLARE snapshot text;
BEGIN
    IF to_regclass('public.app_tasks') IS NULL THEN RETURN ''; END IF;
    EXECUTE 'SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY id)::text, ''[]'') FROM public.app_tasks t' INTO snapshot;
    RETURN snapshot;
END $$;
SELECT 'ROWS=' || count(*) FROM public.demo_items;
SELECT 'DATA=' || md5(coalesce(string_agg(id::text || '|' || name || '|' || quantity::text, E'\n' ORDER BY id), '') || E'\nAPP_TASKS=' || pg_temp.app_tasks_snapshot()) FROM public.demo_items;
SELECT 'SCHEMA=' || md5(string_agg(definition, E'\n' ORDER BY definition))
FROM (
    SELECT table_schema || '.' || table_name || ':' || ordinal_position::text || ':' ||
           column_name || ':' || data_type || ':' || is_nullable || ':' || coalesce(column_default, '') AS definition
    FROM information_schema.columns
    WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
    UNION ALL
    SELECT n.nspname || '.' || t.relname || ':' || c.conname || ':' || pg_get_constraintdef(c.oid)
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
    UNION ALL
    SELECT schemaname || '.' || tablename || ':' || indexname || ':' || indexdef
    FROM pg_indexes WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
) definitions;
