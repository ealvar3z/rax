# Rax Design

**Status:** Draft 0  
**Project:** Rax, or Raku Expressions  
**Normative implementation:** Raku++ (`rakupp`)  
**Initial scope:** Milestone 0 through Milestone 2

The whitepaper explains why Rax should exist. This file says what must be true
when it does.

Rax is a small language and deployment engine for describing software builds as
pure data, realizing only the work requested, and storing each result as an
immutable object. It preserves the durable ideas of functional package
management while keeping the language, identity model, and security claims
small enough to inspect.

The governing sentence is:

> Rax is strict about meaning and lazy about work.

A Rax expression is evaluated eagerly and deterministically into a closed plan.
The plan may be inspected, encoded, hashed, signed, or transmitted before a
builder runs. Realization remains demand-driven: Rax builds only the selected
plan and its dependency closure.

## 1. Authority and Status

This document is the implementation contract for Rax.

When sources disagree, use this order:

1. executable conformance tests;
2. this `DESIGN.md`;
3. the Rax whitepaper;
4. `README.md` and examples.

The Rax Codex skill governs development practice but does not change language
semantics. The whitepaper may explore future work that this design has not yet
accepted.

The words **must**, **must not**, **should**, and **may** express requirements,
recommendations, and permitted choices within this project. Later sections are
marked provisional when implementation experience is still required.

## 2. Goals

Rax has eight primary goals.

1. Different versions and variants must coexist without overwriting one
   another.
2. Evaluation must produce a complete, canonical plan before ordinary build
   effects begin.
3. The requested computation and the realized output must have separate,
   verifiable identities.
4. Build authority must be explicit. Network, process, filesystem, clock, and
   environment access must not leak into pure evaluation.
5. Profiles, upgrades, downgrades, and rollbacks must be atomic root changes.
6. Garbage collection must follow explicit reachability and explain why an
   object remains live.
7. Source builds and binary substitutes must use the same realization model.
8. The core language, canonical encoding, and store protocol must remain small
   enough to reimplement independently.

## 3. Non-goals

Rax is not initially:

- an operating-system configuration language;
- a service manager;
- a package collection;
- a general replacement for Make, Ninja, or project-native build systems;
- a shell language;
- a Raku slang;
- a compatibility layer for Nix expressions or Guix package definitions;
- a promise that software is correct, benevolent, or vulnerability-free;
- a Rakudo compatibility project.

Rax may invoke an existing build system inside an authorized plan. It does not
need to reproduce that build system's internal language.

## 4. Normative Compiler Target

Raku++ is the normative compiler and runtime for Rax.

Rax must:

- run under the active supported `rakupp` interpreter;
- compile with `rakupp --exe`;
- produce equivalent observable results in interpreted and native modes;
- prefer a focused Raku++ regression test and compiler fix over a hidden
  compatibility workaround.

Rakudo parity is not a conformance requirement. Contributors may propose Rakudo
support as a separate patch, but Rax must not narrow its design merely to keep a
second implementation green.

When Raku semantics are unclear, another implementation or the language
specification may provide investigative evidence. Raku++ behavior remains the
project's executable authority unless Rax has exposed a compiler defect that is
then corrected.

## 5. Architectural Invariants

These invariants hold unless this document is deliberately amended.

- `.rax` is a pure external domain-specific language parsed by a Raku grammar
  and actions object.
- Rax does not depend on slangs, macros, RakuAST, arbitrary parse-time grammar
  mutation, or `EVAL`.
- Parsing, evaluation, source resolution, lowering, realization, storage, and
  policy are distinct phases.
- Later phases never interpret surface syntax.
- Evaluation is eager and deterministic by default.
- Imports are explicit and memoized; unrelated modules are not evaluated.
- A closed Plan IR contains no thunks, callables, match objects, open files, or
  ambient resources.
- Canonical identity is derived from semantic data, never source spelling,
  pretty output, native hash iteration order, locale, or timestamps.
- Plan identity and realized-object identity are separate.
- Store objects are immutable after commit.
- Profiles are roots into the store, not alternate installation spaces.
- Structured build steps are the default. Shell is an explicit escape hatch.
- Runtime references are declared; scanning verifies them.
- Network access belongs to explicit source fetchers, never evaluation or an
  ordinary build.
- The initial store is daemonless, per-user, and POSIX-oriented.

## 6. System Pipeline

The complete pipeline is:

