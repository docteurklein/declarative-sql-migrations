\set ON_ERROR_STOP on

\i diff.sql

drop extension if exists dblink;
create extension dblink;

drop schema if exists test_target cascade;
drop schema if exists test_desired cascade;

set search_path to pgdiff;

