use utf8;
package Bio::HICF::Schema;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use Moose;
use MooseX::MarkAsMethods autoclean => 1;
extends 'DBIx::Class::Schema';

__PACKAGE__->load_namespaces;


# Created by DBIx::Class::Schema::Loader v0.07042 @ 2015-01-13 15:26:17
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:/Tydb6euSFy7u3YcKYKMrA

# ABSTRACT: DBIC schema for the HICF repository

=head1 SYNOPSIS

 # read in a manifest
 my $c = Bio::Metadata::Config->new( config_file => 'hicf.conf' );
 my $r = Bio::Metadata::Reader->new( config => $c );
 my $m = $r->read_csv( 'hicf.csv' );

 # load it into the database
 my $schema = Bio::HICF::Schema->connect( $dsn, $username, $password );
 my @sample_ids = $schema->load_manifest($m);

=cut

use Carp qw( croak );
use Bio::Metadata::Validator;
use Bio::Metadata::TaxTree;
use List::MoreUtils qw( mesh );
use TryCatch;
use MooseX::Params::Validate;

#-------------------------------------------------------------------------------

=head1 METHODS

=head2 load_manifest($manifest)

Loads the sample data in a L<Bio::Metadata::Manifest>. Returns a list of the
sample IDs for the newly inserted rows.