```text
.rax source
  -> lexer provided by Rax::Grammar
  -> grammar and actions
  -> source-spanned surface AST
  -> pure strict evaluator
  -> PlanSpec
  -> explicit source resolver
  -> closed canonical Plan IR
  -> PlanId
  -> dependency scheduler
  -> capability-constrained realizer
  -> normalized output tree
  -> ObjectId
  -> realization record
  -> profile, cache, and trust policy
```

The distinction between `PlanSpec` and Plan IR is intentional.

A `PlanSpec` may contain explicit source requests such as a fixed-output HTTPS
source, a Git revision, or a local source-tree request. The evaluator may create
these values but may not perform their effects. The resolver closes each request
into an immutable identity or rejects it. Only the resulting closed Plan IR is
canonical and hashable as a `PlanId`.

For example:

- an HTTPS source with a declared SHA-256 digest can be closed without fetching
  its bytes;
- a Git source must name an immutable revision and a content identity accepted
  by the resolver policy;
- a local tree must be read, normalized, and imported before it can enter a
  closed plan.

No unresolved local path, floating branch, mutable tag, or ambient search result
may enter a Plan IR.

## 7. Rax Language

### 7.1 Character and source model

Rax source is UTF-8. Invalid UTF-8 is a parse error.

Source positions record:

```text
file
byte offset
line
column
length
```

Line and column are for diagnostics. Byte offsets and lengths are the
unambiguous source coordinates.

The grammar must preserve spans for every declaration and expression that can
produce a diagnostic.

### 7.2 Initial expression forms

Milestone 0 supports only:

- `Nil`, Boolean, integer, rational, string, and path literals;
- lists, maps, sets, and pairs;
- lexical bindings;
- named pure routines;
- positional and named arguments;
- routine calls;
- conditionals;
- assertions;
- explicit imports;
- field and index selection;
- exports;
- calls to the fixed Rax prelude.

Milestone 0 excludes:

- mutation and assignment;
- classes, roles, and object metaprogramming;
- arbitrary methods;
- user-defined operators;
- macros and slangs;
- runtime evaluation;
- implicit infinite sequences;
- concurrency;
- process, network, clock, environment, and arbitrary filesystem operations.

### 7.3 Surface syntax

The final grammar is frozen by the end of Milestone 0. Until then, syntax may
change while the semantic model remains stable.

The preferred direction is recognizably Raku-like without pretending that a
`.rax` file is unrestricted Raku:

```raku
sub mk-hello(Bool :$tests = False --> Plan) {
    package(
        name    => "hello",
        version => "2.12.1",

        source => fetch(
            url    => "https://example.invalid/hello-2.12.1.tar.gz",
            sha256 => "...",
        ),

        inputs => {
            build   => [$cc, $make],
            runtime => [$libc],
        },

        outputs => <out>,

        steps => [
            exec($src.child("configure"),
                arg("--prefix=", out("out"))),
            exec($make),
            $tests ?? exec($make, "check") !! skip(),
            exec($make, "install"),
        ],
    )
}

export default = mk-hello();
```

This example is illustrative until the grammar tests declare it normative.

### 7.4 Bindings and routines

Bindings are immutable. A name is introduced once within a lexical scope.
Shadowing in a nested scope is allowed; duplicate declaration in the same scope
is an error.

Routines are pure values during evaluation but must be fully applied before a
closed plan is produced. A callable may exist in evaluator state; it may not
appear in Plan IR.

Recursion is excluded from Milestone 0 unless a demonstrated package-expression
need requires it. If later admitted, direct and mutual recursion must be
explicit and cycle-safe.

### 7.5 Evaluation strategy

Evaluation is strict:

- arguments are evaluated before a call;
- collection members are evaluated before construction;
- bindings hold values, not implicit thunks;
- a selected export must reduce to a closed value or a diagnostic.

Evaluation remains selective:

- only imports needed by the selected module path are loaded;
- imports are evaluated at most once per evaluation session;
- only the selected export is lowered to a plan;
- only the selected plan closure is later realized.

Rax is therefore eager about meaning without being eager about the package
universe.

### 7.6 Truth, equality, and numbers

Booleans are the only values accepted directly as conditions in Milestone 0.
Rax does not inherit broad host-language truthiness accidentally.

Integers are arbitrary precision. Rationals are exact and normalized to a
positive denominator. Floating-point numbers are not admitted into Plan IR.

Equality is structural over the Rax value algebra. Paths compare after Rax path
normalization. Plan and source records compare by semantic fields, not object
identity.

