package Genome::VariantReporting::Framework::ReportResult;

use strict;
use warnings FATAL => 'all';
use Genome::File::Vcf::Reader;
use Genome;
use Memoize qw();

class Genome::VariantReporting::Framework::ReportResult {
    is => 'Genome::SoftwareResult::Stageable',
    has_input => [
        input_vcf_lookup => {
            is => 'Text',
        },
    ],
    has_param => [
        plan_json => {
            is => 'Text',
        },
        variant_type => {
            is => 'Text',
            valid_values => ['snvs', 'indels'],
        },
        provider_json => {
            is => 'Text',
        },
    ],
    has_transient_optional => [
        input_vcf => {
            is => 'Path',
        },
    ],
};

sub create {
    my $class = shift;
    my $self = $class->SUPER::create(@_);
    return unless $self;

    $self->_prepare_staging_directory;
    $self->_run;

    $self->_prepare_output_directory;
    $self->_promote_data;
    $self->_reallocate_disk_allocation;

    return $self;
}

sub resolve_allocation_subdirectory {
    my $self = shift;
    return File::Spec->join('/', 'model_data', 'software-result', $self->id);
}

sub resolve_allocation_disk_group_name {
    $ENV{GENOME_DISK_GROUP_MODELS};
}

sub plan {
    my $self = shift;

    return Genome::VariantReporting::Framework::Plan::MasterPlan->create_from_json($self->plan_json);
}
Memoize::memoize('plan', LIST_CACHE => 'MERGE');

sub translations {
    my $self = shift;
    my $provider = Genome::VariantReporting::Framework::Component::RuntimeTranslations->create_from_json($self->provider_json);

    return $provider->translations;
}
Memoize::memoize('translations', LIST_CACHE => 'MERGE');

sub _run {
    my $self = shift;

    $self->status_message("Reading from: ".$self->input_vcf."\n");

    my @reporters = $self->create_reporters;
    $self->initialize_reporters(@reporters);

    my $vcf_reader = Genome::File::Vcf::Reader->new($self->input_vcf);
    while (my $entry = $vcf_reader->next) {
        for my $reporter (@reporters) {
            $reporter->process_entry($entry);
        }
    }

    $self->finalize_reporters(@reporters);
    return 1;
}

sub create_reporters {
    my $self = shift;

    my @reporters;
    for my $reporter_plan ($self->plan->reporter_plans) {
        push @reporters, $reporter_plan->object($self->translations);
    }

    return @reporters;
}

sub initialize_reporters {
    my $self = shift;
    map {$_->initialize($self->temp_staging_directory)} @_;
    return;
}

sub finalize_reporters {
    my $self = shift;
    map {$_->finalize()} @_;
    return;
}


1;
