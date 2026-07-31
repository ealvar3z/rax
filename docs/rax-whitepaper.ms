.\" rax-whitepaper.ms
.\" GNU troff manuscript using the ms macro package and the classic
.\" Writer's Workbench preprocessors.
.\"
.\" Render PostScript:
.\"   groff -pet -ms -Tps rax-whitepaper.ms > finished.ps
.\"
.\" Render PDF directly:
.\"   groff -pet -ms -Tpdf rax-whitepaper.ms > finished.pdf
.\"
.\" Equivalent explicit pipeline:
.\"   pic rax-whitepaper.ms | tbl | eqn | troff -ms -Tps > finished.ps
.\"
.\" The paper targets the GNU troff toolchain.  Rax itself targets systems
.\" supported by Raku++ and a C++17 implementation; Plan 9 is out of scope.
.nr PS 9
.nr VS 11
.TL
Rax: Strict Expressions for Verifiable Software Deployment
.AU
e. alvarez
.AB
Functional package management established that software deployment can be
modeled as the evaluation of declared inputs into immutable results. Nix
showed that isolated store paths, complete dependency closures, transactional
profiles, and reachability-based garbage collection can make deployment safer
and more flexible than destructive installation. Guix retained those
mechanisms while using Scheme to describe packages and staged build programs.
This paper proposes Rax, or Raku Expressions, as a third design point.
Rax is a small external language implemented in Raku and compiled by Raku++.
It evaluates expressions strictly and deterministically into a canonical plan
intermediate representation (IR), while realizing only the requested plan and
its dependency closure. Thus Rax is strict about meaning and lazy about work.
The design separates a plan identifier (PlanId), which identifies a requested
computation, from an object identifier (ObjectId), which identifies a realized
file-system tree. An immutable
realization record connects the two. Structured build operations, explicit
capabilities, typed dependency classes, and atomic profile roots reduce the
amount of policy hidden in shell scripts, environment variables, and mutable
installation prefixes. The proposal preserves the central safety properties
of functional deployment while narrowing the language and staging surface
that must be understood, tested, and trusted. This paper describes the model,
language boundary, store protocol, implementation strategy, and open research
questions. Rax is presently a design and implementation program; empirical
claims await a working prototype.
.AE
.2C
.SH
Introduction
.PP
Software deployment appears simple because its visible operation is often a
copy: move a program from the place where it was built to the place where it
will be used. The difficult part is not copying bytes. It is preserving the
relationships that make those bytes meaningful. A program may depend on a
particular compiler, library variant, build flag, interpreter, configuration,
or generated file. A conventional installation can overwrite one of those
relationships while leaving the dependent program in place. Upgrade and
removal then become mutations of shared state whose consequences are only
partly known.
.PP
Nix addressed this problem by separating user environments from installation
space and by storing each component variant at a unique immutable path derived
from its inputs [1]. Packages no longer overwrite one another, profiles can be
switched atomically, and unreachable store objects can be collected safely.
The store and its closures become a form of memory management for deployed
software [2]. Guix, a package manager of the GNU Project, whose name is the
recursive acronym "GNU's Not Unix," later retained the low-level functional
deployment model while replacing the Nix expression language with Scheme
interfaces and embedded domain-specific languages [3]. Its later g-expression
mechanism made
cross-stage references explicit and hygienic [4].
.PP
Rax begins from the judgment that these systems discovered the correct
foundation, but not the final language boundary. Nix offers a small independent
language whose pervasive laziness and string interpolation are powerful but
can defer errors and obscure staging. Guix gains the libraries, tooling, and
extensibility of Scheme, but must manage a multi-tier programming environment
in which host expressions generate build-side expressions. Rax proposes a
narrower compromise: the implementation enjoys Raku as a general-purpose
language, while package authors write a restricted external language that
lowers to a small, canonical plan.
.PP
The design can be summarized in one sentence:
.DS L
Rax is strict about meaning and lazy about work.
.DE
.PP
Expression evaluation is eager enough to produce a complete, inspectable plan
before effects begin. Realization remains demand-driven: only the selected
plan and its transitive closure are fetched or built. Strictness therefore
does not mean building an entire package collection. It means that the meaning
of the requested build contains no hidden language thunks when it is hashed,
checked, transmitted, or authorized.
.PP
Rax is named for Raku Expressions. Its compiler and tools are written in Raku
and target the Raku++ implementation. Raku++ is the normative implementation
platform for the initial project. Compatibility with another Raku compiler is
not a core conformance requirement, though contributors may propose it as an
independent extension.
.SH
Motivation
.PP
The original Nix paper identified dependency completeness, variability,
consistency, atomicity, exact identification, source and binary deployment,
and the coexistence of central and local policy as the principal deployment
problems [1]. Those problems remain central. Rax adds several language and
supply-chain concerns that become visible after two decades of experience with
functional package management.
.PP
\fBComplete dependency descriptions.\fP A build must not succeed because an
undeclared compiler, shell, header, locale, or host tool happened to be
present. Conversely, runtime dependencies must remain reachable after build
inputs are no longer needed. A useful plan therefore distinguishes source,
build, host, tool, and runtime inputs rather than placing every path into one
untyped bag.
.PP
\fBExact variants.\fP A package name and version are not sufficient
identifiers. Patches, target platform, compiler, feature selection, builder,
and environment all contribute to the requested computation. Rax therefore
identifies a canonical build plan, not a human label.
.PP
\fBVisible staging.\fP Package systems necessarily cross stages. Source code is
evaluated on the host; a builder later runs in an isolated environment; the
result may run on yet another machine. Nix often crosses this boundary through
strings and environment variables. Guix makes staged Scheme code first class
through g-expressions [4]. Rax instead lowers the host expression to a closed,
data-only plan before the build stage begins.
.PP
\fBReproducibility as evidence, not assumption.\fP A plan can be deterministic
while its builder is not. Time, random seeds, directory order, compiler
nondeterminism, and undeclared kernel behavior can produce different bytes from
the same declared inputs. Rax must distinguish the identity of the requested
computation from the identity of an observed result. A build that disagrees
with a prior result should create evidence of non-reproducibility rather than
silently overwrite history.
.PP
\fBAuditable effects.\fP The evaluator should not perform arbitrary network,
process, clock, or host-file-system operations. Fetching and building are
explicit effects mediated by the realizer. The question "what can this build
do?" should be answerable by inspecting its plan and granted capabilities.
.PP
\fBPortable implementation.\fP Rax should not require changes to the Raku++
parser or runtime before it can prove the deployment model. Raku grammars and
action objects are designed to parse structured languages and construct native
data [7]. Raku multi-dispatch provides a direct way to implement evaluators,
canonical encoders, and validators over a small algebra of values [8].
Raku++ already supplies a hand-written front end, tree evaluator, and native
C++ compilation path for the supported Raku language [9].
.SH
Design Goals
.PP
Rax has eight primary goals.
.IP "1." 4
Concurrent versions and variants must coexist without overwriting one another.
.IP "2." 4
A successful evaluation must produce a complete, canonical plan before any
fetch or build effect begins.
.IP "3." 4
The requested computation and the realized content must have separate,
verifiable identities.
.IP "4." 4
Profiles, upgrades, downgrades, and rollbacks must be atomic root changes.
.IP "5." 4
Garbage collection must operate on explicit reachability and must explain why
an object is retained.
.IP "6." 4
Build actions and capabilities must be represented as structured data by
default; shell programs remain an explicit escape hatch.
.IP "7." 4
Source builds and binary substitution must share one realization protocol.
.IP "8." 4
The language core, canonical representation, and store protocol must remain
small enough to audit and reimplement.
.PP
Rax is not initially intended to be an operating-system configuration
language, a service manager, a package collection, or a universal build
system. Those layers may be built above the deployment core after its
identities and invariants are stable.
.SH
Overview
.PP
The Rax system contains five principal parts: a source language, a pure
evaluator, a canonical Plan IR, a realizer, and an immutable store. Profiles
provide user-visible environments, and caches provide alternate realizations.
Figure 1 shows the compilation path.
.KS
.PS
boxwid = 1.65
boxht = 0.32
lineht = 0.18
down
box "Rax source"
arrow
box "Grammar and actions"
arrow
box "Surface syntax tree"
arrow
box "Strict evaluator"
arrow
box "Canonical Plan IR"
arrow
box "Realizer and store"
.PE
.ce
Figure 1: The Rax compilation and realization boundary.
.KE
.PP
The boundary between the evaluator and the realizer is the architectural
center. Everything above that boundary computes meaning. Everything below it
performs authorized effects. The Plan IR can be printed, hashed, signed,
transmitted, compared, and checked without retaining parser or evaluator state.
.PP
The system is demand-driven at two levels. First, an import graph need only
load modules required to resolve the selected export. Second, the realizer only
builds the selected plan and dependencies reachable from it. No unrelated
package is built merely because it was present in the same repository.
.SH
Rax Expressions
.PP
Rax source resembles Raku where Raku's native notation improves clarity, but it
is not unrestricted Raku and is not evaluated with the Raku runtime-evaluation
routine (EVAL). A dedicated grammar parses a deliberately small language. The
initial value algebra contains the categories in Table 1.
.KS
.TS
center, box, tab(@);
lb lb
l l.
Category@Values
Scalar@Nil, Bool, Int, Rat, Str, Path
Collection@List, Map, Set
Deployment@Source, Input, Output, Step, Plan
.TE
.ce
Table 1: Initial Rax value algebra.
.KE
.PP
The initial expression forms are literals, lists, maps, lexical bindings, pure
functions, calls, named arguments, conditionals, assertions, imports, and field
selection. Mutation, classes, arbitrary methods, user-defined operators,
macros, slangs, runtime evaluation, ambient module loading, and implicit
infinite sequences are excluded from the language core.
.PP
An illustrative package expression follows. Its fixed source is described by a
Uniform Resource Locator (URL) using Hypertext Transfer Protocol Secure (HTTPS)
and by a digest from the 256-bit Secure Hash Algorithm (SHA-256). The precise
surface syntax may change during implementation; the semantic shape is the
important part.
.DS L
let mk-hello = --> :$tests = False {
    package(
        name    => "hello",
        version => "2.12.1",

        source => fetch(
            url    => "https://example.invalid/hello.tar.gz",
            sha256 => "...",
        ),

        inputs => {
            build   => [$cc, $make],
            runtime => [$libc],
        },

        steps => [
            exec($src.child("configure"),
                 arg("--prefix=", $out)),
            exec($make),
            $tests ?? exec($make, "check") !! skip(),
            exec($make, "install"),
        ],
    )
};

