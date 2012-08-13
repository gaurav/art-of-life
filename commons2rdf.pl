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

my $HARD_LIMIT = 50;

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

# Set up the MediaWiki API.
my $mw = MediaWiki::API->new({
    api_url => 'http://commons.wikimedia.org/w/api.php',
    use_http_get => 1,      # We're mostly retrieving stuff
});

# Store templates into a special data structure.
my %templates;

while(<>) {
# Figure out what we need to extract.
    chomp;

    $HARD_LIMIT--;
    last if $HARD_LIMIT <= 0;

    my $name_or_url = $_;
    my $url;

    if(not defined $name_or_url) {
        die "Please provide a filename or URL at STDIN!";
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

    process_page($url);
}

say $rdf->serialize(format => 'rdfxml');
#say $rdf->serialize(format => 'turtle');
exit 0;

sub process_page {
# Retrieve the appropriate page.
    my $url = shift;
    my $page;

    say STDERR "Processing URL '$url'.";

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
        block: template_with_param | template_without_param | non_template_text | link | <error>
        template_without_param: /\s*{{\s*/s template_name /\s*}}\s*/s 
            {['Template:' . $item[2] ]} 
            | <error>
        template_with_param: /\s*{{\s*/s template_name /\s*\|\s*/ block(s?) /\s*}}\s*/s 
            {['Template:' . $item[2], $item[4]]}
            | <error>
        template_name: /(?:(?!{{)(?!}})(?!\|).)+/s
        non_template_text: /(?:(?!{{)(?!}})(?!\[\[)(?!\]\]).)+/s

        link: link_with_name | link_without_name | <error>
        link_without_name: "[[" non_link_text "|" non_link_text "]]"
            {['Template:template_links', [$item[2], $item[4]]] }
            | <error>
        link_with_name: "[[" non_link_text "]]" 
            {['Template:template_links', [$item[2]]] }
            | <error>
        non_link_text: /(?:(?!\[\[)(?!\]\])(?!\|).)+/s
#);

    use Data::Dumper;
    my $whole_parsetree = $parser->startrule($content);
    die "Unable to parse!" unless defined $whole_parsetree;

#say Dumper($whole_parsetree);
#exit 0;

    # Reset templates.
    %templates = ();

# The following code was initially written to try to make sense
# of the entire parse tree. I have since modified it to just capture
# templates which don't have templates inside them.
    collect_template_info(\@{$whole_parsetree->[1]}, undef, 0);
    sub collect_template_info {
        my ($parsetree, $current_template, $flag_in_template) = @_;
        my @parsetree = @$parsetree;

        # say "collect_template_info:$parsetree";

        for(my $x = 0; $x <= $#parsetree; $x++) {
            my $prevnode =  $parsetree[$x-1];
            my $node =      $parsetree[$x];
            my $nextnode =  $parsetree[$x+1];

            if(ref($node) eq 'ARRAY') {
                collect_template_info($node, $current_template, $flag_in_template);
            } else {
                # print "Examining node <<$node>>";

                if($node =~ /^Template:/) {
                    chomp $node;

                    if(ref($nextnode) eq 'ARRAY') {
                        # print ": a node template!";

                        my $new_template = {};
                        collect_template_info($nextnode, $new_template, 1);
                        add_to_hash_of_lists($current_template, 'contains_templates', $new_template)
                            if defined $current_template;
                        add_to_hash_of_lists(\%templates, $node, $new_template);
                        $new_template = undef;

                        $x++;   # Skip next node.
                    } else {
                        # print ": a simple template!";
                        add_to_hash_of_lists($current_template, 'contains_templates', $node)
                            if defined $current_template;
                        add_to_hash_of_lists(\%templates, $node, 1);
                    }
                } elsif($flag_in_template) {
                    my @attributes;

                    #add_to_hash_of_lists($current_template, 'contains_text', $node)
                    #    if defined $current_template;

                    if($node =~ /\|/) {
                        @attributes = split(/\s*\|\s*/, $node);
                    } else {
                        @attributes = ($node);
                    }

                    shift @attributes   if (defined($prevnode) and (ref($prevnode) eq 'ARRAY'));
                    pop @attributes     if (defined($nextnode) and (ref($nextnode) eq 'ARRAY'));

                    foreach my $attribute (@attributes) {
                        next if $attribute =~ /^\s*$/;

                        my $key;
                        my $value;
                        if($attribute =~ /^\s*(\w+)\s*=\s*(.*)\s*$/) {
                            $key = $1;
                            $value = $2;
                        } else {
                            $key = $attribute;
                        }

                        if(defined $value) {
                            $current_template->{lc($key)} = $value;

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
                    # add_to_hash_of_lists($current_template, 'contains_text', $node);
                }
            }

            # print "\n";
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

#    say Dumper(\%templates);

# Information template.
    my $information;
    $information = $templates{'Template:Information Art of Life'};
    $information = $templates{'Template:Information'} unless defined $information;
    $information = [{}] unless defined $information;
    $information = [{}] unless (1 == (scalar @$information));

    $information = $information->[0];

    $rdf->assert_literal($url, 'dc:title', $information->{'title'}) 
        if(exists $information->{'title'});
# TODO: Should we duplicate the title into rdfs:label?

    $rdf->assert_literal($url, 'dc:source', $information->{'source'}) 
        if(exists $information->{'source'});

    $rdf->assert_literal($url, 'dc:description', $information->{'description'}) 
        if(exists $information->{'description'});

# BHL URL.
    my $template_bhl = $templates{'Template:Biodiversity Heritage Library'};
    if ((defined $template_bhl) and (1 == scalar(@$template_bhl))) {
        $rdf->assert_resource($url, 'dc:source', $template_bhl->[0]{'url'})
            if(exists $template_bhl->[0]{'url'});
    }

# Add categories.
    if(exists $templates{'Template:template_links'}) {
        my @page_links = @{$templates{'Template:template_links'}};
        foreach my $page_url (@page_links) {
            my $page = $page_url->{'arg_1'};
            my $title = $page_url->{'arg_2'} // $page;

            if($page =~ /^Category:(.*)$/) {
                my $qname = $1;
                $qname =~ s/\s/_/g;
                $rdf->assert_resource($url, 'dc:subject', "wccat:$qname");
                    # TODO: *Very* approximate!
            } elsif($page =~ /^:Category:(.*)$/) {
                # Links to categories
            } elsif($page =~ /^:(?:w:)?(?:en:)?(.*)$/) {
                # Links to enwiki
            }
        }
    }
}


1; 
