begin;

create schema if not exists pgdiff;

\i src/types.sql
\i src/alterations.sql
\i src/exec.sql
\i src/migrate.sql
\i src/query.sql
\i src/webhook.sql

commit;
