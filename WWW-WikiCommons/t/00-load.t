#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'WWW::WikiCommons' ) || print "Bail out!\n";
}

diag( "Testing WWW::WikiCommons $WWW::WikiCommons::VERSION, Perl $], $^X" );