### 7.7 Maps and duplicate keys

Plan maps use string keys. Map key order has no semantic meaning.

Duplicate keys in source are errors, even when the duplicate values are equal.
Silent last-write-wins behavior would hide mistakes and make diagnostics depend
on construction order.

### 7.8 Paths

A Rax path is not a host `IO::Path` object. It is an immutable semantic value.

Plan paths:

- use `/` as the separator;
- contain valid UTF-8;
- contain no empty component, `.` component, or `..` component;
- are relative unless represented by a typed store or output reference;
- never consult the host current directory during canonical encoding.

Host paths exist only in boundary adapters and are converted to source requests
or rejected before Plan IR.

### 7.9 Imports

Imports are explicit and closed under a deterministic resolution policy.

Milestone 0 supports relative file imports. Search paths supplied by the CLI may
be added later, but their ordered values must be explicit inputs to evaluation.
No zef repository, environment variable, current module cache, or host-specific
library path is searched implicitly.

An import cycle is a diagnostic in Milestone 0.

Imported modules expose named exports. Private bindings do not cross the module
boundary.

## 8. Surface AST

The AST is data, not a class hierarchy.

A node has at least:

```raku
%(
    kind => NodeKind::Call,
    span => %span,
    ...node-specific fields...
).Map
```

The AST uses immutable `Map`, `List`, `Pair`, and scalar values where supported
cleanly by Raku++. Finite tags use enums.

The AST must preserve distinctions needed for good diagnostics even when those
distinctions disappear after evaluation. Examples include literal spelling,
named versus positional arguments, and declaration spans.

`Match` objects must not leave `Rax::Actions`.

## 9. Runtime Value Algebra

The evaluator may use only this initial semantic algebra:

```text
Nil
Bool
Int
Rat
Str
Path
List
Map
Set
SourceSpec
InputSpec
OutputSpec
StepSpec
PlanSpec
Callable        evaluator only
Module          evaluator only
```

The closed Plan IR uses:

```text
Nil
Bool
Int
Rat
Str
Path
List
Map
Set
Source
Input
Output
Step
Plan
```

The following are rejected before canonical encoding:

- `Num` and other floating-point values;
- `Match`;
- arbitrary Raku objects;
- open files and sockets;
- promises, supplies, and channels;
- callables;
- exceptions;
- native pointers;
- host process or environment handles.

## 10. PlanSpec and Closed Plan IR

### 10.1 PlanSpec

A `PlanSpec` is the pure evaluator's result. Its conceptual shape is:

```raku
%(
    schema       => "rax.plan-spec/1",
    name         => "hello",
    version      => "2.12.1",
    target       => %target,
    sources      => %source-specs,
    inputs       => %input-specs,
    outputs      => @outputs,
    environment  => %environment,
    steps        => @steps,
    capabilities => $capabilities,
    metadata     => %metadata,
).Map
```

Human metadata that does not affect realization must be placed in a
non-semantic envelope and excluded explicitly. The default rule is conservative:
if a field can alter output bytes or builder behavior, it is semantic.

### 10.2 Source

A closed source contains an immutable content identity and one or more locators:

```raku
%(
    kind      => SourceKind::Archive,
    digest    => "sha256:...",
    locators  => ["https://..."],
    unpack    => %unpack-policy,
).Map
```

Locators do not establish identity. They say where bytes may be sought. The
resolver or fetcher must reject bytes that do not match the declared identity.

### 10.3 Inputs

Inputs are typed:

```text
source   immutable source material
tool     build helper not expected at runtime
build    dependency required while building
host     target-linked or target-loaded dependency
runtime  dependency required by the installed output
```

An input record names a specific output of another Plan or an immutable source
object. Human package names are metadata, not identity.

### 10.4 Outputs

Each Plan declares one or more named outputs. Milestone 0 may use only `out`, but
the IR supports multiple names from its first version.

An output declaration includes:

```raku
%(
    name       => "out",
    references => $declared-reference-policy,
    normalize  => %tree-normalization-policy,
).Map
```

### 10.5 Steps

Structured steps form a closed algebra. The initial planned set is:

```text
Exec
Mkdir
Copy
Move
Remove
Write
Symlink
Unpack
Patch
Skip
Script
```

Milestone 2 need not implement every step. It must implement the smallest subset
needed for one complete local build.

Each step is data. For example:

