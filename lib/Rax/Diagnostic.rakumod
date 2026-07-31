unit module Rax::Diagnostic;

sub error-diagnostic(
    Str :$code!,
    Str :$message!,
    Map :$primary!,
    List :$secondary = ().List,
    List :$notes = ().List,
    --> Map,
) is export {
    %(
        severity  => 'error',
        code      => $code,
        message   => $message,
        primary   => $primary,
        secondary => $secondary,
        notes     => $notes,
    ).Map
}