export default = mk-hello();
.DE
.PP
Functions describe variants by returning new values. They do not modify an
existing package object. This preserves the useful functional composition found
in Nix and Guix without requiring a class hierarchy for record-shaped data.
.PP
Imports are pure source dependencies. Their contents, module identities, and
resolution rules contribute to the PlanId. Import resolution may be memoized,
but memoization cannot change observable results. A lock file may record
resolved source revisions; it is an input to evaluation, not a second package
language.
.SH
Strict Evaluation and Demand-Driven Realization
.PP
Nix's language is purely functional, lazy, and dynamically typed [3]. Laziness
allows large recursive package sets and avoids evaluating values that are never
demanded. It also means that an error can remain dormant until a distant field
is forced, and that canonical export of an expression may require forcing more
of the graph than the consumer expected. Guix uses an ordinarily strict Scheme
host but introduces selected thunked fields and explicit staged expressions
where delayed computation is useful [3,4].
.PP
Rax adopts strict evaluation as the default semantic rule. A selected export is
evaluated to normal form before plan validation and hashing. The result may
contain references to other Plans, Sources, and Steps, but it contains no
unevaluated Rax expression. This gives four practical properties.
.IP "First," 6
errors appear during evaluation, with source spans that identify the expression
that produced them.
.IP "Second," 6
canonicalization operates on values rather than thunks, closures, or evaluator
state.
.IP "Third," 6
policy checks can inspect the whole plan before authorizing effects.
.IP "Fourth," 6
remote builders need only implement the Plan IR and store protocol, not the Rax
surface language.
.PP
Strictness does not imply eager realization. A plan is a description of work,
not the work itself. The command:
.DS L
rax build packages.rax#hello
.DE
.PP
may evaluate the selected export and its semantic dependencies, query caches,
and realize only the closure needed for hello. Documentation, tests, or other
exports are not realized unless reachable. If real package definitions later
show that explicit delayed values are necessary, Rax can add a named delay
construct with defined forcing and hashing semantics. Pervasive implicit
laziness is not part of the initial trusted core.
.SH
Canonical Plan IR
.PP
The evaluator lowers surface values to a smaller store language called the Plan
IR. This follows the compiler separation already present in the original Nix
design, where high-level expressions are translated to simpler store
expressions [1]. The Plan IR describes one or more outputs and contains only
canonical data.
.PP
A Plan contains at least:
.IP "-" 3
a format version and digest algorithm;
.IP "-" 3
a target and, where relevant, build platform;
.IP "-" 3
a set of named outputs;
.IP "-" 3
classified inputs and their exact plan or source identities;
.IP "-" 3
a sequence or graph of structured build Steps;
.IP "-" 3
a normalized environment map;
.IP "-" 3
declared capabilities;
.IP "-" 3
runtime reference expectations; and
.IP "-" 3
metadata that affects realization.
.PP
Human metadata such as a synopsis may accompany a Plan, but fields that do not
affect realization must be explicitly excluded from PlanId computation. This
prevents a spelling correction from rebuilding software while preventing a
build-relevant flag from escaping the identity.
.PP
The Rax Canonical Encoding, version 1 (RAX-CANON/1), is independent of
native hash iteration order and source formatting. It uses explicit type tags,
strings encoded with the 8-bit Unicode Transformation Format (UTF-8) and
prefixed by byte length, normalized integers and rational numbers, ordered lists,
map keys sorted by encoded bytes, sets sorted by encoded element bytes, and
versioned path rules. Floating-point values, timestamps, native object
identities, and host-dependent textual renderings are forbidden in Plans.
.PP
The canonical encoder is part of the compatibility contract. A newer encoding
uses a new version tag rather than silently changing old PlanIds.
.SH
Dual Identity and Realization Records
.PP
A functional deployment system must identify both a requested computation and
an observed result. Let H denote the selected cryptographic hash function. The
Rax Tree Encoding, version 1 (RAX-TREE/1), canonically represents a realized
file-system tree. Rax defines the identities mathematically as follows:
.KS
.EQ
roman PlanId = H ( "RAX-CANON/1" ( roman Plan ) )
.EN
.EQ
roman ObjectId = H ( "RAX-TREE/1" ( roman "realized tree" ) )
.EN
.TS
center, box, tab(@);
lb lb
l l.
Identifier@Meaning
PlanId@Requested computation
ObjectId@Realized output tree
.TE
.ce
Table 2: The two Rax identities.
.KE
.PP
A PlanId is known before building. It identifies the builder, declared inputs,
platform, environment, steps, outputs, and capabilities. It is the key used to
ask whether a suitable realization already exists.
.PP
An ObjectId is known only after realization. It identifies a normalized output
tree: file contents, relative paths, executable bits, symbolic-link targets,
and other explicitly supported metadata. Ownership, timestamps, and incidental
file-system allocation are normalized or excluded.
.PP
An immutable realization record connects them:
.DS L
(PlanId, platform, output-name)
    -> (ObjectId, references, metadata, attestations)
