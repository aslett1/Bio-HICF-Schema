use utf8;
package Bio::HICF::Schema::ResultSet::AntimicrobialResistance;

use Moose;
use MooseX::NonMoose;
use MooseX::Params::Validate;

use Carp qw ( croak );
use Bio::Metadata::Types;
use TryCatch;

extends 'DBIx::Class::ResultSet';

sub BUILDARGS { $_[2] }
# see https://metacpan.org/pod/DBIx::Class::ResultSet#ResultSet-subclassing-with-Moose-and-similar-constructor-providers

#-------------------------------------------------------------------------------

# ABSTRACT: resultset for the antimicrobial_resistance table

=head1 METHODS

=head2 load_antimicrobial_resistance($args)

Adds the specified antimicrobial resistance rest result to the database. Requires
a single argument, a hash containing the parameters specifying the resistance
test. The hash must contain the following five keys:

=over

=item C<sample_id> - the ID of an existing sample

=item C<name> - the name of an existing antimicrobial

=item C<susceptibility> - a susceptibility term; must be one of "S", "I" or "R"

=item C<mic> - minimum inhibitor concentration, in microgrammes per millilitre; must be a valid integer

=item C<diagnostic_centre> - name of the centre that carried out the susceptibility testing; optional

=back

Throws an exception if any of the parameters is invalid, or if the resistance
test result is already present in the database.

=cut

sub load_antimicrobial_resistance {
  my ( $self, %params ) = validated_hash(
    \@_,
    sample_id         => { isa => 'Int' },
    name              => { isa => 'Bio::Metadata::Types::AntimicrobialName' },
    susceptibility    => { isa => 'Bio::Metadata::Types::SIRTerm' },
    mic               => { isa => 'Int' },
    diagnostic_centre => { isa => 'Str' },
  );

  my $amr = $self->find_or_new(
    {
      sample_id          => $params{sample_id},
      antimicrobial_name => $params{name},
      susceptibility     => $params{susceptibility},
      mic                => $params{mic},
      diagnostic_centre  => $params{diagnostic_centre}
    },
    { key => 'primary' }
  );

  croak 'ERROR: antimicrobial resistance result already exists' if $amr->in_storage;

  try {
    $amr->insert;
  }
  catch ( DBIx::Class::Exception $e where { m/FOREIGN KEY constraint failed/ } ) {
    croak 'ERROR: both the antimicrobial and the sample must exist';
  }
}

#-------------------------------------------------------------------------------

__PACKAGE__->meta->make_immutable;

1;
