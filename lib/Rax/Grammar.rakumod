unit grammar Rax::Grammar;

token ws {
    [ \s+ | '#' <-[\n]>* ]*
}

rule TOP {
    <.ws> <export-statement> <.ws>
}

rule export-statement {
    'export' 'default' '=' <expression> ';'
}

proto rule expression {*}

rule expression:sym<nil> {
    'Nil'
}

rule expression:sym<bool> {
    'True' | 'False'
}

token expression:sym<rat> {
    '-'? <[0..9]>+ '/' <[0..9]>+
}

token expression:sym<int> {
    '-'? <[0..9]>+
}

token expression:sym<str> {
    <string>
}

rule expression:sym<list> {
    '[' [ <expression>+ % ',' ]? [ ',' ]? ']'
}

rule expression:sym<map> {
    '{' [ <pair>+ % ',' ]? [ ',' ]? '}'
}

rule pair {
    <key> '=>' <expression>
}

token key {
    <identifier> | <string>
}

token identifier {
    <[A..Za..z_]> <[A..Za..z0..9_-]>*
}

token string {
    '"' [ <escape> | <-["\\\n\r]> ]* '"'
}

token escape {
    '\\' <["\\nrt]>
}
