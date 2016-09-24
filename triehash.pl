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
my $enum_name = "PerfectKey";
my $function_name = "PerfectHash";
my $enum_class = 0;

my $code_name = "-";
my $header_name = "-";


GetOptions ("code=s" => \$code_name,
            "header|H=s"   => \$header_name,
            "function-name=s" => \$function_name,
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

    sub print_table {
        my ($self, $fh, $indent, $index) = @_;
        $indent //= 0;
        $index //= 0;
        
        printf $fh (("    " x $indent) . "switch(%d < length ? string[%d] : 0) {\n", $index, $index);

        foreach my $key (sort keys %{$self->{children}}) {
            printf $fh ("    " x $indent . "case '%s':\n", lc($key));
            printf $fh ("    " x $indent . "case '%s':\n", uc($key)) if lc($key) ne uc($key);

            $self->{children}{$key}->print_table($fh, $indent + 1, $index + 1);
        }

        printf $fh ("    " x $indent . "case 0: return %s;\n", ($enum_class ? "${enum_name}::" : "").$self->{label}) if defined $self->{value};
        printf $fh ("    " x $indent . "default: return %s$unknown_label;\n", ($enum_class ? "${enum_name}::" : ""));
        printf $fh ("    " x $indent . "}\n");
    }

    sub print_words {
        my ($self, $fh, $indent, $sofar) = @_;

        $indent //= 0;
        $sofar //= "";


        printf $fh ("    " x $indent."%s = %s,\n", $self->{label}, $self->{value}) if defined $self->{value};

        foreach my $key (sort keys %{$self->{children}}) {
            $self->{children}{$key}->print_words($fh, $indent, $sofar . $key);
        }
    }
}

my $trie = Trie->new;
my $static = ($code_name eq $header_name) ? "static" : "";
my $code = *STDOUT;
my $header = *STDOUT;
my $enum_specifier = $enum_class ? "enum class" : "enum";

open(my $input, '<', $ARGV[0]) or die "Cannot open ".$ARGV[0].": $!";
open($code, '>', $code_name) or die "Cannot open ".$ARGV[0].": $!" if ($code_name ne "-");
open($header, '>', $header_name) or die "Cannot open ".$ARGV[0].": $!" if ($header_name ne "-");


sub word_to_label {
    my $word = shift;

    $word =~ s/-/_/g;
    return $word;
}


my $counter = $counter_start;
while (my $line = <$input>) {
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

print $header ("#include <stddef.h>\n");
print $header ("enum { ${enum_name}Max = $counter };\n");
print $header ("${enum_specifier} ${enum_name} {\n");
$trie->print_words($header, 1);
printf $header ("    $unknown_label = $unknown,\n");
print $header ("};\n");
print $header ("$static enum ${enum_name} ${function_name}(const char *string, size_t length);\n");

print $code ("$static enum ${enum_name} ${function_name}(const char *string, size_t length)\n");
print $code ("{\n");
$trie->print_table($code, 1);
print $code ("}\n");


=head1 LICENSE

triehash is available under the MIT/Expat license, see the source code
for more information.

=head1 AUTHOR

Julian Andres Klode <jak@jak-linux.org>

=cut

