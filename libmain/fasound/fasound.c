//#define DEBUG  // before fish-util-h

#include "fasound.h"
#include <inttypes.h> // abs

//#define TEST 

struct ctl {
    snd_mixer_elem_t *elem; // simple mixer element = PCM etc.
    int chans[CHAN_MAX - CHAN_MIN + 1];
    int num_chans;
    const char *name;
    long min;
    long max;
    bool active;

    long cur_val[CHAN_MAX - CHAN_MIN + 1];
};

struct card {
    int idx; // corresponds to hw:<idx>

    const char *name_hw;
    const char *name_string;

    snd_mixer_t *mixer;
    struct ctl **ctls;
    int num_ctls;

    bool can_poll;

    struct pollfd *pollfds; // only internal
    int *fds;
    int num_fds;
};

static struct {
    int initted;
    int finished;

    struct card **cards;
    int num_cards;

    int max_num_ctls;
} g;

static snd_mixer_t *get_mixer(const char *card);
static bool get_card_info(bool);
static bool get_poll_descriptors(struct card *card);

/* TODO
 * mallocs
 * mute
 */

bool asound_interface_init(int options, 
        const char *card_names_string[MAX_SOUND_CARDS], 
        const char *card_names_hw[MAX_SOUND_CARDS],
        const char *ctl_names[MAX_SOUND_CARDS][MAX_ELEMS],
        int fds[MAX_SOUND_CARDS][MAX_FDS]
) {
    /*
     * When things change, we do call init again.
    if (g.initted) {
        f_warn("asound_interface_init called twice.");
        return false;
    }
    */

    bool quiet = options & FASOUND_OPTIONS_QUIET;

    if (!get_card_info(quiet)) 
        f_pieprf;

    for (int i = 0; i < MAX_SOUND_CARDS; i++) {
        struct card *card = g.cards[i];
        if (!card) 
            continue;

        const char *name_hw = card->name_hw;
        card_names_hw[i] = strdup(name_hw); // -O-
        const char *name_string = card->name_string;
        card_names_string[i] = strdup(name_string); // -O-

        for (int j = 0; j < card->num_ctls; j++) {
            struct ctl *ctl = card->ctls[j];
            const char *elem_name = ctl->name;
            ctl_names[i][j] = strdup(elem_name);
        }
        for (int j = 0; j < card->num_fds; j++) {
            int fd = card->fds[j];
            fds[i][j] = fd;
        }
    }

#ifdef TEST
    card_names_hw[1] = "hw:x";
    card_names_string[1] = "testy card";
    ctl_names[1][0] = "PCM";
    ctl_names[1][1] = "Headshit";
    fds[1][0] = 1;
    fds[1][1] = 2;
#endif

    g.initted = 1;
    return true;
}

bool asound_interface_set(int card_idx, int ctl_idx, double val_perc) {
    if (card_idx >= g.num_cards)
        pieprf;
    struct card *card = g.cards[card_idx];
    if (ctl_idx >= card->num_ctls) 
        pieprf;
    struct ctl *ctl = card->ctls[ctl_idx];

    double set = ctl->min + val_perc / 100.0 * 1.0 * (ctl->max - ctl->min);
    if (set > ctl->max) set = ctl->max;
    if (set < ctl->min) set = ctl->min;

    debug("capi: set %f max %d min %d", set, ctl->max, ctl->min, set);

    snd_mixer_elem_t* elem = ctl->elem;
    int rc;
    if (rc = snd_mixer_selem_set_playback_volume_all(elem, set)) 
        _errorrf(rc);

    return true;
}

