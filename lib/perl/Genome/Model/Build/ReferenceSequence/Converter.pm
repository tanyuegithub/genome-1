package Genome::Model::Build::ReferenceSequence::Converter;

use Genome;
use warnings;
use strict;
use Sys::Hostname;
use List::Util qw( first );

class Genome::Model::Build::ReferenceSequence::Converter {
    is => ['Genome::SoftwareResult'],
    has => [
        source_reference_build => {
            is => 'Genome::Model::Build::ReferenceSequence',
            id_by => 'source_reference_build_id',
        },
        destination_reference_build => {
            is => 'Genome::Model::Build::ReferenceSequence',
            id_by => 'destination_reference_build_id',
        },
    ],
    has_input => [
        source_reference_build_id => {
            is => 'Number',
            doc => 'the reference to use by id',
        },
        destination_reference_build_id => {
            is => 'Number',
            doc => 'the reference to use by id',
        },
    ],
    has_metric => [
        algorithm => { # README - If adding an algorithm, please add to the list of valid algorithms
            is => 'Text',
            valid_values => [qw/ convert_chrXX_contigs_to_GL chop_chr prepend_chr lift_over no_op drop_extra_contigs/],
            doc => 'method to use to convert from the source to the destination',
        },
        resource => {
            is => 'Text',
            doc => 'additional resource to facilitate conversion if the algorithm requires (e.g. lift_over chain file)',
            is_optional => 1,
        },
    ],
};

sub exists_for_references {
    my $class = shift;
    my $source_reference = shift;
    my $destination_reference = shift;

    my $ref = $class->_faster_get(source_reference_build => $source_reference, destination_reference_build => $destination_reference);
    return defined($ref);
}

sub convert_bed {
    my $class = shift;
    my ($source_bed, $source_reference, $destination_bed, $destination_reference) = @_;

    my $self = $class->_faster_get(source_reference_build => $source_reference, destination_reference_build => $destination_reference);
    unless($self) {
        $class->error_message('Could not find converter from ' . $source_reference->__display_name__ . ' to ' . $destination_reference->__display_name__  . '. (See `genome model reference-sequence converter list` for available conversions.)');
        return;
    }

    if($self->__errors__) {
        $class->error_message('Loaded converter could not be used due to errors: ' . join(' ',map($_->__display_name__, $self->__errors__)));
        return;
    }

    if($self->is_per_position_algorithm($self->algorithm)) {
        $self->parse_and_write_bed($source_bed, $destination_bed, $self->algorithm, undef);
    } else {
        #operate on the whole BED file at once
        my $algorithm = $self->algorithm;
        $self->$algorithm($source_bed, $source_reference, $destination_bed, $destination_reference);
    }

   return $destination_bed;
}

sub is_per_position_algorithm {
    my $self = shift;
    my ($algorithm) = @_;

    return !grep($_ eq $algorithm, 'liftOver', 'no_op', 'drop_extra_contigs');
}

sub convert_position {
    my $self = shift;
    my ($algorithm, $chrom, $start, $stop) = @_;

    unless($chrom and $start and $stop) {
        $self->error_message('Missing one or more of chrom, start, stop. Got: (' . ($chrom || '') . ', ' . ($start || '') . ', ' . ($stop || '') . ').');
        return;
    }

    my ($new_chrom, $new_start, $new_stop) =  $self->$algorithm($chrom, $start, $stop);
    unless($new_chrom and $new_start and $new_stop) {
        $self->error_message('Could not convert one or more of chrom, start, stop. Got: (' . ($new_chrom || '') . ', ' . ($new_start || '') . ', ' . ($new_stop || '') . ').');
        return;
    }

    return ($new_chrom, $new_start, $new_stop);
}