.DE
.PP
This separation makes non-reproducibility visible. If the same PlanId is built
twice and yields different ObjectIds, the store records a conflict or multiple
observations; it never silently declares the results identical. Conversely,
different Plans that produce the same normalized content can share physical
storage when their runtime addressing permits it.
.PP
A difficulty arises because many builds embed their own installation prefix.
The final content identity is unknown before the build, but the prefix must be
known while configuring and linking. Rax therefore separates logical plan
addresses from physical object addresses.
.DS L
/rax/store/plans/<PlanId>/<output>
        -> /rax/store/objects/<ObjectId>
.DE
.PP
The logical plan address is known before realization and is the path exposed to
the builder. After success, an immutable realization binds that address to an
object. Programs may retain plan addresses without creating a circular hash
over their own ObjectId. If two plans produce byte-identical trees that embed
different plan addresses, their ObjectIds will correctly differ. If they do not
embed those addresses, the underlying object may be shared.
.PP
A PlanId and ObjectId include their algorithm names. For example:
.DS L
plan:sha256:4c8d...
object:sha256:a891...
.DE
.PP
Algorithm agility is thereby represented in data rather than hidden in a fixed
path convention.
.SH
The Store
.PP
The store contains immutable source objects, realized objects, plans,
realization records, profiles, roots, leases, locks, and private temporary
build directories. The Rax store-root environment variable (RAX_STORE) names
its root. A possible layout is:
.DS L
$RAX_STORE/
    objects/<algorithm>/<ObjectId>/
    plans/<algorithm>/<PlanId>.raxp
    realizations/<PlanId>/<platform>/<output>.raxr
    aliases/<PlanId>/<output>
    profiles/<name>/generations/
    profiles/<name>/current
    roots/
    leases/
    locks/
    tmp/
