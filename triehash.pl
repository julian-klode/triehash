#!/usr/bin/perl -w
#
# Copyright (C) 2016 Julian Andres Klode <jak@jak-linux.org>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.


=head1 NAME

triehash - Generate a perfect hash function derived from a trie.

=cut

use strict;
use warnings;
use Getopt::Long;

=head1 SYNOPSIS

B<triehash> [S<I<option>>] [S<I<input file>>]

=head1 DESCRIPTION

triehash takes a list of words in input file and generates a function and
an enumeration to describe the word

=head1 INPUT FILE FORMAT

The file consists of multiple lines of the form:

    [label ~ ] word [= value]

This maps word to value, and generates an enumeration with entries of the form:

    label = value

If I<label> is undefined, the word will be used, the minus character will be
replaced by an underscore. If value is undefined it is counted upwards from
the last value.

There may also be one line of the format

    [ label ~] = value

Which defines the value to be used for non-existing keys. Note that this also
changes default value for other keys, as for normal entries. So if you place

    = 0

at the beginning of the file, unknown strings map to 0, and the other strings
map to values starting with 1. If label is not specified, the default is
I<Unknown>.

=head1 OPTIONS

=over 4

=item B<-C>I<.c file> B<--code>=I<.c file>

Generate code in the given file.

=item B<-H>I<header file> B<--header>=I<header file>

Generate a header in the given file, containing a declaration of the hash
function and an enumeration.

=item B<--enum-name=>I<word>

The name of the enumeration.

=item B<--function-name=>I<word>

The name of the function.

=item B<--namespace=>I<name>

Put the function and enum into a namespace (C++)

=item B<--class=>I<name>

Put the function and enum into a class (C++)

=item B<--enum-class>

Generate an enum class instead of an enum (C++)

=item B<--extern-c>

Wrap everything into an extern "C" block. Not compatible with the C++
options, as a header with namespaces, classes, or enum classes is not
valid C.

=back

=cut

my $unknown = -1;
my $unknown_label = "Unknown";
my $counter_start = 0;
my $enum_name = "PerfectKey";
my $function_name = "PerfectHash";
my $enum_class = 0;

my $code_name = "-";
my $header_name = "-";
my $code;
my $header;
my $ignore_case = 0;


Getopt::Long::config('default',
                     'bundling',
                     'no_getopt_compat',
                     'no_auto_abbrev',
                     'permute',
                     'auto_help');

GetOptions ("code|C=s" => \$code_name,
            "header|H=s"   => \$header_name,
            "function-name=s" => \$function_name,
            "ignore-case" => \$ignore_case,
            "enum-name=s" => \$enum_name,
            "enum-class" => \$enum_class)
    or die("Could not parse options!");


package Trie {

    sub new {
        my $class = shift;
        my $self = {};
        bless $self, $class;

        $self->{children} = {};
        $self->{value} = undef;
        $self->{label} = undef;

        return $self;
    }

    sub insert {
        my ($self, $key, $label, $value) = @_;

        if (length($key) == 0) {
            $self->{label} = $label;
            $self->{value} = $value;
            return;
        }

        my $child = substr($key, 0, 1);
        my $tail = substr($key, 1);

        $self->{children}{$child} = Trie->new if (!defined($self->{children}{$child}));

        $self->{children}{$child}->insert($tail, $label, $value);
    }

    sub filter_depth {
        my ($self, $togo) = @_;

        my $new = Trie->new;

        if ($togo != 0) {
            my $found = 0;
            foreach my $key (sort keys %{$self->{children}}) {
                if ($togo > 1 || defined $self->{children}{$key}->{value}) {
                    my $child = $self->{children}{$key}->filter_depth($togo - 1);

                    $new->{children}{$key}= $child if defined $child;
                    $found = 1 if defined $child;
                }
            }
            return undef if (!$found);
        } else {
            $new->{value} = $self->{value};
            $new->{label} = $self->{label};
        }

        return $new;
    }
}

