package Fish::Vol::Mixer;

use 5.18.0;

use Fish::Utility_a;

use constant DEBUG => main::DEBUG;
use constant DO_BENCHMARK => 0;

use if DO_BENCHMARK, 'Fish::Utility_m' => qw, bench_start bench_end_pr ,;
use if ! DO_BENCHMARK, 'Fish::Vol::Utility::NoBenchmark' => qw, bench_start bench_end_pr ,;


sub set;

sub mute {
    shift if $_[0] eq __PACKAGE__;
    my $which = shift or iwar, 
        return;
    set $which, 'mute';
}

sub unmute {
    shift if $_[0] eq __PACKAGE__;
    my $which = shift or iwar, 
        return;
    set $which, 'unmute';
}

sub set {
    my ($self, $card_idx, $ctl_idx, $val_perc) = @_;

    defined or iwar,
        return for $card_idx, $ctl_idx, $val_perc;

    if ($val_perc eq 'mute') {
        # XX
        $val_perc = 'off';
        #info ("amixer can't mute/unmute PCM, skipping."), return if $id;
    }
    elsif ($val_perc eq 'unmute') {
        # XX
        $val_perc = 'on';
        #info ("amixer can't mute/unmute PCM, skipping."), return if $id eq 'pcm';
    }
    else {
        $val_perc =~ / \d+ /x or iwar,
            return;
    }

    info 'Mixer: setting val_perc', $val_perc, 'card', $card_idx, 'ctl_idx', $ctl_idx, if DEBUG;
bench_start('xs_set');

    my $ret = main::xs_set($card_idx, $ctl_idx, $val_perc) or iwar,
        return;
bench_end_pr('xs_set');

    $ret
}

sub rel {
    my ($self, $card_idx, $ctl_idx, $delta) = @_;

    defined or iwar, 
        return for $card_idx, $ctl_idx, $delta;

    my $ret = main::xs_set_rel($card_idx, $ctl_idx, $delta) or iwar,
        return;

    $ret
}

sub update {
    shift if $_[0] eq __PACKAGE__;
    my ($card_idx, $ctl_idx) = @_;
    (defined $card_idx and defined $ctl_idx) or iwar, 
        return;

    my $ret = main::xs_update($card_idx, $ctl_idx);
    defined $ret or iwar,
        return;

    $ret
}

sub get {
    shift if $_[0] eq __PACKAGE__;
    my ($card_idx, $ctl_idx) = @_;
    (defined $card_idx and defined $ctl_idx) or iwar, 
        return;

bench_start('xs_get');
    my $val_perc = main::xs_get($card_idx, $ctl_idx);
    defined $val_perc or iwar,
        return;

bench_end_pr('xs_get');
    info 'Mixer: got val_perc', $val_perc, 'for card', $card_idx, 'ctl', $ctl_idx if DEBUG;

    $val_perc
}


1;
