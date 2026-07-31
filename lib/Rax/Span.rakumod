unit module Rax::Span;

sub source-context(Buf $bytes, Str :$file = '<memory>' --> Map) is export {
    %(
        file  => $file,
        bytes => $bytes,
    ).Map
}

sub utf8-width(Int $byte --> Int) {
    return 1 if $byte < 0x80;
    return 2 if $byte < 0xE0;
    return 3 if $byte < 0xF0;
    4
}

sub line-column(%context, Int $offset --> List) {
    my $bytes = %context<bytes>;
    my $line = 1;
    my $column = 1;
    my $index = 0;

    while $index < $offset {
        my $byte = $bytes[$index];

        if $byte == 0x0D && $index + 1 < $bytes.elems && $bytes[$index + 1] == 0x0A {
            $index += 2;
            $line++;
            $column = 1;
        }
        elsif $byte == 0x0A {
            $index++;
            $line++;
            $column = 1;
        }
        else {
            $index += utf8-width($byte);
            $column++;
        }
    }

    ($line, $column).List
}

sub span-at(%context, Int $start, Int $end --> Map) is export {
    my ($line, $column) = line-column(%context, $start);

    %(
        file   => %context<file>,
        offset => $start,
        line   => $line,
        column => $column,
        length => $end - $start,
    ).Map
}
