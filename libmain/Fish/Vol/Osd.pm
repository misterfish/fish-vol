package Fish::Vol::Osd;

use 5.18.0;

BEGIN {
    use File::Basename;
    push @INC, dirname $0;
}

# Loaded dynamically (maybe) in constructor.
# use X11::Aosd ':all';

use Moo;
use MooX::Types::MooseLike::Base ':all';

use List::Util qw, min max ,;
use Math::Trig ':pi';
use Time::HiRes qw, time sleep ,;

use Fish::Utility;
use Fish::Utility_l 'list', 'is_defined', 'pushr';
use Fish::Class 'o';

use Fish::Vol::Utility;

use constant DEBUG => main::DEBUG;

use constant DO_BENCHMARK => 0;

use if DO_BENCHMARK, 'Fish::Utility_m' => qw, bench_start bench_end_pr ,;
use if ! DO_BENCHMARK, 'Fish::Vol::Utility::NoBenchmark' => qw, bench_start bench_end_pr ,;

# Animation possible in principle by changing this.
my $NUM_STEPS = 1;

sub color_to_decimal;
# Percentages are specified as e.g. 65, not .65.

# Percentage. Setting it doesn't cause display.
has actual => (
    is => 'rw',
    isa => Num,
);

#has ignore => (
#    is => 'rw',
#    isa => Bool,
#);

# Percentage.
has _cur_value => (
    is => 'rw',
    isa => Num,
);

# Percentage.
has _cur_target => (
    is => 'rw',
    isa => Num,
);

has _aosd => (
    is  => 'rw',
    isa => sub { errortrace 'Need X11::Aosd' unless ref $_[0] eq 'X11::Aosd' },
);

has _hide_timeouts => (
    is => 'rw',
    isa => ArrayRef,
    default => sub {[]},
);

has card_name => (
    is => 'ro',
    isa => Str,
);

has row => (
    is => 'rw',
    isa => Int,
);

has col => (
    is => 'rw',
    isa => Int,
);

has _do_stop => (
    is => 'rw',
    isa => Bool,
);

has radius1 => (
    is => 'rw',
    isa => Int,
);

has radius2 => (
    is => 'rw',
    isa => Int,
);

has height => (
    is  => 'rw',
    isa => Int,
);

has width => (
    is => 'rw',
    isa => Int,
);

has spacing_x => (
    is => 'rw',
    isa => Int,
);

has spacing_y => (
    is => 'rw',
    isa => Int,
);

has stroke_width => (
    is => 'rw',
    isa => Num,
);

has opacity => (
    is => 'rw',
    isa => Num,
);

has color1 => (
    is => 'rw',
    #isa => ArrayRef,
    isa => Str,
);

has color2 => (
    is => 'rw',
    #isa => ArrayRef,
    isa => Str,
);

has transparency_type => (
    is => 'rw',
    isa => Str,
);

around actual => sub {
    my ($orig, $self, @args) = @_;
    if (is_defined my $a = $args[0]) {
        $self->_cur_value($a);
    }
    $self->$orig(@args);
};

my $g = o(
    # If X11::Aosd could load.
    ok => 0,

    transparency_composite => -1,
    transparency_fake => -1,
    transparency_none => -1,
    coordinate_center => -1,
);

{
    my $ok = eval "use X11::Aosd; 1";
    if (not $ok) {
        war "Unable to load X11::Aosd, OSD disabled. (Try -X to silence this warning.)";
    }
    else {
        $g->ok(1);

        $g->transparency_composite(X11::Aosd::TRANSPARENCY_COMPOSITE());
        $g->transparency_fake(X11::Aosd::TRANSPARENCY_FAKE());
        $g->transparency_none(X11::Aosd::TRANSPARENCY_NONE());
        $g->coordinate_center(X11::Aosd::COORDINATE_CENTER());
    }
}

sub ok { $g->ok }

sub set {
bench_start('set');
    my ($self, $val_perc) = @_;

    kill_timeout $_ for list $self->_hide_timeouts;
    $self->_hide_timeouts([]);

    $self->_cur_target($val_perc);
    DEBUG and info 'going to', $self->_cur_target;
    $self->show;

    pushr $self->_hide_timeouts, timeout 1000, sub {
        $self->hide;
    };
bench_end_pr('set');
}