```raku
%(
    kind => StepKind::Exec,
    program => $make,
    argv => ["install"],
    cwd => path("build"),
    env => {},
).Map
```

`Script` is the explicit shell escape hatch. Its interpreter, script bytes,
arguments, environment, inputs, and capabilities all contribute to `PlanId`.

### 10.6 Capabilities

The initial capability vocabulary is:

```text
ReadInput
WriteOutput
WriteTemporary
ExecuteDeclared
SetNormalizedEnvironment
```

Future explicit capabilities may include network fetching, limited devices, or
platform-specific sandbox features. An ordinary build receives no network,
clock, user-home, arbitrary-host-path, or undeclared-executable capability.

Capabilities describe permission, not proof of enforcement. Realization records
must report the isolation level actually achieved.

## 11. Canonical Encoding: RAX-CANON/1

`RAX-CANON/1` is the normative encoding for semantic Rax values and Plan IR.
It is independent of Raku serialization and pretty printing.

The encoding must be:

- deterministic;
- prefix-free;
- byte-oriented;
- independently implementable;
- versioned from its first byte;
- stable across interpreted and native Raku++ modes.

The stream begins with:

```text
RAX-CANON/1\0
```

The conceptual type grammar is:

```text
N                     Nil
B 0|1                 Bool
I length:decimal      Int
Q integer integer     normalized Rat numerator and denominator
S length:utf8-bytes   Str
P length:utf8-bytes   Path
L count values...     List
M count pairs...      Map
E count values...     Set
T tag fields          tagged Plan IR record
```

The concrete byte tags and delimiters must be frozen by golden tests before the
first `PlanId` is treated as durable.

Rules:

- integers use minimal signed decimal spelling with no leading zeroes;
- zero is `0`, never `-0`;
- rationals are reduced and have a positive denominator;
- strings are normalized to the selected Unicode normalization form before
  encoding; Milestone 0 must choose and test that form explicitly;
- lengths count bytes, not graphemes or code points;
- list order is preserved;
- map entries are sorted by the canonical bytes of their string keys;
- set members are sorted by their complete canonical bytes;
- duplicate canonical map keys or set values are errors before encoding;
- paths use Rax path normalization;
- tagged records encode a stable tag plus a map of fields;
- no timestamp, locale, host order, memory address, or source span enters a
  semantic encoding.

Source spans and diagnostics may use a separate noncanonical format.

## 12. Digest Model

Rax identifiers carry their algorithm:

```text
plan:sha256:<hex>
object:sha256:<hex>
source:sha256:<hex>
```

Milestone 0 uses SHA-256 through a narrow digest interface.

```text
PlanId = SHA-256(RAX-CANON/1(Plan))
```

The initial implementation should provide a pure Raku SHA-256 reference module
that runs under Raku++. It must pass published known-answer vectors. Optional
development checks may compare it with the host `shasum` utility, but Rax
runtime behavior must not depend on that executable.

A future digest algorithm requires a new algorithm label. Existing identifiers
retain their original meaning.

## 13. Object Trees and RAX-TREE/1

`ObjectId` identifies a normalized filesystem tree, not unfiltered host
metadata.

```text
ObjectId = SHA-256(RAX-TREE/1(tree))
```

The first tree format supports:

- directories;
- regular files with an executable Boolean and byte contents;
- symbolic links with normalized textual targets.

Milestone 1 excludes or normalizes away:

- ownership;
- access-control lists;
- timestamps;
- device nodes;
- sockets;
- platform-specific flags;
- extended attributes;
- sparse-file layout;
- hard-link identity.

Unsupported entries cause an explicit error rather than silent omission.

Tree entries are ordered by canonical path bytes. A tree path is relative,
normalized, valid UTF-8, and contains no `.` or `..` component.

### 13.1 Self references

A build may retain its own output path. Because the final `ObjectId` is not known
before the build, self references require a deliberate protocol.

The provisional Rax protocol is:

1. assign each output a fixed-length placeholder derived from `PlanId` and the
   output name;
2. expose that placeholder as the build output path;
3. after build, locate exact placeholder references in output files;
4. canonicalize those references as a typed self-reference marker while
   computing `RAX-TREE/1`;
5. compute `ObjectId`;
6. rewrite fixed-length placeholders to the final object path;
7. verify the final tree by normalizing its self path back to the same marker.

The placeholder and final object path must have equal byte length. Reference
rewriting is exact byte replacement, never a general textual substitution.

