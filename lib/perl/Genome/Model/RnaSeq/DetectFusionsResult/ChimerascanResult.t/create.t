#!/usr/bin/env genome-perl
use strict;
use warnings;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
};

use above 'Genome';
use Test::More;
use lib File::Spec->join(File::Basename::dirname(File::Basename::dirname(File::Spec->rel2abs(__FILE__))), "ChimerascanBase.t");
use chimerascan_test_setup "setup";
use chimerascan_test_create "test_create";

my $picard_version = 1.82;
my $chimerascan_version = '0.4.5';
my $chimerascan_result_class = "Genome::Model::RnaSeq::DetectFusionsResult::ChimerascanResult";
my ($alignment_result, $annotation_build, @bam_files) = setup(test_data_version => 4,
        chimerascan_version => $chimerascan_version,
        chimerascan_result_class => $chimerascan_result_class,
        picard_version => $picard_version);

test_create(
        alignment_result => $alignment_result,
        annotation_build => $annotation_build,
        chimerascan_version => $chimerascan_version,
        chimerascan_result_class => $chimerascan_result_class,
        picard_version => $picard_version,
        original_bam_paths => \@bam_files,
);

done_testing();

1;
