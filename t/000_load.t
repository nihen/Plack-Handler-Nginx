#!perl -w
use strict;
use Test::More tests => 1;
use Test::Requires 'nginx';

BEGIN {
    use_ok 'Plack::Handler::Nginx';
}

diag "Testing Plack::Handler::Nginx/$Plack::Handler::Nginx::VERSION";
