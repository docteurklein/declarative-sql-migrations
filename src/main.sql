begin;

drop schema if exists pgdiff cascade;
create schema pgdiff;

\i src/types.sql
\i src/alterations.sql
\i src/exec.sql
\i src/migrate.sql
\i src/query.sql

commit;