This protocol is provisional until Milestone 2 proves it. Before then, builds
that retain temporary output paths must be rejected rather than committed.

References to dependencies use their immutable object paths and therefore enter
the tree hash directly.

## 14. Dual Identity and Realizations

Rax separates request from result.

```text
PlanId
    identifies the closed requested computation

ObjectId
    identifies one normalized realized output tree
```

A realization record connects them:

```raku
%(
    schema       => "rax.realization/1",
    plan-id      => $plan-id,
    platform     => $platform,
    output       => "out",
    object-id    => $object-id,
    references   => @object-ids,
    builder      => %builder-facts,
    capabilities => @granted-capabilities,
    isolation    => $isolation-level,
    log-digest   => $log-digest,
).Map
```

More than one `ObjectId` may exist for the same `(PlanId, platform, output)`.
Rax must preserve that conflict as evidence of nondeterminism, platform leakage,
or malice. The store protocol never silently overwrites one realization with
another.

Selection among competing realizations is policy, not store semantics.

## 15. Store

The initial store is per-user and daemonless.

```text
$RAX_STORE/
  objects/
    sha256/<ObjectId>/
  plans/
    sha256/<PlanId>.raxp
  realizations/
    sha256/<PlanId>/<platform>/<output>/<ObjectId>.raxr
  profiles/
    <name>/
      generations/<number>.raxg
      current
  roots/
  leases/
  locks/
  tmp/
```

Store records use canonical or explicitly versioned encodings. Pretty JSON or
Raku `.raku` output is not a durable protocol.

### 15.1 Commit protocol

A realization commits as follows:

1. acquire a lock scoped to the Plan output;
2. realize declared dependencies;
3. create a private temporary build directory;
4. execute the builder under the granted capabilities;
5. validate declared outputs;
6. normalize the output tree;
7. verify declared and observed references;
8. compute `ObjectId`;
9. atomically rename the object into the store if absent;
10. write the realization record atomically;
11. release the lock.

If the same `ObjectId` already exists, its tree must verify before it is reused.
If the target exists but does not verify, the store is corrupt and the
operation fails loudly.

Store objects are read-only after commit to the extent the platform can enforce.
Immutability is also checked by `rax store verify`; filesystem permissions alone
are not the proof.

### 15.2 References and closures

A committed object has an explicit direct-reference manifest. Its closure is the
transitive closure of that manifest.

Output scanning verifies references to known store paths:

- a declared retained reference that is observed is valid;
- a declared retained reference that is not observed may produce a warning;
- an observed undeclared store reference is an error in strict mode;
- an arbitrary external absolute path is an error in strict mode.

Scanning is evidence, not the sole source of dependency truth. Compressed,
encoded, or computed references may be invisible to byte scanning.

## 16. Realizer

The realizer consumes Plan IR only. It never imports modules, parses `.rax`
source, or evaluates language expressions.

The realizer receives:

- the Plan and its declared inputs;
- named output placeholders;
- private temporary storage;
- normalized target data;
- normalized environment values;
- explicit capabilities.

It does not receive by default:

- network access;
- the user's home directory;
- the host `PATH`;
- current time;
- random data;
- arbitrary devices;
- arbitrary host filesystem paths;
- undeclared executables.

Isolation claims use these terms:

```text
normalized
    environment and inputs are explicit, but the host may still be visible

isolated
    filesystem and process isolation prevent ordinary ambient access

hermetic
    declared inputs and capabilities are the only meaningful build influences,
    within the documented platform threat model
```

Rax must not call a build hermetic merely because it cleared environment
variables.

Milestone 2 may begin with normalized execution on macOS and Linux. Stronger
platform sandboxes are later adapters and must report their actual enforcement.

## 17. Profiles, Roots, and Leases

A profile generation is an immutable manifest selecting named outputs and a
collision policy.

Creating or changing a profile never mutates a store object. Activation creates
a new generation and atomically replaces the profile's `current` reference.

Old generations remain available until pruned. Rollback is an atomic switch to
an earlier generation.

Garbage-collection roots include:

- current profile generations;
- retained historical generations;
- explicit pins;
- active builds;
- active cache transfers;
- runtime leases.

A runtime lease protects an object's closure while a launched process may still
need it, even if its profile changes.

Garbage collection is mark-and-sweep over explicit object references. Dry-run
output must explain each retained root and each candidate deletion.

## 18. Fetchers and Locking

Fetchers are explicit effects separate from evaluation and ordinary builds.

