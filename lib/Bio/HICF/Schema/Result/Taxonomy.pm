use utf8;
package Bio::HICF::Schema::Result::Taxonomy;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Bio::HICF::Schema::Result::Taxonomy

=cut

use strict;
use warnings;

use Moose;
use MooseX::NonMoose;
use MooseX::MarkAsMethods autoclean => 1;
extends 'DBIx::Class::Core';

=head1 COMPONENTS LOADED

=over 4

=item * L<DBIx::Class::InflateColumn::DateTime>

=item * L<DBIx::Class::TimeStamp>

=back

=cut

__PACKAGE__->load_components("InflateColumn::DateTime", "TimeStamp");

=head1 TABLE: C<taxonomy>

=cut

__PACKAGE__->table("taxonomy");

=head1 ACCESSORS

=head2 ncbi_taxid

  data_type: 'integer'
  is_nullable: 0

=cut

__PACKAGE__->add_columns("ncbi_taxid", { data_type => "integer", is_nullable => 0 });

=head1 PRIMARY KEY

=over 4

=item * L</ncbi_taxid>

=back

=cut

__PACKAGE__->set_primary_key("ncbi_taxid");

=head1 RELATIONS

=head2 samples

Type: has_many

Related object: L<Bio::HICF::Schema::Result::Sample>

=cut

__PACKAGE__->has_many(
  "samples",
  "Bio::HICF::Schema::Result::Sample",
  { "foreign.ncbi_taxid" => "self.ncbi_taxid" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07042 @ 2015-01-14 15:53:57
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:GmJ8rtcJG8ULfK3lcGowtA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
