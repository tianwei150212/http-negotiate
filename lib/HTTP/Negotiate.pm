# $Id: Negotiate.pm,v 1.1 1996/03/05 10:45:52 aas Exp $
#

package HTTP::Negotiate;

$VERSION = sprintf("%d.%02d", q$Revision: 1.1 $ =~ /(\d+)\.(\d+)/);
sub Version { $VERSION; }

require 5.002;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(choose);

require HTTP::Headers;

$DEBUG = 0;

sub choose ($;$)
{
    my($variants, $request) = @_;
    my(%accept);

    unless (defined $request) {
	# Create a request object from the CGI envirionment variables
	$request = new HTTP::Headers;
	$request->header('Accept', $ENV{HTTP_ACCEPT})
	  if $ENV{HTTP_ACCEPT};
	$request->header('Accept-Charset', $ENV{HTTP_ACCEPT_CHARSET})
	  if $ENV{HTTP_ACCEPT_CHARSET};
	$request->header('Accept-Encoding', $ENV{HTTP_ACCEPT_ENCODING})
	  if $ENV{HTTP_ACCEPT_ENCODING};
	$request->header('Accept-Language', $ENV{HTTP_ACCEPT_LANGUAGE})
	  if $ENV{HTTP_ACCEPT_LANGUAGE};
    }

    # Get all Accept values from the request.  Build a hash initialized
    # like this:
    #
    #   %accept = ( type =>     { 'audio/*'     => { q => 0.2, mbx => 20000 },
    #                             'audio/basic' => { q => 1 },
    #                           },
    #               language => { 'no'          => { q => 1 },
    #                           }
    #             );

    $request->scan(sub {
	my($key, $val) = @_;
	return unless $key =~ s/^Accept-?//;
	my $type = lc $key;
	$type = "type" unless length $key;
	$val =~ s/\s+//g;
	my $name;
	for $name (split(/,/, $val)) {
	    $name =~ s/;(.*)//;
	    my(%param, $param);
	    for $param (split(/;/, $1)) {
		my ($pk, $pv) = split(/=/, $param, 2);
		$param{$pk} = $pv;
	    }
	    $name = lc $name;
	    if (defined $param{'q'}) {
		$param{'q'} = 1 if $param{'q'} > 1;
		$param{'q'} = 0 if $param{'q'} < 0;
	    } else {
		$param{'q'} = 1;
	    }
	    
	    $param{'q'} = 1 unless defined $param{'q'};
	    $accept{$type}{$name} = \%param;
	}
    });

    # Check if any of the variants specify a language, because this
    # influence how we treat those without (they default to 0.5
    # istead of 1).
    my $any_lang = 0;
    for $var (@$variants) {
	if ($var->[5]) {
	    $any_lang = 1;
	    last;
	}
    }

    if ($DEBUG) {
	print "Netgotiantion parameters in the request\n";
	for $type (keys %accept) {
	    print " $type:\n";
	    for $name (keys %{$accept{$type}}) {
		print "    $name\n";
		for $pv (keys %{$accept{$type}{$name}}) {
		    print "      $pv = $accept{$type}{$name}{$pv}\n";
		}
	    }
	}
    }

    my @Q = ();  # This is where we collect the results of the
                 # quality calcualtions

    # Calculate quality for all the variant's that are available.
    for (@$variants) {
	my($id, $qs, $ct, $enc, $cs, $lang, $bs) = @$_;
	$qs = 1 unless defined $qs;
	$bs = 0 unless defined $bs;
	if ($DEBUG) {
	    print "\nEvaluating $id ($ct)\n";
	    printf "  qs   = %.3f\n", $qs;
	    print  "  enc  = $enc\n"  if $enc && !ref($enc);
	    print  "  enc  = @$enc\n" if $enc && ref($enc);
	    print  "  cs   = $cs\n"   if $cs;
	    print  "  lang = $lang\n" if $lang;
	    print  "  bs   = $bs\n"   if $bs;
	}

	# Calculate encoding quality
	my $qe = 1;
	# If the variant has no assignes Content-Encoding, or if no
	# Accept-Encoding field is present, then the value assigned
	# is "qe=1".  If *all* of the variant's content encoddings
	# are listed in the Accept-Encoding field, then the value
	# assigned is "qw=1".  If *any* of the variant's content
	# encodings are not listed in the provided Accept-Encoding
	# field, then the value assigned is "qe=0"
	if (exists $accept{'encoding'} && $enc) {
	    my @enc = ref($enc) ? @$enc : ($enc);
	    for (@enc) {
		print "Is encoding $_ accepted? " if $DEBUG;
		unless(exists $accept{'encoding'}{$_}) {
		    print "no\n" if $DEBUG;
		    $qe = 0;
		    last;
		} else {
		    print "yes\n" if $DEBUG;
		}
	    }
	}

	# Calculate charset quality
	my $qc  = 1;
	# If the variant's media-type has not charset parameter,
	# or the variant's charset is US-ASCII, or if no Accept-Charset
	# field is present, then the value assigned is "qc=1".  If the
	# variant�s charset is listed in the Accept-Charset field,
	# then the value assigned is "qc=1.  Otherwise, if the variant's
	# charset is not listed in the provided Accept-Encoding field,
	# then the value assigned is "qc=0".
	if (exists $accept{'charset'} && $cs && $cs ne 'us-ascii' ) {
	    $qc = 0 unless $accept{'charset'}{$cs};
	}

	# Calculate language quality
	my $ql  = 1;
	if ($lang && exists $accept{'language'}) {
	    my @lang = ref($lang) ? @$lang : ($lang);
	    # If any of the variant's content languages are listed
	    # in the Accept-Language field, the the value assigned is
	    # the maximus of the "q" paramet values for thos language
	    # tags.
	    my $q = undef;
	    for (@lang) {
		next unless exists $accept{'language'}{$_};
		my $this_q = $accept{'language'}{$_}{'q'};
		$q = $this_q unless defined $q;
		$q = $this_q if $this_q > $q;
	    }
	    unless (defined $q) {
		# If there was no exact match and at least one of
		# the Accept-Language field values is a complete
		# subtag prefix of the content language tag(s), then
		# the "q" parameter value of the largest matching
		# prefix is used.
		my $selected = undef;
		for $al (keys %{ $accept{'language'} }) {
		    if (substr($lang, 0, length($al)) eq $al) {
			$selected = $al unless defined $selected;
			$selected = $al if length($al) > length($selected);
		    }
		}
		$q = $accept{'language'}{$selected}{'q'} if $selected;
		
		# If none of the variant's content language tags or
		# tag prefixes are listed in the provided
		# Accept-Language field, then the value assigned
		# is "ql=0.001"
		$q = 0.001 unless defined $q;
	    }
	    $ql = $q;
	} else {
	    $ql = 0.5 if $any_lang && exists $accept{'language'};
	}
	
	my $q   = 1;
	my $mbx = undef;
	# If no Accept field is given, then the value assigned is "q=1".
	# If at least one listed media range matches the variant's media
	# type, then the "q" parameter value assigned to the most specific
	# of those matched is used (e.g. "text/html;version=3.0" is more
	# specific than "text/html", which is more specific than "text/*",
	# which in turn is more specific than "*/*"). If not media range
	# in the provided Accept field matches the variant's media type,
	# then the value assigned is "q=0".
	if (exists $accept{'type'} && $ct) {
	    # First we clean up our content-type
	    $ct =~ s/\s+//g;
	    $ct =~ s/;(.*)//;
	    my($type, $subtype) = split("/", $ct, 2);
	    my %param = ();
	    for $param (split(/;/, $1)) {
		my($pk,$pv) = split(/=/, $param, 2);
		$param{$pk} = $pv;
	    }

	    my $sel_q = undef;
	    my $sel_mbx = undef;
	    my $sel_specificness = 0;

	    ACCEPT_TYPE:
	    for $at (keys %{ $accept{'type'} }) {
		print "Consider $at...\n" if $DEBUG;
		my($at_type, $at_subtype) = split("/", $at, 2);
		# Is it a match on the type
		next if $at_type    ne '*' && $at_type    ne $type;
		next if $at_subtype ne '*' && $at_subtype ne $subtype;
		my $specificness = 0;
		$specificness++ if $at_type ne '*';
		$specificness++ if $at_subtype ne '*';
		# Let's see if content-type parameters also match
		while (($pk, $pv) = each %param) {
		    print "Check if $pk = $pv is true\n" if $DEBUG;
		    next unless exists $accept{'type'}{$at}{$pk};
		    next ACCEPT_TYPE
		      unless $accept{'type'}{$at}{$pk} eq $pv;
		    print "yes it is!!\n" if $DEBUG;
		    $specificness++;
		}
		print "Hurray, type match with specificness = $specificness\n"
		  if $DEBUG;

		if (!defined($sel_q) || $sel_specificness < $specificness) {
		    $sel_q   = $accept{'type'}{$at}{'q'};
		    $sel_mbx = $accept{'type'}{$at}{'mbx'};
		    $sel_specificness = $specificness;
		}
	    }
	    $q   = $sel_q || 0;
	    $mbx = $sel_mbx;
	}
	
	my $Q;
	if (!defined($mbx) || $mbx >= $bs) {
	    $Q = $qs * $qe * $qc * $ql * $q;
	} else {
	    $Q = 0;
	    print "Variant's size is too large ==> Q=0\n" if $DEBUG;
	}

	if ($DEBUG) {
	    $mbx = "undef" unless defined $mbx;
	    printf "Q=%.3f", $Q;
	    print "  (q=$q, mbx=$mbx, qe=$qe, qc=$qc, ql=$ql, qs=$qs)\n";
	}

	push(@Q, [$id, $Q, $bs]);
    }


    @Q = sort { $b->[1] <=> $a->[1] || $a->[2] <=> $b->[2] } @Q;

    return @Q if wantarray;
    return undef unless @Q;
    return undef if $Q[0][1] == 0;
    $Q[0][0];
}