# Code generator for C and C++
package CCodeGen {
    my $static = ($code_name eq $header_name) ? "static" : "";
    my $enum_specifier = $enum_class ? "enum class" : "enum";

    sub new {
        my $class = shift;
        my $self = {};
        bless $self, $class;

        return $self;
    }

    sub open_output {
        my $self = shift;
        if ($code_name ne "-") {
            open($code, '>', $code_name) or die "Cannot open ".$ARGV[0].": $!" ;
        } else {
            $code = *STDOUT;
        }
        if($code_name eq $header_name) {
            $header = $code;
        } elsif ($header_name ne "-") {
            open($header, '>', $header_name) or die "Cannot open ".$ARGV[0].": $!" ;
        } else {
            $header = *STDOUT;
        }
    }

    sub word_to_label {
        my ($class, $word) = @_;

        $word =~ s/_/__/g;
        $word =~ s/-/_/g;
        return $word;
    }

    sub print_table {
        my ($self, $trie, $fh, $indent, $index) = @_;
        $indent //= 0;
        $index //= 0;

        if (defined $trie->{value}) {
            printf $fh ("    " x $indent . "return %s;\n", ($enum_class ? "${enum_name}::" : "").$trie->{label});
            return;
        }

        # The difference between lowercase and uppercase alphabetical characters
        # is that they have one bit flipped. If we have alphabetical characters
        # in the search space, and the entire search space works fine if we
        # always turn on the flip, just OR the character we are switching over
        # with the bit.
        my $want_use_bit = 0;
        my $can_use_bit = 1;
        foreach my $key (sort keys %{$trie->{children}}) {
            $can_use_bit &= not main::ambiguous($key);
            $want_use_bit |= ($key =~ /^[a-zA-Z]+$/);
        }

        if ($ignore_case && $can_use_bit && $want_use_bit) {
            printf $fh (("    " x $indent) . "switch(string[%d] | 32) {\n", $index);
        } else {
            printf $fh (("    " x $indent) . "switch(string[%d]) {\n", $index);
        }

        my $notfirst = 0;
        foreach my $key (sort keys %{$trie->{children}}) {
            if ($notfirst) {
                printf $fh ("    " x $indent . "    break;\n");
            }
            if ($ignore_case) {
                printf $fh ("    " x $indent . "case '%s':\n", lc($key));
                printf $fh ("    " x $indent . "case '%s':\n", uc($key)) if lc($key) ne uc($key) && !($can_use_bit && $want_use_bit);
            } else {
                printf $fh ("    " x $indent . "case '%s':\n", $key);
            }

            $self->print_table($trie->{children}{$key}, $fh, $indent + 1, $index + 1);

            $notfirst=1;
        }

        printf $fh ("    " x $indent . "}\n");
    }

    sub print_words {
        my ($self, $trie, $fh, $indent, $sofar) = @_;

        $indent //= 0;
        $sofar //= "";


        printf $fh ("    " x $indent."%s = %s,\n", $trie->{label}, $trie->{value}) if defined $trie->{value};

        foreach my $key (sort keys %{$trie->{children}}) {
            $self->print_words($trie->{children}{$key}, $fh, $indent, $sofar . $key);
        }
    }

    sub main {
        my ($self, $trie, $num_values, %lengths) = @_;
        print $header ("#ifndef TRIE_HASH_${function_name}\n");
        print $header ("#define TRIE_HASH_${function_name}\n");
        print $header ("#include <stddef.h>\n");
        print $header ("enum { ${enum_name}Max = $num_values };\n");
        print $header ("${enum_specifier} ${enum_name} {\n");
        $self->print_words($trie, $header, 1);
        printf $header ("    $unknown_label = $unknown,\n");
        print $header ("};\n");
        print $header ("$static enum ${enum_name} ${function_name}(const char *string, size_t length);\n");

        print $code ("#include \"$header_name\"\n") if ($header_name ne $code_name);

        foreach my $local_length (sort { $a <=> $b } (keys %lengths)) {
            print $code ("static enum ${enum_name} ${function_name}${local_length}(const char *string)\n");
            print $code ("{\n");
            $self->print_table($trie->filter_depth($local_length), $code, 1);
            printf $code ("    return %s$unknown_label;\n", ($enum_class ? "${enum_name}::" : ""));
            print $code ("}\n");
        }
        print $code ("$static enum ${enum_name} ${function_name}(const char *string, size_t length)\n");
        print $code ("{\n");
        print $code ("    switch (length) {\n");
        foreach my $local_length (sort { $a <=> $b } (keys %lengths)) {
            print $code ("    case $local_length:\n");
            print $code ("        return ${function_name}${local_length}(string);\n");
        }
        print $code ("    default:\n");
        printf $code ("        return %s$unknown_label;\n", ($enum_class ? "${enum_name}::" : ""));
        print $code ("    }\n");
        print $code ("}\n");

        # Print end of header here, in case header and code point to the same file
        print $header ("#endif                       /* TRIE_HASH_${function_name} */\n");
    }
}

# Check if the word can be reached by exactly one word in (alphabet OR 0x20).
sub ambiguous {
    my $word = shift;

    foreach my $char (split //, $word) {
        # Setting the lowercase flag in the character produces a different
        # character, the character would thus not be matched.
        return 1 if ((ord($char) | 0x20) != ord(lc($char)));

        # A word is also ambiguous if any character in lowercase can be reached
        # by ORing 0x20 from another character in the charset that is not a
        # lowercase character of the current character.
        # Assume that we have UTF-8 and the most significant bit can be set
        for (my $i = 0; $i < 256; $i++) {
            return 1 if (($i | 0x20) == ord(lc($char)) && lc(chr($i)) ne lc($char));
        }
    }

    return 0;
}

sub build_trie {
    my $codegen = shift;
    my $trie = Trie->new;

    my $counter = $counter_start;
    my %lengths;

    open(my $input, '<', $ARGV[0]) or die "Cannot open ".$ARGV[0].": $!";
    while (my $line = <$input>) {
        my ($label, $word, $value) = $line =~/\s*(?:([^~\s]+)\s*~)?(?:\s*([^~=\s]+)\s*)?(?:=\s*([^\s]+)\s+)?\s*/;

        if (defined $word) {
            $counter = $value if defined($value);
            $label //= $codegen->word_to_label($word);

            $trie->insert($word, $label, $counter);
            $lengths{length($word)} = 1;
            $counter++;
        } elsif (defined $value) {
            $unknown = $value;
            $unknown_label = $label if defined($label);
            $counter = $value + 1;
        } else {
            die "Invalid line: $line";
        }
    }

    return ($trie, $counter, %lengths);
}


my $codegen = CCodeGen->new();
my ($trie, $counter, %lengths) = build_trie($codegen);

$codegen->open_output();
$codegen->main($trie, $counter, %lengths);


=head1 LICENSE

triehash is available under the MIT/Expat license, see the source code
for more information.

=head1 AUTHOR

Julian Andres Klode <jak@jak-linux.org>

=cut

