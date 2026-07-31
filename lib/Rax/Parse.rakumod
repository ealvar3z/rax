unit module Rax::Parse;

use Rax::Actions;
use Rax::Diagnostic;
use Rax::Grammar;
use Rax::Span;

sub continuation-byte(Int $byte --> Bool) {
    $byte >= 0x80 && $byte <= 0xBF
}

sub utf8-error-offset(Buf $bytes --> Int) {
    my $index = 0;

    while $index < $bytes.elems {
        my $first = $bytes[$index];

        if $first <= 0x7F {
            $index++;
            next;
        }

        if $first >= 0xC2 && $first <= 0xDF {
            return $index if $index + 1 >= $bytes.elems;
            return $index unless continuation-byte($bytes[$index + 1]);
            $index += 2;
            next;
        }

        if $first == 0xE0 {
            return $index if $index + 2 >= $bytes.elems;
            return $index unless $bytes[$index + 1] >= 0xA0 && $bytes[$index + 1] <= 0xBF;
            return $index unless continuation-byte($bytes[$index + 2]);
            $index += 3;
            next;
        }

        if ($first >= 0xE1 && $first <= 0xEC) || ($first >= 0xEE && $first <= 0xEF) {
            return $index if $index + 2 >= $bytes.elems;
            return $index unless continuation-byte($bytes[$index + 1]);
            return $index unless continuation-byte($bytes[$index + 2]);
            $index += 3;
            next;
        }

        if $first == 0xED {
            return $index if $index + 2 >= $bytes.elems;
            return $index unless $bytes[$index + 1] >= 0x80 && $bytes[$index + 1] <= 0x9F;
            return $index unless continuation-byte($bytes[$index + 2]);
            $index += 3;
            next;
        }

        if $first == 0xF0 {
            return $index if $index + 3 >= $bytes.elems;
            return $index unless $bytes[$index + 1] >= 0x90 && $bytes[$index + 1] <= 0xBF;
            return $index unless continuation-byte($bytes[$index + 2]);
            return $index unless continuation-byte($bytes[$index + 3]);
            $index += 4;
            next;
        }

        if $first >= 0xF1 && $first <= 0xF3 {
            return $index if $index + 3 >= $bytes.elems;
            return $index unless continuation-byte($bytes[$index + 1]);
            return $index unless continuation-byte($bytes[$index + 2]);
            return $index unless continuation-byte($bytes[$index + 3]);
            $index += 4;
            next;
        }

        if $first == 0xF4 {
            return $index if $index + 3 >= $bytes.elems;
            return $index unless $bytes[$index + 1] >= 0x80 && $bytes[$index + 1] <= 0x8F;
            return $index unless continuation-byte($bytes[$index + 2]);
            return $index unless continuation-byte($bytes[$index + 3]);
            $index += 4;
            next;
        }

        return $index;
    }

    -1
}

sub parse-failure(Str $file, List $diagnostics --> Map) {
    %(
        ok          => False,
        file        => $file,
        module      => Nil,
        diagnostics => $diagnostics,
    ).Map
}

sub parse-bytes(Buf $bytes, Str :$file = '<memory>' --> Map) is export {
    my %context = source-context($bytes, :$file);
    my $invalid-offset = utf8-error-offset($bytes);

    if $invalid-offset >= 0 {
        my $end = $invalid-offset + 1;
        return parse-failure(
            $file,
            (error-diagnostic(
                code    => 'RAX0001',
                message => 'invalid UTF-8 sequence',
                primary => span-at(%context, $invalid-offset, $end),
            ),).List,
        );
    }

    my $source = $bytes.decode('utf8');
    my $actions = Actions.new(context => %context.Map);
    my $match = Rax::Grammar.subparse($source, :actions($actions));

    unless $match.defined && $match.from == 0 {
        return parse-failure(
            $file,
            (error-diagnostic(
                code    => 'RAX0002',
                message => 'invalid Rax syntax',
                primary => span-at(%context, 0, 0),
            ),).List,
        );
    }

    if $match.to != $bytes.elems {
        return parse-failure(
            $file,
            (error-diagnostic(
                code    => 'RAX0002',
                message => 'unexpected trailing source',
                primary => span-at(%context, $match.to, $match.to),
            ),).List,
        );
    }

    my $diagnostics = $actions.diagnostics;
    if $diagnostics.elems {
        return parse-failure($file, $diagnostics);
    }

    %(
        ok          => True,
        file        => $file,
        module      => $match.made,
        diagnostics => ().List,
    ).Map
}
