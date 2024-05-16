#!/usr/bin/perl
# Parse a service catalog to get the Swift URL
# Arguments:
# 1: catalog file
# 2: region
# 3: object store interface (probably "public" or "internal")

use strict;
use warnings;
use JSON::PP;

my $catalog_file = shift @ARGV;
my $region = shift @ARGV;
my $object_store_interface = shift @ARGV;

open(my $catalog_fh, '<', $catalog_file) or die "Couldn't open $catalog_file";

$/ = undef;

# load the full catalog as a single string
my $catalog_string = <$catalog_fh>;

close $catalog_fh;

# turn the catalog into a hash reference
my $catalog_hash = decode_json $catalog_string;
my $catalog_service_list = $catalog_hash->{token}->{catalog};

ENDPOINT: for my $service (@{$catalog_service_list})
{
    next unless "$service->{type}" eq "object-store";
    my $endpoints_list = $service->{endpoints};
    for my $endpoint (@{$endpoints_list}) {
        next unless "$endpoint->{interface}" eq "$object_store_interface" and
                    "$endpoint->{region}" eq "$region";
        print "$endpoint->{url}";
        last ENDPOINT;
    }
}