1;

__END__


=head1 NAME

choose - choose a variant of a document to serve (HTTP content negotiation)

=head1 SYNPSIS

 use HTTP::Negotiate;

 #  ID       QS     Content-Type   Encoding Char-Set        Lang   Size
 $variants = 
  [['var1',  1.000, 'text/html',   undef,   'iso-8859-1',   'en',   3000],
   ['var2',  0.950, 'text/plain',  'gzip',  'us-ascii',     'no',    400],
   ['var3',  0.3,   'image/gif',   undef,   undef,          undef, 43555],
 ]

 @prefered = choose($variants, $request_headers);
 $the_one  = choose($variants);

=head1 DESCRIPTION

This module provide a complete implementation of the HTTP content
negotiation algorithm specified in draft-ietf-http-v11-spec-00.ps
chapter 12.  Content negotiation allows for selection of a preferred
content representation based upon attributes of the negotiable
variants and the value of Accept* header fields in the request.

The variants are ordered by preference by calling the function
choose().

The first parameter is the variants that we can choose among.  The
variants are prepresented by a reference to an array.  Each element in
this array is an array with the values [$id, $qs, $content_type,
$content_encoding, $charset, $content_language, $content_length].
The meaning of these values are described below. The
$content_encoding and $content_language can be either a single scalar
value or an array reference if there are many values.

