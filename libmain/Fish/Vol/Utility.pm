package Fish::Vol::Utility;

use 5.18.0;

BEGIN { 
    use base 'Exporter';
    our @EXPORT = qw, 
        timeout kill_timeout 
        check_type
    ,;
}

use Fish::Utility;

sub timeout {
    my ($ms, $sub) = @_;

    Glib::Timeout->add($ms, $sub)
}

sub kill_timeout(_) {
    # e.g. as returned by Timeout->add.
    my ($tag) = @_;

    Glib::Source->remove($tag)
}

sub check_type(_) {
    my ($type) = @_;
    sub { 
        my $err = sprintf "Property doesn't meet type constraint (wanted %s, got %%s)", Y $type;
        $_[0] // ierror sprintf $err, BR 'undef';
        my $ref = ref $_[0];
        $ref eq $type or 
            ierror sprintf $err, BR $ref;
    }
}


1;
