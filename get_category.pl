#!/usr/bin/perl -w

=head1 NAME

get_category.pl - Retrieve all the images in a category.

=head1 SYNOPSIS

    get_category.pl "Category:Files from the Biodiversity Heritage Library"

Returns the names of all the images in that category, and in subcategories
up to $RECURSION_LIMIT.

=head1 OUTPUT

STDOUT has a list of newline-separated filenames. STDERR has information 
about which categories were accessed. STDOUT has tabs to clarify which
category each file is from, but 

=head1 LIMIT

At the moment, the limit is up to 100,000 images. There is currently
no test to see if we've hit this limit.

=cut

use v5.12;

use strict;
use warnings;

use MediaWiki::API;
use RDF::Helper;
use URI::Escape;

# Constants.
my $RECURSION_LIMIT = 5;
my $REQUEST_LIMIT = 1000;       # x 100: each request can retrieve 100 entries.
                                # The MediaWiki API will make $REQUEST_LIMIT
                                # separate requests.

# utf8 output
binmode STDOUT, ':utf8';
binmode STDERR, ':utf8';

# Figure out what we need to extract.
my $name_or_url = $ARGV[0];
my $url;

if(not defined $name_or_url) {
    die "Please provide a filename or URL at the command line!";
}

if($name_or_url =~ /^http/) {
    $url = $name_or_url;
} else {

    if($name_or_url =~ /^Category\:(.*)$/) {
        $name_or_url = uri_escape_utf8($1);
        $url = "http://commons.wikimedia.org/wiki/Category:$name_or_url";
    } else {
        $name_or_url = uri_escape_utf8($name_or_url);
        $url = "http://commons.wikimedia.org/wiki/Category:$name_or_url";
    }
}

# Set up the MediaWiki API.
my $mw = MediaWiki::API->new({
    api_url => 'http://commons.wikimedia.org/w/api.php',
    use_http_get => 1,      # We're mostly retrieving stuff
});

# Retrieve the appropriate category.
my $list;
my $count_files = 0;
my $count_categories = 1;
my $recurse_count = 0;

given($url) {
    when(qr{^http://commons\.wikimedia\.org/w/index\.php\?.*&oldid=(\d+)}) {
        die "Sorry, looking up a category by pageid is not yet supported!";
    }

    when(qr{^http://commons\.wikimedia\.org/wiki/Category:(.*)$}) {
        list_category($1);

        sub list_category {
            my $category_name = shift;
            my $tablevel = shift;

            $tablevel = "" unless defined $tablevel;

            # Don't recurse more than $RECURSION_LIMIT levels!
            $recurse_count++;
            if($recurse_count >= $RECURSION_LIMIT) {
                say STDERR "${tablevel}Bailing out; recursion limit hit.";
            }

            $list = $mw->list({
                action => 'query',
                list => 'categorymembers',
                cmtitle => "Category:" . uri_unescape($1),
                cmlimit => 100,
                # cmtype => 'file', -- ignored when looking by timestamp.
                cmsort => 'timestamp'
            }, { 
                max => $REQUEST_LIMIT,
                hook => sub {
                    my ($sublist) = @_;

                    foreach my $ref (@$sublist) {
                        my $title = $ref->{'title'};

                        if($title =~ /^Category:(.+)$/) {
                            say STDERR "${tablevel}Entering category '$1'";
                            list_category($1, "$tablevel\t");
                            $count_categories++;
                        } else {

                            # If STDOUT is a terminal, write tabs so the output
                            # is pretty; otherwise, just print it one line at
                            # a time.
                            if(-t STDOUT) {
                                say $tablevel . $title;
                            } else {
                                say $title;
                            }

                            $count_files++;
                        }
                    }
                }
            }) || die $mw->{error}->{code} . ': ' . $mw->{error}->{details};

            $recurse_count--;
        }
    }

    default {
        die "Could not understand url: '$url'";
    }
}

say STDERR "$count_files files from " . ($count_categories == 1 ? "a single category" : "$count_categories categories") . " returned.";
