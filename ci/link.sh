#!/bin/sh
#
# Drive the link_func module against a running nginx with a real HTTP
# client.  The module loads a user C library at run time and dispatches
# requests to functions in it; this compiles the bundled sample library
# (build_test_resources/linkfuntest.c) against the module header, loads it
# with ngx_link_func_lib and checks that a call reaches the function, that
# the response it writes comes back, and that the request query string is
# handed through.  This is also what the FreeBSD job, the sanitizer job and
# the valgrind job run.
#
# usage: ci/link.sh <nginx binary>
#
# Set LINK_LOAD_MODULE to the path of ngx_http_link_func_module.so to test a
# loadable build.  Set LINK_VALGRIND=1 to run one foreground nginx under
# valgrind and fail on any memory finding.

set -eu

NGINX=${1:?path to the nginx binary missing}
SRC=$(cd "$(dirname "$0")/.." && pwd)
WORK=${CI_WORK:-$SRC/ci-work}/link
PORT=${LINK_PORT:-18690}

command -v curl > /dev/null || { echo "curl(1) is needed" >&2; exit 2; }
command -v cc > /dev/null || { echo "a C compiler (cc) is needed" >&2; exit 2; }

VG=${LINK_VALGRIND:-}
vglog="$WORK/logs/valgrind.log"
maxtime=10
daemon_mode=on
master_mode=on
if [ -n "$VG" ]; then
	command -v valgrind > /dev/null || { echo "valgrind(1) is needed" >&2; exit 2; }
	daemon_mode=off
	master_mode=off
	maxtime=60
fi

rm -rf "$WORK"
mkdir -p "$WORK/conf" "$WORK/logs"

fail=0
note() { echo "  $1" >&2; fail=1; }

# Build the sample application library against the module header.  The
# ngx_link_func_* API it calls is resolved at load time from the nginx
# binary, so undefined symbols at link time are expected and fine.
applib="$WORK/liblinkfuntest.so"
cc -shared -fPIC -I "$SRC/src" -o "$applib" "$SRC/build_test_resources/linkfuntest.c" ||
	{ echo "ci/link.sh: could not build the sample library" >&2; exit 1; }

load=
[ -n "${LINK_LOAD_MODULE:-}" ] && load="load_module $LINK_LOAD_MODULE;"

# Run as root (the FreeBSD job does) and nginx workers drop to "nobody",
# which cannot read the library under $WORK, so pin the workers to root.
ngx_user=
if [ "$(id -u)" = 0 ]; then
	ngx_user="user root $(id -gn);"
fi

cat > "$WORK/conf/nginx.conf" <<CONF
$load
$ngx_user
daemon $daemon_mode;
master_process $master_mode;
worker_processes 1;
pid $WORK/logs/nginx.pid;
error_log $WORK/logs/error.log info;
events { worker_connections 64; }
http {
    access_log off;

    server {
        listen 127.0.0.1:$PORT;
        ngx_link_func_lib "$applib";

        location = /greeting {
            ngx_link_func_call "my_app_simple_get_greeting";
        }
        location = /args {
            ngx_link_func_call "my_app_simple_get_args";
        }
    }
}
CONF

"$NGINX" -p "$WORK" -c "$WORK/conf/nginx.conf" -t 2> "$WORK/logs/t.log" ||
	{ cat "$WORK/logs/t.log" >&2; echo "ci/link.sh: config rejected" >&2; exit 1; }

ngxpid=
if [ -n "$VG" ]; then
	valgrind --leak-check=full --show-leak-kinds=definite,indirect \
		--errors-for-leak-kinds=definite,indirect --error-exitcode=99 \
		--log-file="$vglog" --suppressions="$SRC/valgrind.suppress" \
		--trace-children=no \
		"$NGINX" -p "$WORK" -c "$WORK/conf/nginx.conf" &
	ngxpid=$!
	up=0; i=0
	while [ $i -lt 80 ]; do
		if curl -s -o /dev/null --max-time 5 "http://127.0.0.1:$PORT/greeting"; then
			up=1; break
		fi
		sleep 0.5; i=$((i + 1))
	done
	[ "$up" = 1 ] || { echo "ci/link.sh: nginx did not come up under valgrind" >&2; kill "$ngxpid" 2>/dev/null; exit 1; }
else
	"$NGINX" -p "$WORK" -c "$WORK/conf/nginx.conf"
	sleep 1
fi

stop() {
	if [ -n "$ngxpid" ]; then
		kill -QUIT "$ngxpid" 2>/dev/null
		wait "$ngxpid" 2>/dev/null || true
	elif [ -s "$WORK/logs/nginx.pid" ]; then
		kill -QUIT "$(cat "$WORK/logs/nginx.pid")" 2>/dev/null
	fi
	return 0
}
trap stop EXIT INT TERM

base="http://127.0.0.1:$PORT"

echo "== a call reaches the loaded library and its response comes back"
out=$(curl -s -w '\n%{http_code}' --max-time "$maxtime" "$base/greeting")
code=$(printf '%s' "$out" | tail -1)
body=$(printf '%s' "$out" | sed '$d')
echo "  GET /greeting $code"; [ "$code" = 200 ] || note "call not 200 ($code)"
printf '%s' "$body" | grep -q 'greeting from ngx_link_func testing' ||
	note "the library response did not come back (\"$body\")"

echo "== the query string is handed to the function"
q='greeting=hello_nginx'
got=$(curl -s --max-time "$maxtime" "$base/args?$q")
echo "  GET /args?$q -> $got"
printf '%s' "$got" | grep -q "$q" || note "the query string was not handed through"

echo "== error log"
if grep -qE '\[(alert|emerg|crit)\]' "$WORK/logs/error.log"; then
	note "alert/emerg/crit in the error log"
	grep -E '\[(alert|emerg|crit)\]' "$WORK/logs/error.log" | head -3 >&2
else
	echo "  clean"
fi

if [ -n "$VG" ]; then
	echo "== valgrind"
	stop
	ngxpid=
	trap - EXIT INT TERM
	errs=$(sed -n 's/.*ERROR SUMMARY: \([0-9][0-9]*\) errors.*/\1/p' "$vglog" | tail -1)
	defl=$(sed -n 's/.*definitely lost: \([0-9,]*\) bytes.*/\1/p' "$vglog" | tr -d , | tail -1)
	indl=$(sed -n 's/.*indirectly lost: \([0-9,]*\) bytes.*/\1/p' "$vglog" | tr -d , | tail -1)
	if [ "${errs:-0}" != 0 ] || [ "${defl:-0}" != 0 ] || [ "${indl:-0}" != 0 ]; then
		note "valgrind: ${errs:-?} errors, definitely lost ${defl:-?}, indirectly lost ${indl:-?}"
		grep -niE "Invalid read|Invalid write|uninitialised|Mismatched free" "$vglog" >&2
	else
		echo "  clean (errors $errs, suppressed shown in log)"
	fi
fi

[ "$fail" -eq 0 ] || { echo "ci/link.sh: failed" >&2; exit 1; }
echo "ci/link.sh: ok"
