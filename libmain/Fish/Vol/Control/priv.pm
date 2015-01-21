package Fish::Vol::Control::priv;

use 5.18.0;

BEGIN { 
    push @INC,  '../..';
}

use Moo;
use MooX::Types::MooseLike::Base ':all';

use List::Util qw, min max,;
use Time::HiRes 'time';

use Fish::Utility;
use Fish::Utility_l 'keysr';
use Fish::Utility_m 'is_num';
use Fish::Class 'o';

use Fish::Vol::Utility 'timeout', 'kill_timeout';

use constant DEBUG => main::DEBUG;
use constant DO_BENCHMARK => 0;
use if DO_BENCHMARK, 'Fish::Utility_m' => qw, bench_start bench_end_pr ,;
use if ! DO_BENCHMARK, 'Fish::Vol::Utility::NoBenchmark' => qw, bench_start bench_end_pr ,;

# order: conf, this value.
my $DEFAULT_NUM_FADE_STEPS = 20;
my $DEFAULT_MIN_FADE_STEP_TIME = 50; #ms

has conf => (
    is => 'rw',
    isa => sub { ref $_[0] eq 'Fish::Conf' or ierror "Need Fish::Conf"},
);

has cur_fade_tids => (
    is => 'rw',
    isa => HashRef,
    default => sub {{}},
);

has fading => (
    is => 'rw',
    isa => Bool,
);

my $g = o(
    # class names
    c => o(
        mixer => 'Fish::Vol::Mixer',
    ),
);

sub fade {
    my ($self, $card_idx, $ctl_idx, $cur, $fade_to, $secs) = @_;

    my $conf = $self->conf;
    my $nfs = $conf->c('num-fade-steps') // $DEFAULT_NUM_FADE_STEPS;
    my $sleep_per_step = $secs / $nfs;

    my $time_start;
    $time_start = time if DEBUG;

    my $min_fade_step_time = $conf->c('min-fade-step-time') // $DEFAULT_MIN_FADE_STEP_TIME;
    my $min_fade_step_time_s = $min_fade_step_time / 1000;

    if ($sleep_per_step < $min_fade_step_time_s ) {
        info "fade timeout is less than $min_fade_step_time ms, decreasing num frames and setting timeout to $min_fade_step_time";
        my $factor = $sleep_per_step / $min_fade_step_time_s;
        my $olds = $sleep_per_step;
        my $oldn = $nfs;
        $sleep_per_step = $min_fade_step_time_s;
        $nfs = int ($nfs * $factor);
        info "sleep", BR $olds, 'num steps', BR $oldn, '-> ', G $sleep_per_step, G $nfs if DEBUG;
    }

    info 'Fade to', Y $fade_to, 'cur', CY $cur, 'num_steps', Y $nfs, 'sleep_per_step (s)', G 1000 * $sleep_per_step if DEBUG;

    my $m = $cur;
    my $i = 0;

    $self->fading(1);

    # The number of actual steps might be one or two off, since we do it
    # based on time, and ensure that the goal is reached.
    my $delta_m = ($fade_to - $cur) / $nfs;

    # Set timeout for this card and ctl. All will run concurrently.
    my $tid;
    $tid = timeout $sleep_per_step * 1000, sub {
        $m += $delta_m;

        if ($m < 0) {
            $m = 0;
        }
        elsif ($m > 100) {
            $m = 100;
        }
        elsif ($delta_m > 0 and $m > $fade_to) {
            $m = $fade_to;
        }
        elsif ($delta_m < 0 and $m < $fade_to) {
            $m = $fade_to;
        }

        $self->set($card_idx, $ctl_idx, $m) or iwar,
            return;

        if ($m == $fade_to) {
            if (DEBUG) {
                info 'done fading, actual time %s', Y sprintf "%.1f", (time - $time_start);
            }
            $self->fading(0);
            delete $self->cur_fade_tids->{$tid};
            return;
        }

        1
    };

    $tid or iwar, 
        return;

    $self->cur_fade_tids->{$tid} = 1;

    1
}

sub rel {
    my ($self, $card_idx, $ctl_idx, $delta) = @_;
    info 'relative set for card', Y $card_idx, 'ctl', CY $ctl_idx, 'delta', $delta if DEBUG;
    $g->c->mixer->rel($card_idx, $ctl_idx, $delta) or war, 
        return;

    1
}

sub set {
    my ($self, $card_idx, $ctl_idx, $val_perc) = @_;

bench_start('control:_set');

    if ($val_perc eq 'mute') {
    }
    elsif ($val_perc eq 'unmute') {
    }
    else {
        $val_perc = max $val_perc, 0;
        $val_perc = min $val_perc, 100;

        info 'setting card', Y $card_idx, 'ctl', CY $ctl_idx, 'val_perc', $val_perc if DEBUG;
bench_start('control: set -> mixer->set');
        $g->c->mixer->set($card_idx, $ctl_idx, $val_perc) or war, 
            return;
bench_end_pr('control: set -> mixer->set');
    }

bench_end_pr('control: set');

    1
}

sub stop_cur_fade {
    my ($self) = @_;
    my @tids = keysr $self->cur_fade_tids;
    return -1 unless @tids; #ok

    my $ok = 1;
    for (@tids) {
        kill_timeout or iwar,
            $ok = 0;
        delete $self->cur_fade_tids->{$_};
    }

    $ok
}

1;
