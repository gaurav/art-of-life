#!/usr/bin/perl -w

use v5.12;

use strict;
use warnings;

use MediaWiki::API;
use RDF::Helper;
use URI::Escape;
use Parse::RecDescent;

# Figure out what we need to extract.
my $name_or_url = $ARGV[0];
my $url;

if(not defined $name_or_url) {
    die "Please provide a filename or URL at the command line!";
}

if($name_or_url =~ /^http/) {
    $url = $name_or_url;
} else {

    if($name_or_url =~ /^File\:(.*)$/) {
        $name_or_url = uri_escape_utf8($1);
        $url = "http://commons.wikimedia.org/wiki/File:$name_or_url";
    } else {
        $name_or_url = uri_escape_utf8($name_or_url);
        $url = "http://commons.wikimedia.org/wiki/File:$name_or_url";
    }
}

# Set up the MediaWiki API.
my $mw = MediaWiki::API->new({
    api_url => 'http://commons.wikimedia.org/w/api.php',
    use_http_get => 1,      # We're mostly retrieving stuff
});

# Retrieve the appropriate page.
my $page;

given($url) {
    when(qr{^http://commons\.wikimedia\.org/w/index\.php\?.*&oldid=(\d+)}) {
        die "Sorry, looking up a page by revid is not yet supported!";
    }

    when(qr{^http://commons\.wikimedia\.org/wiki/File:(.*)$}) {
        $page = $mw->get_page({'title' => "File:" . uri_unescape($1)});
    }

    default {
        die "Could not understand url: '$url'";
    }
}

my $content = $page->{'*'};

# Parse out the template structure on this page.
$::RD_ERRORS = 1;
$::RD_HINT = 1;
$::RD_TRACE = 1;
my $parser = Parse::RecDescent->new(q#

    startrule: block(s?) {[@item]} | <error>
    block: template_with_param | template_without_param | non_template_text | <error>
    template_without_param: /\s*{{\s*/s template_name /\s*}}\s*/s {[$item[2]]} | <error>
    template_with_param: /\s*{{\s*/s template_name /\s*\|\s*/ block(s?) /\s*}}\s*/s {[$item[2], $item[4]]} | <error>
    template_name: /(?:(?!{{)(?!}})(?!\|).)+/s
    non_template_text: /(?:(?!{{)(?!}}).)+/s
#);

use Data::Dumper;
my $results = $parser->startrule($content);
say "<<" . Dumper($results) . ">>";

1; 
