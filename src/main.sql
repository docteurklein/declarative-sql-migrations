\set ON_ERROR_STOP on

begin;

drop schema if exists pgdiff cascade;
create schema pgdiff;

\i src/types.sql
\i src/alterations/columns.sql
\i src/alterations/constraints.sql
\i src/alterations/domains.sql
\i src/alterations/routines.sql
\i src/alterations/tables.sql
\i src/alterations/types.sql
\i src/alterations/indices.sql
\i src/alterations.sql
\i src/exec.sql
\i src/migrate.sql
\i src/query.sql

commit;
