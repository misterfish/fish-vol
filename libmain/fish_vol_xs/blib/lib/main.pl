use 5.18.0;

BEGIN {
    push @INC, 'lib';
}

use strict;
use warnings;

# Adds blib/* dirs to INC.
use ExtUtils::testlib;

use xs_asound;

xs_init();

while (<STDIN>) {
    chomp;
    xs_set($_);
}

xs_finish();
