#!/usr/bin/env perl

use above 'Genome';
use Test::More;

use strict;
use warnings;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

my $pkg = "Genome::File::Vcf::Reader";

use_ok($pkg);

# NOTE: this data is "clean". It comes from the public VCF spec at:
# http://www.1000genomes.org/wiki/Analysis/Variant%20Call%20Format/vcf-variant-call-format-version-41
my $vcf_str = <<EOS;
##fileformat=VCFv4.1
##fileDate=20090805
##source=myImputationProgramV3.1
##reference=file:///seq/references/1000GenomesPilot-NCBI36.fasta
##contig=<ID=20,length=62435964,assembly=B36,md5=f126cdf8a6e0c7f379d618ff66beb2da,species="Homo sapiens",taxonomy=x>
##phasing=partial
##INFO=<ID=NS,Number=1,Type=Integer,Description="Number of Samples With Data">
##INFO=<ID=DP,Number=1,Type=Integer,Description="Total Depth">
##INFO=<ID=AF,Number=A,Type=Float,Description="Allele Frequency">
##INFO=<ID=AA,Number=1,Type=String,Description="Ancestral Allele">
##INFO=<ID=DB,Number=0,Type=Flag,Description="dbSNP membership, build 129">
##INFO=<ID=H2,Number=0,Type=Flag,Description="HapMap2 membership">
##FILTER=<ID=noident,Description="No identifier">
##FILTER=<ID=q10,Description="Quality below 10">
##FILTER=<ID=s50,Description="Less than 50% of samples have data">
##FORMAT=<ID=GT,Number=1,Type=String,Description="Genotype">
##FORMAT=<ID=GQ,Number=1,Type=Integer,Description="Genotype Quality">
##FORMAT=<ID=DP,Number=1,Type=Integer,Description="Read Depth">
##FORMAT=<ID=HQ,Number=2,Type=Integer,Description="Haplotype Quality">
#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tNA00001\tNA00002\tNA00003
20\t14370\trs6054257\tG\tA\t29\tPASS\tNS=3;DP=14;AF=0.5;DB;H2\tGT:GQ:DP:HQ\t0|0:48:1:51,51\t1|0:48:8:51,51\t1/1:43:5:.,.
20\t17330\t.\tT\tA\t3\tq10\tNS=3;DP=11;AF=0.017\tGT:GQ:DP:HQ\t0|0:49:3:58,50\t0|1:3:5:65,3\t0/0:41:3
20\t1110696\trs6040355\tA\tG,T\t67\tPASS\tNS=2;DP=10;AF=0.333,0.667;AA=T;DB\tGT:GQ:DP:HQ\t1|2:21:6:23,27\t2|1:2:0:18,2\t2/2:35:4
20\t1230237\t.\tT\t.\t47\tPASS\tNS=3;DP=13;AA=T\tGT:GQ:DP:HQ\t0|0:54:7:56,60\t0|0:48:4:51,51\t0/0:61:2
20\t1234567\tmicrosat1,foo\tGTC\tG,GTCT\t50\tPASS\tNS=3;DP=9;AA=G\tGT:GQ:DP\t0/1:35:4\t0/2:17:2\t1/1:40:3
EOS

subtest "peek" => sub {
    my $vcf_fh = new IO::String($vcf_str);
    my $reader = $pkg->fhopen($vcf_fh, "Test Vcf");

    # Peek!
    my $entry_peek = $reader->peek;
    ok($entry_peek, 'Peeked at first entry');
    is_deeply($entry_peek->{identifiers}, ['rs6054257'], 'Got the right entry');

    # Peek again, make sure we still get the first thing
    $entry_peek = $reader->peek;
    is_deeply($entry_peek->{identifiers}, ['rs6054257'], 'Re-peek');

    # Now take, advancing to the next entry. Make sure we get the right thing.
    my $peek_str = $entry_peek->to_string;
    my $entry = $reader->next;
    is($entry->to_string, $peek_str, 'next returns peeked entry');

    # Advance again, make sure we actually keep moving and don't get stuck.
    $entry = $reader->next;
    is($entry->{position}, 17330, 'Got the 2nd entry');

    # Peek time!
    $entry_peek = $reader->peek;
    ok($entry_peek, 'Peeked at 3rd entry');
    is($entry_peek->{position}, 1110696, 'Got the 3rd entry');

    $peek_str = $entry_peek->to_string;
    $entry = $reader->next;
    is($entry->to_string, $peek_str, 'next returns peeked entry');
};

