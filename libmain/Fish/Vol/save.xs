#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

/* Not necessary to #include fasound.h.
 */

MODULE = fish_vol_xs		PACKAGE = fish_vol_xs		

int 
xs_test()
    CODE:
        RETVAL = 3
    OUTPUT:
        RETVAL

/*
bool
xs_test()
    CODE:
        AV* outer = newAV();
        {
            AV* i = newAV();
            av_push(i, newSVpv("Intel card", 0)); // -O- static string
            av_push(i, newSVpv("Master", 0));
            av_push(i, newSVpv("Speaker", 0));
            av_push(i, newSVpv("Headphone", 0));
            av_push(outer, newRV((SV*) i));
        }
        {
            AV* i = newAV();
            av_push(i, newSVpv("USB thing", 0)); // -O- static string
            av_push(i, newSVpv("Master", 0));
            av_push(i, newSVpv("Left", 0));
            av_push(i, newSVpv("Right", 0));
            av_push(i, newSVpv("Front", 0));
            av_push(i, newSVpv("Back", 0));
            av_push(outer, newRV((SV*) i));
        }

        //RETVAL = outer;
        RETVAL = false;
    OUTPUT: 
        RETVAL
        */

AV*
xs_init()
    CODE:
        char *objects;
        int n;
        RETVAL = newAV();
        if (!asound_interface_init(&objects, &n)) {
            XSRETURN_EMPTY; // Just returning newAV() produces (undef), not empty.
        }
    OUTPUT:
        RETVAL

bool
xs_set(which, val)
        int which 
        int val
    CODE:
        RETVAL = asound_interface_set(which, val);
    OUTPUT:
        RETVAL

int
xs_get(which)
        int which
    CODE:
        int val;
        asound_interface_get(which, &val);
        RETVAL = val;
    OUTPUT:
        RETVAL

void
xs_finish()
    CODE:
        asound_interface_finish();
