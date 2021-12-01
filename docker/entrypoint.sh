set -exuo pipefail

mkdir -p /etc/pam.d
if [[ ! -f /etc/passwd ]]; then
  echo "root:x:0:0::/root:/bin/bash" > /etc/passwd
  echo "root:!x:::::::" > /etc/shadow
fi
if [[ ! -f /etc/group ]]; then
  echo "root:x:0:" > /etc/group
  echo "root:x::" > /etc/gshadow
fi
if [[ ! -f /etc/pam.d/other ]]; then
  cat > /etc/pam.d/other <<EOF
account sufficient pam_unix.so
auth sufficient pam_rootok.so
password requisite pam_unix.so nullok sha512
session required pam_unix.so
EOF
fi
if [[ ! -f /etc/login.defs ]]; then
  touch /etc/login.defs
fi
echo 'ALL ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/all.conf

cp /share/postgresql/extension/plpgsql_check* "$(pg_config --sharedir)/extension/" -v
cp /lib/plpgsql_check.so "$(pg_config --pkglibdir)/" -v

useradd -m app

mkdir -p "$PGDATA" /run/postgresql
chown -R app:app "$PGDATA" /run/postgresql

[ ! -d "$PGDATA" ] && sudo -E -u app pg_ctl initdb && sudo -E -u app createdb

sudo -E -u app pg_ctl -w start

exec "$@"
