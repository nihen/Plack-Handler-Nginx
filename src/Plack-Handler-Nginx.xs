#define NEED_newSVpvn_flags
#include "xshelper.h"
#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>

#define ngx_http_perl_set_request(r)                                          \
    r = INT2PTR(ngx_http_request_t *, SvIV((SV *) SvRV(ST(0))))

#define MAX_HEADER_NAME_LEN 1024

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
ngx_plack_handler_http_header_set(r, SV* envref)
CODE:
{
    ngx_http_request_t  *r;
    HV* env;
    ngx_uint_t i;
    ngx_table_elt_t *h;
    ngx_list_part_t *part;
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
            strncmp_tou((char*)h[i].key.data, "CONTENT-TYPE", sizeof("CONTENT-TYPE") - 1) == 0
        ) {
            name = "CONTENT_TYPE";
            name_len = sizeof("CONTENT_TYPE") - 1;    
        }
        else if ( h[i].key.len == sizeof("CONTENT-LENGTH") - 1 &&
            strncmp_tou((char*)h[i].key.data, "CONTENT-LENGTH", sizeof("CONTENT-LENGTH") - 1) == 0
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

