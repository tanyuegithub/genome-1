#!/usr/bin/env genome-perl

use strict;
use warnings FATAL => 'all';

use Data::Dump 'pp';
use Test::Exception;
use Test::More;
use Test::Deep;
use above 'Genome';
use Genome::Utility::Inputs qw(
    encode
    decode
);

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
};

{
    package Test::URObject;

    use strict;
    use warnings FATAL => 'all';
    use UR;

    class Test::URObject {
        is => ['UR::Object'],
    };

}

{

    package Test::Object;

    use strict;
    use warnings FATAL => 'all';

    sub new { my ($c, %p) = @_; return bless(\%p, $c); }
    sub name { return $_[0]->{name}; }

}

subtest "Basic" => sub {
    my $inputs = {
        a => Test::URObject->create(),
        b => Test::Object->new(name => 'Ren'),
        c => 'foo',
    };
    my $other_inputs = {
        a => Test::URObject->create(),
        b => Test::Object->new(name => 'Stimpy'),
        c => 'foo',
    };

    ok(!eq_deeply($inputs, $other_inputs), "Different inputs don't compare as equal (sanity)");

    for my $k (qw/ a b /) {
        ok(Scalar::Util::blessed($inputs->{$k}), "Raw value is a blessed reference");
        ok(!Scalar::Util::blessed(encode($inputs)->{$k}), "Encoded value is **not** a blessed reference");
    }

    cmp_deeply(decode(encode($inputs)), $inputs, "Roundtrip successful");
};

subtest "ARRAY" => sub {
    my $inputs = {
        a => [Test::URObject->create(), Test::URObject->create()],
        d => Test::Object->new(name => 'Mr. Horse'),
        c => 'foo',
    };

    ok(Scalar::Util::blessed($inputs->{a}->[0]), "Raw ARRAY element is a blessed reference");
    ok(!Scalar::Util::blessed(encode($inputs)->{a}->[0]), "Encoded ARRAY element is **not** a blessed reference");

    cmp_deeply(decode(encode($inputs)), $inputs, "Roundtrip successful");
};

subtest "Mixed ARRAY" => sub {
    my $inputs = {
        a => ['taco', Test::URObject->create()],
    };

    ok(Scalar::Util::blessed($inputs->{a}->[1]), "Raw ARRAY element is a blessed reference");
    ok(!Scalar::Util::blessed(encode($inputs)->{a}->[1]), "Encoded ARRAY element is **not** a blessed reference");

    cmp_deeply(decode(encode($inputs)), $inputs, "Roundtrip successful");
};

subtest "Nested ARRAY" => sub {
    my $inputs = {
        a => [[Test::URObject->create()]],
    };

    ok(Scalar::Util::blessed($inputs->{a}->[0]->[0]), "Raw ARRAY element is a blessed reference");
    ok(!Scalar::Util::blessed(encode($inputs)->{a}->[0]->[0]), "Encoded ARRAY element is **not** a blessed reference");

    cmp_deeply(decode(encode($inputs)), $inputs, "Roundtrip successful");
};

subtest "Non-object HASHREF" => sub {
    my $inputs = {
        a => {one => 1, two => 2},
    };

    cmp_deeply(decode(encode($inputs)), $inputs, "Roundtrip successful");
};

subtest "Nested HASHREFs and ARRAYs" => sub {
    my $inputs = {
        a => {one => 1, two => ['a', {three => 3}] },
    };

    cmp_deeply(decode(encode($inputs)), $inputs, "Roundtrip successful");
};

subtest "Ensure UR objects are encoded with proper encoder" => sub {
    my $inputs = {
        a => Test::URObject->create(),
    };

    my $encoded_inputs = encode($inputs);
    cmp_deeply($encoded_inputs->{a}->{__decoder_type__}, 'UR object', "__decoder_type__ properly set");
};

subtest "Failure to convert hash to UR::Object" => sub {
    my $hash = { class => 'Test::URObject', id => 'blah', };
    throws_ok(
        sub{ Genome::Utility::Inputs::_decode_ur_object($hash);},
        qr/Nothing returned/,
        '_decode_ur_object fails when object cannot be found',
    );
};

done_testing();
