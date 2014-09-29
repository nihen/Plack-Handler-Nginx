package Plack::Handler::Nginx;
use strict;
use warnings;
use 5.008_001;
use nginx;
use Carp;
use Plack::Util ();

our $VERSION = '0.01';

require XSLoader;
XSLoader::load('Plack::Handler::Nginx', $VERSION);

my $null_io = do { open my $io, "<", \""; $io };

my %apps = ();

sub load_app {
    my $psgi_app = shift;

    $apps{$psgi_app} ||= do {
        Plack::Util::load_psgi $psgi_app;
    };
}
sub handler {
    my $r = shift;

    my $ret = $r->has_request_body(\&psgi_handler_read_body);
    unless ( $ret ) {
        return psgi_handler($r, $null_io);
    }
    return OK;
}

sub psgi_handler {
    my ( $r, $input ) = @_;
    my $app = load_app($r->variable('psgi'));

    my $env = {
        'psgi.version'      => [1, 1],
        'psgi.input'        => $input,
        'psgi.errors'       => *STDERR,
        'psgi.multithread'  => Plack::Util::FALSE,
        'psgi.multiprocess' => Plack::Util::TRUE,
        'psgi.run_once'     => Plack::Util::FALSE,
        'psgi.nonblocking'  => Plack::Util::TRUE,
        'psgi.streaming'    => Plack::Util::TRUE,
        'psgix.nginx_request' => $r,
    };
    if ( ngx_psgi_env_set_per_request($r, $env) != 0 ) {
        warn("http_header_set fail");
        return HTTP_INTERNAL_SERVER_ERROR;
    }

    my $res = Plack::Util::run_app $app, $env;

    if ( ref $res eq 'ARRAY' ) {
        write_response_header($r, $res);
        write_response_body($r, $res->[2]);
    }
    elsif ( ref $res eq 'CODE' ) {
        $res->(
            sub {
                my $res = shift;

                if ( @$res < 2 ) {
                    croak "Insufficient arguments";
                }
                elsif ( @$res == 2 ) {
                    my ( $status, $headers ) = @$res;

                    write_response_header($r, $res);
                    $r->rflush;

                    return Plack::Util::inline_object
                        write => sub { $r->print($_[0]); $r->rflush; },
                        close => sub {}
                    ;
                }
                else {
                    write_response_header($r, $res);
                    write_response_body($r, $res->[2]);
                }
            }
        );
    }
    else {
        warn("Unknown response type: $res");
        return HTTP_INTERNAL_SERVER_ERROR;
    }

    return OK;
}
sub psgi_handler_read_body {
    my $r = shift;

    my $input;
    my $body = $r->request_body;
    if ( defined $body ) {
        unless ( open $input, '<', \$body ) {
            warn "read body: $!";
            return HTTP_INTERNAL_SERVER_ERROR;
        }
    }
    else {
        my $file = $r->request_body_file;
        if ( $file && -f $file ) {
            unless ( open $input, '<', $file ) {
                warn "$file: $!";
                return HTTP_INTERNAL_SERVER_ERROR;
            }
        }
    }
    return psgi_handler($r, $input);
}

sub write_response_header {
    my $r    = shift;
    my $res  = shift;

    $r->status($res->[0]);

    my $content_type = '';

    Plack::Util::header_iter($res->[1], sub {
        if ( uc $_[0] eq 'CONTENT-TYPE' ) {
            $content_type = $_[1];
        }
        else {
            $r->header_out($_[0], $_[1]);
        }
    });
    $r->send_http_header($content_type);
}

sub write_response_body {
    my $r    = shift;
    my $body = shift;

    if (Scalar::Util::blessed($body) and $body->can('path') and my $path = $body->path) {
        $r->sendfile($path);
    }
    else {
        Plack::Util::foreach($body, sub { $r->print($_[0]) });
    }
}

1;



__END__

=head1 NAME

Plack::Handler::Nginx - nginx handlers to run PSGI application

=head1 SYNOPSIS

  http {
    ...
    perl_require Plack/Handler/Nginx.pm;
    ...    
  }

  location / {
    set $psgi '/path/to/app.psgi';
    perl Plack::Handler::Nginx::handler;
  }

=head1 INSTALL

  NGINX_SRC_PATH=/path/to/nginx_src_path/ perl Makefile.PL
  NGINX_BIN=/path/to/nginx_bin_path make test
  make install

=head1 DESCRIPTION

This is a handler module to run any PSGI application with Nginx with EmbeddedPerlModule

=head1 AUTHOR

Masahiro Chiba

=head1 SEE ALSO

L<Plack>

ngx_mod_psgi: L<https://github.com/yko/ngx_mod_psgi>

nginx-psgi-patchs: L<https://github.com/yappo/nginx-psgi-patchs>

=cut

=head1 LICENSE

This module uses code from L<HTTP::Parser::XS>, nginx-psgi-patchs L<https://github.com/yappo/nginx-psgi-patchs> and ngx_mod_psgi L<https://github.com/yko/ngx_mod_psgi>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
