#!/usr/bin/env bash
# Offline test runner for kitodo-presentation (unit + functional suites).
#
# Run this with the machine's network DISABLED to prove that the test suites
# need no external connection. It requires the already-installed vendor/
# directory and the Docker images used by docker-compose.yml (no pulls, no
# composer).
#
# It:
#   1. records whether the network is actually reachable,
#   2. runs the unit suite (no other containers needed),
#   3. starts web/solr/mariadb, waits for them, runs the functional suite,
#   4. tears everything down.
#
# When docker is provided by podman (e.g. on macOS), two temporary local
# workarounds are applied to Build/Test/docker-compose.yml (podman cannot
# resolve 'host-gateway' and does not support 'links:'); the file is restored
# afterwards in all cases. Real Docker does not need them.
#
# Usage:
#   Build/Test/runOfflineTests.sh                 # PHP 8.4 (default)
#   PHP_VERSION=8.2 Build/Test/runOfflineTests.sh # PHP 8.2
#   PHP_VERSION=8.5 Build/Test/runOfflineTests.sh # PHP 8.5
#
# The full output is written to a temporary log file; its location is printed
# at the end. The exit code is 0 only if both suites passed.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
CT="$SCRIPT_DIR"
COMPOSE="$CT/docker-compose.yml"
PHP_VERSION="${PHP_VERSION:-8.4}"
case "$PHP_VERSION" in
    8.2|8.4|8.5) ;;
    *) echo "PHP_VERSION must be 8.2, 8.4 or 8.5" >&2; exit 1 ;;
esac
# Same transformation as runTests.sh: "8.4" -> "php84"
DOCKER_PHP_IMAGE="php${PHP_VERSION//./}"

WORK="$(mktemp -d)"
BACKUP="$WORK/compose.bak"
LOG="$WORK/offline-tests.log"
KEEPLOG="${TMPDIR:-/tmp}/offline-tests.log"
cp "$COMPOSE" "$BACKUP"
restore() {
    cp "$BACKUP" "$COMPOSE"
    docker compose -p dlf_testing down --remove-orphans --timeout 5 >/dev/null 2>&1 || true
    rm -f "$CT/.env"
    cp "$LOG" "$KEEPLOG" 2>/dev/null || true
    rm -rf "$WORK"
}
trap restore EXIT

# --- temporary podman workarounds (see header) ---
if docker version 2>/dev/null | grep -q "Podman Engine"; then
    python3 - "$COMPOSE" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace("host.docker.internal:host-gateway", "host.docker.internal:127.0.0.1")
s = s.replace("""    links:
      - ${DBMS}
      - web
      - solr
""", "")
open(p, "w").write(s)
PY
fi

# .env normally written by runTests.sh; create it ourselves
{
    echo "COMPOSE_PROJECT_NAME=dlf_testing"
    echo "HOST_UID=$(id -u)"
    echo "HOST_GID=$(id -g)"
    echo "DLF_ROOT=$REPO"
    echo "HOST_USER=${USER:-$(whoami)}"
    echo "TYPO3_VERSION="
    echo "TEST_FILE="
    echo "PHP_XDEBUG_ON=0"
    echo "PHP_XDEBUG_PORT=9003"
    echo "SERVER_PORT=8000"
    echo "DOCKER_PHP_IMAGE=$DOCKER_PHP_IMAGE"
    echo "EXTRA_TEST_OPTIONS="
    echo "SCRIPT_VERBOSE=0"
    echo "PHPUNIT_WATCH=0"
    echo "DBMS=mariadb"
    echo "DATABASE_DRIVER=mysqli"
    echo "MARIADB_VERSION=10.3"
    echo "MYSQL_VERSION=8.0"
    echo "PHP_VERSION=$PHP_VERSION"
} > "$CT/.env"

# Print to both the console and the log.
log() {
    echo "$@" | tee -a "$LOG"
}

run_suite() {
    local name="$1"; shift
    log "--- running ${name} ---"
    docker compose run "$@" 2>&1 | tee -a "$LOG"
    # with pipefail, this is docker compose's exit code
    local rc=${PIPESTATUS[0]}
    log "--- ${name} finished with exit code: ${rc} ---"
    return "$rc"
}

cd "$CT" || exit 1

{
    echo "=== Offline test run (unit + functional): $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
    if ping -c 2 -t 2 1.1.1.1 >/dev/null 2>&1 || ping -c 2 -W 2 1.1.1.1 >/dev/null 2>&1; then
        echo "NETWORK CHECK: 1.1.1.1 reachable - the machine still HAS network (run again with network off!)"
    else
        echo "NETWORK CHECK: 1.1.1.1 unreachable - machine is offline (good)"
    fi
} | tee -a "$LOG"

run_suite "unit suite (PHP $PHP_VERSION)" unit
RC_UNIT=$?

log "--- starting web/solr/mariadb ---"
docker compose up -d web solr mariadb 2>&1 | tee -a "$LOG"
log "--- waiting for dependencies ---"
DEPS_UP=0
for i in $(seq 1 60); do
    if docker exec dlf_testing-web-1 sh -c 'nc -z solr 8983 && nc -z mariadb 3306' >/dev/null 2>&1; then
        log "dependencies up after ${i} polls"
        DEPS_UP=1
        break
    fi
    sleep 5
done
if [ "$DEPS_UP" -ne 1 ]; then
    log "TIMEOUT waiting for dependencies"
    RC_FUNC=1
    log "=== offline run finished: unit=${RC_UNIT} functional=${RC_FUNC} (dependency timeout) ==="
    exit 1
fi

run_suite "functional suite (PHP $PHP_VERSION, mariadb)" functional
RC_FUNC=$?

log "=== offline run finished: unit=${RC_UNIT} functional=${RC_FUNC} ==="
log "unit:       exit ${RC_UNIT}"
log "functional: exit ${RC_FUNC}"
log "log: ${KEEPLOG}"

[ "$RC_UNIT" -ne 0 ] && exit "$RC_UNIT"
exit "$RC_FUNC"
