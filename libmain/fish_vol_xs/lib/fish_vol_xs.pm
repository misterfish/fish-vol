package fish_vol_xs;

use 5.018001;
use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);

our @EXPORT_OK = qw, 
    xs_init 
    xs_set xs_set_rel
    xs_finish xs_get
    xs_handle_event
    xs_update
,;

our $VERSION = '0.01';

require XSLoader;
XSLoader::load('fish_vol_xs', $VERSION);

# Preloaded methods go here.

1;
__END__

=head1 NAME

fish_vol_xs - Perl extension for blah blah blah

=head1 SYNOPSIS

  use fish_vol_xs;

=head1 DESCRIPTION

=head2 EXPORT

=head1 SEE ALSO

=head1 AUTHOR

=head1 COPYRIGHT AND LICENSE

=cut
