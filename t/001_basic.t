#!perl -w
use strict;
use Test::More;

use FindBin;
use Plack;
use Plack::Test::Suite;
use Cwd qw/realpath/;
my $blib_path = realpath($FindBin::Bin . '/../blib');
my $tmpdir = $ENV{NGINX_TMP_DIR} || File::Temp::tempdir( CLEANUP => 1 );
$tmpdir =~ s{/$}{}g;

Plack::Test::Suite->run_server_tests(run_httpd(\&_render_conf));
kill 'TERM', `cat $tmpdir/nginx_pid`;

done_testing;


sub run_httpd {
    my $render_conf = shift;
    my $nginx_bin;
    for my $_nginx_bin ( $ENV{NGINX_BIN}, '/usr/local/nginx/sbin/nginx', '/usr/sbin/nginx', '/usr/local/sbin/nginx' ) {
        if ( $_nginx_bin && -f $_nginx_bin ) {
            diag("nginx_bin: $_nginx_bin");
            $nginx_bin = $_nginx_bin;
            last;
        }
    }
    if ( !$nginx_bin ) {
        die("not found nginx_bin")
    }
    sub {
        my $port = shift;


        write_file("$tmpdir/app.psgi", _render_psgi());
        write_file("$tmpdir/nginx.conf", $render_conf->($tmpdir, $port, "$tmpdir/app.psgi"));

        exec "$nginx_bin -c $tmpdir/nginx.conf";
    };
}


sub write_file {
    my($path, $content) = @_;

    open my $out, ">", $path or die "$path: $!";
    print $out $content;
}


sub _render_psgi {
    return <<'EOF';
use lib "blib";
use Plack::Test::Suite;

Plack::Test::Suite->test_app_handler;
EOF
}


sub _render_conf {
    my ($tmpdir, $port, $psgi_path) = @_;
    <<"END";
pid $tmpdir/nginx_pid;
lock_file $tmpdir/nginx_lock;
error_log $tmpdir/error_log;

events {
    worker_connections  1024;
    multi_accept on;
}

http {
    access_log off;
    client_body_temp_path $tmpdir/client_body_temp;
    merge_slashes off;
    perl_modules $blib_path/lib;
    perl_modules $blib_path/arch;
    perl_require Plack/Handler/Nginx.pm;
    server {
        listen       $port default;
        location / {
            set \$psgi '$tmpdir/app.psgi';
            perl Plack::Handler::Nginx::handler;
        }
    }
}
END
}
