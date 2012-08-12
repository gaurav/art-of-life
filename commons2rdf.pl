#!/usr/bin/perl -w

=head1 NAME

commons2rdf.pl - 

=head1 SYNOPSIS

    commons2rdf.pl "http://commons.wikimedia.org/wiki/File:Greenwaxbill.jpg"
    commons2rdf.pl "File:Orangutan (illustration).jpg"
    commons2rdf.pl "Simonkai.jpg"

=cut

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
$::RD_HINT = 0;
my $parser = Parse::RecDescent->new(q#

    startrule: block(s?) {[@item]} | <error>
    block: template_with_param | template_without_param | non_template_text | <error>
    template_without_param: /\s*{{\s*/s template_name /\s*}}\s*/s {'Template:' . $item[2]} | <error>
    template_with_param: /\s*{{\s*/s template_name /\s*\|\s*/ block(s?) /\s*}}\s*/s 
        {['Template:' . $item[2], $item[4]]}
        | <error>
    template_name: /(?:(?!{{)(?!}})(?!\|).)+/s
    non_template_text: /(?:(?!{{)(?!}}).)+/s
#);

use Data::Dumper;
my $whole_parsetree = $parser->startrule($content);
die "Unable to parse!" unless defined $whole_parsetree;

#say Dumper($whole_parsetree);
#exit 0;

# Store templates into a special data structure.
my %templates;

# If I had a degree in computer science, I would know the
# better way of coding the following function. Unfortunately,
# I don't.
collect_template_info(\@{$whole_parsetree->[1]}, undef, 0);
sub collect_template_info {
    my ($parsetree, $current_template, $flag_in_template) = @_;
    my @parsetree = @$parsetree;

    say "collect_template_info:$parsetree";

    for(my $x = 0; $x <= $#parsetree; $x++) {
        my $node = $parsetree[$x];
        my $nextnode = $parsetree[$x+1];

        if(ref($node) eq 'ARRAY') {
            collect_template_info($node, $current_template, 0);
        } else {
            print "Examining node <<$node>>";
            print " (current template: " . $current_template->{'template_name'} . ")"
                if defined $current_template;

            if($node =~ /^Template:/) {
                if(ref($nextnode) eq 'ARRAY') {
                    print ": a node template!";

                    my $new_template = {
                        'template_name' => $node,
                        'template_arrayref' => $nextnode
                    };
                    collect_template_info($nextnode, $new_template, 1);
                    add_to_hash_of_lists($current_template, 'contains_templates', $new_template)
                        if defined $current_template;
                    add_to_hash_of_lists(\%templates, $node, $new_template);
                    $new_template = undef;

                    $x++;   # Skip next node.
                } else {
                    print ": a simple template!";
                    add_to_hash_of_lists($current_template, 'contains_templates', $node)
                        if defined $current_template;
                    add_to_hash_of_lists(\%templates, $node, 1);
                }
            } elsif($flag_in_template) {
                my @attributes;

                add_to_hash_of_lists($current_template, 'contains_text', $node)
                    if defined $current_template;

                if($node =~ /\|/) {
                    @attributes = split(/\s*\|\s*/, $node);
                } else {
                    @attributes = ($node);
                }

                foreach my $attribute (@attributes) {
                    next if $attribute =~ /^\s*$/;

                    my ($key, $value) = split(/\s*=\s*/, $attribute);

                    if(defined $value) {
                        $current_template->{$key} = $value;
                    } elsif(not defined $key) {
                        die "No key/value on splitting '$attribute'.";
                    } else {
                        my $last_number = $current_template->{'last_number'};
                        $last_number = 1 if not defined $last_number;

                        $current_template->{"arg_$last_number"} = $key;
                        $last_number++;

                        $current_template->{'last_number'} = $last_number;
                    }
                }
            } else {
                add_to_hash_of_lists($current_template, 'contains_text', $node);
            }
        }

        print "\n";
    }
}

sub add_to_hash_of_lists {
    my ($hash, $key, $value) = @_;

    if (exists $hash->{$key}) {
        push @{$hash->{$key}}, $value;
    } else {
        $hash->{$key} = [$value];
    }
}

say Dumper(\%templates);

# Convert the parse tree into an RDF file.
use RDF::Helper;
use RDF::Helper::Constants qw(:rdf :rdfs :dc);

my $rdf = RDF::Helper->new(
    BaseInterface => 'RDF::Trine',
    namespaces => {
        'rdf' =>    RDF_NS,
        'rdfs' =>   RDFS_NS,
        'dc' =>     DC_NS,
        'wcfile' => 'http://commons.wikimedia.org/wiki/File:',
        'wctmpl' => 'http://commons.wikimedia.org/wiki/Template:',
        'wccat' =>  'http://commons.wikimedia.org/wiki/Category:'
    },
    ExpandQNames => 1
);

# Extract fields!
sub extract_information_field {
    my ($fieldname) = @_;

    
}

# say $rdf->serialize(format => 'rdfxml');
say $rdf->serialize(format => 'turtle');

1; 
