\set ON_ERROR_STOP on

set search_path to pgdiff;

\i diff.sql
\i src/throws.sql
