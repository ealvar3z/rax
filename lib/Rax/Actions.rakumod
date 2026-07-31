unit module Rax::Actions;

use Rax::Diagnostic;
use Rax::Span;

enum ParseKind is export <Module Export Literal List Map Pair>;
enum LiteralKind is export <Nil Bool Int Rat Str>;

class Actions is export {
    has $.context;
    has @!diagnostics;

    method diagnostics(--> List) {
        @!diagnostics.List
    }

    method span($/) {
        span-at($!context, $/.from, $/.to)
    }

    method node($kind, $/, *%fields --> Map) {
        my %node = kind => $kind, span => self.span($/);
        for %fields.kv -> $key, $value {
            %node{$key} = $value;
        }
        %node.Map
    }

    method TOP($/) {
        make self.node(
            ParseKind::Module,
            $/,
            declarations => ($<export-statement>.made,).List,
        );
    }

    method export-statement($/) {
        make self.node(
            ParseKind::Export,
            $/,
            name       => 'default',
            expression => $<expression>.made,
        );
    }

    method expression:sym<nil>($/) {
        make self.node(
            ParseKind::Literal,
            $/,
            literal-kind => LiteralKind::Nil,
            raw          => ~$/,
        );
    }

    method expression:sym<bool>($/) {
        make self.node(
            ParseKind::Literal,
            $/,
            literal-kind => LiteralKind::Bool,
            raw          => ~$/,
        );
    }

    method expression:sym<int>($/) {
        make self.node(
            ParseKind::Literal,
            $/,
            literal-kind => LiteralKind::Int,
            raw          => ~$/,
        );
    }

    method expression:sym<rat>($/) {
        make self.node(
            ParseKind::Literal,
            $/,
            literal-kind => LiteralKind::Rat,
            raw          => ~$/,
        );
    }

    method expression:sym<str>($/) {
        make self.node(
            ParseKind::Literal,
            $/,
            literal-kind => LiteralKind::Str,
            raw          => ~$/,
        );
    }

    method expression:sym<list>($/) {
        my @items;
        if $<expression>.defined {
            @items = $<expression>.map({ .made }).Array;
        }
        make self.node(ParseKind::List, $/, items => @items.List);
    }

    method expression:sym<map>($/) {
        my @entries;
        if $<pair>.defined {
            @entries = $<pair>.map({ .made }).Array;
        }

        my %seen;
        for @entries -> $entry {
            my $key = $entry<key>;
            if %seen{$key}:exists {
                @!diagnostics.push: error-diagnostic(
                    code      => 'RAX0003',
                    message   => "duplicate map key \"$key\"",
                    primary   => $entry<key-span>,
                    secondary => (%seen{$key}<key-span>,).List,
                );
            }
            else {
                %seen{$key} = $entry;
            }
        }

        make self.node(ParseKind::Map, $/, entries => @entries.List);
    }

    method pair($/) {
        my $key-match = $<key>;
        my $key = ~$key-match;
        make self.node(
            ParseKind::Pair,
            $/,
            key      => $key,
            key-span => self.span($key-match),
            value    => $<expression>.made,
        );
    }
}
