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

=item B<-c>I<.c file> B<--code>=I<.c file>

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

    sub print_table {
        my ($self, $index) = @_;
        $index = 0 if !defined($index);
        
        printf(("    " x $index) . "switch(%d < length ? string[%d] : 0) {\n", $index, $index);

        foreach my $key (sort keys %{$self->{children}}) {
            printf "    " x $index . "case '%s':\n", lc($key);
            printf "    " x $index . "case '%s':\n", uc($key) if (lc($key) ne uc($key));

            $self->{children}{$key}->print_table($index + 1);
        }

        printf("    " x $index . "case 0: return %s;\n", $self->{value}) if defined($self->{value});
        printf("    " x $index . "default: return $unknown;\n");
        printf("    " x $index . "}\n");
    }

    sub print_words {
        my ($self, $sofar) = @_;

        $sofar = "" if !defined($sofar);

        printf "%s = %s,\n", $self->{label}, $self->{value} if defined $self->{value};

        foreach my $key (sort keys %{$self->{children}}) {
            $self->{children}{$key}->print_words($sofar . $key);
        }
    }
}

my $trie = Trie->new;

sub word_to_label {
    my $word = shift;

    $word =~ s/-/_/g;
    return $word;
}


open(my $fh, '<', $ARGV[0]) or die "Cannot open ".$ARGV[0].": $!";


my $counter = $counter_start;
while (my $line = <$fh>) {
    my ($label, $word, $value) = $line =~/\s*(?:([^~\s]+)\s*~)?(?:\s*([^~=\s]+)\s*)?(?:=\s*([^\s]+)\s+)?\s*/;

    if (defined $word) {
        $counter = $value if defined($value);
        $label //= word_to_label($word);

        $trie->insert($word, $label, $counter);
        $counter++;
    } elsif (defined $value) {
        $unknown = $value;
        $unknown_label = $label if defined($label);
        $counter = $value + 1;
    } else {
        die "Invalid line: $line";
    }
}

print("#include <stddef.h>\n");
print("static int PerfectHashMax = $counter;\n");
print("static int PerfectHash(const char *string, size_t length)\n");
print("{\n");
$trie->print_table();
print("}\n");
print("enum class PerfectKey {\n");
$trie->print_words();
printf("$unknown_label = $unknown,\n");
print("};\n");

=head1 LICENSE

triehash is available under the MIT/Expat license, see the source code
for more information.

=head1 AUTHOR

Julian Andres Klode <jak@jak-linux.org>

=cut

