package Data::Sah::Tiny;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010001;
use strict 'refs', 'vars';
use warnings;
use Log::ger;

use Data::Sah::Normalize qw(normalize_schema);

use Exporter qw(import);
our @EXPORT_OK = qw(gen_validator normalize_schema);

# data_term, return_type must already be set
sub _gen_src_code {
    my ($schema0, $opts) = @_;

    my $nschema = $opts->{schema_is_normalized} ?
        $schema0 : normalize_schema($schema0);
    log_trace "normalized schema: %s", $nschema;
    my $type = $nschema->[0];
    my $clset = { %{$nschema->[1]} };
    my $dt = $opts->{data_term};

    my $src = '';

    my $code_fail_unless = sub { my $cond = shift; $src .= ($opts->{_fail_stmt}    // " return " . ($opts->{return_type} eq 'bool_valid+val' ? "[0,$dt]" : "0"))." unless $cond;" };
    my $code_success_if  = sub { my $cond = shift; $src .= ($opts->{_success_stmt} // " return " . ($opts->{return_type} eq 'bool_valid+val' ? "[1,$dt]" : "1"))." if $cond;"     };

    require Data::Dmp;

    # first, handle 'default'
    if (exists $clset->{default}) {
        if ($dt =~ /\A\$_\[\d+\]\z/) {
            $src .= "my \$_dst_tmp = $dt; ";
            $dt = "\$_dst_tmp";
        }
        $src .= "$dt = ".Data::Dmp::dmp($clset->{default}).
            " unless defined $dt;";
    }
    delete $clset->{default};

    # then handle 'req'
    if (delete $clset->{req}) {
        $code_fail_unless->("defined($dt)");
    } else {
        $code_success_if->("!defined($dt)");
    }

  PROCESS_BUILTIN_TYPES: {
        if ($type eq 'int') {
            $code_fail_unless->("!ref($dt) && $dt =~ /\\A-?[0-9]+\\z/");
            if (defined(my $val = delete $clset->{min})) { $code_fail_unless->("$dt >= $val") }
            if (defined(my $val = delete $clset->{max})) { $code_fail_unless->("$dt <= $val") }
        } elsif ($type eq 'array') {
            $code_fail_unless->("ref($dt) eq 'ARRAY'");
            if (defined(my $val = delete $clset->{min_len})) { $code_fail_unless->("\@{$dt} >= $val") }
            if (defined(my $val = delete $clset->{max_len})) { $code_fail_unless->("\@{$dt} <= $val") }
            if (defined(my $val = delete $clset->{of})) {
                my $src_sub = _gen_src_code(
                    $val,
                    {
                        data_term => "\$_dst_elem",
                        return_type=>'bool_valid',
                        _fail_stmt    => '($ok=0, last)',
                        _success_stmt => '($ok=0, last)',
                    },
                );
                $code_fail_unless->("do { my \$ok=1; for my \$_dst_elem (\@{$dt}) { $src_sub } \$ok }");
            }
        } else {
            die "Unknown type '$type'";
        }

        if (keys %$clset) {
            die "Unknown clause(s) for type '$type': ".
                join(", ", sort keys %$clset);
        }
    }

    $src .= $opts->{return_type} eq 'bool_valid+val' ?
        " [1, $dt]" : " 1";

    $src;
}

sub gen_validator {
    my ($schema, $opts0) = @_;
    $opts0 //= {};

    my $opts = {};
    $opts->{_level} = 1;
    $opts->{schema_is_normalized} = delete $opts0->{schema_is_normalized};
    $opts->{source} = delete $opts0->{source};
    $opts->{return_type} = delete $opts0->{return_type} // "bool_valid";
    $opts->{return_type} =~ /\A(bool_valid\+val|bool_valid)\z/
        or die "return_type must be bool_valid or bool_valid+val";
    $opts->{data_term} = $opts0->{data_term} // '$_[0]';
    keys %$opts0 and die "Unknown option(s): ".join(", ", sort keys %$opts0);

    my $dt0 = $opts->{data_term};
    my $src0 = _gen_src_code($schema, $opts);
    my $src = join(
        "",
        "sub {",
        ($dt0 eq '$_[0]' ? '' : " my $dt0;"),
        $src0,
        " }",
    );
    return $src if $opts->{source};

    my $code = eval $src;
    die if $@;
    $code;
}

1;
# ABSTRACT: Make human-readable terse representation of Sah schema

=head1 SYNOPSIS

 use Data::Sah::Terse qw(terse_schema);

 say terse_schema("int");                                      # int
 say terse_schema(["int*", min=>0, max=>10]);                  # int
 say terse_schema(["array", {of=>"int"}]);                     # array[int]
 say terse_schema(["any*", of=>['int',['array'=>of=>"int"]]]); # int|array[int]


=head1 DESCRIPTION


=head1 FUNCTIONS

None exported by default, but they are exportable.

=head2 terse_schema($sch[, \%opts]) => str

Make a human-readable terse representation of Sah schema. Currently only schema
type is shown, all clauses are ignored. Special handling for types C<array>,
C<any> and C<all>. This routine is suitable for showing type in a function or
CLI help message.

Options:

=over

=item * schema_is_normalized => bool

=back


=head1 SEE ALSO

L<Data::Sah::Compiler::human>

=cut