bool asound_interface_set_rel(int card_idx, int ctl_idx, int delta_perc) {
    if (card_idx >= g.num_cards)
        pieprf;
    struct card *card = g.cards[card_idx];
    if (ctl_idx >= card->num_ctls) 
        pieprf;
    struct ctl *ctl = card->ctls[ctl_idx];

    bool ok = true;
    for (int chan_ary_id = 0; chan_ary_id < ctl->num_chans; chan_ary_id++) {
        int chan = ctl->chans[chan_ary_id];

        /* cur is assumed to always be kept current.
         */
        long cur = ctl->cur_val[chan];

        double old_perc = cur * 1.0 * 100 / (ctl->max - ctl->min);
        double new_perc = old_perc + delta_perc;

        double set = new_perc * 1.0 * (ctl->max - ctl->min) / 100;

        /* If the delta percentage is too small, rounding can mean that the
         * value will get stuck. Ensure step of at least one.
         */
        if (abs(set - cur) < 1) 
            set = delta_perc > 0 ? cur + 1 : cur - 1;

        if (set > ctl->max) set = ctl->max;
        if (set < ctl->min) set = ctl->min;

        debug("capi: set relative card %d ctl %d chan %d delta_perc %d set %f \n  max %d min %d old_perc %f new_perc %f cur %d", card_idx, ctl_idx, chan, delta_perc, set, ctl->max, ctl->min,
                old_perc, new_perc, cur
                );

        snd_mixer_elem_t *elem = ctl->elem;
        int rc;
        if (rc = snd_mixer_selem_set_playback_volume(elem, chan, set)) {
            _error(rc);
            ok = false;
        }
    }

    return ok;
}

bool asound_interface_update(int card_idx, int ctl_idx, bool *changed) {
    *changed = false;
    if (card_idx >= g.num_cards)
        pieprf;
    struct card *card = g.cards[card_idx];
    if (ctl_idx >= card->num_ctls) 
        pieprf;
    struct ctl *ctl = card->ctls[ctl_idx];
    snd_mixer_elem_t *elem = ctl->elem;

    long this_value;

    for (int chan_ary_idx = 0; chan_ary_idx < ctl->num_chans; chan_ary_idx++) {
        int chan = ctl->chans[chan_ary_idx];
        if (snd_mixer_selem_get_playback_volume(elem, chan, &this_value)) {
            _();
            BR(ctl->name);
            spr("%d", chan);
            Y(_t);
            f_warnp("Can't get volume for ctl %s, chan %s.", _s, _u);
            ctl->cur_val[chan] = -1;
            return false;
        }

        long old_value = ctl->cur_val[chan];
        if (old_value != this_value) {
            ctl->cur_val[chan] = this_value;
            *changed = true;
        }

        debug("capi: Got value %d for card %d ctl %d chan %d", this_value, card_idx, ctl_idx, chan);

        /*
        if (value == LONG_MAX) 
            return false;
        */
    }

    return true;
}

bool asound_interface_get(int card_idx, int ctl_idx, double *val_perc) {
    *val_perc = -1;
    if (card_idx >= g.num_cards)
        pieprf;
    struct card *card = g.cards[card_idx];
    if (ctl_idx >= card->num_ctls) 
        pieprf;
    struct ctl *ctl = card->ctls[ctl_idx];

    long this_value;
    // Take average if channels differ. 
    long total = 0;

    for (int chan_ary_idx = 0; chan_ary_idx < ctl->num_chans; chan_ary_idx++) {
        int chan = ctl->chans[chan_ary_idx];
        this_value = ctl->cur_val[chan];
        if (this_value == -1)
            pieprf;
        total += this_value;
    }

    double value = total * 1.0 / ctl->num_chans;

    *val_perc = 100.0 * (value - ctl->min) / (ctl->max - ctl->min);

    return true;
}

bool asound_interface_handle_event(int card_num) {
    assert(card_num < g.num_cards);
    struct card *card = g.cards[card_num];
    if (! card) 
        pieprf;
    snd_mixer_t *mixer = card->mixer;
    /* Clear the flag on the file descriptor. There might be a cheaper way
     * to do this.
     */
    int rc = snd_mixer_handle_events(mixer);
    return true;    
}

bool asound_interface_finish() {
    if (g.finished) {
        f_warn("asound_interface_finished called multiple times.");
        return false;
    }

    info("Goodbye.");
    //snd_mixer_close(g.mixer);
    g.finished = 1;
    return true;
}

