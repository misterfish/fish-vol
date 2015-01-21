package Fish::Vol::Osd;

use Moose;

use 5.10.0;


BEGIN {
    use File::Basename;
    push @INC, dirname $0;
}

use X11::Aosd ':all';

use Fish::Utility_a;
use Math::Trig ':pi';

use Time::HiRes qw/ time sleep /;

use threads;
use threads::shared;

# units of vol perc
my $FADE_STEP = .01;

# to control responsiveness of osd loop.
# a decent number to allow interruption.

# great responsiveness. tons of cpu.
#my $OSD_SLEEP = .001;

my $OSD_SLEEP = .005;
my $STROKE_WIDTH = 2;
my $RADIUS = 28;

my @COLOR = (.8, .4, .1);
my @COLOR2 = (.1, .1, .1);

has init => (
    is => 'ro',
    isa => 'Num',
);

has _cur_perc => (
    is => 'rw',
    isa => 'Num',
);

# what the renderer sees
has perc => (
    is => 'rw',
    isa => 'Num',
    default => 0,
);

#bool
has fading => (
    is => 'rw',
    isa => 'Num',
);

# time to stay on screen
has display_time => (
    is => 'rw',
    isa => 'Num',
);

#bool
has redraw => (
    is => 'rw',
    isa => 'Num',
);

has index => (
    is => 'ro',
    isa => 'Int',
);

# bool
has _do_stop => (
    is => 'rw',
    isa => 'Int',
);

sub BUILD {
    my ($self, @args) = @_;

    share($self->{$_}) for qw, perc fading display_time redraw _do_stop, ;

    async { $self->main_loop($self->init) }->detach;

}

sub main_loop {

    my ($self, $init) = @_;

    my $HEIGHT = 400;
    my $WIDTH = 200;
    my $TRANSPARENCY = .8;

    my $aosd = X11::Aosd->new;

    $aosd->set_transparency(TRANSPARENCY_COMPOSITE);

    $aosd->set_position_with_offset(
      COORDINATE_CENTER,
      COORDINATE_CENTER,
      # actually width then height
      $HEIGHT, $WIDTH, 0 + $self->index * 100, 0
    );

    $aosd->set_hide_upon_mouse_event(1);

    $aosd->set_renderer(sub {
        my ($cr) = @_;
        $cr->set_source_rgba (@COLOR, $TRANSPARENCY);
        $cr->set_line_width($STROKE_WIDTH);

#D 'renderer perc', $self->perc;
        $cr->arc(100,100, $RADIUS, 0, 2 * pi * $self->perc);
        $cr->stroke;

        $cr->set_source_rgba (@COLOR2, $TRANSPARENCY);
        $cr->arc(100,100, $RADIUS + $STROKE_WIDTH, 0, 2 * pi * $self->perc);

        $cr->stroke;
    });

    my $_cur_perc = $init;
    $self->_cur_perc($_cur_perc);
#D $_cur_perc;

    while (1) {
        # shared 
        my $perc = $self->perc;

        # something's been set
        if ($self->redraw) {
            my $time = $self->display_time;
#D 'showing';
            $aosd->show;

            my $target;
            my $cur;
            my $step;
            my $num_steps;

            $target = $perc;
            $cur = $self->_cur_perc;

#D 'cur', $cur;
            # what the renderer sees
            $self->perc($cur);

            my $delta = $target - $cur;
            my $delta_abs = abs($delta);
#D 'target', $target;
#D 'cur', $cur;
#D 'delta', $delta;

#D 'fading', $self->fading;
#D 'display_time', $self->display_time;

            # set with big diff, just go
            my $smooth;
            my $fading = $self->fading;
            if ($delta_abs > .2 and !$fading) {
                $num_steps = 1;
                $smooth = 0;
                $num_steps = 10;
            }
            else {
                $num_steps = 1 + int ($delta_abs / $FADE_STEP);
                $smooth = 1;

                # when not fading, spend the first half of the interval
                # moving, the last half static.
                if ($fading) {
                    $step = $delta / $num_steps;
                }
                else {
                    my $ns = 1 + int ($num_steps / 2);
                    $step = $delta / $ns;
                }
            }

            # it can be set to 1 from outside while we're busy with
            # following loop.
            $self->redraw(0);

#D 'num_steps', $num_steps;

            # loop that animates/updates osd
            for (my $i = 0; $i < $num_steps; $i++) {

                if ($self->redraw) {
                    # exit inner loop and don't hide.
                    last;
                }

                if ($self->_do_stop) {
                    # exit inner loop and hide.
                    $self->_do_stop(0);

                    $aosd->hide;
                    # render + loop_once. actually hide.
                    $aosd->update;

                    last;
                }

                # lock here?
                if ($smooth) {
                    my $p = $self->perc;
                    if ($p == $target) {
                    }
                    else {
                        if ($step > 0) {
                            if ($target - $p < $step) {
                                $self->perc($target);
                            } 
                            else {
                                $self->perc($p + $step);
                            }
                        }
                        else {
                            if ($target - $p > $step) {
                                $self->perc($target);
                            } 
                            else {
                                $self->perc($p + $step);
                            }
                        }
                    }
                }
                else {
                    $self->perc($target);
                }
                my $t1 = time;
                $aosd->update;
                $self->_cur_perc($self->perc);
                my $sleep = $time / $num_steps - (time - $t1);
                if ($sleep < 0) {
                    warn "loop took longer than sleep, decrease num steps";
                    $sleep = 0;
                }

                if ($i == $num_steps - 1) {
                    $aosd->hide;
                    # render + loop_once. actually hide.
                    $aosd->update;
                }

                # animation sleep is calculated based on num_steps.
                sleep $sleep;
            }
        }

        $self->perc(max($self->perc, 0));

        # to control responsiveness of osd loop.
        sleep $OSD_SLEEP;
    }
}

sub update {
    my ($self) = @_;
    $self->redraw(1);
}

sub stop {
    my ($self) = @_;
    $self->_do_stop(1);
}

sub max {
    my ($a, $b) = @_;
    return $a > $b ? $a : $b;
}

sub min {
    my ($a, $b) = @_;
    return $a < $b ? $a : $b;
}


1;
