package Genome::InstrumentData::Command::RefineReads::GatkBase;

use strict;
use warnings;

use Genome;

require Genome::Utility::Text;

class Genome::InstrumentData::Command::RefineReads::GatkBase {
    is => 'Command::V2',
    is_abstract => 1,
    has => {
        version => { is => 'Text', },
        bam_source => { is => 'Genome::InstrumentData::AlignedBamResult', },
    },
    has_many => {
        known_sites => { is => 'Genome::Model::Build::ImportedVariationList', },
    },
    has_optional => {
        params => { is => 'Text', }, # FIXME not used
    },
    has_optional_transient => {
        final_result => { is => 'Genome::InstrumentData::AlignedBamResult', },
        results => { is => 'Hash', default_value => {}, },
    },
};

sub result_names {
    die 'Provide result names in sub-classes!';
}

sub result_method_for_name {
    my ($self, $result_name) = @_;

    die 'No result name given to get method!' if not $result_name;

    my $result_method = $result_name;
    $result_method =~ s/\s/_/g;
    $result_method .= '_result';

    return $result_method;
}

sub shortcut {
    my $self = shift;
    $self->debug_message('Attempting to shortcut...');

    my $load_results = $self->_load_results('get_with_lock');
    if ( not $load_results ) {
        $self->debug_message('Failed to load all results, cannot shortcut!');
        return;
    }

    $self->debug_message('Shortcut...OK');
    return $self->final_result;
}

sub execute {
    my $self = shift;
    $self->debug_message('Execute '.$self->class);

    # Always try to shortcut
    my $shortcut = $self->shortcut;
    return $shortcut if $shortcut;

    # [Get or] Create results
    my $load_results = $self->_load_results('get_or_create');
    return if not $load_results;

    $self->debug_message('Execute...OK');
    return $self->final_result;
}

sub _load_results {
    my ($self, $retrieval_method) = @_;

    die 'No retrieval method given to load result!' if not $retrieval_method;

    # [Get or] Create each result, setting the previous result as the bam source
    my $bam_source = $self->bam_source;
    for my $result_name ( $self->result_names ) {
        my $result = $self->_load_result(
            bam_source => $bam_source, 
            result_name => $result_name,
            retrieval_method => $retrieval_method,
        );
        return if not $result;
        $self->final_result($result);
        $bam_source = $result;
    }

    return 1;
}

sub _load_result {
    my ($self, %params) = @_;

    my $bam_source = delete $params{bam_source};
    die 'No bam source given to load result!' if not $bam_source;
    my $reference_build = $bam_source->reference_build;
    die 'Bam source does not have a reference build! '.$bam_source->__display_name__ if not $reference_build;
    my $result_name = delete $params{result_name};
    die 'No result name given to load result!' if not $result_name;
    my $retrieval_method = delete $params{retrieval_method};
    die 'No retrieval method given to load result!' if not $retrieval_method;

    # Check accessor
    my $result_method = $self->result_method_for_name($result_name);
    return $self->$result_method if $self->$result_method;

    # Class name
    $self->debug_message("Looking for $result_name result...");
    my $result_class = 'Genome::InstrumentData::Gatk::'.Genome::Utility::Text::string_to_camel_case($result_name).'Result';
    $self->debug_message('Class: '.$result_class);
    $self->debug_message('Method: '.$retrieval_method);

    # Params
    my @known_sites = $self->known_sites;
    my %result_params = (
        bam_source => $bam_source,
        version => $self->version,
        reference_build => $reference_build,
        known_sites => \@known_sites,
        # TODO use params from class
    );
    $self->debug_message("Result params: \n".$self->_params_display_name(\%result_params));

    # Retrieve
    my $result = $result_class->$retrieval_method(%result_params);
    return if not $result;
    $self->results->{$result_method} = $result;

    $self->debug_message(ucfirst($result_name).': '.$result->__display_name__);
    $self->debug_message(ucfirst($result_name).' output directory: '.$result->output_dir);
    return $result;
}

sub _params_display_name {
    my ($self, $params) = @_;

    my $display_name;
    for my $key ( keys %$params ) {
        $display_name .= $key.': ';
        if ( my $ref = ref $params->{$key} ) {
            my @params = ( $ref eq 'ARRAY' ) ? @{$params->{$key}} : $params->{$key};
            for my $param ( @params ) {
                $display_name .= $param->id."\n";
            }
        }
        else {
            $display_name .=  $params->{$key}."\n";
        }
    }

    return $display_name;
}

1;