Planned fetchers are:

- fixed-output HTTPS;
- immutable Git revision;
- normalized local tree.

Every fetched result is verified before entering the store.

A project lock file records resolved source identities and resolver decisions.
It is ordinary versioned data, not a second language or project wrapper.

The lock format must be deterministic and reviewable. Updating a lock is an
explicit command and should show what source identities changed.

## 19. Security Model

Rax addresses supply-chain integrity, not universal software safety.

The precise promise is:

> Given an authenticated plan and an explicit trust policy, Rax can make it
> independently verifiable that installed bytes are an accepted realization of
> that exact plan and dependency closure.

A hash is a seal, not a conscience. It proves identity. It does not prove that
source is kind, correct, reviewed, or free of a patient backdoor.

### 19.1 Threats Rax can materially reduce

Rax is designed to reduce:

- accidental dependency omission;
- destructive package interference;
- unauthorized modification of committed objects;
- cache substitution of bytes with the wrong content identity;
- silent disagreement between repeated realizations;
- rollback through mutable local profiles;
- ambient build authority;
- hidden selection of host tools and environment values.

### 19.2 Threats outside the core guarantee

Rax cannot by itself prove:

- that a maintainer is honest;
- that reviewers understood the source;
- that source contains no malicious logic;
- that software contains no exploitable bug;
- that a compiler, linker, strip tool, kernel, or bootstrap seed is clean;
- that independent builders do not collude;
- that the user chose the intended package;
- that runtime configuration and mutable state are safe;
- that a network adversary cannot deny service.

### 19.3 Facts, claims, and policy

Rax keeps three layers distinct.

**Facts** are locally verifiable:

```text
PlanId
ObjectId
canonical inputs
observed references
capabilities granted
isolation reported
```

**Claims** are signed statements by an actor:

```text
builder B realized Plan P as Object O
reviewer R approved source revision S
rebuilder W independently reproduced P as O
release authority A authorized profile generation G
```

A signature proves who made a claim. It does not make the claim true.

**Policy** belongs to the user or organization:

```text
which source authorities are accepted
which builders are trusted
how many signatures are required
whether freshness and rollback metadata are valid
how many independent rebuilders must agree
which bootstrap roots count as independent
```

The store records evidence. It does not impose one global trust policy.

### 19.4 Reproducibility and independence

Repeated agreement is useful, but agreement is not independence.

Two builders derived from the same compromised bootstrap ancestry may produce
the same hostile object. Reproduction evidence should therefore include a trust
root graph covering, where available:

```text
Raku++ ObjectId
C++ compiler ObjectId
assembler and linker ObjectIds
post-processing tools
runtime libraries
operating-system and kernel lineage
sandbox implementation
bootstrap seed
builder operator
```

The first implementation only records this model. Diverse rebuilding and
bootstrap verification are later research milestones.

### 19.5 Transparency and updates

Future signed caches and releases should support:

- threshold authorization;
- delegation;
- metadata expiration;
- rollback and freeze detection;
- append-only transparency records;
- independent monitoring;
- preservation of conflicting realizations.

Rax should interoperate with established provenance and update formats where
possible instead of inventing incompatible vocabulary merely to appear novel.

## 20. Command-line Interface

The initial command family is:

```text
rax parse FILE
rax check FILE
rax eval FILE [--export NAME]
rax plan FILE [--export NAME]
```

Milestone 0 options:

```text
rax plan FILE --pretty       stable human-readable Plan IR
rax plan FILE --canonical    write RAX-CANON/1 bytes
rax plan FILE --id           print PlanId only
```

Later commands are added with their milestones:

```text
rax build FILE
rax run FILE
rax shell FILE
rax profile install FILE
rax profile list
rax profile switch GENERATION
rax profile rollback
rax store verify [OBJECT]
rax store refs OBJECT
rax store closure OBJECT
rax gc [--dry-run]
rax cache pull
rax cache push
```

The CLI is a thin adapter. Parsing, evaluation, encoding, storage, and policy
remain callable module routines.

### 20.1 Exit status

The CLI uses stable classes:

```text
0   success
1   source, evaluation, or validation error
2   resolution error
3   realization error
4   store corruption or protocol error
5   trust-policy rejection
70  unexpected internal error
```

Diagnostics go to standard error. Requested data goes to standard output.

## 21. Diagnostics

A diagnostic contains:

```text
severity
stable code
message
primary span
secondary spans
notes
```

