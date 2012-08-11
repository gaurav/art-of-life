use 5.006;
use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'WWW::WikiCommons',
    license             => 'perl',
    dist_author         => q{Gaurav Vaidya <gaurav@ggvaidya.com>},
    dist_version_from   => 'lib/WWW/WikiCommons.pm',
    build_requires => {
        'Test::More' => 0,
    },
    requires => {
        'perl' => 5.006,
    },
    add_to_cleanup      => [ 'WWW-WikiCommons-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