void f_warn(const char* format, ...) {
    int WARN_LENGTH = 500;
    int COLOR_LENGTH = 5;
    int COLOR_LENGTH_RESET = 4;
    static const char* BULLET = "ঈ";
    static const int BULLET_LENGTH = 3; // in utf-8 at least XX

    char* new = str(WARN_LENGTH);
    char* new2 = str(WARN_LENGTH + 1);
    va_list arglist, arglist_copy;
    va_start( arglist, format );
    va_copy(arglist_copy, arglist);
    vsnprintf(new, WARN_LENGTH, format, arglist );
    vsnprintf( new2, WARN_LENGTH + 1, format, arglist_copy );
    if (strncmp(new, new2, WARN_LENGTH)) { // no + 1 necessary
        //warn("Warn string truncated.");
        printf("warn: warn string truncated\n");
    }
    va_end( arglist );

    char* warning = str(strlen(new) + COLOR_LENGTH + COLOR_LENGTH_RESET + BULLET_LENGTH + 1 + 1 + 1);
    char* c = BR_(BULLET);
    sprintf(warning, "%s %s\n", c, new);
    fprintf(stderr, warning);
    free(warning);
    free(c);
    free(new);
    free(new2);
} 


/* - - - private - - -
 */

static snd_mixer_t *get_mixer(const char* name_hw) { 
    snd_mixer_t* mixer;
    int rc;
    if (rc = snd_mixer_open(&mixer, 0))  // open mode 0
        _errorrnull(rc);

    if (rc = snd_mixer_attach(mixer, name_hw))
        _errorrnull(rc);

    if (rc = snd_mixer_selem_register(mixer, NULL, NULL)) 
        _errorrnull(rc);
    if (rc = snd_mixer_load(mixer)) 
        _errorrnull(rc);

    return mixer;
}
    
