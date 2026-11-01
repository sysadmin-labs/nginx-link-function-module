#!/usr/bin/perl

# Tests for nginx-link-function.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http/)->plan(3);

# Build the sample application library against the module header.  The
# ngx_link_func_* API is resolved from the nginx binary at load time.
my $src = "$FindBin::Bin/..";
my $lib = $t->testdir() . "/liblinkfuntest.so";
system("cc -shared -fPIC -I '$src/src' -o '$lib' "
	. "'$src/build_test_resources/linkfuntest.c'") == 0
	or plan(skip_all => "could not build the sample library");

$t->write_file_expand('nginx.conf', <<"EOF");

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        ngx_link_func_lib "$lib";

        location = /greeting {
            ngx_link_func_call "my_app_simple_get_greeting";
        }
        location = /args {
            ngx_link_func_call "my_app_simple_get_args";
        }
    }
}

EOF

$t->run();

###############################################################################

my $g = http_get('/greeting');
like($g, qr!^HTTP/\S+ 200!m,                    'a library call returns 200');
like($g, qr/greeting from ngx_link_func testing/, 'the library response comes back');

my $a = http_get('/args?greeting=hello_nginx');
like($a, qr/greeting=hello_nginx/,              'the query string is handed to the function');

###############################################################################
