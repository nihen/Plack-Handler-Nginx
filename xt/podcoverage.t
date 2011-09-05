#!perl -w
use Test::More;
eval q{use Test::Pod::Coverage 1.04};
plan skip_all => 'Test::Pod::Coverage 1.04 required for testing POD coverage'
    if $@;

all_pod_coverage_ok({
    also_private => [qw(unimport BUILD DEMOLISH init_meta)],
});