static bool get_card_info(bool quiet) {
    /* Start from -1, meaning, _next gives first card.
     */
    int rcard = -1;
    int rc;

    snd_ctl_t *ctl;
    snd_ctl_card_info_t *card_info;
    snd_ctl_card_info_alloca(&card_info);

    char hw[6];
    assert(MAX_SOUND_CARDS < 99);

    bool found_a_card = false;

    g.cards = calloc(MAX_SOUND_CARDS, sizeof(char*));

    /* Card loop.
     */
    for (int i = 0; i < MAX_SOUND_CARDS + 1; i++) {
        if (i == MAX_SOUND_CARDS) {
            _();
            spr("%d", MAX_SOUND_CARDS);
            Y(_s);
            spr("More than %s sound cards found, ignoring extra ones.", _t);
            f_warn(_u);
            break;
        }
        if (rc = snd_card_next(&rcard)) 
            _errorrf(rc);

        if (rcard < 0) 
            break; // ok, we're done

        sprintf(hw, "hw:%d", i);
        if (rc = snd_ctl_open(&ctl, hw, 0)) { // mode 0
            _();
            BR(hw);
            spr("Couldn't open sound control %s", _s);
            _errormsg(rc, _t, strlen(_t));
            continue;
        }
        if (rc = snd_ctl_card_info(ctl, card_info)) {
            _error(rc);
            continue;
        }
        if (rc = snd_ctl_close(ctl)) {
            _error(rc);
            continue;
        }

        char *name_string = strdup(snd_ctl_card_info_get_name(card_info));
        char *name_hw = strdup(hw);

        _();
        G(name_string);
        Y(name_hw);
        if (!quiet) info("Found card %s at %s", _s, _t);

        struct card *card = malloc(sizeof(struct card));
        memset(card, '\0', sizeof(struct card));
        g.num_cards++;
        card->idx = i;

        card->name_hw = name_hw;
        card->name_string = name_string;

        /*
         * name here is the alsa-ish name, not the card name as returned above,
         * try aplay -L.
         * direct hardware names work: hw:0, hw:1, ...
         */
        snd_mixer_t *mixer = get_mixer(name_hw);
        if (!mixer) {
            f_piep;
            continue;
        }
        card->mixer = mixer;

        if (get_poll_descriptors(card)) {
            card->can_poll = true;
        }
        else {
            piep; // not fatal
            card->can_poll = false;
        }

        int count = snd_mixer_get_count(mixer);
        
        bool found_a_ctl = false;
        snd_mixer_elem_t *elem;

        card->ctls = calloc(count, sizeof(struct card*));

        /* Elem loop.
         */
        int j = -1;
        for (elem = snd_mixer_first_elem(mixer); elem;
                elem = snd_mixer_elem_next(elem)) {
            const char* sn = snd_mixer_selem_get_name(elem);

            if (!snd_mixer_selem_has_playback_switch(elem) ||
            snd_mixer_selem_has_capture_switch(elem)) 
                continue;

            /* But it could be mutable XX
             */
            long min, max;
            int rc = snd_mixer_selem_get_playback_volume_range(elem, &min, &max);
            if (rc) {
                f_warn("Element has no playback range, skipping.");
                continue;
            }

            _();
            G(sn);
            if (!quiet) info(" Found playback control %s", _s);

            _();
            M("Range");
            if (!quiet) info("  %s: %d - %d", _s, min, max);

            bool active = (bool) snd_mixer_selem_is_active(elem);
            if (!active) {
                if (!quiet) info("  Element not active.");
                continue;
            }

            struct ctl *ctl = malloc(sizeof(struct ctl));
            memset(ctl, '\0', sizeof(struct ctl));
            
            ctl->name = sn;
            ctl->elem = elem;
            ctl->min = min;
            ctl->max = max;
            ctl->active = active;

            /* Channel loop.
             */
            int chan_ary_id = -1;
            bool found_a_chan = false;

            for (int chan_id = CHAN_MIN; chan_id <= CHAN_MAX; chan_id++) {
                //chan_ary_id++;
                if (snd_mixer_selem_has_playback_channel(elem, chan_id)) {
                    _();
                    B("Channel");
                    if (!quiet) info("   %s %d supported.", _s, chan_id);
                    chan_ary_id++;
                    ctl->chans[chan_ary_id] = chan_id;
                    found_a_chan = true;
                }
            }
            ctl->num_chans = chan_ary_id + 1;
            if (! found_a_chan) {
                if (count) 
                    f_warn(" Didn't find any usable channels.");
                else 
                    info(" Didn't find any usable channels.");
                continue;
            }
            j++;
            card->ctls[j] = ctl;
            found_a_ctl = true;
        }
        card->num_ctls = j + 1;

        if (card->num_ctls > g.max_num_ctls) 
            g.max_num_ctls = card->num_ctls;

        if (!found_a_ctl) {
            f_warn("  Didn't find any usable elements.");
            continue;
        }

        g.cards[i] = card;
        found_a_card = true;
    }
    if (!found_a_card) {
        f_warn("Couldn't find any sound cards.");
        return false;
    }
    return true;
}

static bool get_poll_descriptors(struct card *card) {
    card->can_poll = false;
    int num_fds = 0;
    num_fds = snd_mixer_poll_descriptors_count(card->mixer);
    if (num_fds == 0) {
        f_warn("Couldn't get poll descriptors count.");
        return false;
    }

    card->num_fds = num_fds;
    struct pollfd *pollfds = calloc(num_fds, sizeof(struct pollfd));
    int rc = snd_mixer_poll_descriptors(card->mixer, pollfds, num_fds);
    if (!rc) {
        f_warn("Couldn't get poll descriptors.");
        return false;
    }

    card->fds = calloc(num_fds, sizeof(int));
    struct pollfd *p = pollfds;
    for (int i = 0; i < num_fds; i++) {
        card->fds[i] = p->fd;
        p++;
    }
    card->pollfds = pollfds;

    return true;
}

