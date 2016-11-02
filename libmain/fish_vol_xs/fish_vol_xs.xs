#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

/* Not necessary to #include fasound.h for compiling --
 * but, we want MAX_ constants.
 */

#include "../../libextra/fish-lib-asound/fish-asound.h"

MODULE = fish_vol_xs		PACKAGE = fish_vol_xs		

int 
xs_test()
    CODE:
        //RETVAL = 3;
        XSRETURN_UNDEF;
    OUTPUT:
        RETVAL

AV*
xs_init(options)
        int options
    CODE:
        int m = FASOUND_MAX_SOUND_CARDS;
        int n = FASOUND_MAX_ELEMS;
        int o = FASOUND_MAX_FDS;
        const char *card_names_hw[FASOUND_MAX_SOUND_CARDS] = {0};
        const char *card_names_string[FASOUND_MAX_SOUND_CARDS] = {0};
        const char *ctl_names[FASOUND_MAX_SOUND_CARDS][FASOUND_MAX_ELEMS] = {0};
        int fds[FASOUND_MAX_SOUND_CARDS][FASOUND_MAX_FDS] = {0};

        RETVAL = newAV();
        sv_2mortal((SV*)RETVAL);

        if (!fasound_init(options, card_names_string, card_names_hw, ctl_names, fds)) {
            XSRETURN_EMPTY; // Just returning newAV() produces (undef), not empty.
        }
        int i, j, k; // not c99
        bool found_one = false;
        for (i = 0; i < m; i++) {
            AV *card_av = newAV();
            const char *card_name_hw = card_names_hw[i];
            if (! card_name_hw)
                continue;
            found_one = true;

            const char *card_name_string = card_names_string[i];
            if (! card_name_string)
                card_name_string = "UNKNOWN";

            SV *card_idx_sv = newSViv(i);
            av_push(card_av, card_idx_sv);

            int size;

            size = strnlen(card_name_hw, FASOUND_MAX_CARD_NAME_HW_SIZE) == FASOUND_MAX_CARD_NAME_HW_SIZE ? FASOUND_MAX_CARD_NAME_HW_SIZE : 0; // 0 means let them do it for us
            SV *card_name_hw_sv = newSVpv(card_name_hw, size);
            av_push(card_av, card_name_hw_sv);

            size = strnlen(card_name_string, FASOUND_MAX_CARD_NAME_STRING_SIZE) == FASOUND_MAX_CARD_NAME_STRING_SIZE ? FASOUND_MAX_CARD_NAME_STRING_SIZE : 0; // 0 means let them do it for us
            SV *card_name_string_sv = newSVpv(card_name_string, size);
            av_push(card_av, card_name_string_sv);

            AV *ctl_av = newAV();
            for (j = 0; j < n; j++) {
                const char *ctl_name = ctl_names[i][j];
                if (! ctl_name) 
                    continue;
                int size = strnlen(ctl_name, FASOUND_MAX_ELEM_NAME_SIZE) == FASOUND_MAX_ELEM_NAME_SIZE ? FASOUND_MAX_ELEM_NAME_SIZE : 0;
                SV *sv = newSVpv(ctl_name, size);
                av_push(ctl_av, sv);
            }
            av_push(card_av, newRV((SV*) ctl_av));
            AV *pollav = newAV();
            for (k = 0; k < 2; k++) {
                int fd = fds[i][k];
                if (!fd) 
                    continue;
                SV *sv = newSViv(fd);
                av_push(pollav, sv);
            }
            av_push(card_av, newRV((SV*) pollav));
            av_push(RETVAL, newRV((SV*) card_av));
        }
        if (!found_one) 
            XSRETURN_EMPTY;
    OUTPUT:
        RETVAL

bool
xs_set(card_idx, ctl_idx, val_perc)
        int card_idx 
        int ctl_idx 
        double val_perc
    CODE:
        RETVAL = fasound_set(card_idx, ctl_idx, FASOUND_CHAN_ALL, val_perc);
    OUTPUT:
        RETVAL

bool
xs_set_rel(card_idx, ctl_idx, delta_perc)
        int card_idx 
        int ctl_idx 
        int delta_perc
    CODE:
        RETVAL = fasound_set_rel(card_idx, ctl_idx, FASOUND_CHAN_ALL, delta_perc);
    OUTPUT:
        RETVAL

bool 
xs_update(card_idx, ctl_idx)
        int card_idx
        int ctl_idx
    CODE:
        bool changed;
        if (!fasound_update(card_idx, ctl_idx, &changed))
            XSRETURN_UNDEF;
        RETVAL = changed;
    OUTPUT:
        RETVAL

double
xs_get(card_idx, ctl_idx)
        int card_idx
        int ctl_idx
    CODE:
        double val;
        /* man perlcall
         */
        if (!fasound_get(card_idx, ctl_idx, &val)) 
            XSRETURN_UNDEF;
        RETVAL = val;
    OUTPUT:
        RETVAL

bool
xs_finish()
    CODE:
        RETVAL = fasound_finish();
    OUTPUT:
        RETVAL

bool
xs_handle_event(card_num)
        int card_num
    CODE:
        RETVAL = fasound_handle_event(card_num);
    OUTPUT:
        RETVAL