Preferred rendering:

```text
hello.rax:8:9: error[RAX0203]: duplicate map key "name"
  |
8 |         name => "other",
  |         ^^^^ already defined here
```

Parser recovery should report more than one independent error when reliable, but
must not invent cascades after the grammar state is lost.

Canonical encoders and store operations report semantic paths such as
`plan.inputs.runtime[2]` in addition to source spans when possible.

## 22. Module Layout

The initial repository should remain compact:

```text
rax/
  README.md
  DESIGN.md
  LICENSE
  META6.json
  bin/
    rax
  lib/Rax/
    Grammar.rakumod
    Actions.rakumod
    Span.rakumod
    Diagnostic.rakumod
    Value.rakumod
    Eval.rakumod
    Resolve.rakumod
    Validate.rakumod
    IR.rakumod
    Canon.rakumod
    Digest.rakumod
    Tree.rakumod
    Store.rakumod
    Realize.rakumod
    Profile.rakumod
    Policy.rakumod
  examples/
    hello.rax
  t/
  patches/
```

Files should be combined when separation adds ceremony without a real boundary.
The tree above names responsibilities, not a mandate for one class or module per
noun.

There is no repository `AGENTS.md`. Project-specific Codex guidance lives in the
Rax skill.

## 23. Raku Implementation Style

Rax is data-oriented Raku.

Prefer:

- native `Map`, `List`, `Pair`, `Set`, and scalar values;
- small typed routines;
- `proto` and `multi` for semantic dispatch;
- `given` and `when` for finite tagged-data dispatch;
- grammars and actions at the source boundary;
- immutable values between phases;
- explicit state ownership at store and realizer boundaries.

Use classes only when identity, lifecycle, protected mutable state, grammar
action methods, or typed exceptions make them the clearer model.

Avoid:

- an AST class hierarchy;
- service and repository object layers that only forward calls;
- global mutable domain state;
- side effects hidden inside `map` or `grep`;
- framework dependencies before the exact path works under `rakupp`;
- implementation behavior that depends on a failed `use` merely warning and
  continuing.

## 24. Verification

Every used surface must be exercised under Raku++.

Milestone 0 baseline:

```sh
rakupp --lint bin/rax
rakupp -I lib bin/rax check examples/hello.rax
rakupp -I lib bin/rax plan examples/hello.rax --canonical \
  > /tmp/rax.plan.1
rakupp -I lib bin/rax plan examples/hello.rax --canonical \
  > /tmp/rax.plan.2
cmp /tmp/rax.plan.1 /tmp/rax.plan.2
rakupp -I lib --exe bin/rax -o /tmp/rax
/tmp/rax plan examples/hello.rax --canonical \
  > /tmp/rax.native.plan
cmp /tmp/rax.plan.1 /tmp/rax.native.plan
```

No required test invokes Rakudo.

### 24.1 Milestone 0 acceptance

Milestone 0 is complete only when:

- comments and whitespace do not change `PlanId`;
- map insertion order does not change canonical bytes;
- set insertion order does not change canonical bytes;
- a semantic value change does change `PlanId`;
- repeated runs under the same pinned Raku++ build are byte-identical;
- interpreted and native Raku++ emit byte-identical canonical plans;
- malformed source reports file, line, column, and useful context;
- duplicate map keys are rejected;
- invalid UTF-8 is rejected;
- integer and rational edge cases are canonical;
- SHA-256 passes known-answer tests;
- unsupported runtime values cannot enter Plan IR;
- evaluation has no process, network, clock, environment, or arbitrary
  filesystem capability.

### 24.2 Golden data

Golden tests freeze:

- grammar examples;
- diagnostic codes and important spans;
- RAX-CANON/1 byte vectors;
- PlanId vectors;
- SHA-256 vectors;
- later, RAX-TREE/1 and ObjectId vectors.

A canonical-format change requires a new format version. Tests must never be
updated merely because implementation output changed unexpectedly.

### 24.3 Raku++ defects

When a test exposes a Raku++ defect:

1. reduce it to the smallest Raku program;
2. add a focused regression test in the appropriate place;
3. patch or report Raku++;
4. keep Rax semantics unchanged unless the design itself was wrong.

Do not hide the defect behind a fallback with different semantics.

## 25. Milestones

### Milestone 0: Language core

Deliver only:

