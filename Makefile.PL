#!perl
use strict;
use warnings;
BEGIN {
    unshift @INC, 'inc';

    # author requires, or bundled modules
    my @devmods = qw(
        inc::Module::Install             1.00
        Module::Install::AuthorTests     0.002
        Module::Install::Repository      0.06
        Test::Requires                   0.06
        Module::Install::XSUtil 0.32
    );
    my @not_available;
    while(my($mod, $ver) = splice @devmods, 0, 2) {
        eval qq{use $mod $ver (); 1} or push @not_available, $mod;
    }
    if(@not_available) {
        print qq{# The following modules are not available.\n};
        print qq{# `perl $0 | cpanm` will install them:\n};
        print $_, "\n" for @not_available;
        exit 1;
     }
}
use inc::Module::Install;


all_from 'lib/Plack/Handler/Nginx.pm';

use_xshelper;
cc_warnings;
cc_src_paths 'src';

my $nginx_src_path = $ARGV[0] || $ENV{NGINX_SRC_PATH} || '/tmp/nginx/';
$nginx_src_path =~ s{/$}{}g;
unless ( 
    -d $nginx_src_path . '/src/http/' &&
    -d $nginx_src_path . '/src/http/modules/' &&
    -d $nginx_src_path . '/src/core/' &&
    -d $nginx_src_path . '/src/event/' &&
    -d $nginx_src_path . '/src/os/unix/' &&
    -d $nginx_src_path . '/objs/'
) {
    print "Usage: perl Makefile.PL /path/to/nginx_src_path/\n";
    exit(-1);
}
cc_include_paths
    $nginx_src_path . '/src/http/',
    $nginx_src_path . '/src/http/modules/',
    $nginx_src_path . '/src/core/',
    $nginx_src_path . '/src/event/',
    $nginx_src_path . '/src/os/unix/',
    $nginx_src_path . '/objs/',
;

test_requires 'Test::More'     => '0.88';
test_requires 'Test::Requires' => '0.06';

requires 'Plack';

auto_set_repository;

tests_recursive;
author_tests 'xt';


clean_files qw(
    Plack-Handler-Nginx-*
    *.stackdump
    cover_db *.gcov *.gcda *.gcno
    nytprof
    *.out
);

WriteAll(check_nmake => 0);
