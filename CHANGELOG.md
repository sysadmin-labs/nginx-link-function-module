# Changelog

## 3.2.5 (2026-11-01)

Taken over as a maintained fork of Taymindis/nginx-link-function, whose
newest release is 3.2.4 (2020).  This release is that code, built and tested
against current nginx, with the two changes the FreeBSD port has carried as
local patches folded in.

- The module includes its own header with `#include "ngx_link_func_module.h"`
  instead of `<ngx_link_func_module.h>`, so the build no longer requires the
  header to be installed into a system include path first (FreeBSD port
  patch).
- The addon `config` was rewritten to the standard nginx form.  Upstream's
  config refused to build unless the header was already installed system-wide
  and it wrote generated test files back into the source tree during
  `configure`; neither is needed here, so the module simply builds static or
  dynamic like any other (this is what the FreeBSD port's config patch was
  for).

No behaviour of the module itself is changed; the work in this release is the
build, the test harness and the packaging.

The `t/` suite builds the bundled sample library (build_test_resources),
loads it with `ngx_link_func_lib` and checks a call through the nginx core
`Test::Nginx` (vendored under `t/lib`).  `ci/link.sh` drives the same with
curl end to end.

Valgrind runs against that end-to-end driver, not the Test::Nginx suite: the
driver starts one foreground nginx under valgrind and stops it with QUIT, so
the pools are freed and a leak report would be the module's own.