- grammar, actions, and source spans;
- immutable surface AST;
- pure evaluator;
- module imports and selected exports;
- PlanSpec;
- source-resolution interfaces with fixed test adapters;
- closed Plan IR and validation;
- RAX-CANON/1;
- SHA-256 and `PlanId`;
- `parse`, `check`, `eval`, and `plan`;
- interpreted/native Raku++ equivalence.

Do not add a builder, object store, profile, cache, or garbage collector.

### Milestone 1: Immutable store

Deliver:

- normalized local-tree import;
- RAX-TREE/1;
- `ObjectId`;
- object verification;
- Plan and realization records;
- atomic commits and locks;
- direct-reference manifests.

No arbitrary build execution is required.

### Milestone 2: Structured realization

Deliver:

- the minimum structured Step set;
- normalized execution;
- one complete local build from fixed source;
- declared capability enforcement available on the host;
- output validation and reference scanning;
- provisional self-reference protocol or explicit rejection of retained
  temporary paths.

### Milestone 3: Profiles

Deliver generations, activation, rollback, roots, collision policy, and runtime
leases.

### Milestone 4: Garbage collection

Deliver explainable mark-and-sweep collection and store verification.

### Milestone 5: Fetchers and locks

Deliver fixed-output HTTPS, immutable Git, local-tree resolution, and a stable
lock-file format.

### Milestone 6: Caches and evidence

Deliver object archives, signed realization claims, threshold policy hooks,
cache pull and push, freshness metadata, and conflict-preserving lookup.

### Milestone 7: Parallel and remote realization

Deliver dependency scheduling, cancellation, log streaming, remote builders,
and builder ancestry records. Add concurrency only after serial correctness.

### Milestone 8: Ecosystem

Create a separate package collection, standard build plans, development
environments, platform adapters, and higher-level policy.

The package collection must not become part of the evaluator or store protocol.

## 26. Patch Plan

Every patch must live in the repository's `patches/` directory. Prefix each
filename with a monotonically increasing sequence number, zero-padded to at
least three digits:

```text
patches/000-meaningful-name.patch
patches/001-next-change.patch
...
patches/999-later-change.patch
patches/1000-still-later-change.patch
```

Allocate the next number greater than every existing patch. Never reuse a gap or
renumber a patch once it has been shared, applied, or recorded in project
history. Refer to a patch by its full `patches/<filename>` path in documentation
and commands.

After the existing design and whitepaper patches, the first implementation
series is:

```text
patches/007-project-charter.patch
patches/008-repository-skeleton.patch
patches/009-grammar-and-spans.patch
patches/010-surface-ast.patch
patches/011-pure-evaluator.patch
patches/012-plan-spec-and-resolution.patch
patches/013-plan-ir.patch
patches/014-canonical-encoding.patch
patches/015-sha256-and-plan-id.patch
patches/016-cli-and-native-equivalence.patch
```

Each patch must:

- apply with either the macOS `patch` utility or Git's `git apply` command;
- contain one architectural move;
- leave the tree testable;
- avoid code for later milestones;
- include the tests that establish its behavior.

## 27. Deferred Decisions

These questions remain open until the named milestone supplies evidence.

### Milestone 0

- exact surface grammar;
- Unicode normalization form for semantic strings;
- concrete RAX-CANON/1 byte tags;
- whether routine recursion is needed;
- stable pretty-print format.

### Milestone 1

- complete RAX-TREE/1 path and symlink rules;
- treatment of executable permissions across platforms;
- durable record encoding and recovery after interruption.

### Milestone 2

- final self-reference and placeholder protocol;
- the first portable sandbox adapters;
- format-aware reference scanners;
- whether `Script` ships immediately or after structured steps prove adequate.

### Milestone 6 and later

- signature envelope and key management;
- update and rollback metadata format;
- transparency-log interoperability;
- assurance-level vocabulary;
- formal representation of bootstrap ancestry and builder independence.

A deferred decision is not permission to make an accidental choice in code.
Implementations should expose the uncertainty, keep the boundary narrow, and
wait for evidence.

## 28. Final Test of the Design

A successful Rax system should make these questions easy to answer:

```text
What exactly was requested?
Which source identities and dependencies entered the request?
What effects was the builder permitted?
Which bytes were produced?
Which immutable objects does the result reference?
Did another builder produce the same object?
What trust claims authorize its use?
Why is this object still in the store?
Can the previous environment be restored atomically?
```

When Rax cannot answer one of them, it should say so plainly. Silence is not a
security property, and a green check mark is not an argument.