The second optional parameter is a reference to the request headers.
This is used to look for "Accept*" headers.  You can pass a reference
to either a HTTP::Request or a HTTP::Headers object.  If this
parameter is missing, then the accept specification is initialized
from the CGI envirionment variables HTTP_ACCEPT, HTTP_ACCEPT_CHARSET,
HTTP_ACCEPT_ENCODING and HTTP_ACCEPT_LANGUAGE.

In array context choose() returns a list of variant identifier,
calculated quality pairs.  The values are sorted by quality, highest
quality first.  If the calculated quality is the same for two
variants, then they are sorted by size (smallest first). E.g.:

  (['var1' => 1], ['var2', 0.3], ['var3' => 0]);

Note that any zero quality variants are included in the list even if
these should never be served to the client.

In scalar context it returns the identifier of the variant with the
highest score or undef in none have non-zero quality.

If the $HTTP::Negotiate::DEBUG variable is set to TRUE, then a lot of
noise on STDOUT is generated during evaluation of choose().

=head1 VARIANTS

A variant is described by and list of the following values.  If the
attribute does not make sence or is unknown for a variant, then use
undef instead.

=over 3

=item identifier

This is just some string that you use as a name for the variant.  The
identifier of the preferred variant is returned by choose().

=item qs

This is a number between 0.000 and 1.000 that describes the "source
quality".  This is what draft-ietf-http-v11-spec-00.ps says about this
value:

