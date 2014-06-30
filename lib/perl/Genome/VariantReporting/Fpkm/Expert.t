#!/usr/bin/env genome-perl

use strict;
use warnings FATAL => 'all';

use Test::More;
use above 'Genome';
use Genome::Utility::Test qw(compare_ok);
use Genome::VariantReporting::Framework::TestHelpers qw(
    get_test_somatic_variation_build_with_vep_annotations
    test_dag_xml
    test_dag_execute
    get_test_dir
);
use Genome::VariantReporting::Plan::TestHelpers qw(
    set_what_interpreter_x_requires
);
use Sub::Install qw(reinstall_sub);

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
    $ENV{NO_LSF} = 1;
};

my $pkg = 'Genome::VariantReporting::Fpkm::Expert';
use_ok($pkg) || die;
my $factory = Genome::VariantReporting::Factory->create();
isa_ok($factory->get_class('experts', $pkg->name), $pkg);

my $VERSION = 1; # Bump these each time test data changes
my $BUILD_VERSION = 2;
my $test_dir = get_test_dir($pkg, $VERSION);

my $expert = $pkg->create();
my $dag = $expert->dag();
my $expected_xml = File::Spec->join($test_dir, 'expected.xml');
test_dag_xml($dag, $expected_xml);

set_what_interpreter_x_requires('fpkm');
my $build = get_test_somatic_variation_build_with_vep_annotations(version => $BUILD_VERSION);

# Make fpkm file findable
reinstall_sub( {
        into => $pkg->adaptor_class,
        as => 'fpkm_file',
        code => sub { return File::Spec->join($test_dir, 'test.fpkm'); },
});

my $plan = Genome::VariantReporting::Plan->create_from_file(
    File::Spec->join($test_dir, 'plan.yaml'),
);
$plan->validate();

my $variant_type = 'snvs';
my $expected_vcf = File::Spec->join($test_dir, "expected_$variant_type.vcf.gz");
test_dag_execute($dag, $expected_vcf, $variant_type, $build, $plan);

done_testing();
