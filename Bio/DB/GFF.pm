=head1 NAME

Bio::DB::GFF -- Storage and retrieval of sequence annotation data

=head1 SYNOPSIS

  use Bio::DB::GFF;

  # Open the sequence database
  my $db      = Bio::DB::GFF->new( -adaptor => 'dbi::mysqlopt',
                                   -dsn     => 'dbi:mysql:elegans',
				   -fasta   => '/usr/local/fasta_files'
				 );

  # fetch a 1 megabase segment of sequence starting at landmark "ZK909"
  my $segment = $db->segment('ZK909', 1 => 1000000);

  # pull out all transcript features
  my @transcripts = $segment->features('transcript');

  # for each transcript, total the length of the introns
  my %totals;
  for my $t (@transcripts) {
    my @introns = $t->Intron;
    $totals{$t->name} += $_->length foreach @introns;
  }

  # Sort the exons of the first transcript by position
  my @exons = sort {$a->start <=> $b->start} $transcripts[0]->Exon;

  # Get a region 1000 bp upstream of first exon
  my $upstream = $exons[0]->segment(-1000,0);

  # get its DNA
  my $dna = $upstream->dna;

  # and get all curated polymorphisms inside it
  @polymorphisms = $upstream->contained_features('polymorphism:curated');

  # get all feature types in the database
  my @types = $db->types;

  # count all feature types in the segment
  my %type_counts = $segment->types(-enumerate=>1);

  # get an iterator on all curated features of type 'exon' or 'intron'
  my $iterator = $db->features(-type     => ['exon:curated','intron:curated'],
                               -iterator => 1);

  while ($_ = $iterator->next_feature) {
      print $_,"\n";
  }

=head1 DESCRIPTION

Bio::DB::GFF provides fast indexed access to a sequence annotation
database.  It supports multiple database types (ACeDB, relational),
and multiple schemas through a system of adaptors and aggregators.

The following operations are supported by this module:

  - retrieving a segment of sequence based on the ID of a landmark
  - retrieving the DNA from that segment
  - finding all annotations that overlap with the segment
  - finding all annotations that are completely contained within the
    segment
  - retrieving all annotations of a particular type, either within a
    segment, or globally
  - conversion from absolute to relative coordinates and back again,
    using any arbitrary landmark for the relative coordinates
  - using a sequence segment to creatie new segments based on relative 
    offsets