sub convert_chrXX_contigs_to_GL {
    my $self = shift;
    my ($chrom, $start, $stop) = $self->chop_chr(@_);

    if($chrom =~ /\d+_(GL\d+)R/) {
        $chrom = $1 . '.1';
    } elsif ($chrom =~ /Un_gl(\d+)/i) {
        $chrom = 'GL' . $1 . '.1';
    }elsif ( $chrom =~ /\d+_GL(\d+)_random$/i) {
        $chrom = "GL" .  $1 . '.1';
    }

    return ($chrom, $start, $stop);
}

sub chop_chr {
    my $self = shift;
    my ($chrom, $start, $stop) = @_;

    $chrom =~ s/^chr//;

    return ($chrom, $start, $stop);
}

sub prepend_chr {
    my $self = shift;
    my ($chrom, $start, $stop) = @_;

    unless($chrom =~ /^chr/) {
        $chrom = 'chr' . $chrom;
    }

    return ($chrom, $start, $stop);
}

sub lift_over {
    my $self = shift;
    my ($source_bed, $source_reference, $destination_bed, $destination_reference) = @_;

    my $chain_file = $self->resource;
    unless($chain_file and -s $chain_file) {
        $self->error_message('No chain file resource found for liftOver.');
        die $self->error_message;
    }
    my $lift_over_cmd = Genome::Model::Tools::LiftOver->create(
        source_file => $source_bed,
        chain_file => $chain_file,
        destination_file => $destination_bed,
    );
    unless($lift_over_cmd->execute()) {
        die $self->error_message('LiftOver failed: ' . $lift_over_cmd->error_message);
    }

    return $destination_bed;
}

sub no_op {
    my $self = shift;
    my ($source_bed, $source_reference, $destination_bed, $destination_reference) = @_;

    #possibly useful for recording that two reference sequences are completely equivalent except in name
    Genome::Sys->copy_file($source_bed, $destination_bed);
    return $destination_bed;
}

sub parse_and_write_bed {
    my $self = shift;
    my ($source_bed, $destination_bed, $position_algorithm, $site_test) = @_;

    my $source_fh = Genome::Sys->open_file_for_reading($source_bed);
    my $destination_fh = Genome::Sys->open_file_for_writing($destination_bed);
    
    while(my $line = <$source_fh>) {
        chomp $line;
        my ($chrom, $start, $stop, @extra) = split("\t", $line);
        unless(
            defined $chrom 
            && defined $start 
            && defined $stop
        ) {
            $self->debug_message('Not converting non-entry line %s', $line);
            $destination_fh->say($line);
            next;
        }
        my ($new_chrom, $new_start, $new_stop) = ($chrom, $start, $stop);
        if($position_algorithm) {
            ($new_chrom, $new_start, $new_stop) = $self->convert_position($position_algorithm, $chrom, $start, $stop);
        }
        my $new_line = join("\t", $new_chrom, $new_start, $new_stop, @extra) . "\n";
        print $destination_fh $new_line if !$site_test || $site_test->($new_chrom, $new_start, $new_stop);
    }
    $source_fh->close;
    $destination_fh->close;
}

sub drop_extra_contigs {
    my $self = shift;
    my ($source_bed, $source_reference, $destination_bed, $destination_reference) = @_;

    my $chromosome_set = Set::Scalar->new(@{$self->destination_reference_build->chromosome_array_ref});
    my $algorithm = $self->resource;
    if($algorithm) {
        unless($self->validate_algorithm_name($algorithm) && $self->is_per_position_algorithm($algorithm)) {
            die "Per-position algorithm from resource property is not a valid converter\n";
        }
    }

    my $site_test = sub {
        my ($chrom) = @_;
        return $chromosome_set->has($chrom);
    };
    $self->parse_and_write_bed($source_bed, $destination_bed, $algorithm, $site_test);
}

sub validate_algorithm_name {
    my $self = shift;
    my ($algorithm_name) = @_;

    return first { $_ eq $algorithm_name } @{$self->__meta__->property_meta_for_name('algorithm')->valid_values};
}

1;
