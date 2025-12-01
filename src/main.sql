\set ON_ERROR_STOP on

begin;

drop schema if exists pgdiff cascade;
create schema pgdiff;

\ir types.sql
\ir alterations/columns.sql
\ir alterations/constraints.sql
\ir alterations/domains.sql
\ir alterations/routines.sql
\ir alterations/tables.sql
\ir alterations/types.sql
\ir alterations/indices.sql
\ir alterations.sql
\ir exec.sql
\ir migrate.sql
\ir query.sql

commit;
