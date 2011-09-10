#define NEED_newSVpvn_flags
#include "xshelper.h"
#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>

#define ngx_http_perl_set_request(r)                                          \
    r = INT2PTR(ngx_http_request_t *, SvIV((SV *) SvRV(ST(0))))

#define MAX_HEADER_NAME_LEN 1024
#define hv_stores_from_ngx_str(hv, key, val) \
    (void)hv_stores(hv, key, newSVpvn((char*)val.data, val.len))
#define hv_stores_from_ngx_var(hv, key, val) \
    (void)hv_stores(hv, key, newSVpvn((char*)val->data, val->len))
#if (NGX_HTTP_SSL)
#define is_ssl(r) r->connection->ssl
#else
#define is_ssl(r) 1==0
#endif

STATIC_INLINE
char tou(char ch)
{
  if ('a' <= ch && ch <= 'z')
    ch -= 'a' - 'A';
  return ch;
}


STATIC_INLINE
int strncmp_tou(const char* lname, const char* rname, size_t len)
{
  const char* x, * y;
  for (x = lname, y = rname; len != 0; --len, ++x, ++y)
    if (tou(*x) != *y)
      return -1;
  return 0;
}

MODULE = Plack::Handler::Nginx    PACKAGE = Plack::Handler::Nginx

PROTOTYPES: DISABLE

int
ngx_psgi_env_set_per_request(r, SV* envref)
CODE:
{
    ngx_http_request_t         *r;
    HV*                        env;
    ngx_uint_t                 i;
    ngx_table_elt_t            *h;
    ngx_list_part_t            *part;
    ngx_http_variable_value_t  *vv;
    ngx_str_t                  var;
    char tmp[MAX_HEADER_NAME_LEN + sizeof("HTTP_") -1];
    int ret;

    ret = 0;

    ngx_http_perl_set_request(r);

    if ( !SvROK(envref) ) {
        Perl_croak(aTHX_ "nginx_http_header_set_to_env param should be a hashref");
    }

    env = (HV*)SvRV(envref);
    if ( SvTYPE(env) != SVt_PVHV ) {
        Perl_croak(aTHX_ "nginx_http_header_set_to_env param should be a hashref");
    }

    hv_stores_from_ngx_str(env, "REQUEST_METHOD", r->method_name);
    (void)hv_stores(env, "SCRIPT_NAME", newSVpvs(""));
    hv_stores_from_ngx_str(env, "PATH_INFO", r->uri);
    hv_stores_from_ngx_str(env, "REQUEST_URI", r->unparsed_uri);

    if ( r->args.len > 0 ) {
        hv_stores_from_ngx_str(env, "QUERY_STRING", r->args);
    }
    else {
        (void)hv_stores(env, "QUERY_STRING", newSVpvs(""));
    }

    var = (ngx_str_t)ngx_string("server_addr");
    vv = ngx_http_get_variable(r, &var, ngx_hash_key((u_char*)STR_WITH_LEN("server_addr")));
    if ( vv ) {
        hv_stores_from_ngx_var(env, "SERVER_NAME", vv);
    }

    var = (ngx_str_t)ngx_string("server_port");
    vv = ngx_http_get_variable(r, &var, ngx_hash_key((u_char*)STR_WITH_LEN("server_port")));
    if ( vv ) {
        hv_stores_from_ngx_var(env, "SERVER_PORT", vv);
    }

    hv_stores_from_ngx_str(env, "SERVER_PROTOCOL", r->http_protocol);
    hv_stores_from_ngx_str(env, "REMOTE_ADDR", r->connection->addr_text);

    if ( is_ssl(r) ) {
        (void)hv_stores(env, "psgi.url_scheme", newSVpvs("https"));
    }
    else {
        (void)hv_stores(env, "psgi.url_scheme", newSVpvs("http"));
    }

    part = &r->headers_in.headers.part;
    h = part->elts;
    for (i = 0; /* void */ ; i++) {
        const char* name;
        size_t name_len;
        SV** slot;

        if (i >= part->nelts) {
            if (part->next == NULL) {
                break;
            }

            part = part->next;
            h = part->elts;
            i = 0;
        }

        if ( h[i].key.len == sizeof("CONTENT-TYPE") - 1 &&
            strncmp_tou((char*)h[i].key.data, STR_WITH_LEN("CONTENT-TYPE")) == 0
        ) {
            name = "CONTENT_TYPE";
            name_len = sizeof("CONTENT_TYPE") - 1;    
        }
        else if ( h[i].key.len == sizeof("CONTENT-LENGTH") - 1 &&
            strncmp_tou((char*)h[i].key.data, STR_WITH_LEN("CONTENT-LENGTH")) == 0
        ) {
            name = "CONTENT_LENGTH";
            name_len = sizeof("CONTENT_LENGTH") - 1;    
        }
        else {
            const char* s;
            char* d;
            size_t n;

            if (sizeof(tmp) - 5 < h[i].key.len ) {
                ret = -1;
                goto done;
            }

            strcpy(tmp, "HTTP_");
            for (
                s = (char*)h[i].key.data, n = h[i].key.len, d = tmp + 5;
                n != 0;
                s++, --n, d++
            ) {
                *d = *s == '-' ? '_' : tou(*s);
            }
            name = tmp;
            name_len = h[i].key.len + 5;
        }

        slot = hv_fetch(env, name, name_len, 1);

        if ( !slot )
            Perl_croak(aTHX_ "failed to create hash entry");

        if ( SvOK(*slot)) {
            sv_catpvn(*slot, ", ", 2);
            sv_catpvn(*slot, (char*)h[i].value.data, h[i].value.len);
        }
        else {
            sv_setpvn(*slot, (char*)h[i].value.data, h[i].value.len);
        }
    }

  done:
    RETVAL = ret;
}
OUTPUT:
  RETVAL

