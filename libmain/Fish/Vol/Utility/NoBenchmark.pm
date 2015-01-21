package Fish::Vol::Utility::NoBenchmark;

use 5.18.0;

BEGIN {
    use base 'Exporter';
    our @EXPORT = qw, bench_start bench_end bench_end_pr bench_pr ,;
}

# all subs no-ops
sub bench_start {}
sub bench_end {}
sub bench_pr {}
sub bench_end_pr {}

1;