The database changes are made inside a transaction (see
L<DBIx::Class::Storage#txn_do>). If there is a problem during loading an
exception is throw and we try to roll back any database changes that have been
made. If the roll back fails, the error message will include the phrase "roll
back failed".

=cut

sub load_manifest {
  my ( $self, $manifest ) = @_;

  croak 'not a Bio::Metadata::Manifest'
    unless ref $manifest eq 'Bio::Metadata::Manifest';

  my $v = Bio::Metadata::Validator->new;

  croak 'ERROR: the data in the manifest are not valid'
    unless $v->validate($manifest);

  # build a transaction
  my @row_ids;
  my $txn = sub {

    # add a row to the manifest table
    my $rs = $self->resultset('Manifest')
                  ->find_or_create(
                    {
                      manifest_id => $manifest->uuid,
                      md5         => $manifest->md5,
                      config      => { config => $manifest->config->config_string }
                    },
                    { key => 'primary' }
                  );

    # load the sample rows
    my $field_names = $manifest->field_names;

    foreach my $row ( $manifest->all_rows ) {

      # zip the field names and values together to form a hash...
      my %upload = mesh @$field_names, @$row;

      # ... add the manifest ID...
      $upload{manifest_id} = $manifest->uuid;

      # ... and pass that hash to the ResultSet to load
      push @row_ids, $self->resultset('Sample')->load_row(\%upload);
    }

  };

  # run the transaction
  try {
    $self->txn_do( $txn );
  }
  catch ( $e ) {
    if ( $e =~ m/Rollback failed/ ) {
      croak "ERROR: there was an error when loading the manifest but roll back failed: $e";
    }
    else {
      croak "ERROR: there was an error when loading the manifest; changes have been rolled back: $e";
    }
  }

  return @row_ids;
}

#-------------------------------------------------------------------------------

=head2 get_manifest($manifest_id)

Returns a L<Bio::Metadata::Manifest> object for the specified manifest.

=cut

sub get_manifest {
  my ( $self, $manifest_id ) = @_;

  # create a B::M::Config object from the config string that we have stored for
  # this manifest
  my $config_rs = $self->resultset('Manifest')
                       ->search( { manifest_id => $manifest_id },
                                 { prefetch => [ 'config' ] } )
                       ->single;

  return unless $config_rs;

  my %config_args = ( config_string => $config_rs->config->config );
  if ( defined $config_rs->config->name ) {
    $config_args{config_name} = $config_rs->config->name;
  }

  my $c = Bio::Metadata::Config->new(%config_args);

  # get the values for the samples in the manifest and add them to a new
  # B::M::Manifest
  my $values = $self->get_samples($manifest_id);
  my $m = Bio::Metadata::Manifest->new( config => $c, rows => $values );

  return $m;
}

#-------------------------------------------------------------------------------

=head2 get_sample($sample_id)

Returns a reference to an array containing the field values for the specified
sample.

=cut

sub get_sample {
  my ( $self, $sample_id ) = @_;

  my $sample = $self->resultset('Sample')
                    ->find($sample_id);
  croak "ERROR: no sample with that ID ($sample_id)"
    unless defined $sample;

  my $values = $sample->get_field_values;
  croak "ERROR: couldn't get values for sample $sample_id"
    unless ( defined $values and scalar @$values );

  return $values;
}

#-------------------------------------------------------------------------------

=head2 get_samples(@args)

Returns a reference to an array containing the field values for the specified
samples, one sample per row. If the first element of C<@args> looks like a UUID,
it's assumed to be a manifest ID and the method returns the field data for all
samples in that manifest. Otherwise C<@args> is assumed to be a list of sample
IDs and the field data for each is return.

=cut

sub get_samples {
  my ( $self, @args ) = @_;

  my $samples;

  if ( $args[0] =~ m/^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$/i ) {
    # we were handed a manifest ID
    my $rs = $self->resultset('Sample')
                  ->search( { manifest_id => $args[0] },
                            { prefetch => 'antimicrobial_resistances' } );
    push @$samples, $_->get_field_values for ( $rs->all );
  }
  else {
    my $sample_ids = ( ref $args[0] eq 'ARRAY' )
                   ? $args[0]
                   : \@args;
    # we were handed a list of sample IDs
    push @$samples, $self->get_sample($_) for @$sample_ids;
  }

  return $samples;
}

#-------------------------------------------------------------------------------

=head2 load_antimicrobial($name)

Adds the specified antimicrobial compound name to the database. Throws an
exception if the supplied name is invalid, e.g. contains non-word characters.

=cut

sub load_antimicrobial {
  my ( $self, $name ) = @_;

  chomp $name;

  try {
    $self->resultset('Antimicrobial')->load_antimicrobial($name);
  }
  catch ( $e where { m/did not pass/ } ) {
    croak "ERROR: couldn't load '$name'; invalid antimicrobial compound name";
  }
}

#-------------------------------------------------------------------------------

=head2 load_antimicrobial_resistance(%amr)

Loads a new antimicrobial resistance test result into the database. See
L<Bio::HICF::Schema::ResultSet::AntimicrobialResistance::load_antimicrobial_resistance>
for details.

=cut

sub load_antimicrobial_resistance {
  my ( $self, %amr ) = @_;
  $self->resultset('AntimicrobialResistance')->load_antimicrobial_resistance(%amr);
}

#-------------------------------------------------------------------------------

=head2 load_tax_tree($tree, $?slice_size)

load the given tree into the taxonomy table. Requires a reference to a
L<Bio::Metadata::TaxTree> object containing the tree data. The rows
representing the tree nodes are loaded in chunks of 1000 rows at a time
(default). This "slice size" can be overridden with the C<$slice_size>
parameter.

B<Note> that the C<taxonomy> table will be truncated before loading.

Throws DBIC exceptions if loading fails. If possible, the entire transaction,
including the table truncation and any subsequent loading, will be rolled back.
If roll back fails, the error message will contain the string C<roll back
failed>.

=cut

sub load_tax_tree {
  my ( $self, $tree, $slice_size ) = @_;

  $slice_size ||= 1000;

  # get a simple list of column values for all of the nodes in the tree
  my $nodes = $tree->get_node_values;

  my $rs = $self->resultset('Taxonomy');

  # wrap this whole operation in a transaction
  my $txn = sub {

    # empty the table before we start
    $rs->delete;

    # since the number of rows to insert will be very large, we'll use the fast
    # insertion routines in DBIC and we'll load in chunks
    for ( my $i = 0; $i < scalar @$nodes; $i = $i + $slice_size ) {

      # the column names must be the first row
      my $rows = [
        [ qw( tax_id name lft rgt parent_tax_id ) ]
      ];

      # work out the bounds of the array slice
      my $from = $i,
      my $to   = $i + $slice_size - 1;

      # add the slice to the list of rows, grepping out undefined rows (needed
      # to avoid insertion errors when the last slice isn't full)
      push @$rows, grep defined, @$nodes[$from..$to];

      $rs->populate($rows);
    }

  };

  # execute the transaction
  try {
    $self->txn_do( $txn );
  }
  catch ( $e ) {
    if ( $e =~ m/Rollback failed/ ) {
      croak "ERROR: loading the tax tree failed but roll back failed ($e)";
    }
    else {
      croak "ERROR: loading the tax tree failed and the changes were rolled back ($e)";
    }
  }
}

#-------------------------------------------------------------------------------

=head2 load_ontology($table, $file, $?slice_size)

load the given ontology file into the specified table. Requires the name of the
table to load, which must be one of "gazetteer", "envo", or "brenda".  Requires
the path to the ontology file to be loaded. Since the ontologies may be large,
the terms are loaded in chunks of 10,000 at a time. This "slice size" can be
overridden with the C<$slice_size> parameter.

B<Note> that the specified table is emptied before loading.

Throws exceptions if loading fails. If possible, the entire transaction,
including the table truncation and any subsequent loading, will be rolled back.
If roll back fails, the error message will contain the string C<roll back
failed>.

=cut

sub load_ontology {
  my $self = shift;
  my ( $table, $file, $slice_size ) = pos_validated_list(
    \@_,
    { isa => 'Bio::Metadata::Types::OntologyName' },
    { isa => 'Str' },
    { isa => 'Bio::Metadata::Types::PositiveInt', optional => 1 },
  );
  # TODO the error message that comes back from the validation call is dumb
  # TODO and ugly. Just validate the ontology name ourselves and throw a
  # TODO sensible error

  croak "ERROR: ontology file not found ($file)"
    unless ( defined $file and -f $file );

  open ( FILE, $file )
    or croak "ERROR: can't open ontology file ($file): $!";

  $slice_size ||= 10_000;
  my $rs_name = ucfirst $table;
  my $rs = $self->resultset($rs_name);

  # wrap this whole operation in a transaction
  my $txn = sub {

    # before we start, truncate the table
    $rs->delete;

    # walk the file and load it in chunks
    my $chunk = [ [ 'id', 'description' ] ];
    my $term  = [];
    my $n = 1;

    while ( <FILE> ) {
      if ( m/^id: (.*?)$/ ) {
        my $id = $1;
        croak "ERROR: found an invalid ontology term ID ($1)"
          unless $id =~ m/^[A-Z]+:\d+$/;
        push @$term, $id;
      }
      if ( m/^name: (.*)$/ ) {
        push @$term, $1;
        push @$chunk, $term;

        # load the chunk every Nth term
        if ( $n % $slice_size == 0 ) {
          try {
            $rs->populate($chunk);
          }
          catch ( $e ) {
            croak "ERROR: there was a problem loading the '$table' table: $e";
          }
          # reset the chunk array
          $chunk = [ [ 'id', 'description' ] ];
        }
        $n++;

        $term = [];
      }
    }
    # load the last chunk
    if ( scalar @$chunk > 1 ) {
      try {
        $rs->populate($chunk);
      }
      catch ( $e ) {
        croak "ERROR: there was a problem loading the '$table' table: $e";
      }
    }
  };

  # execute the transaction
  try {
    $self->txn_do( $txn );
  }
  catch ( $e ) {
    if ( $e =~ m/Rollback failed/ ) {
      croak "ERROR: loading the ontology failed but roll back failed ($e)";
    }
    else {
      croak "ERROR: loading the ontology failed and the changes were rolled back ($e)";
    }
  }
}

#-------------------------------------------------------------------------------

=head1 SEE ALSO

L<Bio::Metadata::Validator>

=head1 CONTACT

path-help@sanger.ac.uk

=cut

__PACKAGE__->meta->make_immutable;

1;
