begin;

create schema if not exists pgdiff;

set local search_path to pgdiff;

\i src/types.sql
\i src/alterations.sql
\i src/exec.sql
\i src/migrate.sql

commit;
