\set ON_ERROR_STOP on

\i diff.sql

drop extension if exists dblink;
create extension dblink;

drop schema if exists target cascade;
drop schema if exists desired cascade;

set search_path to pgdiff;