# Used for update+show or just show.

sub show {
    my ($self) = @_;
    $self->_aosd->show;

    my $c = $self->_cur_value;
    my $t = $self->_cur_target;

    my $do_update = 1;
    $do_update = 0 unless defined $c and defined $t;

    if (! $do_update) {
        $self->_aosd->update; # meaning, just show
        return;
    }

    my $delta = ($t - $c) / $NUM_STEPS;

    my $i = 0;
    while ($i++ < $NUM_STEPS) {
        if ($self->_do_stop) {
            $self->_do_stop(0);
            DEBUG and info 'external stop';
            last;
        }

            $self->_cur_value(
                $c + $delta * $i
            );
            DEBUG and info 'set to', $self->_cur_value;
        $self->_aosd->update;
    }
}

sub hide {
    my ($self) = @_;
    $self->_aosd->hide;
    $self->_aosd->update;
}

sub BUILD {
    my ($self, @args) = @_;

    if ($g->ok) {
        my $aosd = X11::Aosd->new;
        $self->_aosd($aosd);
    }
}

sub build {
    my ($self) = @_;

    my $aosd = $self->_aosd;

    my $tr = $self->transparency_type;

    $aosd->set_transparency(
        $tr eq 'composite' ? $g->transparency_composite :
        $tr eq 'fake' ? $g->transparency_fake :
        $tr eq 'none' ? $g->transparency_none :
        warreturn $g->transparency_none, 'Unknown transparency type:', BR $tr
    );

    $aosd->set_position_with_offset(
      $g->coordinate_center,
      $g->coordinate_center,
      # actually width then height XX
      $self->height, $self->width, 
      0 + $self->col * $self->spacing_x, 
      0 + $self->row * $self->spacing_y, 
    );

    $aosd->set_hide_upon_mouse_event(1);

    my $center_x = $self->width / 2;
    my $center_y = $self->height / 2;

    my @color1_decimal = color_to_decimal $self->color1;
    my @color2_decimal = color_to_decimal $self->color2;

    $aosd->set_renderer(sub {
        my ($cr) = @_;
        $cr->set_source_rgba (@color1_decimal, $self->opacity);
        $cr->set_line_width($self->stroke_width);

        my $val_perc = $self->_cur_value;
        my $angle = 2 * pi * $val_perc / 100;
        $angle = -.001 if $angle > 2 * pi;
        $cr->arc($center_x,$center_y, $self->radius1, 0, $angle);
        $cr->stroke;

# never stops XX
info 'rendering cur_val', $angle if DEBUG;

        $cr->set_source_rgba (@color2_decimal, $self->opacity);
        $cr->arc($center_x,$center_y, $self->radius2, 0, $angle);

        $cr->stroke;
    });
}

sub color_to_decimal {
    my ($col) = @_;
    state $hex_dig = qr, [a-f0-9] ,xi;
    strip_s $col;
    # actually, # is impossible (seen as comment in conf file)
    $col =~ m, ^ \#? ($hex_dig {3} | $hex_dig {6}) $ ,x;
    my $c = $1;
    if (not $c) {
        war "Invalid color:", BR $col;
        return 0,0,0;
    }
    # fff -> f0f0f0, check XX   
    if (length $c == 3) {
        my @s = split //, $c;
        @s = map { sprintf "%02x", 16 * hex } @s;
        $c = join '', @s;
    }

    my $rr = 1 / 255 * hex substr $c, 0, 2;
    my $gg = 1 / 255 * hex substr $c, 2, 2;
    my $bb = 1 / 255 * hex substr $c, 4, 2;

    $rr, $gg, $bb
}

# e.g., immediately process next key stroke.
sub stop_osd {
    my ($self) = @_;
    $self->_do_stop(1);
}

sub aosd_update {
    my ($self) = @_;
    my $a = $self->_aosd or war, 
        return;
    $a->update;
}


1;
