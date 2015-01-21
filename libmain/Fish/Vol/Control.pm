package Fish::Vol::Control; 
use 5.18.0;

BEGIN { 
    push @INC,  '../..';
}

use Moo;
use MooX::Types::MooseLike::Base ':all';

use Fish::Vol::Control::priv;

use Fish::Utility;
use Fish::Utility_m 'is_num', 'is_int';
use Fish::Vol::Utility 'check_type';

use constant DEBUG => main::DEBUG;

use constant DO_BENCHMARK => 0;
use if DO_BENCHMARK, 'Fish::Utility_m' => qw, bench_start bench_end_pr ,;
use if ! DO_BENCHMARK, 'Fish::Vol::Utility::NoBenchmark' => qw, bench_start bench_end_pr ,;

# order: socket cmd, conf, this value.
my $DEFAULT_FADE_IN_SECS = 3;
my $DEFAULT_FADE_OUT_SECS = 3;
my $DEFAULT_FADE_TO_SECS = 3;

has conf => (
    is => 'rw',
    isa => check_type 'Fish::Conf',
);

has _priv => (
    is => 'rw',
    isa => check_type 'Fish::Vol::Control::priv',
);

my %CMDS = (
    fadein    => \&fadein,
    'fade-in'   => \&fadein,
    'fadeup'    => \&fadein,
    'fade-up'   => \&fadein,
    'fin'       => \&fadein,

    fadeout     => \&fadeout,
    'fade-out'     => \&fadeout,
    fadedown     => \&fadeout,
    'fade-down'     => \&fadeout,
    fo     => \&fadeout,

    fade                => \&fadeto,
    fadeto              => \&fadeto,
    'fade-to'           => \&fadeto,

#print       => \&print,

    default     => \&default,
    factor      => \&factor,
    relative    => \&relative,
    rel    => \&relative,
    'rel-all'   => \&relative_all,
    'relative-all'   => \&relative_all,
    set         => \&set,
    'set-all'   => \&set_all,

    mute        => \&mute,
    unmute      => \&unmute,

    help        => \&help,

    stop        => \&stop,
);

my %cmds;

# allow unique abbreviations
for (keys %CMDS) {
    #my $l = length;
    #for (my $i = $l; $i > 0; $i--) {
    #    my $s = substr $_, 0, $i;
    #    #if (delete $cmds{$s}) {
    #    if (exists $cmds{$s}) {
    #        #
    #    }
    #    else {
    #        $cmds{$s} = $CMDS{$_};
    #    }
    #}
}

%cmds = %CMDS;

# XX
my $err;

sub BUILD {
    my ($self) = @_;
    $self->_priv(Fish::Vol::Control::priv->new(
        conf => $self->conf,
    ));
}

sub cmd {
    my ($self, $cmd, @args) = @_;

    my $cb = $cmds{$cmd} or war("Unrecognized cmd:", BR $cmd),
        return;

    $cb->($self, @args)
}

#sub fadexxx-all ...

sub fadein {
    my ($self, $secs) = @_;
    $secs //= $self->conf->c('default-fade-in-secs') // $DEFAULT_FADE_IN_SECS;
    my $fade_to;
    (is_num $secs and $secs >= 0) or war(sprintf "Invalid value (%s)", BR $secs),
        return;

    $self->fade('default', $secs)
}

sub help {
    war 'help not implemented';
    return;
}

# stop a fade
sub stop {
    my ($self) = @_;
    
    $self->_priv->stop_cur_fade
}

sub fadeout {
    my ($self, $secs) = @_;
    $secs //= $self->conf->c('default-fade-out-secs') // $DEFAULT_FADE_OUT_SECS;
    (is_num $secs and $secs >= 0) or war(sprintf "Invalid value (%s)", BR $secs),
        return;

    $self->fade(0, $secs)
}

sub fadeto {
    my ($self, $fade_to, $secs) = @_;
    $fade_to //= 'undef';
    (is_num $fade_to and $fade_to >= 0 and $fade_to <= 100) or war(sprintf "Invalid value for %s (%s)", Y 'fade_to', BR $fade_to),
        return;
    $secs //= $self->conf->c('default-fade-to-secs') // $DEFAULT_FADE_TO_SECS;
    (is_num $secs and $secs >= 0) or war(sprintf "Invalid value for %s (%s)", Y 'secs', BR $secs),
        return;

    $self->fade($fade_to, $secs)
}

sub default_all {
    warn;
}

sub default {
    my ($self) = @_;

    # XX
    warn;
}

sub factor_all {
    warn;
}

sub factor {
    warn;
    #XX
}

# e.g. -5 => cur - 5 (not cur * .95)
# e.g. 5 or +5 => cur + 5 (not cur * 1.05)
# +-5 allowed for legacy

