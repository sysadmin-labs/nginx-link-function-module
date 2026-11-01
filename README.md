# nginx-link-function-module

[![Build&Test][build-test-badge]][build-test-link]
[![Link function][link-badge]][link-link]
[![FreeBSD][freebsd-badge]][freebsd-link]
[![A/UBSan][sanitizers-badge]][sanitizers-link]
[![Valgrind][valgrind-badge]][valgrind-link]
[![Reload][reload-badge]][reload-link]
[![CodeQL][codeql-badge]][codeql-link]
[![Lint][lint-badge]][lint-link]

[build-test-badge]: https://github.com/sysadmin-labs/nginx-link-function-module/actions/workflows/build-test.yml/badge.svg
[build-test-link]: https://github.com/sysadmin-labs/nginx-link-function-module/actions/workflows/build-test.yml
[link-badge]: https://github.com/sysadmin-labs/nginx-link-function-module/actions/workflows/link.yml/badge.svg
[link-link]: https://github.com/sysadmin-labs/nginx-link-function-module/actions/workflows/link.yml
[freebsd-badge]: https://github.com/sysadmin-labs/nginx-link-function-module/actions/workflows/freebsd.yml/badge.svg
[freebsd-link]: https://github.com/sysadmin-labs/nginx-link-function-module/actions/workflows/freebsd.yml
[sanitizers-badge]: https://github.com/sysadmin-labs/nginx-link-function-module/actions/workflows/sanitizers.yml/badge.svg
[sanitizers-link]: https://github.com/sysadmin-labs/nginx-link-function-module/actions/workflows/sanitizers.yml
[valgrind-badge]: https://github.com/sysadmin-labs/nginx-link-function-module/actions/workflows/valgrind.yml/badge.svg
[valgrind-link]: https://github.com/sysadmin-labs/nginx-link-function-module/actions/workflows/valgrind.yml
[reload-badge]: https://github.com/sysadmin-labs/nginx-link-function-module/actions/workflows/reload.yml/badge.svg
[reload-link]: https://github.com/sysadmin-labs/nginx-link-function-module/actions/workflows/reload.yml
[codeql-badge]: https://github.com/sysadmin-labs/nginx-link-function-module/actions/workflows/codeql.yml/badge.svg
[codeql-link]: https://github.com/sysadmin-labs/nginx-link-function-module/actions/workflows/codeql.yml
[lint-badge]: https://github.com/sysadmin-labs/nginx-link-function-module/actions/workflows/lint.yml/badge.svg
[lint-link]: https://github.com/sysadmin-labs/nginx-link-function-module/actions/workflows/lint.yml

This module lets nginx hand a request to a function in a C library you load
at run time, so you can serve a location straight from your own compiled
code without writing an nginx module.  It is a maintained fork of
Taymindis/nginx-link-function.

## Synopsis

```nginx
http {
    server {
        # the application library, loaded once per worker
        ngx_link_func_lib "/etc/nginx/liblinkfuntest.so";

        location = /greeting {
            ngx_link_func_call "my_app_simple_get_greeting";
        }
    }
}
```

The library is an ordinary shared object built against the module header
`src/ngx_link_func_module.h`; a worked example is in
`build_test_resources/linkfuntest.c`:

```sh
cc -shared -fPIC -I /path/to/nginx-link-function-module/src \
    -o liblinkfuntest.so linkfuntest.c
```

## Directives

- `ngx_link_func_lib <path>`: the shared library to load for this server;
  its `ngx_link_func_init_cycle` runs on worker start and
  `ngx_link_func_exit_cycle` on exit.
- `ngx_link_func_call "<function>"`: dispatch this location to the named
  function in the library.
- `ngx_link_func_shm_size <size>`: size of the shared-memory zone the API
  offers to applications.

See the upstream documentation for the full application API (request body
and args, response and headers, shared memory, subrequests).

## Building

```sh
./configure --add-module=/path/to/nginx-link-function-module
```

or as a loadable module

```sh
./configure --add-dynamic-module=/path/to/nginx-link-function-module
```

with `load_module modules/ngx_http_link_func_module.so;` in the main
context.

## Testing

```sh
ci/build.sh 1.30.5 /tmp/nginx-test
TEST_NGINX_BINARY=/tmp/nginx-test/sbin/nginx prove -r t/
ci/link.sh /tmp/nginx-test/sbin/nginx
ci/reload.sh /tmp/nginx-test/sbin/nginx
```

The `t/` suite needs only core Perl and a C compiler; the nginx core
`Test::Nginx` is vendored under `t/lib`.  `ci/link.sh` needs `curl` and a C
compiler to build the sample library.

## License

BSD 2-Clause, see [LICENSE](LICENSE).
