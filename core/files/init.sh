#!/bin/bash
set -uo pipefail

# Fixes ownership of misp-core's bind-mounted host directories before
# misp-core itself starts. misp-core runs as a fixed non-root user (33:0)
# from process 1 and can no longer chown these on its own on first start -
# see entrypoint.sh's nss_wrapper comment for the same underlying
# constraint. This runs as root, once, via docker-compose.yml's
# misp-core-init service (entrypoint override + user: "0:0"), which
# misp-core depends on via condition: service_completed_successfully.
#
# Only misp-core's own bind mounts are listed here. misp-nginx's ./ssl
# mount is read-only (nginx never writes to it) and needs no ownership
# fix - see the "Certificates" section of README.md for its own
# (read-permission, not ownership) constraint instead.
TARGETS=(
    /var/www/MISP/app/Config
    /var/www/MISP/app/tmp/logs
    /var/www/MISP/app/files
    /var/www/MISP/.gnupg
)

for path in "${TARGETS[@]}"; do
    if [ ! -d "$path" ]; then
        echo "init: $path is not mounted, skipping"
        continue
    fi

    owner="$(stat -c '%u:%g' "$path")"
    if [ "$owner" = "33:0" ]; then
        echo "init: $path already owned by 33:0, skipping"
        continue
    fi

    echo "init: fixing ownership of $path (was $owner)"
    chown -R 33:0 "$path" || echo "init: chown on $path failed (continuing best-effort - e.g. Docker Desktop bind mounts don't support arbitrary chown)"
    chmod -R g+rwX "$path" || echo "init: chmod on $path failed (continuing best-effort)"
done

# Best-effort: a failed chown/chmod above is logged but never fails this
# script, since misp-core depends on it via service_completed_successfully
# and a hard failure here would block the whole stack from starting even
# when misp-core could still work fine (e.g. Docker Desktop bind mounts
# that are already group-writable without needing a real chown).
exit 0