sub relative {
    my ($self, $card_id, $ctl_id, $delta) = @_;
    $delta //= 'undef';
    war(sprintf "Invalid value for %s (%s)", Y 'delta', BR $delta),
        return unless is_num $delta and
            $delta >= -100 and
            $delta <= 100;

    # otherwise the vol can change due to rounding, etc.
    return 1 if $delta == 0;

    $delta =~ s/\+//;

    $self->on_matching_cards($card_id, $ctl_id, sub {
        my ($self, $card_idx, $ctl_idx) = @_;
        $self->_priv->rel($card_idx, $ctl_idx, $delta)
    })
}

sub relative_all {
    my ($self, $delta) = @_;
    # arg checked in single call
    $self->all(sub {
        my ($self, $card_idx, $ctl_idx) = @_;

        $self->relative($card_idx, $ctl_idx, $delta)
    })
}

sub all {
    my ($self, $sub) = @_;
    my $ok = 1;
    my $iter = main::main_iter();
    while (my $i = $iter->()) {
        my $card_idx = $i->card_idx;
        my $ctl_idx = $i->ctl_idx;
        my $this_ok = $sub->($self, $card_idx, $ctl_idx) ? 1 : 0;
        $ok &= $this_ok;
    }

    $ok
}

sub set {
    my ($self, $card_id, $ctl_id, $val) = @_;
    $val //= 'undef';
    (is_num $val and $val >= 0 and $val <= 100) or war(sprintf "Invalid value for %s (%s)", Y 'val', BR $val),
        return;

    $self->on_matching_cards($card_id, $ctl_id, sub {
        my ($self, $card_idx, $ctl_idx) = @_;
        $self->_priv->set($card_idx, $ctl_idx, $val)
    })
}

sub set_all {
    my ($self, $val) = @_;

    # arg checked in single call

    $self->all(sub {
        my ($self, $card_idx, $ctl_idx) = @_;

        $self->set($card_idx, $ctl_idx, $val)
    })
}

# XX
sub mute {
    my ($self) = @_;
    warn;
}

sub unmute {
    my ($self) = @_;
    warn;
}

sub fade {
    my ($self, $to, $secs) = @_;

    $self->_priv->stop_cur_fade;

    my $ok = 1;
    my $iter = main::main_iter();
    while (my $i = $iter->()) {
        my $card_idx = $i->card_idx;
        my $ctl_idx = $i->ctl_idx;

        my $cur = main::cur($card_idx, $ctl_idx);
        defined $cur or war,
            return;

        if ($to eq 'default') {
            my $def = main::get_default_vol($card_idx) or iwar("Can't get default for card", $card_idx),
                next;
            $to = $def;
        }
        info("fade cur", $cur, 'card', $card_idx, 'ctl', $ctl_idx) if DEBUG;
        my $this_ok = $self->_priv->fade($card_idx, $ctl_idx, $cur, $to, $secs) ? 1 : 0;
        $ok &= $this_ok;
    }

    $ok
}

# ctl_idx optional
sub check_valid_idx {
    my ($self, $card_idx, $ctl_idx) = @_;
    my $card;
    if (not $card = main::get_card_by_idx($card_idx)) {
        war sprintf "No such card (%s)", BR $card_idx;
        return;
    }
    if (defined $ctl_idx) {
        if (not main::get_ctl_by_idx($card_idx, $ctl_idx)) {
            war sprintf "No such ctl (%s) for card %s", BR $ctl_idx, Y $card_idx;
            return;
        }
    }

    1
}

#allow :
#  <cmd> 0 0 <val>
#  <cmd> 0 pcm <val>
#  <cmd> usb 0 <val>
#  <cmd> usb pcm <val>
#  <cmd> usb all <val>
#  <cmd> all all <val>
    
sub on_matching_cards {
    my ($self, $card_id, $ctl_id, $sub) = @_;

    my @cards;
    my $intcd = is_int $card_id;
    my $intctl = is_int $ctl_id;

    if ($intcd and $intctl) {
        $self->check_valid_idx($card_id, $ctl_id) or
            return;
        @cards = [$card_id, $ctl_id];
    }
    elsif (!$intcd and $intctl) {
        # will warn and return empty on bad card id
        @cards = map { [$_->idx, $ctl_id] } main::get_cards_by_string($card_id);
    }
    elsif ($intcd and !$intctl) {
        $self->check_valid_idx($card_id) or
            return;
        my @ctls = main::get_ctls_for_card_by_string($card_id, $ctl_id);
        @cards = map { [$card_id, $_->idx] } @ctls;
    }
    else {
        my @cards_by_string = main::get_cards_by_string($card_id);
        for my $card (@cards_by_string) {
            my $card_idx = $card->idx;
            my @ctls = main::get_ctls_for_card_by_string($card_idx, $ctl_id);
            push @cards, map { [$card_idx, $_->idx] } @ctls;
        }
    }

    @cards or war("Nothing to do!"), 
        return;

    my $ok = 1;
    for (@cards) {
        my ($card_idx, $ctl_idx) = @$_;
        my $this_ok = $sub->($self, $card_idx, $ctl_idx) ? 1 : 0;
        $ok &= $this_ok;
    }

    $ok
}



1;
