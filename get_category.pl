#!/usr/bin/perl -w

=head1 NAME

get_category.pl - Retrieve all the images in a category.

=head1 SYNOPSIS

    get_category.pl "Category:Files from the Biodiversity Heritage Library"

Returns the names of all the images in that category.

    get_category.pl -r "Category:Files from the Biodiversity Heritage Library"

Returns the names of all the images from that category, and all subcategories.

=head1 OUTPUT

Should be a list of newline-separated

=cut

use v5.12;

use strict;
use warnings;

use MediaWiki::API;
use RDF::Helper;
use URI::Escape;

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

            # Don't recurse more than 3 levels!
            $recurse_count++;
            if($recurse_count > 3) {
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
                max => 100,
                hook => sub {
                    my ($sublist) = @_;

                    foreach my $ref (@$sublist) {
                        my $title = $ref->{'title'};

                        if($title =~ /^Category:(.+)$/) {
                            say STDERR "${tablevel}Entering category '$1'";
                            list_category($1, "$tablevel\t");
                            $count_categories++;
                        } else {
                            say $tablevel . $title;
                            $count_files++;
                        }
                    }
                }
            });

            $recurse_count--;
        }
    }

    default {
        die "Could not understand url: '$url'";
    }
}

say STDERR "$count_files files from " . ($count_categories == 1 ? "a single category" : "$count_categories categories") . " returned.";