Source quality is measured by the content provider as representing the
amount of degradation from the original source.  For example, a
picture in JPEG from would have a lower qs when translated to the XBM
format, and much lower qs when translated to an ASCII-art
representation.  Note, however, that this is a function of the source
- an original piece of ASCII-art may degrade in quality if it is
captured in JPEG form.  The eq values should be assigned to each
variant by the content provider; if no qs value has been assigned, the
default is generally "qs=1".

=item content-type

This is the media type of the variant.  The media type does not
include a charset attribute, but might contain other parameters.
Examples are:

  text/html
  text/html;version=2.0
  text/plain
  image/gif
  image/jpg

=item content-encoding

This is one or more content encodings that has been applied to the
variant.  The content encoding is generally used as a modifier to the
content media type.  The most common content encodings are:

  gzip
  compress

=item content-charset

This is the charater set used when the variant contains textual
content.  The charset value should generally be undef or one of these:

  us-ascii
  iso-8859-1 ... iso-8859-9
  iso-2022-jp
  iso-2022-jp-2
  iso-2022-kr
  unicode-1-1
  unicode-1-1-utf-7
  unicode-1-1-utf-8

=item content-language

This describes one or more languages that are used in the variant.  A
language is in this context a natural language spoken, written, or
otherwise conveyed by human beings for communication of information to
other human beings.  Computer languages are explicitly excluded.

The language tags are the same as those defined by RFC-1766.  Examples
are:

  no               Norwegian
  en               International english
  en-US            US english
  en-cockney

=item content-length

This is the number of bytes used to represent the content.

=back

=head1 ACCEPT HEADERS

The following Accept* headers can be used for descibing content
preferences in a request (This description is just an edited extract
from draft-ietf-http-v11-spec-00.ps):

=over 3

=item Accept

This header can be used to indicate a list of media ranges which are
acceptable as a repose to the request.  The "*" character is used to
group media types into ranges, with "*/*" indicating all media types
and "type/*" indicating all sybtypes of that type.

The parameter q is used to indicate the quality factor, which
represents the user's preference for that range of media types.  The
parameter mxb gives the maximum acceptable size of the response
content. The default values are: q=1 and mbx=infinity. If no Accept
header is present, then the client accepts all media types with q=1.

For example:

  Accept: audio/*;q=0.2, audio/basic

would mean: "I prefer audio/basic, but send me any audio type if it is
the best available after en 80% mark-down in quality"


=item Accept-Charset

Used to indicate what character sets are acceptable for the response.
The "us-ascii" character set is assumed to be acceptable for all user
agents.  If not Accept-Charset field is given, the default is that any
charset is acceptable.  Example:

  Accept-Charset: iso-8859-1, unicode-1-1


=item Accept-Encoding

Restricts the Content-Encoding values which are acceptable in the
repsponse.  If no Accept-Encoding field is present, the server may
assume that the client will accept any content encoding.  An empty
Accept-Encoding means that no content encoding is acceptable.  Example:

  Accept-Encoding: compress, gzip


=item Accept-Language

This field is similiar to Accept, but restrict the set of natural
languages that are preferred as a response.  Each language may be
given an assosiated quality value which represents an estimate of the
user's comprehension of that langugage.  For example:

  Accept-Language: no, en-gb;q=0.8, de;q=0.55

would mean: "I prefer Norwegian, but will accept British English (with
80% comprehension) or German (with 55% comprehension).

=back


=head1 AUTHOR

Gisle Aas <aas@sn.no>

=cut