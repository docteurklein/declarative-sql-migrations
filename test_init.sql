\set ON_ERROR_STOP on

\i diff.sql

drop schema if exists pgdiff_test cascade;
create schema pgdiff_test;
set search_path to pgdiff_test, pgdiff;

