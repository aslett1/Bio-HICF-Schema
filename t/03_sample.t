#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Exception;
use Test::DBIx::Class qw( :resultsets );

# see 01_load.t
fixtures_ok 'main', 'installed fixtures';
lives_ok { Schema->storage->dbh_do( sub { $_[1]->do('PRAGMA foreign_keys = ON') } ) }
  'successfully turned on "foreign_keys" pragma';

my $expected_values = [
  'data:1',
  'ERS111111',
  'New sample',
  'CAMBRIDGE',
  9606,
  undef,
  'Tate JG',
  undef,
  '2015-01-10T14:30:00',
  'GAZ:00444180',
  1,
  'Homo sapiens',
  'healthy',
  'BTO:0000645',
  'inpatient',
  undef,
  'serovar',
  undef,
  'strain',
  undef,
  'am1;S;50;WTSI',
];

my $expected_hash = {
  antimicrobial_resistance => 'am1;S;50;WTSI',
  collected_at             => 'CAMBRIDGE',
  collected_by             => 'Tate JG',
  collection_date          => '2015-01-10T14:30:00',
  host_associated          => 1,
  host_disease_status      => 'healthy',
  host_isolation_source    => 'BTO:0000645',
  isolate                  => undef,
  isolation_source         => undef,
  location                 => 'GAZ:00444180',
  other_classification     => undef,
  patient_location         => 'inpatient',
  raw_data_accession       => 'data:1',
  sample_accession         => 'ERS111111',
  sample_description       => 'New sample',
  scientific_name          => undef,
  serovar                  => 'serovar',
  source                   => undef,
  specific_host            => 'Homo sapiens',
  strain                   => 'strain',
  tax_id                   => 9606
};

my $sample;
lives_ok { $sample = Sample->find(1) } 'retrieved row for sample ID 1';

my $values;
lives_ok { $values = $sample->field_values } 'got field values for sample ID 1';
is_deeply($values, $expected_values, 'got expected values for sample 1');

lives_ok { $values = $sample->fields } 'got field values hash for sample ID 1';
is_deeply($values, $expected_hash, 'got expected values for sample 1');

my $manifest_id       = '4162F712-1DD2-11B2-B17E-C09EFE1DC403';
my $other_manifest_id = '0162F712-1DD2-11B2-B17E-C09EFE1DC403';
my $columns = {
  manifest_id              => $manifest_id,
  raw_data_accession       => 'data:2',
  sample_accession         => 'ERS123456',
  sample_description       => 'New sample',
  collected_at             => 'CAMBRIDGE',
  tax_id                   => 9606,
  scientific_name          => undef,
  collected_by             => 'Tate JG',
  source                   => undef,
  collection_date          => '2015-01-10T14:30:00',
  location                 => 'GAZ:00444180',
  host_associated          => 1,
  specific_host            => 'Homo sapiens',
  host_disease_status      => 'healthy',
  host_isolation_source    => 'BTO:0000645',
  patient_location         => 'inpatient',
  isolation_source         => undef,
  serovar                  => 'serovar',
  other_classification     => undef,
  strain                   => 'strain',
  isolate                  => undef,
  antimicrobial_resistance => 'am1;S;50',
};
my $unknown_terms = {
  'not available; not collected' => 1,
  'unknown'                      => 1,
};

my $sample_id;
lives_ok { $sample_id = Sample->load($columns) } 'row loads ok';

is( $sample_id, 2, '"load" returns expected sample_id for new row' );
is( AntimicrobialResistance->count, 2, 'found expected row in antimicrobial_resistance table' );

is( Sample->all_rs->count, 2, '"all" returns a ResultSet with 2 rows' );
my $samples = Sample->all_rs;
is( $samples->next->sample_id, 1, 'got first sample via "all"' );
is( $samples->next->sample_id, 2, 'got second sample via "all"' );
is( $samples->next, undef, 'got expected number of samples via "all"' );

# load the same sample again
throws_ok { $sample_id = Sample->load($columns) } qr/UNIQUE constraint failed/,
  'error when loading same sample with same manifest ID';
$columns->{manifest_id} = $other_manifest_id;
lives_ok { $sample_id = Sample->load($columns) } 'row loads ok a second time';
is( Sample->all_rs->count, 3, '"all" returns a ResultSet with 3 rows' );

lives_ok { $sample = Schema->get_sample('ERS123456') }
  'successfully retrieved a single sample row by accession';
is( $sample->sample_id, 3, 'sample has correct ID');

my $rs;
lives_ok { $rs = Schema->get_samples('ERS123456') }
  'got rs with returned samples';
is( $rs->count, 2, 'got two samples for accession' );

# check we can load data with "unknown" values
$columns->{sample_accession} = 'ERS654321';
$columns->{location}         = 'not available; not collected';
lives_ok { $sample_id = Sample->load($columns, $unknown_terms) }
  'no error when loading data with "unknown" values';

# test errors

# put the GAZ term back
$columns->{location} = 'GAZ:00444180';

# reset the manifest ID to the original value
$columns->{manifest_id} = $manifest_id;

$columns->{antimicrobial_resistance} = 'am1;X;50';
throws_ok { Sample->load($columns) } qr/Not a valid antimicrobial resistance test result/,
  "error loading invalid amr";
$columns->{antimicrobial_resistance} = 'am1;S;50';

$columns->{raw_data_accession} = 'data:3';
$columns->{scientific_name}    = 'Not a real species';
throws_ok { Sample->load($columns) } qr/not found for scientific name/,
  "error loading when tax ID and scientific name don't match";
is( Sample->count, 4, 'no rows loaded' );

$columns->{tax_id}          = 0;
$columns->{scientific_name} = 'Homo sapiens';
throws_ok { Sample->load($columns) } qr/not found for taxonomy ID/,
  "error loading when tax ID and scientific name don't match";
is( Sample->count, 4, 'no rows loaded' );

$columns->{tax_id}          = 63221;
$columns->{scientific_name} = 'Homo sapiens';
throws_ok { Sample->load($columns) } qr/taxonomy ID \(63221\) and scientific name \(Homo sapiens\) do not match/,
  "error loading when tax ID and scientific name don't match";
is( Sample->count, 4, 'no rows loaded' );

$columns->{tax_id}   = 9606;
$columns->{location} = 'not a gaz term';
throws_ok { Sample->load($columns) } qr/term in 'location' \(not a gaz term\) is not found/,
  "error loading when gazetteer term isn't found";
is( Sample->count, 4, 'no rows loaded' );

$columns->{location}              = 'GAZ:00444180';
$columns->{host_isolation_source} = 'not a bto term';
throws_ok { Sample->load($columns) } qr/term in 'host_isolation_source' \(not a bto term\) is not found/,
  "error loading when BRENDA term isn't found";
is( Sample->count, 4, 'no rows loaded' );

$columns->{host_isolation_source} = 'BTO:0000645';
$columns->{isolation_source}      = 'not an envo term';
throws_ok { Sample->load($columns) } qr/term in 'isolation_source' \(not an envo term\) is not found/,
  "error loading when EnvO term isn't found";
is( Sample->count, 4, 'no rows loaded' );

$DB::single = 1;

done_testing();


