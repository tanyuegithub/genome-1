#!/usr/bin/env genome-perl

use strict;
use warnings;

use above "Genome";
use Genome::Test::Factory::Sample;
use Genome::Test::Factory::ProcessingProfile::ReferenceAlignment;
use Genome::Test::Factory::Model::ImportedReferenceSequence;
use Test::More;
plan tests => 1;

$ENV{UR_DBI_NO_COMMIT} = 1;
$ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;

my $subject = Genome::Test::Factory::Sample->setup_object;
my $processing_profile = Genome::Test::Factory::ProcessingProfile::ReferenceAlignment->setup_object;
my $refseq = Genome::Test::Factory::Model::ImportedReferenceSequence->setup_reference_sequence_build;

subtest 'successfully create model' => sub{
    plan tests => 15;

    my $model_name = "test_model_1";
    my @groups = sort { $a->id cmp $b->id }  map { Genome::ModelGroup->create(name => "test ".$_); } (1..2);
    my $create_command = Genome::Model::Command::Define::ReferenceAlignment->create(
        model_name               => "test_model_1",
        subject_name             => $subject->name,
        processing_profile       => $processing_profile,
        reference_sequence_build => $refseq->id,
        groups => \@groups,
    );

    isa_ok($create_command,'Genome::Model::Command::Define::Helper');

    $create_command->dump_error_messages(0);
    $create_command->dump_warning_messages(0);
    $create_command->dump_status_messages(0);
    $create_command->queue_error_messages(1);
    $create_command->queue_warning_messages(1);
    $create_command->queue_status_messages(1);

    ok($create_command->execute, 'create command execution successful');
    my @error_messages = $create_command->error_messages();
    print @error_messages, "\n";
    my @warning_messages = $create_command->warning_messages();
    my @status_messages = $create_command->status_messages();
    ok(! scalar(@error_messages), 'no error messages');
    ok(scalar(@status_messages), 'There was a status message');

    my @create_status_messages = grep { /Created model:/ } @status_messages;
    ok(@create_status_messages, 'Got create status message');
    my $model_id = $create_command->result_model_id;
    ok($model_id, 'got created model id') or die;
    my $model = Genome::Model->get($model_id,);
    ok($model, 'creation worked for '. $model->name .' model');
    is($model->name, $model_name, 'model_name');
    is($model->reference_sequence_build, $refseq, 'reference_sequence_build');
    my $expected_user_name = Genome::Sys->username;
    is($model->run_as,$expected_user_name,'model run_as accesssor');
    is($model->created_by,$expected_user_name,'model created_by accesssor');
    ok($model->creation_date, 'model creation_date accessor');
    is($model->processing_profile,$processing_profile,'model processing_profile_id indirect accessor');
    is($model->type_name,$processing_profile->type_name,'model type_name indirect accessor');

    is_deeply([$model->model_groups], \@groups, "Model is a member of the correct number of groups");

};

done_testing();