subtest "basic usage (filehandle via fhopen)" => sub {
    my $vcf_fh = new IO::String($vcf_str);
    my $reader = $pkg->fhopen($vcf_fh, "Test Vcf");

    my $header = $reader->header;
    ok($header, "Got vcf header");
    is_deeply([$header->sample_names], [map {"NA0000$_"} 1..3], "Header has expected sample names");
    my $entry = $reader->next;
    ok($entry, "Got first entry");
    is($entry->{chrom}, "20", "chrom accessor");
    is($entry->{position}, "14370", "position accessor");
    is($entry->{reference_allele}, "G", "ref accessor");
    is($entry->sample_field(0, "GT"), "0|0", "sample field accessor");

    my @expected_pos = (17330, 1110696, 1230237, 1234567);
    my @actual_entries;
    while (my $e = $reader->next) {
        push(@actual_entries, $e);
    }
    is(scalar(@actual_entries), scalar(@expected_pos), "Read expected number of entries");
    is_deeply([map {$_->{position}} @actual_entries], \@expected_pos, "Positions of entries are as expected");
};

###############################################################################
# Now let us rewind and test filtering
subtest "add filter for no identifiers" => sub {
    my $vcf_fh = new IO::String($vcf_str);
    my $reader = $pkg->fhopen($vcf_fh, "Test Vcf");

    # Adds a filter to entries that have no identifier (e.g., rsid)
    my $has_identifiers = sub {
        my $entry = shift;
        if (!@{$entry->{identifiers}}) {
            $entry->add_filter("noident");
        }
        return 1;
    };

    $reader->add_filter($has_identifiers);
    my @entries;
    while (my $entry = $reader->next) {
        push(@entries, $entry);
    }

    is(5, @entries);
    my @expected_filters = (["PASS"], ["q10", "noident"], ["PASS"], ["noident"], ["PASS"]);
    is_deeply( [ map { [$_->filters] } @entries ],
        \@expected_filters,
        "filters applied as expected");
};

subtest "filter: identifiers only" => sub {
    my $vcf_fh = new IO::String($vcf_str);
    my $reader = $pkg->fhopen($vcf_fh, "Test Vcf");

    # Returns true when an entry has an identifier (e.g., rsid)
    my $has_identifiers = sub {
        my $entry = shift;
        return @{$entry->{identifiers}} != 0;
    };

    $reader->add_filter($has_identifiers);
    my @entries;
    while (my $entry = $reader->next) {
        push(@entries, $entry);
    }

    is_deeply([map {$_->{identifiers}} @entries],
        [ ["rs6054257"], ["rs6040355"], ["microsat1","foo"] ],
        "Correctly filtered out entries with no identifiers");
};

subtest "unfiltered only" => sub {
    my $vcf_fh = new IO::String($vcf_str);
    my $reader = $pkg->fhopen($vcf_fh, "Test Vcf");

    # Returns true when an entry has an identifier (e.g., rsid)
    my $has_identifiers = sub {
        my $entry = shift;
        return !$entry->is_filtered;
    };
    $reader->add_filter($has_identifiers);
    my @entries;
    while (my $entry = $reader->next) {
        push(@entries, $entry);
    }

    is_deeply([map {$_->{position}} @entries],
        [ 14370, 1110696, 1230237, 1234567 ],
        "Correctly filtered out entries that failed filters");
};

done_testing();