The data model used by Bio::DB::GFF is compatible with the GFF flat
file format (http://www.sanger.ac.uk/software/GFF).  The module can
load a set of GFF files into the database, and serves objects that
have methods corresponding to GFF fields.

The objects returned by Bio::DB::GFF are compatible with the
SeqFeatureI interface, allowing their use by the Bio::Graphics and
Bio::DAS modules.

=head2 GFF Fundamentals

The GFF format is a flat tab-delimited file, each line of which
corresponds to an annotation, or feature.  Each line has nine columns
and looks like this:

 Chr1  curated  CDS 365647  365963  .  +  1  Transcript "R119.7"

The 9 columns are as follows:

=over 4

=item 1. reference sequence

This is the ID of the sequence that is used to establish the
coordinate system of the annotation.  In the example above, the
reference sequence is "Chr1".

=item 2. source

The source of the annotation.  This field describes how the annotation
was derived.  In the example above, the source is "curated" to
indicate that the feature is the result of human curation.  The names
and versions of software programs are often used for the source field,
as in "tRNAScan-SE/1.2".

=item 3. method

The annotation method.  This field describes the type of the
annotation, such as "CDS".  Together the method and source describe
the annotation type.

=item 4. start position

The start of the annotation relative to the reference sequence. 

=item 5. stop position

The stop of the annotation relative to the reference sequence.  Start
is always less than or equal to stop.

=item 6. score

For annotations that are associated with a numeric score (for example,
a sequence similarity), this field describes the score.  The score
units are completely unspecified, but for sequence similarities, it is
typically percent identity.  Annotations that don't have a score can
use "."

=item 7. strand

For those annotations which are strand-specific, this field is the
strand on which the annotation resides.  It is "+" for the forward
strand, "-" for the reverse strand, or "." for annotations that are
not stranded.

=item 8. phase

For annotations that are linked to proteins, this field describes the
phase of the annotation on the codons.  It is a number from 0 to 2, or
"." for features that have no phase.

=item 9. group

GFF provides a simple way of generating annotation hierarchies ("is
composed of" relationships) by providing a group field.  The group
field contains the class and ID of an annotation which is the logical
parent of the current one.  In the example given above, the group is
the Transcript named "R119.7".

The group field is also used to store information about the target of
sequence similarity hits, and miscellaneous notes.  See the next
section for a description of how to describe similarity targets.

=back

The sequences used to establish the coordinate system for annotations
can correspond to sequenced clones, clone fragments, contigs or
super-contigs.  Thus, this module can be used throughout the lifecycle
of a sequencing project.

In addition to a group ID, the GFF format allows annotations to have a
group class.  For example, in the ACeDB representation, RNA
interference experiments have a class of "RNAi" and an ID that is
unique among the RNAi experiments.  Since not all databases support
this notion, the class is optional in all calls to this module, and
defaults to "Sequence" when not provided.

Double-quotes are sometimes used in GFF files around components of the
group field.  Strictly, this is only necessary if the group name or
class contains whitespace.

=head2 Making GFF files work with this module

Some annotations do not need to be individually identified.  For
example, it is probably not useful to assign a unique name to each ALU
repeat in a vertebrate genome.  Others, such as predicted genes,
correspond to named biological objects; you probably want to be able
to fetch the positions of these objects by referring to them by name.

To accomodate named annotations, the GFF format places the object
class and name in the group field.  The name identifies the object,
and the class prevents similarly-named objects, for example clones and
sequences, from collding.

A named object is shown in the following excerpt from a GFF file:

 Chr1  curated transcript  939627 942410 . +  . Transcript Y95B8A.2

This object is a predicted transcript named Y95BA.2.  In this case,
the group field is used to identify the class and name of the object,
even though no other annotation belongs to that group.

It now becomes possible to retrieve the region of the genome covered
by transcript Y95B8A.2 using the segment() method:

  $segment = $db->segment(-class=>'Transcript',-name=>'Y95B8A.2');

It is not necessary for the annotation's method to correspond to the
object class, although this is commonly the case.

As explained above, each annotation in a GFF file refers to a
reference sequence.  It is a good idea for each reference sequence to
be identified by a line in the GFF file.  This allows the Bio::DB::GFF
module to determine the length and class of the reference sequence,
and makes it possible to do relative arithmetic.

For example, if "Chr1" is used as a reference sequence, then it should
have an entry in the GFF file similar to this one:

 Chr1 assembly chromosome 1 14972282 . + . Sequence Chr1

This indicates that the reference sequence named "Chr1" has length
14972282 bp, method "chromosome" and source "assembly".  In addition,
as indicated by the group field, Chr1 has class "Sequence" and name
"Chr".

The object class "Sequence" is used by default when the class is not
specified in the segment() call.  This allows you to use a shortcut
form of the segment() method:

 $segment = $db->segment('Chr1');          # whole chromosome
 $segment = $db->segment('Chr1',1=>1000);  # first 1000 bp

=head2 Sequence alignments

There are two cases in which an annotation indicates the relationship
between two sequences.  The first case is a similarity hit, where the
annotation indicates an alignment.  The second case is a map assembly,
in which the annotation indicates that a portion of a larger sequence
is built up from one or more smaller ones.

Both cases are indicated by using the b<Target> tag in the group
field.  For example, a typical similarity hit will look like this:

 Chr1 BLASTX similarity 76953 77108 132 + 0 Target Protein:SW:ABL_DROME 493 544

The group field contains the Target tag, followed by an identifier for
the biological object referred to.  The GFF format uses the notation
I<Class>:I<Name> for the biological object, and even though this is
stylistically inconsistent, that's the way it's done.  The object
identifier is followed by two integers indicating the start and stop
of the alignment on the target sequence.

Unlike the main start and stop columns, it is possible for the target
start to be greater than the target end.  The previous example
indicates that the the section of Chr1 from 76,953 to 77,108 aligns to
the protein SW:ABL_DROME starting at position 493 and extending to
position 544.

A similar notation is used for sequence assembly information as shown
in this example:

 Chr1        assembly Link   10922906 11177731 . . . Target Sequence:LINK_H06O01 1 254826
 LINK_H06O01 assembly Cosmid 32386    64122    . . . Target Sequence:F49B2       6 31742

This indicates that the region between bases 10922906 and 11177731 of
Chr1 are composed of LINK_H06O01 from bp 1 to bp 254826.  The region
of LINK_H0601 between 32386 and 64122 is, in turn, composed of the
bases 5 to 31742 of cosmid F49B2.

=head2 Adaptors and Aggregators

This module uses a system of adaptors and aggregators in order to make
it adaptable to use with a variety of databases.

=over 4

=item Adaptors

The core of the module handles the user API, annotation coordinate
arithmetic, and other common issues.  The details of fetching
information from databases is handled by an adaptor, which is
specified during Bio::DB::GFF construction.  The adaptor encapsulates
database-specific information such as the schema, user authentication
and access methods.

Currently there are two adaptors: 'dbi::mysql' and 'dbi::mysqlopt'.
The former is an interface to a simple Mysql schema.  The latter is an
optimized version of dbi::mysql which uses a binning scheme to
accelerate range queries and the Bio::DB::Fasta module for rapid
retrieval of sequences.  Note the double-colon between the words.

=item Aggregators

The GFF format uses a "group" field to indicate aggregation properties
of individual features.  For example, a set of exons and introns may
share a common transcript group, and multiple transcripts may share
the same gene group.

Aggregators are small modules that use the group information to
rebuild the hierarchy.  When a Bio::DB::GFF object is created, you
indicate that it use a set of one or more aggregators.  Each
aggregator provides a new composite annotation type.  Before the
database query is generated each aggregator is called to
"disaggregate" its annotation type into list of component types
contained in the database.  After the query is generated, each
aggregator is called again in order to build composite annotations
from the returned components.

For example, during disaggregation, the standard "transcript"
aggregator generates a list of component feature types including
"intron", "exon", "CDS", and "3'UTR".  Later, it aggregates these
features into a set of annotations of type "transcript".

During aggregation, the list of aggregators is called in reverse
order.  This allows aggregators to collaborate to create multi-level
structures: the transcript aggregator assembles transcripts from
introns and exons; the gene aggregator then assembles genes from sets
of transcripts.

Three aggregators are currently provided:

      transcript   assembles transcripts
      clone        assembles clones from Clone_end features
      alignment    assembles gapped alignments from similarity
	           features

The existing aggregators are easily customized.

Note that aggregation will not occur unless you specifically request
the aggregation type.  For example, this call:

  @features = $segment->features('alignment');

will generate an array of aggregated alignment features.  However,
this call:

  @features = $segment->features();

will return a list of unaggregated similarity segments.

=back

=head1 API

The following is the API for Bio::DB::GFF.

=cut

package Bio::DB::GFF;

use strict;

use Bio::DB::GFF::Util::Rearrange;
use Bio::DB::GFF::RelSegment;
use Bio::DB::GFF::Feature;
use Bio::DB::GFF::Aggregator;
use Bio::Root::RootI;

use vars qw($VERSION @ISA);
@ISA = qw(Bio::Root::RootI);

$VERSION = '0.38';
my %valid_range_types = (overlaps     => 1,
			 contains     => 1,
			 contained_in => 1);

=head2 new

 Title   : new
 Usage   : my $db = new Bio::DB::GFF(@args);
 Function: create a new Bio::DB::GFF object
 Returns : new Bio::DB::GFF object
 Args    : lists of adaptors and aggregators
 Status  : Public

These are the arguments:

 -adaptor      Name of the adaptor module to use.  If none
               provided, defaults to "dbi:mysqlopt".

 -aggregator   Array reference to a list of aggregators
               to apply to the database.  If none provided,
	       defaults to ['transcript','clone','alignment'].

  <other>      Any other named argument pairs are passed to
               the adaptor for processing.

The adaptor argument must correspond to a module contained within the
Bio::DB::GFF::Adaptor namespace.  For example, the
Bio::DB::GFF::Adaptor::dbi::mysql adaptor is loaded by specifying
'dbi:mysql'.  By Perl convention, the adaptors names are lower case
because they are loaded at run time.

The aggregator array may contain a list of aggregator names, or a list 
of initialized aggregator objects.  For example, if you wish to change
the components aggregated by the transcript aggregator, you could
pass it to the GFF constructor this way:

  my $transcript = 
     Bio::DB::Aggregator::transcript->new(-sub_parts=>[qw(exon intron utr
                                                          polyA spliced_leader)]);

  my $db = Bio::DB::GFF->new(-aggregator=>[$transcript,'clone','alignment],
                             -adaptor   => 'dbi:mysql',
                             -dsn      => 'dbi:mysql:elegans42');

The commonly used 'dbi:mysql' adaptor recognizes the following
adaptor-specific arguments:

  Argument       Description
  --------       -----------

  -dsn           the DBI data source, e.g. 'dbi:mysql:ens0040'
                 If a partial name is given, such as "ens0040", the
                 "dbi:mysql:" prefix will be added automatically.

  -user          username for authentication

  -pass          the password for authentication

The commonly used 'dbi:mysqlopt' adaptor also recogizes the following
arguments.

  Argument       Description
  --------       -----------

  -fasta         path to a directory containing FASTA files for the DNA
                 contained in this database (e.g. "/usr/local/share/fasta")

  -acedb         an acedb URL to use when converting features into ACEDB
                    objects (e.g. sace://localhost:2005)

=cut

#'

sub new {
  my $package   = shift;
  my ($adaptor,$aggregators,$args);

  if (@_ == 1) {  # special case, default to dbi::mysqlopt
    $adaptor = 'dbi::mysqlopt';
    $args = {DSN => shift};
  } else {
    ($adaptor,$aggregators,$args) = rearrange([
					       [qw(ADAPTOR FACTORY)],
					       [qw(AGGREGATOR AGGREGATORS)]
					      ],@_);
  }

  $adaptor    ||= 'dbi::mysqlopt';
  my $class = "Bio::DB::GFF::Adaptor::\L${adaptor}\E";
  eval "require $class";
  $package->throw("Unable to load $adaptor adaptor: $@") if $@;

  my $self = $class->new($args);

  # handle the aggregators.
  # aggregators are responsible for creating complex multi-part features
  # from the GFF "group" field.  If none are provided, then we provide a
  # list of the two used in WormBase.
  # Each aggregator can be a scalar or a ref.  In the former case
  # it is treated as a class name to call new() on.  In the latter
  # the aggreator is treated as a ready made object.
  $aggregators = $self->default_aggregators unless defined $aggregators;
  my @a = ref($aggregators) eq 'ARRAY' ? @$aggregators : $aggregators;
  my @aggregators;
  for my $a (@a) {
    $self->add_aggregator($a);
  }

  # default settings go here.....
  $self->automerge(1);  # set automerge to true

  $self;
}

=head2 load

 Title   : load
 Usage   : $db->load($file|$directory|$filehandle);
 Function: load GFF data into database
 Returns : count of records loaded
 Args    : a directory, a file, a list of files, 
           or a filehandle
 Status  : Public

This method takes a single overloaded argument, which can be any of:

=over 4

=item 1. a scalar corresponding to a GFF file on the system

A pathname to a local GFF file.  Any files ending with the .gz, .Z, or
.bz2 suffixes will be transparently decompressed with the appropriate
command-line utility.

=item 2. an array reference containing a list of GFF files on the
system

For example ['/home/gff/gff1.gz','/home/gff/gff2.gz']

=item 3. path to a directory

The indicated directory will be searched for all files ending in the
suffixes .gz, .Z or .bz2.

=item 4. a filehandle

An open filehandle from which to read the GFF data.

=item 5. a pipe expression

A pipe expression will also work. For example, a GFF file on a remote
web server can be loaded with an expression like this:

  $db->load("lynx -dump -source http://stein.cshl.org/gff_test |");

=back

If successful, the method will return the number of GFF lines
successfully loaded.

=cut

sub load {
  my $self              = shift;
  my $file_or_directory = shift || '.';

  local @ARGV;  # to play tricks with reader

  if (-d $file_or_directory) {
    @ARGV = glob("$file_or_directory/*.{gff,gff.gz,gff.Z,gff,bz2}");
  } elsif (my $fd = fileno($file_or_directory)) {
    open SAVEIN,"<&STDIN";
    open STDIN,"<&=$fd" or $self->throw("Can't dup STDIN");
    @ARGV = '-';
  } elsif (ref $file_or_directory) {
    @ARGV = @$file_or_directory;
  } else {
    @ARGV = $file_or_directory;
  }

  return unless @ARGV;
  foreach (@ARGV) {
    if (/\.gz$/) {
      $_ = "gunzip -c $_ |";
    } elsif (/\.Z$/) {
      $_ = "uncompress -c $_ |";
    } elsif (/\.bz2$/) {
      $_ = "bunzip2 -c $_ |";
    }
  }

  my $result = $self->load_gff;

  my $junk = fileno(SAVEIN);  # avoids "possible typo" warning in next line

  open STDIN,"<&SAVEIN";  # restore STDIN
  return $result;
}

=head2 lock_on_load

 Title   : lock_on_load
 Usage   : $lock = $db->lock_on_load([$lock])
 Function: set write locking during load
 Returns : current value of lock-on-load flag
 Args    : new value of lock-on-load-flag
 Status  : Public

This method is honored by some of the adaptors.  If the value is true,
the tables used by the GFF modules will be locked for writing during
loads and inaccessible to other processes.

=cut

sub lock_on_load {
  my $self = shift;
  my $d = $self->{lock};
  $self->{lock} = shift if @_;
  $d;
}

=head2 initialize

 Title   : initialize
 Usage   : $db->initialize($erase);
 Function: initialize a GFF database
 Returns : true if initialization successful
 Args    : an optional flag indicating that existing
           contents should be wiped clean
 Status  : Public

This method can be used to initialize an empty database.  It will not
overwrite existing data unless a true $erase flag is present.

=cut

sub initialize {
    shift->do_initialize(@_);
}

=head2 error

 Title   : error
 Usage   : $db->error( [$new error] );
 Function: read or set error message
 Returns : error message
 Args    : an optional argument to set the error message
 Status  : Public

This method can be used to retrieve the last error message.  Errors
are not reset to empty by successful calls, so contents are only valid
immediately after an error condition has been detected.

=cut

sub error {
  my $self = shift;
  my $g = $self->{error};
  $self->{error} = shift if @_;
  $g;
}

=head2 debug

 Title   : debug
 Usage   : $db->debug( [$flag] );
 Function: read or set debug flag
 Returns : current value of debug flag
 Args    : new debug flag (optional)
 Status  : Public

This method can be used to turn on debug messages.  The exact nature
of those messages depends on the adaptor in use.

=cut

sub debug {
  my $self = shift;
  my $g = $self->{debug};
  $self->{debug} = shift if @_;
  $g;
}


=head2 automerge

 Title   : automerge
 Usage   : $db->automerge( [$new automerge] );
 Function: get or set automerge value
 Returns : current value (boolean)
 Args    : an optional argument to set the automerge value
 Status  : Public

By default, this module will use the aggregators to merge groups into
single composite objects.  This default can be changed to false by
calling automerge(0).

=cut

sub automerge {
  my $self = shift;
  my $g = $self->{automerge};
  $self->{automerge} = shift if @_;
  $g;
}

=head2 segment

 Title   : segment
 Usage   : $db->segment(@args);
 Function: create a segment object
 Returns : a segment object
 Args    : numerous, see below
 Status  : public

This method generates a segment object, which is a Perl object
subclassed from Bio::DB::GFF::Segment.  The segment can be used to
find overlapping features and the raw DNA.

When making the segment() call, you specify the ID of a sequence
landmark (e.g. an accession number, a clone or contig), and a
positional range relative to the landmark.  If no range is specified,
then the entire extent of the landmark is used to generate the
segment.

You may also provide the ID of a "reference" sequence, which will set
the coordinate system and orientation used for all features contained
within the segment.  The reference sequence can be changed later.  If
no reference sequence is provided, then the coordinate system is based
on the landmark.

Arguments:

 -seq          ID of the landmark sequence.

 -class        Database object class for the landmark sequence.
               "Sequence" assumed if not specified.  This is
               irrelevant for databases which do not recognize
               object classes.

 -start        Start of the segment relative to landmark.  Positions
               follow standard 1-based sequence rules.  If not specified,
               defaults to the beginning of the landmark.

 -stop         Stop of the segment relative to the landmark.  If not specified,
               defaults to the end of the landmark.

 -offset       For those who prefer 0-based indexing, the offset specifies the
               position of the new segment relative to the start of the landmark.

 -length       For those who prefer 0-based indexing, the length specifies the
               length of the new segment.

 -refseq       Specifies the ID of the reference landmark used to establish the
               coordinate system for the newly-created segment.

 -refclass     Specifies the class of the reference landmark, for those databases
               that distinguish different object classes.  Defaults to "Sequence".

 -name,-sequence,-sourceseq   Aliases for -seq.

 -begin,-end   Aliases for -start and -stop

 -off,-len     Aliases for -offset and -length

 -seqclass     Alias for -class

Here's an example to explain how this works:

  my $db = Bio::DB::GFF->new(-dsn => 'dbi:mysql:human',-adaptor=>'dbi:mysql');

If successful, $db will now hold the database accessor object.  We now
try to fetch the fragment of sequence whose ID is A0000182 and class
is "Accession."

  my $segment = $db->segment(-name=>'A0000182',-class=>'Accession');

If successful, $segment now holds the entire segment corresponding to
this accession number.  By default, the sequence is used as its own
reference sequence, so its first base will be 1 and its last base will
be the length of the accession.

Assuming that this sequence belongs to a longer stretch of DNA, say a
contig, we can fetch this information like so:

  my $sourceseq = $segment->sourceseq;

and find the start and stop on the source like this:

  my $start = $segment->abs_start;
  my $stop = $segment->abs_stop;

If we had another segment, say $s2, which is on the same contiguous
piece of DNA, we can pass that to the refseq() method in order to
establish it as the coordinat reference point:

  $segment->refseq($s2);

Now calling start() will return the start of the segment relative to
the beginning of $s2, accounting for differences in strandedness:

  my $rel_start = $segment->start;

IMPORTANT NOTE: This method can be used to return the segment spanned
by an arbitrary named annotation.  However, if the annotation appears
at multiple locations on the genome, for example an EST that maps to
multiple locations, then, provided that all locations reside on the
same physical segment, the method will return a segment that spans the
minimum and maximum positions.  If the reference sequence occupies
ranges on different physical segments, then it returns undef.

The segments() method, described below, can be used to retrieve all
the segments spanned by a named feature, regardless of whether it is
on a contiguous physical segment.

=cut
#'

sub segment {
  my $self = shift;
  unless ($_[0] =~ /^-/) {
    @_ = (-class=>$_[0],-name=>$_[1]) if @_ == 2;
    @_ = (-name=>$_[0])               if @_ == 1;
  }
  return $_[0] =~ /^-/ ? Bio::DB::GFF::RelSegment->new(-factory => $self,@_)
                       : Bio::DB::GFF::RelSegment->new($self,@_);
}

=head2 abs_segment

 Title   : abs_segment
 Usage   : $db->abs_segment(@args);
 Function: create an absolute segment object
 Returns : a segment object
 Args    : numerous, see below
 Status  : public

This method behaves in the same way as segment(), but it forces the
method to return the segment in absolute coordinates.

=cut

sub abs_segment {
  my $self = shift;
  if ($_[0] !~ /^-/) {
    @_ = (-name=> $_[0], -start=>$_[1],-stop=>$_[2]) if @_ == 3;
    @_ = (-class=>$_[0],-name=>$_[1]) if @_ == 2;
    @_ = (-name=> $_[0])              if @_ == 1;
  }
  push @_,('-force_absolute'=>1);
  return Bio::DB::GFF::RelSegment->new(-factory => $self,@_);
}

=head2 types

 Title   : types
 Usage   : $db->types(@args)
 Function: return list of feature types in range or database
 Returns : a list of Bio::DB::GFF::Typename objects
 Args    : see below
 Status  : public

This routine returns a list of feature types known to the database.
The list can be database-wide or restricted to a region.  It is also
possible to find out how many times each feature occurs.

For range queries, it is usually more convenient to create a
Bio::DB::GFF::Segment object, and then invoke it's types() method.

Arguments are as follows:

  -ref        ID of reference sequence
  -class      class of reference sequence
  -start      start of segment
  -stop       stop of segment
  -enumerate  if true, count the features

The returned value will be a list of Bio::DB::GFF::Typename objects,
which if evaluated in a string context will return the feature type in 
"method:source" format.  This object class also has method() and
source() methods for retrieving the like-named fields.

If -enumerate is true, then the function returns a hash (not a hash
reference) in which the keys are type names in "method:source" format
and the values are the number of times each feature appears in the
database or segment.

The argument -end is a synonum for -stop, and -count is a synonym for
-enumerate.

=cut

sub types {
  my $self = shift;
  my ($refseq,$start,$stop,$enumerate,$refclass,$types) = rearrange ([
								      [qw(REF REFSEQ)],
								      qw(START),
								      [qw(STOP END)],
								      [qw(ENUMERATE COUNT)],
								      [qw(CLASS SEQCLASS)],
								      [qw(TYPE TYPES)],
								     ],@_);
  $types = $self->parse_types($types) if defined $types;
  $self->get_types($refseq,$refclass,$start,$stop,$enumerate,$types);
}

=head2 dna

 Title   : dna
 Usage   : $db->dna($id,$class,$start,$stop)
 Function: return the raw DNA string for a segment
 Returns : a raw DNA string
 Args    : id of the sequence, its class, start and stop positions
 Status  : public

This method is invoked by Bio::DB::GFF::Segment to fetch the raw DNA
sequence.

NOTE: you will probably prefer to create a Segment and then invoke its
dna() method.

=cut

# call to return the DNA string for the indicated region
# real work is done by get_dna()
sub dna {
  my $self = shift;
  my ($id,$start,$stop,$class)  = rearrange([
					     [qw(NAME ID REF REFSEQ)],
					     qw(START),
					     [qw(STOP END)],
    					    'CLASS',
					   ],@_);
  return unless defined $start && defined $stop;
  $self->get_dna($id,$start,$stop,$class);
}

sub features_in_range {
  my $self = shift;
  my ($range_type,$refseq,$class,$start,$stop,$types,$parent,$automerge,$iterator) =
    rearrange([
	       [qw(RANGE_TYPE)],
	       [qw(REF REFSEQ)],
	       qw(CLASS),
	       qw(START),
	       [qw(STOP END)],
	       [qw(TYPE TYPES)],
	       qw(PARENT),
	       [qw(MERGE AUTOMERGE)],
	       'ITERATOR'
	      ],@_);
  $automerge = $self->automerge unless defined $automerge;
  $self->throw("range type must be one of {".
	       join(',',keys %valid_range_types).
	       "}\n")
    unless $valid_range_types{lc $range_type};
  $self->_features(lc $range_type,$refseq,$class,$start,$stop,$types,$parent,$automerge,$iterator);
}

=head2 overlapping_features

 Title   : overlapping_features
 Usage   : $db->overlapping_features(@args)
 Function: get features that overlap the indicated range
 Returns : a list of Bio::DB::GFF::Feature objects
 Args    : see below
 Status  : public

This method is invoked by Bio::DB::GFF::Segment->features() to find
the list of features that overlap a given range.  It is generally
preferable to create the Segment first, and then fetch the features.

This method takes set of named arguments:

  -refseq    ID of the reference sequence
  -class     Class of the reference sequence
  -start     Start of the desired range in refseq coordinates
  -stop      Stop of the desired range in refseq coordinates
  -types     List of feature types to return.  Argument is an array
	     reference containing strings of the format "method:source"
  -parent    A parent Bio::DB::GFF::Segment object, used to create
	     relative coordinates in the generated features.
  -merge     Whether to apply aggregators to the generated features.
  -iterator  Whether to return an iterator across the features.

If -iterator is true, then the method returns a single scalar value
consisting of a Bio::SeqIO object.  You can call next_seq() repeatedly
on this object to fetch each of the features in turn.  If iterator is
false or absent, then all the features are returned as a list.

Currently aggregation is disabled when iterating over a series of
features.

Types are indicated using the nomenclature "method:source".  Either of
these fields can be omitted, in which case a wildcard is used for the
missing field.  Type names without the colon (e.g. "exon") are
interpreted as the method name and a source wild card.  Regular
expressions are allowed in either field, as in: "similarity:BLAST.*".

=cut

# call to return the features that overlap the named region
# real work is done by get_features
sub overlapping_features {
  my $self = shift;
  $self->features_in_range(-range_type=>'overlaps',@_);
}

=head2 contained_features

 Title   : contained_features
 Usage   : $db->contained_features(@args)
 Function: get features that are contained within the indicated range
 Returns : a list of Bio::DB::GFF::Feature objects
 Args    : see overlapping_features()
 Status  : public

This call is similar to overlapping_features(), except that it only
retrieves features whose end points are completely contained within
the specified range.

Generally you will want to fetch a Bio::DB::GFF::Segment object and
call its contained_features() method rather than call this directly.

=cut

# The same, except that it only returns features that are completely contained within the
# range (much faster usually)
sub contained_features {
  my $self = shift;
  $self->features_in_range(-range_type=>'contains',@_);
}

=head2 contained_in

 Title   : contained_in
 Usage   : @features = $s->contained_in(@args)
 Function: get features that contain this segment
 Returns : a list of Bio::DB::GFF::Feature objects
 Args    : see features()
 Status  : Public

This is identical in behavior to features() except that it returns
only those features that completely contain the segment.

=cut

sub contained_in {
  my $self = shift;
  $self->features_in_range(-range_type=>'contained_in',@_);
}

=head2 features

 Title   : features
 Usage   : $db->features(@args)
 Function: get all features, possibly filtered by type
 Returns : a list of Bio::DB::GFF::Feature objects
 Args    : see below
 Status  : public

This routine will retrieve features in the database regardless of
position.  It can be used to return all features, or a subset based on
their method and source.

Arguments are as follows:

  -types     List of feature types to return.  Argument is an array
	     reference containing strings of the format "method:source"
  -merge     Whether to apply aggregators to the generated features.
  -iterator  Whether to return an iterator across the features.

If -iterator is true, then the method returns a single scalar value
consisting of a Bio::SeqIO object.  You can call next_seq() repeatedly
on this object to fetch each of the features in turn.  If iterator is
false or absent, then all the features are returned as a list.

Currently aggregation is disabled when iterating over a series of
features.

Types are indicated using the nomenclature "method:source".  Either of
these fields can be omitted, in which case a wildcard is used for the
missing field.  Type names without the colon (e.g. "exon") are
interpreted as the method name and a source wild card.  Regular
expressions are allowed in either field, as in: "similarity:BLAST.*".

=cut

sub features {
  my $self = shift;
  my ($types,$automerge,$iterator);
  if ($_[0] =~ /^-/) {
    ($types,$automerge,$iterator) = rearrange([
					       [qw(TYPE TYPES)],
					       [qw(MERGE AUTOMERGE)],
					       'ITERATOR'
					      ],@_);
  } else {
    $types = \@_;
  }

  # for whole database retrievals, we probably don't want to automerge!
  $automerge = $self->automerge unless defined $automerge;
  $self->_features('contains',undef,undef,undef,undef,$types,undef,$automerge,$iterator);
}

=head2 segments

 Title   : segments
 Usage   : $db->segments($class => $name)
 Function: fetch segments by group name
 Returns : a list of Bio::DB::GFF::Feature objects
 Args    : the class and name of the desired feature
 Status  : public

This method can be used to fetch a set of one or more named features 
from the database.  GFF annotations are named using the group class and 
name fields, so for features that belong to a group of size one, this method 
can be used to retrieve that group (and is equivalent to the segment() method).

This method may return zero, one, or several Bio::DB::GFF::Feature
objects.

Aggregation is performed on features as usual.

The fetch_group() method is an alias for this one.

=cut

sub segments {
  my $self = shift;
  my ($gclass,$gname);
  if (@_ == 1) {
    $gclass = $self->default_class;
    $gname  = shift;
  } else  {
    ($gclass,$gname) = rearrange(['CLASS','NAME'],@_);
  }
  my %groups;         # cache the groups we create to avoid consuming too much unecessary memory
  my $features = [];
  my $callback = sub { push @$features,$self->make_feature(undef,\%groups,@_) };
  $self->get_feature_by_name($gclass,$gname,$callback);
  @$features;
}

*fetch_group = \&segments;

=head2 get_seq_stream()

Bioperl compatibility.

=cut

# bioperl-compatible stuff
sub get_seq_stream {
  my $self = shift;
  my @args = !defined($_[0]) || $_[0] =~ /^-/ ? (@_,-iterator=>1)
                                              : (-types=>\@_,-iterator=>1);
  $self->features(@args);
}

=head2 get_Stream_by_id ()

Bioperl compatibility.

=cut

sub get_Stream_by_id {
  my $self = shift;
  my @ids  = @_;
  Bio::DB::GFF::ID_Iterator->new($self,\@ids);
}

=head2 all_seqfeatures

 Title   : all_seqfeatures
 Usage   : @features = $db->all_seqfeatures(@args)
 Function: fetch all the features in the database
 Returns : an array of features, or an iterator
 Args    : See below
 Status  : public

This is equivalent to calling $db->features() without any types, and
will return all the features in the database.  The -merge and
-iterator arguments are recognized, and behave the same as described
for features().

=cut

sub all_seqfeatures {
  my $self = shift;
  my ($automerge,$iterator)= rearrange([
					[qw(MERGE AUTOMERGE)],
					'ITERATOR'
				       ],@_);
  my @args;
  push @args,(-merge=>$automerge)   if defined $automerge;
  push @args,(-iterator=>$iterator) if defined $iterator;
  $self->features(@args);
}

=head2 notes

 Title   : notes
 Usage   : @notes = $db->notes($id)
 Function: get the "notes" on a particular feature
 Returns : an array of string
 Args    : feature ID
 Status  : public

Some GFF version 2 files use the groups column to store various notes
and remarks.  Adaptors can elect to store the notes in the database,
or just ignore them.  For those adaptors that store the notes, the
notes() method will return them as a list.

=cut

sub notes {
  my $self = shift;
  return;
}


=head2 fast_queries

 Title   : fast_queries
 Usage   : $flag = $db->fast_queries([$flag])
 Function: turn on and off the "fast queries" option
 Returns : a boolean
 Args    : a boolean flag (optional)
 Status  : public

The mysql database driver (and possibly others) support a "fast" query
mode that caches results on the server side.  This makes queries come
back faster, particularly when creating iterators.  The downside is
that while iterating, new queries will die with a "command synch"
error.  This method turns the feature on and off.

For databases that do not support a fast query, this method has no
effect.

=cut

# override this method in order to set the mysql_use_result attribute, which is an obscure
# but extremely powerful optimization for both performance and memory.
sub fast_queries {
  my $self = shift;
  my $d = $self->{fast_queries};
  $self->{fast_queries} = shift if @_;
  $d;
}



=head2 add_aggregator

 Title   : add_aggregator
 Usage   : $db->add_aggregator($aggregator)
 Function: add an aggregator to the list
 Returns : nothing
 Args    : an aggregator
 Status  : public

This method will append an aggregator to the end of the list of
registered aggregators.

=cut

sub add_aggregator {
  my $self       = shift;
  my $aggregator = shift;
  my $list = $self->{aggregators} ||= [];
  if (ref $aggregator) { # an object
    push @$list,$aggregator;
  } else {
    my $class = "Bio::DB::GFF::Aggregator::\L${aggregator}\E";
    eval "require $class";
    $self->throw("Unable to load $aggregator aggregator: $@") if $@;
    push @$list,$class->new();
  }
}

=head2 aggregators

 Title   : aggregators
 Usage   : $db->aggregators;
 Function: retrieve list of aggregators
 Returns : list of aggregators
 Args    : none
 Status  : public

This method will return a list of aggregators currently assigned to
the object.

=cut

sub aggregators {
  my $self = shift;
  return unless $self->{aggregators};
  return @{$self->{aggregators}};
}

=head2 abscoords

 Title   : abscoords
 Usage   : $db->abscoords($name,$class,$refseq)
 Function: finds position of a landmark in reference coordinates
 Returns : ($ref,$class,$start,$stop,$strand)
 Args    : name and class of landmark
 Status  : public

This method is called by Bio::DB::GFF::RelSegment to obtain the
absolute coordinates of a sequence landmark.  The arguments are the
name and class of the landmark.  If successful, abscoords() returns
the ID of the reference sequence, its class, its start and stop
positions, and the orientation of the reference sequence's coordinate
system ("+" for forward strand, "-" for reverse strand).

If $refseq is present in the argument list, it forces the query to
search for the landmark in a particular reference sequence.

=cut

sub abscoords {
  my $self = shift;
  my ($name,$class,$refseq) = @_;
  $class ||= $self->{default_class};
  $self->get_abscoords($name,$class,$refseq);
}

=head1 Protected API

The following methods are not intended for public consumption, but are
intended to be overridden/implemented by adaptors.

=head2 default_aggregators

 Title   : default_aggregators
 Usage   : $db->default_aggregators;
 Function: retrieve list of aggregators
 Returns : array reference containing list of aggregator names
 Args    : none
 Status  : protected

This method (which is intended to be overridden by adaptors) returns a
list of standard aggregators to be applied when no aggregators are
specified in the constructor.

=cut

sub default_aggregators {
  my $self = shift;
  return ['transcript','clone','alignment'];
}

=head2 load_gff

 Title   : load_gff
 Usage   : $db->load_gff
 Function: load a GFF input stream
 Returns : number of features loaded
 Args    : none
 Status  : protected

This method is called to load a GFF data stream.  The method will read
GFF features from <> and load them into the database.  On exit the
method must return the number of features loaded.

Note that the method is responsible for parsing the GFF lines.  This
is to allow for differences in the interpretation of the "group"
field, which are legion.

=cut

# load from <>
sub load_gff {
  my $self = shift;
  $self->setup_load();

  while (<>) {
    my ($ref,$source,$method,$start,$stop,$score,$strand,$phase,$group) = split "\t";
    next if /^\#/;

    # handle group parsing
    $group =~ s/(\"[^\"]*);([^\"]*\")/$1$;$2/g;  # protect embedded semicolons in the group
    my @groups = split(/\s*;\s*/,$group);
    foreach (@groups) { s/$;/;/g }

    my ($gclass,$gname,$tstart,$tstop,$notes) = $self->_split_group(@groups);

    # no standard way in the GFF file to denote the class of the reference sequence -- drat!
    # so we invoke the factory to do it
    my $class = $self->refclass($ref);

    # call subclass to do the dirty work
    $self->load_gff_line({ref    => $ref,
			  class  => $class,
			  source => $source,
			  method => $method,
			  start  => $start,
			  stop   => $stop,
			  score  => $score,
			  strand => $strand,
			  phase  => $phase,
			  gclass => $gclass,
			  gname  => $gname,
			  tstart => $tstart,
			  tstop  => $tstop,
			  notes  => $notes}
			);
  }

  $self->finish_load();
}

# default is to return 'Sequence' as the class of all references
sub refclass {
  my $self = shift;
  my $refname = shift;
  'Sequence';
}

sub default_class {
   my $self = shift;
   my $d = exists($self->{default_class}) ? $self->{default_class} : 'Sequence';
   $self->{default_class} = shift if @_;
   $d;
}

=head2 setup_load

 Title   : setup_load
 Usage   : $db->setup_load
 Function: called before load_gff_line()
 Returns : void
 Args    : none
 Status  : abstract

This abstract method gives subclasses a chance to do any
schema-specific initialization prior to loading a set of GFF records.
It must be implemented by a subclass.

=cut

sub setup_load {
  shift->throw("setup_load(): must be implemented by an adaptor");
}

=head2 finish_load

 Title   : finish_load
 Usage   : $db->finish_load
 Function: called after load_gff_line()
 Returns : number of records loaded
 Args    : none
 Status  :abstract

This method gives subclasses a chance to do any schema-specific
cleanup after loading a set of GFF records.

=cut

sub finish_load {
  shift->throw("finish_load(): must be implemented by an adaptor");
}

=head2 load_gff_line

 Title   : load_gff_line
 Usage   : $db->load_gff_line(@args)
 Function: called to load one parsed line of GFF
 Returns : true if successfully inserted
 Args    : see below
 Status  : abstract

This abstract method is called once per line of the GFF and passed a
series of parsed data items.  The items are:

 $ref          reference sequence
 $source       annotation source
 $method       annotation method
 $start        annotation start
 $stop         annotation stop
 $score        annotation score (may be undef)
 $strand       annotation strand (may be undef)
 $phase        annotation phase (may be undef)
 $group_class  class of annotation's group (may be undef)
 $group_name   ID of annotation's group (may be undef)
 $target_start start of target of a similarity hit
 $target_stop  stop of target of a similarity hit
 $notes        array reference of text items to be attached

=cut

sub load_gff_line {
  shift->throw("load_gff_line(): must be implemented by an adaptor");
}


=head2 do_initialize

 Title   : do_initialize
 Usage   : $db->do_initialize([$erase])
 Function: initialize and possibly erase database
 Returns : true if successful
 Args    : optional erase flag
 Status  : protected

This method implements the initialize() method described above, and
takes the same arguments.

=cut

sub do_initialize {
    shift->throw('do_initialize(): must be implemented by an adaptor');
}

=head2 get_dna

 Title   : get_dna
 Usage   : $db->get_dna($id,$start,$stop,$class)
 Function: get DNA for indicated segment
 Returns : the dna string
 Args    : sequence ID, start, stop and class
 Status  : protected

If start > stop and the sequence is nucleotide, then this method
should return the reverse complement.  The sequence class may be
ignored by those databases that do not recognize different object
types.

=cut

sub get_dna {
  my $self = shift;
  my ($id,$start,$stop,$class,) = @_;
  $self->throw("get_dna() must be implemented by an adaptor");
}

=head2 get_features

 Title   : get_features
 Usage   : $db->get_features($isrange,$refseq,$class,$start,$stop,$types,$callback)
 Function: get list of features for a region
 Returns : count of number of features retrieved
 Args    : see below
 Status  : protected

Arguments are as follows:

   $rangetype One of "overlaps", "contains" or "contains_in".  Indicates
              the type of range query requested.

   $refseq    ID of the landmark that establishes the absolute 
              coordinate system.

   $class     Class of this landmark.  Can be ignored by implementations
              that don't recognize such distinctions.

   $start,$stop  Start and stop of the range, inclusive.

   $types     Array reference containing the list of annotation types
              to fetch from the database.  Each annotation type is an
              array reference consisting of [source,method].

   $callback  A code reference.  As the passed features are retrieved
              they are passed to this callback routine for processing.

   $automerge A flag.  If present, overrides the value returned by
              the automerge() method.

This routine is responsible for getting arrays of GFF data out of the
database and passing them to the callback subroutine.  The callback
does the work of constructing a Bio::DB::GFF::Feature object out of
that data.  The callback expects a list of 11 fields:

  $srcseq      source sequence
  $start       feature start
  $stop        feature stop
  $source      feature source
  $method      feature method
  $score       feature score
  $strand      feature strand
  $phase       feature phase
  $groupclass  group class (may be undef)
  $groupname   group ID (may be undef)
  $tstart      target start for similarity hits (may be undef)
  $tstop       target stop for similarity hits (may be undef)

These fields are in the same order as the raw GFF file, with the
exception that the group column has been parsed into class and name
fields.

=cut

sub get_features{
  my $self = shift;
  my ($rangetype,$srcseq,$class,$start,$stop,$types,$callback,$automerge) = @_;
  $self->throw("get_features() must be implemented by an adaptor");
}


=head2 get_feature_by_name

 Title   : get_feature_by_name
 Usage   : $db->get_feature_by_name($name,$class,$callback)
 Function: get a list of features by name and class
 Returns : count of number of features retrieved
 Args    : name of feature, class of feature, and a callback
 Status  : protected

This method is used internally.  The callback arguments are those used
by make_feature().

=cut

sub get_feature_by_name {
  my $self = shift;
  my ($class,$name,$callback) = @_;
  $self->throw("get_feature_by_name() must be implemented by an adaptor");
}

=head2 get_abscoords

 Title   : get_abscoords
 Usage   : $db->get_abscoords($name,$class,$refseq)
 Function: get the absolute coordinates of sequence with name & class
 Returns : ($absref,$absstart,$absstop,$absstrand)
 Args    : name and class of the landmark
 Status  : protected

Given the name and class of a genomic landmark, this function returns
a four-element array consisting of:

  $absref      the ID of the reference sequence that contains this landmark
  $absstart    the position at which the landmark starts
  $absstop     the position at which the landmark stops
  $absstrand   the strand of the landmark, relative to the reference sequence

If $refseq is provided, the function searches only within the
specified reference sequence.

=cut

sub get_abscoords {
  my $self = shift;
  my ($name,$class,$refseq) = @_;
  $self->throw("get_abscoords() must be implemented by an adaptor");
}

=head2 get_types

 Title   : get_types
 Usage   : $db->get_types($absref,$class,$start,$stop,$count)
 Function: get list of all feature types on the indicated segment
 Returns : list or hash of Bio::DB::GFF::Typename objects
 Args    : see below
 Status  : protected

Arguments are:

  $absref      the ID of the reference sequence
  $class       the class of the reference sequence
  $start       the position to start counting
  $stop        the position to end counting
  $count       a boolean indicating whether to count the number
	       of occurrences of each feature type

If $count is true, then a hash is returned.  The keys of the hash are
feature type names in the format "method:source" and the values are
the number of times a feature of this type overlaps the indicated
segment.  Otherwise, the call returns a set of Bio::DB::GFF::Typename
objects.  If $start or $stop are undef, then all features on the
indicated segment are enumerated.  If $absref is undef, then the call
returns all feature types in the database.

=cut

sub get_types {
  my $self = shift;
  my ($refseq,$class,$start,$stop,$count,$types) = @_;
  $self->throw("get_types() must be implemented by an adaptor");
}

=head2 make_feature

 Title   : make_feature
 Usage   : $db->make_feature(@args)
 Function: Create a Bio::DB::GFF::Feature object from string data
 Returns : a Bio::DB::GFF::Feature object
 Args    : see below
 Status  : internal

 This takes 14 arguments (really!):

  $parent                A Bio::DB::GFF::RelSegment object
  $group_hash            A hashref containing unique list of GFF groups
  $refname               The name of the reference sequence for this feature
  $refclass              The class of the reference sequence for this feature
  $start                 Start of feature
  $stop                  Stop of feature
  $source                Feature source field
  $method                Feature method field
  $score                 Feature score field
  $strand                Feature strand
  $phase                 Feature phase
  $group_class           Class of feature group
  $group_name            Name of feature group         
  $tstart                For homologies, start of hit on target
  $tstop                 Stop of hit on target

The $parent argument, if present, is used to establish relative
coordinates in the resulting Bio::DB::Feature object.  This allows one
feature to generate a list of other features that are relative to its
coordinate system (for example, finding the coordinates of the second
exon relative to the coordinates of the first).

The $group_hash allows the group_class/group_name strings to be turned
into rich database objects via the make_obect() method (see above).
Because these objects may be expensive to create, $group_hash is used
to uniquefy them.  The index of this hash is the composite key
{$group_class,$group_name,$tstart,$tstop}.  Values are whatever object
is returned by the make_object() method.

The remainder of the fields are taken from the GFF line, with the
exception that "Target" features, which contain information about the
target of a homology search, are parsed into their components.

=cut

# This call is responsible for turning a line of GFF into a
# feature object.
# The $parent argument is a Bio::DB::GFF::Segment object and is used
# to establish the coordinate system for the new feature.
# The $group_hash argument is an hash ref that holds previously-
# generated group objects.
# Other arguments are taken right out of the GFF table.
sub make_feature {
  my $self = shift;
  my ($parent,$group_hash,          # these arguments provided by generic mechanisms
      $srcseq,                      # the rest is provided by adaptor
      $start,$stop,
      $source,$method,
      $score,$strand,$phase,
      $group_class,$group_name,
      $tstart,$tstop,$db_id) = @_;

  return unless $srcseq;            # return undef if called with no arguments.  This behavior is used for
                                    # on-the-fly aggregation.

  my $group;  # undefined
  if (defined $group_class && defined $group_name) {
    $tstart ||= '';
    $tstop  ||= '';
    if ($group_hash) {
      $group = $group_hash->{$group_class,$group_name,$tstart,$tstop}
	||= $self->make_object($group_class,$group_name,$tstart,$tstop);
    } else {
      $group = $self->make_object($group_class,$group_name,$tstart,$tstop);
    }
  }

  if (ref $parent) { # note that the src sequence is ignored
    return Bio::DB::GFF::Feature->new_from_parent($parent,$start,$stop,
						  $method,$source,
						  $score,$strand,$phase,
						  $group,$db_id);
  } else {
    return Bio::DB::GFF::Feature->new($self,$srcseq,
				      $start,$stop,
				      $method,$source,
				      $score,$strand,$phase,
				      $group,$db_id,
				      $tstart,$tstop);
  }
}

sub make_aggregated_feature {
  my $self                 = shift;
  my $matchsub             = shift;
  my $accumulated_features = shift;
  my $parent               = shift;

  my $feature = $self->make_feature($parent,undef,@_);

  # if we have accumulated features and either: 
  # (1) make_feature() returned undef, indicated very end or
  # (2) the current group is different from the previous one
  if (@$accumulated_features &&
      (!defined($feature) || ($accumulated_features->[-1]->group ne $feature->group))) {
    my @aggregated;
    foreach my $a (reverse $self->aggregators) {  # last aggregator gets first shot
      my $agg = $a->aggregate($accumulated_features,$self) or next;
      push @aggregated,@$agg;
    }
    $self->warn("bad aggregator: turned one group into ",scalar(@aggregated)," features") if @aggregated > 1;
    @$accumulated_features = $feature ? ($feature) : ();  # remember this feature
    return $aggregated[0] if $aggregated[0];
    return $feature if $matchsub->($feature);
    return;
  } else {
    return unless defined($feature);
    push @$accumulated_features,$feature if defined $feature->group;
    return unless $matchsub->($feature);
    return $feature;
  }
}

=head2 parse_types

 Title   : parse_types
 Usage   : $db->parse_types(@args)
 Function: parses list of types
 Returns : an array ref containing ['method','source'] pairs
 Args    : a list of types in 'method:source' form
 Status  : internal

This method takes an array of type names in the format "method:source"
and returns an array reference of ['method','source'] pairs.  It will
also accept a single argument consisting of an array reference with
the list of type names.

=cut

# turn feature types in the format "method:source" into a list of [method,source] refs
sub parse_types {
  my $self  = shift;
  return [] if !@_ or !defined($_[0]);

  my @types = ref($_[0]) ? @{$_[0]} : @_;
  my @type_list = map { [split(':',$_,2)] } @types;
  return \@type_list;
}

=head2 make_match_sub

 Title   : make_match_sub
 Usage   : $db->make_match_sub($types)
 Function: creates a subroutine used for filtering features
 Returns : a code reference
 Args    : a list of parsed type names
 Status  : protected

This method is used internally to generate a code subroutine that will
accept or reject a feature based on its method and source.  It takes
an array of parsed type names in the format returned by parse_types(),
and generates an anonymous subroutine.  The subroutine takes a single
Bio::DB::GFF::Feature object and returns true if the feature matches
one of the desired feature types, and false otherwise.

=cut

# a subroutine that matches features indicated by list of types
sub make_match_sub {
  my $self = shift;
  my $types = shift;

  return sub { 1 } unless ref $types && @$types;

  my @expr;
  for my $type (@$types) {
    my ($method,$source) = @$type;
    $method ||= '.*';
    $source ||= '.*';
    push @expr,"$method:$source";
  }
  my $expr = join '|',@expr;
  return $self->{match_subs}{$expr} if $self->{match_subs}{$expr};

  my $sub =<<END;
sub {
  my \$feature = shift or return;
  return \$feature->type =~ /^$expr\$/i;
}
END
  my $compiled_sub = eval $sub;
  $self->throw($@) if $@;
  return $self->{match_subs}{$expr} = $compiled_sub;
}

=head2 make_object

 Title   : make_object
 Usage   : $db->make_object($class,$name,$start,$stop)
 Function: creates a feature object
 Returns : a feature object
 Args    : see below
 Status  : protected

This method is called to make an object from the GFF "group" field.
By default, all Target groups are turned into Bio::DB::GFF::Homol
objects, and everything else becomes a Bio::DB::GFF::Featname.
However, adaptors are free to override this method to generate more
interesting objects, such as true BioPerl objects, or Acedb objects.

Arguments are:

  $name      database ID for object
  $class     class of object
  $start     for similarities, start of match inside object
  $stop      for similarities, stop of match inside object

=cut

# abstract call to turn a feature into an object, given its class and name
sub make_object {
  my $self = shift;
  my ($class,$name,$start,$stop) = @_;
  return Bio::DB::GFF::Homol->new($self,$class,$name,$start,$stop)
    if defined $start and length $start;
  return Bio::DB::GFF::Featname->new($class,$name);
}

=head1 Internal Methods

The following methods are internal to Bio::DB::GFF and are not
guaranteed to remain the same.

=head2 _features

 Title   : _features
 Usage   : $db->_features(@args)
 Function: internal method
 Returns : a list of Bio::DB::GFF::Feature objects
 Args    : see below
 Status  : internal

This is an internal method that is called by overlapping_features(),
contained_features() and features() to do the actual work.  It takes
nine positional arguments:

  $rangetype     One of "overlaps", "contains" or "contains_in".  Indicates
                 the type of range query requested.
  $refseq        reference sequence ID
  $class	 reference sequence class
  $start	 start of range
  $stop		 stop of range
  $types	 list of types
  $parent	 parent sequence, for relative coordinates
  $automerge	 if true, invoke aggregators to merge features
  $iterator	 if true, return an iterator

=cut

sub _features {
  my $self = shift;
  my ($range_type,$refseq,$class,$start,$stop,$types,$parent,$automerge,$iterator) = @_;

  ($start,$stop) = ($stop,$start) if defined($start) && $start > $stop;

  $types = $self->parse_types($types);  # parse out list of types
  my @aggregated_types = @$types;         # keep a copy

  # allow the aggregators to operate on the original
  my $match;
  if ($automerge) {
    $match = $self->make_match_sub($types);
    for my $a ($self->aggregators) {
      $a->disaggregate(\@aggregated_types,$self);
    }
  }

  if ($iterator) {
    my @accumulated_features;
    my $callback = $automerge ? sub { $self->make_aggregated_feature($match,\@accumulated_features,$parent,@_) }
                              : sub { $self->make_feature($parent,undef,@_) };
    return $self->get_features_iterator($range_type,
					$refseq,$class,
					$start,$stop,
					\@aggregated_types,
					$callback,
					$automerge);
  }

  my %groups;         # cache the groups we create to avoid consuming too much unecessary memory
  my $features = [];

  my $callback = sub { push @$features,$self->make_feature($parent,\%groups,@_) };
  $self->get_features($range_type,$refseq,$class,
		      $start,$stop,\@aggregated_types,$callback,0);

  if ($automerge) {
    warn "aggregating...\n" if $self->debug;
    foreach my $a (reverse $self->aggregators) {  # last aggregator gets first shot
      my $agg = $a->aggregate($features,$self) or next;
      push @$features,@$agg;
    }

    warn "filtering...\n" if $self->debug;
    # remove anything from the features list that was not specifically requested.
    return grep { $match->($_) } @$features;
  }

  @$features;
}

=head2 get_features_iterator

 Title   : get_features_iterator
 Usage   : $db->get_features_iterator(@args)
 Function: get an iterator on a features query
 Returns : a Bio::SeqIO object
 Args    : as per get_features()
 Status  : Public

This method takes the same arguments as get_features(), but returns an
iterator that can be used to fetch features sequentially, as per
Bio::SeqIO.

Internally, this method is simply a front end to range_query().
The latter method constructs and executes the query, returning a
statement handle. This routine passes the statement handle to the
constructor for the iterator, along with the callback.

=cut

sub get_features_iterator {
  my $self = shift;
  my ($rangetype,$srcseq,$class,$start,$stop,$types,$callback) = @_;
  $self->throw('feature iteration is not implemented in this adaptor');
}

=head2 _split_group

 Title   : _split_group
 Usage   : $db->_split_group(@groups)
 Function: parse GFF group field
 Returns : ($gclass,$gname,$tstart,$tstop,$notes)
 Args    : a list of group fields from a GFF line
 Status  : internal

This is an internal method that is called by load_gff_line to parse
out the contents of one or more group fields.  It returns the class of
the group, its name, the start and stop of the target, if any, and an
array reference containing any notes that were stuck into the group
field.

=cut

sub _split_group {
  my $self = shift;
  my @groups = @_;

  my ($gclass,$gname,$tstart,$tstop,@notes);

  for (@groups) {

    my ($tag,$value) = /^(\S+)(?:\s+(.+))?/;
    $value ||= '';
    if ($value =~ /^\"(.+)\"$/) {  #remove quotes
      $value = $1;
    }
    $value =~ s/\\t/\t/g;
    $value =~ s/\\r/\r/g;

    # if the tag is "Note", then we add this to the
    # notes array. Do the same thing with
    # additional groups, since we don't handle
    # complex groupings (yet)
    $tag ||= '';
    if ($tag eq 'Note' or ($gclass && $gname)) {
      push @notes,$value;
    }

    # if the tag eq 'Target' then the class name is embedded in the ID
    # (the GFF format is obviously screwed up here)
    elsif ($tag eq 'Target' && /\"([^:\"]+):([^\"]+)\"/) {
      ($gclass,$gname) = ($1,$2);
      ($tstart,$tstop) = /(\d+) (\d+)/;
    }

    elsif (!$value) {
      push @notes,$tag;  # e.g. "Confirmed_by_EST"
    }

    # otherwise, the tag and value correspond to the
    # group class and name
    else {
      ($gclass,$gname) = ($tag,$value);
    }
  }

  return ($gclass,$gname,$tstart,$tstop,\@notes);
}

package Bio::DB::GFF::ID_Iterator;
use strict;
use Bio::Root::RootI;

sub new {
  my $class        = shift;
  my ($db,$ids)    = @_;
  return bless {ids=>$ids,db=>$db},$class;
}

sub next_seq {
  my $self = shift;
  my $next = shift @{$self->{ids}};
  return unless $next;
  my $name = ref($next) eq 'ARRAY' ? Bio::DB::GFF::Featname->new(@$next) : $next;
  my $segment = $self->{db}->segment($name);
  $self->throw("id does not exist") unless $segment;
  return $segment;
}

1;

__END__

=head1 BUGS

Features can only belong to a single group at a time.  This must be
addressed soon.

=head1 SEE ALSO

L<bioperl>,
L<Bio::DB::GFF::RelSegment>,
L<Bio::DB::GFF::Feature>,
L<Bio::DB::GFF::Adaptor::dbi::mysql>,
L<Bio::DB::GFF::Adaptor::dbi::mysqlopt>

=head1 AUTHOR

Lincoln Stein E<lt>lstein@cshl.orgE<gt>.

Copyright (c) 2001 Cold Spring Harbor Laboratory.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