.DE
.PP
A store commit follows a transaction-like protocol.
.IP "1." 4
Acquire a lock for the requested plan output.
.IP "2." 4
Realize all required input closures.
.IP "3." 4
Create a private build directory and normalized environment.
.IP "4." 4
Execute the authorized builder steps.
.IP "5." 4
Normalize and scan each declared output.
.IP "6." 4
Compute its ObjectId and verify declared references.
.IP "7." 4
Atomically commit the object and realization record.
.IP "8." 4
Create the immutable logical alias and release the lock.
.PP
Objects are never modified after commit. A failed build leaves no visible
partial object. Temporary paths are either removed or retained under an
explicit debugging policy outside the object namespace.
.SH
Dependencies and Closures
.PP
Rax classifies dependencies because build-time presence and runtime
reachability are different questions.
.IP "source" 9
A fixed source tree, archive, generated source, or local immutable input.
.IP "build" 9
An input needed to execute the build but not expected at runtime.
.IP "tool" 9
A helper executable used by structured Steps.
.IP "host" 9
A library or component linked or loaded for the target program.
.IP "runtime" 9
An input that must remain in the realized runtime closure.
.PP
The Plan is authoritative. Output scanning is a verifier, not the primary
source of dependency semantics. The scanner searches files and links for known
logical plan addresses and platform-specific binary references. The outcomes
are:
.IP "-" 3
a declared runtime reference is found: valid;
.IP "-" 3
a declared runtime reference is not retained: warning or optimization
opportunity;
.IP "-" 3
an undeclared retained store reference is found: error in strict mode; and
.IP "-" 3
an external absolute dependency is found: error unless a declared capability
permits it.
.PP
Some dependencies are semantic but not embedded as bytes, such as plugins,
data files, interpreters selected by a launcher, or resources discovered from
a manifest. These remain explicitly declared runtime references. Garbage
collection traces both declared references and verified retained references.
.PP
A deployment closure is the transitive set of realized objects reachable from
a selected realization. Copying a closure to another store is complete when
all realization records, objects, and logical aliases required by that closure
are present.
.SH
Structured Builders and Capabilities
.PP
The early Nix design passed derivation attributes to builders through
environment variables and commonly delegated the build to shell scripts [1].
Guix demonstrated that build programs can be written in Scheme, improving
composition and reducing dependence on shell text [3]. Rax adopts a data-first
builder interface.
.PP
The standard Step algebra initially includes:
.DS L
exec  mkdir  copy  move  remove
write symlink unpack patch
.DE
.PP
An exec Step contains an exact executable input, an argument vector, working
directory, environment delta, expected exit behavior, declared output access,
and capability requirements. It does not reconstruct a command by concatenating
unquoted strings. Paths and outputs are typed values rather than accidental
shell syntax.
.PP
A shell Step remains available because many upstream build systems expose only
a shell-oriented interface. It is an explicit escape hatch whose interpreter,
script bytes, environment, and capabilities all contribute to the PlanId. Tools
may warn that a shell Step is less analyzable than structured Steps, but they do
not pretend that the escape hatch does not exist.
.PP
The realizer grants capabilities rather than assuming perfect isolation. A
Plan may request:
.IP "-" 3
read access to declared inputs;
.IP "-" 3
write access to declared outputs and temporary storage;
.IP "-" 3
process execution of declared tools;
.IP "-" 3
network access for a fixed-output fetcher;
.IP "-" 3
specific devices or kernel facilities; or
.IP "-" 3
clock, randomness, locale, or user-database access.
.PP
The default build receives no network, home directory, ambient executable
search path (PATH), host package database, or arbitrary device access. Platform
back ends may provide different strengths of enforcement. Rax distinguishes
three claims:
.IP "normalized" 11
a clean environment and explicit inputs;
.IP "isolated" 11
process and file-system isolation; and
.IP "hermetic" 11
isolation plus the exclusion or control of nondeterministic ambient
capabilities.
.PP
A platform must not call a build hermetic merely because it cleared environment
variables.
.SH
Sources and Fetchers
.PP
Evaluation does not contact the network. A Source value describes an expected
immutable input. A fetcher is a specialized realization whose network access is
explicit and whose result is accepted only if it matches a declared content
identity.
.PP
Initial source forms may include HTTPS archives, Git commits, and local trees.
A moving branch name or unverified URL cannot directly enter a reproducible
Plan.
Resolution tools may discover a revision and update a lock file, but the
resolved revision and content digest become the Plan inputs.
.PP
Secrets are capabilities, not plan values. Credentials must not appear in
canonical Plan IR, logs, store paths, or cache records. A private fetch may
request a named secret channel whose existence and policy are outside the
content identity; the fetched result is still checked against its declared
content digest.
.SH
Profiles, Generations, and Atomicity
.PP
A profile is an immutable manifest selecting realized outputs and defining
collision policy for their user-visible names. Building a new profile creates a
new generation. Activation changes one root, normally by atomic rename of a
symbolic link:
.DS L
profiles/work/current -> generations/43
.DE
.PP
Users and processes therefore observe either the old generation or the new
one, not a mixture. Rollback switches the root to an earlier generation. The
store objects remain untouched.
.PP
Profiles may be personal, site-wide, task-specific, or service-specific. A
profile may include another profile as an input, enabling layered policy
without merging mutable installation prefixes. Whether a local layer overrides
or rejects a site-wide collision is a profile policy, not a store invariant.
.PP
A process launched through Rax may hold a runtime lease on its closure. The
lease prevents collection even if the profile that launched the process is
switched or deleted while the process continues to run. Leases expire through
an explicit protocol rather than by guessing from profile state.
.SH
Garbage Collection
.PP
There is no command that destructively uninstalls a store object. A user removes
an output from a profile or deletes a retained generation. The garbage
collector then computes reachability from:
.IP "-" 3
current and retained profile generations;
.IP "-" 3
explicit pins and administrative roots;
.IP "-" 3
active builds and transfers;
.IP "-" 3
runtime leases; and
.IP "-" 3
policy-defined archival roots.
.PP
Objects outside the transitive closure of those roots are collectible. A dry
run must explain both sides of the decision: which objects would be deleted and
which root keeps each retained object alive. Explainability is part of safe
operation, not merely a user-interface convenience.
.PP
Collection removes physical objects only after removing no-longer-needed
aliases and realization records according to a crash-safe order. A store
verification command can reconstruct reachability, rehash objects, and detect
broken aliases without trusting cached database state.
.SH
Substitution and Binary Caches
.PP
Binary deployment is an optimization of source deployment, not a separate
package format. A cache indexes a PlanId, platform, and output name to a signed
realization record and object archive. The client:
.IP "1." 4
requests a realization for the exact PlanId;
.IP "2." 4
applies local trust policy to the record and signer;
.IP "3." 4
fetches the object and referenced closure;
.IP "4." 4
computes each ObjectId locally; and
.IP "5." 4
commits the verified realization through the normal store protocol.
.PP
Trust in a cache does not replace content verification. It answers a different
question: whether the client accepts the claim that a particular ObjectId is an
authorized realization of the PlanId. Rebuilding the Plan independently can
provide stronger reproducibility evidence. Guix's work on authenticated
updates and independently verifiable supply chains demonstrates why source
history, build provenance, and binary attestation must be treated as connected
but distinct concerns [11].
.PP
Cache selection, signature thresholds, organizational authorization, and
retention are policy. The store protocol only defines the records and
verification rules required to implement those policies.
.SH
Implementation in Raku and Raku++
.PP
The reference implementation is written in Raku and compiled with Raku++.
Raku++ is a from-scratch Raku implementation written to the 2017 revision of
C++ (C++17), with a hand-written lexer, parser, tree-walking evaluator, and
native C++ code-generation mode [9]. Its
current grammar and action support is sufficient for an external Rax parser,
while deep parser replacement and slangs need not be part of the Rax design
[9,10].
.PP
The front end uses a Raku grammar and an actions object. Actions immediately
produce native immutable values and source spans; Match objects do not escape
into the evaluator. The implementation favors Raku's native data model:
.IP "-" 3
Map, List, Pair, Set, and scalar values represent records and trees;
.IP "-" 3
enums identify node, step, input, and output kinds;
.IP "-" 3
subsets validate digests and identifiers;
.IP "-" 3
proto and multi routines implement evaluation, validation, canonical encoding,
and store operations; and
.IP "-" 3
classes are reserved for grammar actions, exceptions, stateful resources, and
objects with real lifecycle or identity.
.PP
The implementation pipeline is divided into independently testable modules:
.DS L
Rax::Grammar       source -> Match
Rax::Actions       Match -> surface data
Rax::Eval          surface data -> values
Rax::Validate      values -> checked plan
Rax::IR            checked plan -> Plan IR
Rax::Canon         Plan IR -> canonical bytes
Rax::Digest        bytes -> PlanId or ObjectId
Rax::Store         immutable commit and query
Rax::Realize       authorized effects
Rax::Profile       generations and roots
.DE
.PP
The evaluator, canonical encoder, and Plan validator contain no network or
process operations. Side effects enter through narrow adapters. The command-line
program is orchestration, not the domain core.
.PP
Raku++ is the normative compiler for Rax. Tests compare interpreted Raku++ with
a binary produced by its native compilation mode. The project does not require
Rakudo parity or constrain its design around another implementation's behavior.
When Rax exposes a Raku++ defect, the preferred remedy is a focused compiler
regression and patch rather than a hidden compatibility workaround.
.SH
Validation Strategy
.PP
The first milestone proves the language boundary before attempting package
builds. It must provide parsing, source-spanned diagnostics, strict evaluation,
Plan IR, validation, canonical encoding, PlanId computation, and a native Rax
executable.
.PP
Acceptance tests include:
.IP "-" 3
comments and whitespace do not change a PlanId;
.IP "-" 3
map insertion order does not change canonical bytes;
.IP "-" 3
a semantic value change does change the PlanId;
.IP "-" 3
repeated runs under the same pinned compiler produce identical output;
.IP "-" 3
interpreted and native-compiled Raku++ produce byte-identical plans;
.IP "-" 3
malformed source reports a file, line, column, and useful message; and
.IP "-" 3
evaluation cannot access the network, execute processes, or read arbitrary
host paths.
.PP
Later milestones add store imports, structured realization, profiles, garbage
collection, fixed-output fetchers, caches, and remote builders. Each milestone
must finish a thin end-to-end slice before widening the surface.
.SH
Security as Evidence
.PP
A hash is a seal, not a conscience. It can show that bytes did not change. It
cannot show that the bytes are kind, correct, recent, or wisely chosen. Rax
therefore does not claim to solve software supply-chain security. No package
manager can. Its narrower promise is useful enough: given an authenticated Plan
and an explicit trust policy, Rax should make it independently verifiable that
an installed object is an authorized realization of that exact Plan and its
complete closure.
.PP
Trust does not disappear. It comes out of hiding.
.PP
\fBThreat model.\fP The adversary may submit unauthorized source, compromise a
source repository or signing key, alter build parameters, operate a builder,
cache, mirror, or transparency service, replay an old release, present different
releases to different users, or poison a tool in the bootstrap chain. A builder
may attempt undeclared file, process, clock, environment, or network access. A
cache may bind the right name to the wrong bytes. Several actors may collude.
.PP
The initial model assumes that the selected cryptographic hash and signature
algorithms hold, and that the local verifier, its policy state, and the machine
executing that verifier have not already been subverted. Kernel, hardware, and
cryptographic failure belong to a deeper model. Rax must state these assumptions
instead of burying them beneath the word secure. The threat classes follow the
source, build, distribution, selection, and usage boundaries described by
Supply-chain Levels for Software Artifacts (SLSA) [13].
.PP
\fBSecurity goals.\fP Rax should bind an ObjectId to the exact PlanId that
requested it; reject undeclared inputs and effects when the platform can enforce
that claim; verify downloaded objects locally; preserve conflicting
realizations; authenticate source and release history; resist rollback, freeze,
and mix-and-match attacks; gather evidence from independent builders; and let
the user decide which evidence is enough.
.PP
\fBNon-goals.\fP Rax cannot prove that source is benevolent, that a
maintainer is honest, that reviewers understood the code, that a program is
free of defects, or that several witnesses did not collude. It cannot make an
unsafe configuration safe, recover a compromised machine, or prevent a network
adversary from denying
service. A reproducible backdoor remains a backdoor. SLSA makes similar limits
explicit: provenance does not establish code quality, producer honesty, or the
security of every transitive dependency [13].
.PP
\fBThe realization evidence model.\fP The store holds facts. Signatures hold
claims. Policy makes a decision. These three must not be confused.
.KS
.DS L
Fact:      hash(object bytes) = ObjectId
Claim:     builder B says PlanId produced ObjectId
Decision:  policy P accepts a set of facts and claims
.DE
.KE
.PP
A realization record should contain the PlanId, ObjectId, declared inputs,
observed references, granted capabilities, builder identity, platform, and the
normalization rules applied to the output. The client verifies every fact it can
verify locally. A signature proves who made a claim; it does not make the claim
true.
.PP
Rax should export attestations compatible with SLSA provenance rather than
invent a private vocabulary for common build facts [13]. Work outside the
realizer, such as review, testing, release approval, and publication, can be
expressed as signed steps in the style of in-toto [14]. The Rax Plan is stronger
than a report written after the build: it is also the capability envelope that
constrains the build while it runs.
.PP
\fBSource and update authentication.\fP Integrity begins before compilation. A
perfect build of an unauthorized revision is still unauthorized. Rax package
collections should carry authenticated source history, following the useful
precedent established by Guix [11]. Release metadata must also say which keys or
roles may authorize which objects, when that authority expires, and what version
the client has already seen.
.PP
The Update Framework (TUF) supplies mature machinery for threshold keys,
delegation, expiration, and resistance to rollback, freeze, fast-forward, and
mix-and-match attacks [15]. Rax should adopt those semantics or a demonstrably
equivalent protocol. A content hash says, "this is the old object." It does not
say, "the old object is still the object you should run."
.PP
\fBIndependent and diverse rebuilding.\fP Reproducible builds ask whether the
same declared inputs produce the same bytes [12]. Agreement is valuable, but
agreement is not independence. Two witnesses taught by the same compromised
teacher are one witness wearing two coats.
.PP
Rax should distinguish repeated, independent, diverse, and bootstrapped builds.
A second build on the same service is repeated. A build on another operator's
machine is independent only in an administrative sense. A diverse build has a
materially different toolchain or bootstrap ancestry. Diverse double-compiling
(DDC) gives a researched method for testing whether a compiler binary
corresponds to its claimed source under stated assumptions [18].
.PP
The compiler is not the only ancestor that matters. A 2026 preprint demonstrates
a trusting-trust attack against the NixOS bootstrap using a malicious
\fBstrip\fP utility. The poisoned tool propagated through later generations,
left the final dependency closure, and still altered most resulting executables
[19]. The lesson is plain: any tool allowed to rewrite an artifact may carry the
knife.
.PP
\fBBootstrap ancestry.\fP Every builder attestation should identify the roots
from which its result grew: the Raku++ ObjectId, the C++ compiler, assembler,
linker, binary-rewriting tools, runtime libraries, bootstrap seeds, operating
system, sandbox implementation, and relevant hardware or virtual-machine class.
This is a graph, not a badge.
.PP
Rax policy may then ask whether two agreeing builders actually descend from
different roots. It may prefer minimized and auditable binary seeds, as
Guix's bootstrap work does, but it must never call two builds diverse merely
because their hostnames
differ [11,18,19].
.PP
\fBTransparency and equivocation resistance.\fP A signature can lie consistently
to one victim. Transparency forces the lie into public view. Signed source
revisions, realizations, reproduction results, and release authorizations should
be eligible for inclusion in an append-only log. Clients verify inclusion;
monitors verify that the log remains append-only; independent observers compare
log views.
.PP
Sigstore's Rekor demonstrates a general transparency log for signed
software-supply-chain metadata [16]. Nikitin et al. combine independent
witnesses, verified builds, collective release authorization, and a
tamper-evident
release history [17]. Rax need not require one global log. A person, project,
company, or nation may operate its own. What matters is that equivocation leaves
evidence
and that clients are not forced to trust the log operator in silence.
.PP
\fBLocal acceptance policy.\fP Rax should carry evidence, not issue absolution.
The final decision belongs to the user or organization. A policy may require:
.IP "-" 3
the downloaded bytes to match the ObjectId;
.IP "-" 3
a signed binding from the requested PlanId to that ObjectId;
.IP "-" 3
a builder whose isolation claims meet local requirements;
.IP "-" 3
fresh source and update authorization;
.IP "-" 3
agreement from a threshold of independent rebuilders;
.IP "-" 3
materially distinct bootstrap roots among those rebuilders; and
.IP "-" 3
inclusion of the release and its evidence in monitored logs.
.PP
Failure should explain which fact, claim, or policy rule was missing. The user
should see \fIcontent verified\fP, \fIplan bound\fP, \fIisolated\fP,
\fIreproduced\fP, \fIdiverse\fP, or \fItransparent\fP, not a green shield that
pretends all these words mean the same thing.
.PP
\fBResidual trust.\fP Rax cannot make evil source good, careless source wise, or
a compromised kernel faithful. It cannot prove that reviewers read what they
signed or that independent builders are not secretly one actor. It can make each
remaining trust decision smaller, named, and challengeable.
.PP
That is the security claim: not trustlessness, but evidence. Not certainty, but
a chain whose links can be held in the hand. The store tells us what is there.
The evidence tells us who said it should be there. Local policy decides whether
to open the door.
.SH
Related Work
.PP
\fBNix.\fP Rax directly inherits Nix's separation of user and installation
space, immutable isolated variants, closure deployment, atomic profiles,
substitution, and reachability-based collection [1,2]. It differs principally
at the language and identity boundaries: Rax is strict by default, lowers to a
closed data plan, represents build operations structurally, and separates plan
identity from observed content identity.
.PP
\fBGuix.\fP Guix demonstrates the benefit of a rich host language, first-class
package objects, functional package transformations, Scheme build programs,
and explicit code staging [3,4]. Rax adopts the preference for language-native
builders over shell text, but places package authors in a restricted external
language rather than the full host language. This reduces library access and
metaprogramming power in exchange for a smaller semantic and security surface.
.PP
\fBVesta.\fP Vesta treated software construction as a functional computation
and provided automatic dependency detection and repeatable builds [5]. Nix and
Guix both cite Vesta as an important predecessor. Rax shares the goal of a
precise computation graph but emphasizes deployment profiles and a portable
user-space implementation.
.PP
\fBMake and conventional build tools.\fP Make expresses a dependency graph and
incremental commands but traditionally relies on mutable working directories,
timestamps, and ambient tools [6]. Rax can invoke such build systems inside a
plan; it does not assume that their internal graph is sufficient to identify a
portable deployment result.
.PP
\fBReproducible Builds.\fP The Reproducible Builds project defines a build as
reproducible when identical source, environment, instructions, and dependencies
produce bit-for-bit identical artifacts [12]. Rax's PlanId identifies the
declared side of that equation, while repeated ObjectIds provide direct
observations of the result.
.SH
Open Questions
.PP
Several issues require implementation experience and measurement.
.PP
\fBRecursive package collections.\fP Strict evaluation must remain practical for
large package sets. Selective imports, memoized module evaluation, explicit
functions, and indexes may suffice. If not, Rax should add explicit delay rather
than pervasive implicit laziness.
.PP
\fBSelf and dependency references.\fP Logical plan addresses avoid a direct
self-hash cycle, but they may reduce content sharing when embedded paths differ.
The prototype must measure how often this matters and whether normalized
reference tables or relocatable outputs are worth the added complexity.
.PP
\fBCanonical tree rules.\fP Platforms disagree about executable bits, symbolic
links, extended attributes, sparse files, case folding, and path encodings.
RAX-TREE/1 must define a portable core and explicit platform extensions.
.PP
\fBReference scanning.\fP Byte scanning is general but can produce false
positives and miss compressed or encoded references. Format-aware scanners can
improve evidence but increase the trusted surface. Explicit declarations remain
necessary.
.PP
\fBSandbox parity.\fP Linux, Berkeley Software Distribution (BSD) systems,
and macOS expose different isolation mechanisms. Capability claims must be
testable and must not conceal a weaker platform behind a common word such as
hermetic.
.PP
\fBCyclic build graphs.\fP The initial Plan graph should be acyclic.
Bootstrapping cycles can be represented through staged seed objects or fixed
points only after
the ordinary model is stable.
.PP
\fBCache consensus.\fP Multiple valid ObjectIds for one PlanId may indicate
nondeterminism, platform leakage, or malicious substitution. User interfaces and
policy engines must present this evidence without silently choosing a winner.
.SH
Implementation Roadmap
.PP
The proposed sequence is deliberately conservative.
.IP "Milestone 0" 12
Grammar, actions, source spans, evaluator, Plan IR, validation, canonical
encoding, PlanId, command-line inspection, and native compilation.
.IP "Milestone 1" 12
Immutable local store, tree normalization, ObjectId, realization records,
locking, and verification.
.IP "Milestone 2" 12
Structured Steps and one complete local C build from a fixed source.
.IP "Milestone 3" 12
Profiles, generations, atomic activation, rollback, roots, and leases.
.IP "Milestone 4" 12
Explainable mark-and-sweep garbage collection.
.IP "Milestone 5" 12
Fixed-output HTTPS, Git, and local-tree fetchers.
.IP "Milestone 6" 12
Signed realization records, object archives, binary caches, and local evidence
policy.
.IP "Milestone 7" 12
Authenticated source and update history, transparency logs, independent and
diverse rebuilding, and bootstrap-ancestry records.
.IP "Milestone 8" 12
Parallel scheduling, remote builders, cancellation, and log streaming.
.IP "Milestone 9" 12
A separate package collection and higher-level development environments.
.PP
The language must not absorb a feature merely because a future package
collection might find it convenient. New syntax requires a demonstrated
semantic need, a canonical representation, deterministic behavior,
source-spanned
diagnostics, and interpreter/native equivalence under Raku++.
.SH
Conclusion
.PP
Nix's lasting achievement was to make deployment resemble memory management:
immutable values occupy isolated addresses, roots select live environments,
and unreachable values can be collected [1,2]. Guix showed that richer language
abstractions and staged build programs can make that model more extensible and
more pleasant to program [3,4]. Rax seeks to preserve both lessons while drawing
a firmer boundary between language evaluation and deployment effects.
.PP
A Rax expression evaluates strictly to a complete canonical Plan. A PlanId
names the requested computation. Realization occurs only on demand. An ObjectId
names the observed content. A realization record connects request to result.
Profiles move atomically; garbage collection follows explicit roots; caches
supply verified realizations; and capabilities state what effects a builder may
attempt.
.PP
Rax cannot certify goodness. It can require each accepted object to answer four
questions: what Plan requested it, what bytes were produced, who witnessed the
relation, and why local policy allowed it through. The aim is not to abolish
trust, but to make every remaining trust decision visible and contestable.
.PP
The proposal is intentionally smaller than an operating-system distribution.
Its first obligation is to prove that the language, identity, and store
protocols are understandable and correct. If that foundation holds, package
collections, development environments, services, and remote build systems can
be layered above it without becoming hidden parts of the evaluator.
.PP
Rax therefore does not reject laziness as an implementation technique or a
useful abstraction. It assigns laziness to the place where it yields the most
operational value: deciding which work must be realized. Meaning itself remains
strict, inspectable, and hashable.
.\" Force References onto a fresh, single-column page.
.nr Rr \n%
.1C
.if \n%=\n(Rr .bp
.rr Rr
.na
.SH
References
.IP "[1]" 5
E. Dolstra, M. de Jonge, and E. Visser, "Nix: A Safe and Policy-Free
System for Software Deployment," Proceedings of the 18th Large Installation
System Administration Conference, USENIX Association, formerly the UNIX Users
Group, 2004, pp. 79-92.
https:\://www.usenix.org/\:conference/\:lisa-04/\:\c
nix-safe-and-policy-free-system-software-deployment
.IP "[2]" 5
E. Dolstra, E. Visser, and M. de Jonge, "Imposing a Memory Management
Discipline on Software Deployment," Proceedings of the 26th International
Conference on Software Engineering, Institute of Electrical and Electronics
Engineers Computer Society, 2004, pp. 583-592.
.IP "[3]" 5
L. Courtes, "Functional Package Management with Guix," European Lisp
Symposium, 2013. arXiv:1305.4584.
https:\://arxiv.org/\:abs/\:1305.4584
.IP "[4]" 5
L. Courtes, "Code Staging in GNU Guix," Proceedings of the 16th Association
for Computing Machinery Special Interest Group on Programming Languages
International Conference on Generative
Programming: Concepts and Experiences, 2017. Digital object identifier (DOI):
10.1145/3136040.3136045.
.IP "[5]" 5
A. Heydon, R. Levin, T. Mann, and Y. Yu, "The Vesta Approach to Software
Configuration Management," Compaq Systems Research Center Research Report
168, 2001.
.IP "[6]" 5
S. I. Feldman, "Make - A Program for Maintaining Computer Programs,"
Software: Practice and Experience, vol. 9, no. 4, 1979, pp. 255-265.
.IP "[7]" 5
The Raku Documentation Project, "Grammars" and "Grammar Tutorial," Raku
language documentation.
https:\://docs.raku.org/\:language/\:grammars
https:\://docs.raku.org/\:language/\:grammar_tutorial
.IP "[8]" 5
The Raku Documentation Project, "Functions: Multi-dispatch," Raku language
documentation.
https:\://docs.raku.org/\:language/\:functions
.IP "[9]" 5
A. Shitov, "Raku++" and "Raku++ Architecture," project repository and
architecture documentation, 2026.
https:\://github.com/\:ash/\:rakupp
.IP "[10]" 5
A. Shitov, "Raku++ Language-Mutation and Metaprogramming Coverage," project
documentation, 2026.
https:\://github.com/\:ash/\:rakupp/blob/main/docs/METAPROGRAMMING.md
.IP "[11]" 5
L. Courtes, "Building a Secure Software Supply Chain with GNU Guix,"
arXiv:2206.14606, 2022.
https:\://arxiv.org/\:abs/\:2206.14606
.IP "[12]" 5
Reproducible Builds, "Definitions," project documentation.
https:\://reproducible-builds.org/\:docs/\:definition/
.IP "[13]" 5
Supply-chain Levels for Software Artifacts, "SLSA Specification," version 1.2,
Linux Foundation, 2026.
https:\://slsa.dev/\:spec/\:v1.2/
.IP "[14]" 5
S. Torres-Arias, H. Afzali, T. K. Kuppusamy, R. Curtmola, and J. Cappos,
"in-toto: Providing Farm-to-Table Guarantees for Bits and Bytes," Proceedings
of the 28th USENIX Security Symposium, 2019, pp. 1393-1410.
https:\://www.usenix.org/\:conference/\:usenixsecurity19/\:\c
presentation/\:torres-arias
.IP "[15]" 5
The Update Framework, "The Update Framework Specification," version 1.0.35,
project documentation.
https:\://theupdateframework.github.io/\:specification/\:v1.0.35/
.IP "[16]" 5
Sigstore, "Rekor," project documentation.
https:\://docs.sigstore.dev/\:logging/\:overview/
.IP "[17]" 5
K. Nikitin, E. Kokoris-Kogias, P. Jovanovic, N. Gailly, L. Gasser,
I. Khoffi, J. Cappos, and B. Ford, "CHAINIAC: Proactive Software-Update
Transparency via Collectively Signed Skipchains and Verified Builds,"
Proceedings of the 26th USENIX Security Symposium, 2017, pp. 1271-1287.
.IP "[18]" 5
D. A. Wheeler, "Countering Trusting Trust through Diverse Double-Compiling,"
Proceedings of the 21st Annual Computer Security Applications Conference,
Institute of Electrical and Electronics Engineers Computer Society, 2005,
pp. 28-40. DOI: 10.1109/CSAC.2005.17.
.IP "[19]" 5
J. Malka, A. Sharma, M. Monperrus, S. Zacchiroli, and T. Zimmermann,
"Trusting-Trust Attack against an Entire Linux Distribution through Binary
Manipulation," arXiv:2607.24888, 2026. Preprint.
https:\://arxiv.org/\:abs/\:2607.24888

.sp 2
.ad b
.SH
Research Assistance Disclosure
.PP
ChatGPT was used as a glorified Google search. It did assist with source
discovery, citation planning, and concurrent reading of secondary sources for
the author (she's a much faster reader). No claim or citation should be
accepted without review against the referenced source.
