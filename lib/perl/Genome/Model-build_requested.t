#!/usr/bin/env genome-perl

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;
use Genome::Model::TestHelpers qw(
    define_test_classes
    create_test_sample
    create_test_pp
    create_test_model
);

use Genome::Test::Factory::AnalysisProject;

define_test_classes();
my $sample = create_test_sample('test_sample');
my $pp = create_test_pp('test_pp');
my $model = create_test_model($sample, $pp, 'test_model');

my $anp = Genome::Test::Factory::AnalysisProject->setup_object;
$anp->add_model_bridge(model_id => $model->id);

my $tx = UR::Context::Transaction->begin();

$model->build_requested(0);
is($model->build_requested, 0, 'unset build requested');
{
    my $count = count_notes(
        notes => [$model->notes],
        header_text => 'build_unrequested',
        body_text => 'no reason given',
    );
    is($count, 1, 'found expected note');
}

my $reason = 'test build';
$model->build_requested(1, $reason);
is($model->build_requested, 1, 'set build requested with reason provided');
{
    my $count = count_notes(
        notes => [$model->notes],
        header_text => 'build_requested',
        body_text => $reason,
    );
    is($count, 1, 'found expected note');
}

$tx->rollback();
{
    my $count = count_notes(
        notes => [$model->notes],
        header_text => 'build_unrequested',
        body_text => 'no reason given',
    );
    is($count, 0, 'no new notes created during rollback');
}

done_testing();

sub count_notes {
   my %args = Params::Validate::validate(
       @_, { notes => 1, header_text => 1, body_text => 1 },
   );

   my $count = 0;
   for my $n (@{$args{notes}}) {
        if ($n->header_text eq $args{header_text}
            && index($n->body_text, $args{body_text}) >= 0
        ) {
            $count++;
        } else {
            diag $n->header_text, "\n", $n->body_text, "\n";
        }
   }

   return $count;
}
