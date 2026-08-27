## 2.8.1

### Fixed
* A Huawei AppGallery publish no longer fails after the bundle has already
  landed. The publisher uploads the artifact, attaches it, and then polls AGC
  for the server-side compile status. A failure of that last *query* aborted the
  whole job, which threw away a successful upload and skipped the release notes
  the job exists to write — the artifact sat in AGC as a draft with no "what's
  new" against it, and the run reported `exit 1`. The status query is now
  advisory: it logs a warning and carries on. A compilation that genuinely fails
  (`successStatus` below zero) still stops the job, and the polling interval and
  timeout are unchanged.
* The package id read back from Huawei's attach response can no longer be a
  version string. The lookup accepted `pkgVersion` next to `packageId` and
  `pkgId`, and it walks the response in field order, so a payload that carried
  `pkgVersion` first produced something like `3.1.1.301`. Handed to `pkgIds`,
  AGC rejects it as an unknown package with code 204144711
  (`call amis/ascf to get app apk failed`), which is the failure the previous
  item then turned into a dead run. `pkgVersion` is no longer a candidate and
  `pkgIds` is; when the response carries no id at all, the existing
  skip-the-polling path takes over, which is what it was there for.

## 2.8.0

### Added
* **Independent tasks can run in parallel.** `-j 2`, `-j auto`, or
  `parallel: true` in `distribution.yaml`. Given the usual

  ```
  android.build  →  android.publish
  ios.build      →  ios.publish
  ```

  the two chains overlap, so `android.publish` uploads while `ios.build` is
  still compiling. Jobs *inside* a task stay strictly ordered — that ordering is
  the point, since a publish must not start before the build it uploads.

  `flutter build` is serialised even when tasks overlap: two builds in the same
  checkout share `.dart_tool/` and `build/`, and `--pub` has both running
  `pub get` over the same directory, which Flutter does not lock. Everything
  around the compile still runs concurrently, which is where the time goes — so
  two build-only tasks gain nothing, and build-and-publish pipelines gain the
  whole upload.

  Each task's output is collected and printed as one block when it finishes,
  rather than interleaved live. The indentation counter and the output sink are
  now per-task rather than global, which is what makes that possible.
  `--fail-fast` stops starting new tasks; ones already running finish, because a
  build cannot be safely killed part way through.

* **Globally coordinated start gaps for parallel tasks.** Use
  `parallel: {tasks: 3, gap: 15s}` or `--gap 15s` to avoid starting every task
  or store upload at once. Durations accept `ms`, `s`, `m`, and `h`.
  `parallel: true`, `parallel: false`, `parallel: auto`, and numeric values
  remain backwards compatible.

* **Persistent run state and safe resume.** Every real run records job status,
  attempts, resolved version, and artifact metadata in
  `.distribute/last-run.json`. `--resume` and `--retry-failed` skip successful
  work, `--status` inspects the saved state, `--state-file` changes its location,
  and `--force-resume` explicitly overrides compatibility checks. A build is
  skipped only when every saved artifact still has the same size and SHA-256.
  The configuration, selected operation, and committed Git revision are part of
  the resume fingerprint, and Ctrl-C flushes state before stopping work.

* **Run, task, and job lifecycle hooks.** `pre` and `post` accept a command or a
  structured step with arguments, environment, working directory, timeout,
  `continue-on-error`, and `on: always|success|failure`. Hooks share the normal
  variable expansion and secret redaction, receive `DISTRIBUTE_*` context in
  their environment, and post-hooks can use `${{ARTIFACT}}` and
  `${{ARTIFACT_DIR}}`. Dry runs print hooks without executing them.

* **Job reliability controls.** `retry-delay` spaces retry attempts and
  `timeout` bounds each job attempt. Timeouts cancel in-process HTTP requests,
  send SIGTERM to tracked child processes, and escalate to SIGKILL when a child
  does not exit. `on-error: stop|continue` provides the same policy in YAML that
  `--fail-fast` provides on the command line.

* **Run-level automatic versioning.** A `version:` section resolves one shared
  version before parallel work begins, injects `${{VERSION_NAME}}` and
  `${{VERSION_CODE}}`, and includes it in state and JSON reports. Build numbers
  can come from `pubspec.yaml`, an increment, the Git commit count, a timestamp,
  or a positive literal. Optional `write-back` changes only the top-level
  `version:` line and is disabled during dry runs.

* **Safe automatic and standalone cleanup.** A `clean:` section can run after
  success, failure, or every run, after all post-hooks have finished.
  `distribute clean --flutter|--outputs|--all [--dry-run]` exposes the same
  operation directly. Cleanup only accepts paths inside the project and refuses
  symlinks or directories containing metadata, credentials, logs, or run state.

* **Huawei AppGallery publishing.** `publisher.huawei` and
  `distribute publish huawei` upload APK/AAB artifacts, resolve the AppGallery
  app ID, attach the uploaded package, poll compilation, update localized release
  notes, and optionally submit the release. Authentication supports the
  recommended Service Account PS256 JWT flow and the legacy API client flow.
  The create wizard and configuration validator understand the new publisher.

* **Wildcard artifact paths.** Any `file-path` accepts `*`, `?`, `[abc]` and
  `**`: `distribution/android/output/*.aab`, `build/**/*.ipa`. A publisher that
  uploads one binary takes the newest match whose extension agrees with
  `binary-type`, so `out/*` beside both an APK and its mapping file still
  uploads the APK. The GitHub publisher attaches every match, which is how
  `out/*.apk` uploads each split-per-ABI build as its own asset. A pattern
  matching nothing is an error during a real run and a note during `--dry-run`.

### Changed
* The minimum Dart SDK is now 3.2.0.
* GitHub and Huawei REST work participate in job cancellation, so an expired
  timeout or Ctrl-C does not leave uploads running in the background.
* Parallel stop-on-error releases workers waiting on a task-start gap
  immediately. Tasks that had already started are still allowed to finish.
* Explicit operation keys must be exactly `task` or `task.job`; malformed keys
  such as `task.job.extra` are rejected instead of silently ignoring segments.

### Fixed
* Concurrent jobs no longer race while replacing the same run-state temporary
  file. State writes are serialised and atomically replace the destination on
  platforms with different rename semantics; malformed state files now produce
  a controlled format error.
* Resuming a task no longer skips a downstream saved success after an upstream
  build had to run again. Once one ordered job is invalidated, the remainder of
  that task runs again as well.
* Long task gaps, retry delays, and Huawei compilation polling now wake
  immediately after the matching stop, timeout, or interrupt signal.
* One failing in-process cancellation callback no longer prevents other HTTP
  operations and child processes from being terminated.
* Flutter build output streams are fully drained before artifacts are moved, so
  late diagnostics are not lost.
* Duration validation rejects negative, zero-when-forbidden, and non-finite
  values consistently. Job and hook timeout values also round-trip through YAML
  using the keys the parser accepts.
* Git-derived version codes fail with an actionable message in shallow clones
  instead of silently producing a non-monotonic build number. Literal build
  numbers must be greater than zero.
* Cleanup now runs `flutter clean` from the project root, tracks the process for
  interruption, protects custom credential/state/log paths, handles
  case-insensitive filesystems, and rejects targets reached through a symlinked
  parent.
* Huawei upload requests include `releaseType`, normalize Huawei's legacy
  `fileDestUlr` spelling to `fileDestUrl`, reject incomplete upload responses,
  and wait for package compilation before submitting.
* Unexpected lifecycle hook, variable, report, notification, and state errors
  are converted to a controlled non-zero run result instead of escaping as an
  unhandled exception.

### Security
* Huawei bearer tokens and API client IDs are removed from the HTTP client while
  sending a file to the presigned upload host, then restored for AppGallery API
  calls. Credentials are never forwarded to an unrelated upload origin.
* Cleanup refuses to remove an output directory that contains configured
  Fastlane or Huawei credentials, custom logs, protected metadata, or the active
  resume state, including through symlink and case-insensitive path tricks.

## 2.7.1

### Added
* **`distribute changelog`** — release notes from the git history.

  The range defaults to everything since the previous tag, which is what one
  release actually contains. The boundary is the nearest tagged *ancestor* of
  the range's end, not the newest tag by date: a tag cut on a side branch or
  added retroactively would otherwise make a release re-list commits that had
  already shipped while dropping ones that had not.

  [Conventional commit](https://www.conventionalcommits.org) prefixes are used
  for grouping when they are there and ignored when they are not, so a
  repository with ordinary commit messages gets a flat list rather than an
  error. `--format plain` drops the headings for stores that show plain text,
  `-o` writes to a file, and `--ai` hands the result to the configured model for
  an editorial pass under an instruction that forbids inventing or dropping a
  change.

  It warns when the range is empty, and when it is run in a shallow clone — the
  default for most CI checkouts — where the notes would silently be missing
  everything before the cut.

* **`${{CHANGELOG}}`, `${{CHANGELOG_PLAIN}}` and `${{CHANGELOG_RANGE}}`** — the
  same notes as variables, so a publisher can fill `release-notes` or
  `release-body` without a wrapper script. The history is read once per run and
  shared by every job that references it. Outside a git repository the
  placeholder is left unresolved and `validate` reports it, rather than quietly
  publishing empty notes.

* **A `changelog:` section** in `distribution.yaml` setting the range, the
  format, grouping, hashes, merges and the optional AI pass. `ai: true` is off
  by default because it sends your commit subjects to the model on every
  publish; when it is on and the request fails, the job fails rather than
  shipping raw commit subjects nobody asked for.

* **A spinner while a build or upload runs.** Those stages produce nothing on
  screen below `--verbose` and can last minutes, so the CLI looked hung. One
  line, rewritten in place, carrying the step and its elapsed time.

  It is drawn only on a real terminal and never under `--quiet`, `--silent` or
  `--verbose`, so piped output, CI logs and the log file are untouched. Any log
  line printed while it runs erases it first, so the two never share a row, and
  the line is truncated to the pane width — a wrapped spinner cannot be erased,
  because a carriage return only returns to the start of the last row.

## 2.7.0

> Everything from 2.4.0 onwards is one upgrade for anyone coming from 2.3.5.
> The behaviour changes worth knowing about before you update:
> `distribute run --json` is a flag rather than an option (use `--json-file` for
> a path); `permission: auto` is no longer honoured from `distribution.yaml`;
> a `%{{command}}` substitution that fails now stops the job instead of
> silently substituting its error text; and a publisher refuses an artifact
> whose build mode does not match, rather than promoting whatever it finds.

### Added
* **`distribute ai "<request>"`** — ask a model to pick the right command:
  `distribute ai "tolong build yang ios"` → `distribute run -o ios.build`.
  The assistant never composes a shell string. It fills in a constrained schema
  whose only commands are `run`, `validate` and `doctor`, and whose operation
  keys come from a generated list of the keys that exist in *this* project — so
  it cannot invent a task, and cannot reach anything a typed command could not.
  Chosen commands run through the same `CommandRunner` as a hand-typed one.
* **Two provider backends behind one interface.** `AiProvider` has an
  OpenAI-compatible adapter (OpenAI, OpenRouter, Groq, Together, DeepSeek, a
  local Ollama — anything serving `POST /chat/completions`) and an Anthropic
  Messages API adapter. They differ in more than a URL — bearer token vs
  `x-api-key`, nested `function` vs `input_schema`, a JSON-string argument blob
  vs a parsed map, and Anthropic's refusals arriving as a *successful* HTTP 200
  that has to be checked before reading any content.
* **Three permission modes**, set by `permission:` or `-p`:
  `manual` (show the command, confirm before running — the default),
  `auto` (run it straight away), `plan` (print it, never run).
* **`distribute ai --setup`** — an interactive wizard with numbered menus and
  non-echoing secret entry. It asks whether to store the settings machine-wide
  (`~/.distribute/ai.json`, written `chmod 600`) or in the project.
* **`ai:` section in `distribution.yaml`**, which overrides the machine-wide
  store. Layering, most specific first: CLI flags → `distribution.yaml` →
  machine-wide store → environment (`OPENAI_API_KEY` / `ANTHROPIC_API_KEY`).
  `api-key` accepts `${{VAR}}`, and the wizard defaults to writing a placeholder
  rather than the literal key, since `distribution.yaml` is normally committed.
  Whatever the source, the resolved key is registered with the logger and masked
  everywhere.

### Changed
* **The `create` wizards were rebuilt.** They used to dump a list of tasks and
  ask you to retype a key from it, reject a duplicate only after every question
  had been answered, and write the file without showing you what it was about to
  add. Now the task is picked from a numbered list that shows the jobs it
  already has, the key is suggested from the name and validated at the question,
  the detected package name is offered as a default instead of being forced, and
  platforms and publishers are multi-select (`1,3`, `1-2` or `all`). The result
  is shown as a review block and confirmed before anything is written; answering
  no leaves the file untouched.
* `distribute create` accepts `-c/--config` like every other command. It writes
  to the configuration file, so needing the global `--config` for it was a trap.
* **`distribute create` silently deleted every comment in `distribution.yaml`.**
  The document is re-encoded from scratch, so adding one task threw away every
  `#` line and all the blank-line grouping in a file that is hand-maintained and
  committed. It now says so: the wizard shows the warning as part of the review,
  before the single confirm, and the scripted form warns without blocking, since
  automation asked for the change explicitly.

### Fixed
* **A failing `%{{command}}` substituted its own error text into the build.**
  `build-name: "%{{git describe}}"` outside a git repository produced
  `--build-name=fatal: not a git repository ...`, which split into extra
  arguments on the flutter command line — and the run reported success. A
  missing binary substituted an empty string just as quietly. Both now stop the
  job and name the command that failed.
* **A variable declared with no value blanked the real environment variable.**
  `FIREBASE_TOKEN:` with nothing after it overwrote the exported credential with
  an empty string, resolved the placeholder to nothing, and left `validate`
  reporting no problems. A key with no value is now a declaration, not an
  assignment.
* **The publisher promoted whatever it found, including a debug APK.** With an
  empty output directory the scoring made a lone `app-debug.apk` the best
  candidate and uploaded it. An artifact labelled with a different build mode is
  now refused outright rather than ranked lower.
* **Copying an artifact onto itself deleted it.** Pointing `output:` at the
  directory the build already writes to made source and target the same file;
  the target was deleted and then copied "from", and the run only reported a
  failed copy.
* **`xcrun --file-path` was declared, marked mandatory, and never read.** The
  publisher uploaded whatever sat in `distribution/ios/output`, so passing an
  explicit path silently shipped a different, usually stale, IPA.
* **The debug-symbol archive could come from the wrong build variant.** Matching
  was by substring and ties were broken by name length, so flavor `dev` also
  matched `devQaRelease`, and a leftover `debugRelease` beat an exact `release`.
  Variants are matched exactly now, with the loose match kept as a fallback
  ordered by modification time.
* **An unset value reached publishers as the literal string `"null"`.** The
  round trip through variable substitution stringified everything, so an omitted
  `target-commitish` was sent to the GitHub API as a branch named `null`.
* **`distribute build` printed nothing at all when it failed.** flutter's own
  diagnostics go to the verbose channel, and the standalone build commands
  return straight to the process exit code, so the console stayed empty.
* **`distribute run --dry-run` failed for any configuration with a GitHub
  publisher**, because it insisted on an artifact the rehearsal had not built.
* **`run -o task.job` could exit 0 having run nothing.** A job present in `jobs`
  but absent from the task's `workflows` was re-filtered out after being
  selected. An explicit job key now overrides the workflow ordering, `--list`
  marks jobs a whole-task run would skip, and a run that executed nothing is a
  failure rather than a silent success.
* **A malformed `pubspec.yaml` took the whole CLI down with exit 255.** Project
  metadata is read before the error handling was installed; it is optional, so a
  failure there now warns and continues.
* Mistyped YAML no longer surfaces as a raw Dart type error with no location.
  `workflows: j`, `key: 7`, `builder.android: apk`, a non-text `webhook-url` and
  the fastlane `version-code` / `rollout` / `version-codes-to-retain` keys all
  produce a message naming the file and the key. `continue-on-error: "true"` and
  `version-code: "42"` — the quoted forms editors produce — are understood now
  rather than rejected.
* `distribute doctor` reported a tool that is not installed as "found but exited
  with code 127".
* `--json-file -` produced no report at all.
* The failure hint no longer points at a log file when `--log-file ""` disabled
  file logging.
* Colours are decided from the stream the human output actually goes to, so
  `--json` piped to a parser keeps its colours on the terminal.
* `validate` warns when a job appears twice in `workflows`, and when the inert
  `output:` key is set.
* The `build` and `publish` sub-command descriptions were three lines of prose
  each; they are one line now, and `example/example.md` reproduces the real help
  output verbatim.
* The publisher wizard's tool question read stdin directly, so it was the one
  prompt that neither validated its answer nor stopped at end-of-input.
* `distribute create job -w` against a configuration with no tasks asked every
  question before failing; it now says to create a task first and stops.
* The README documented `distribute create task builder -w`, which is not a
  command.
* **A wizard started without a terminal never stopped.** `stdin.readLineSync`
  returns null once input ends and keeps returning null, so `distribute create
  task -w` in CI recursed until the stack overflowed — 14,000 frames of trace
  instead of an error — and the newer prompts spun on the same empty answer
  forever. Every prompt now treats end-of-input as an abort and exits `64` with
  a message saying to pass the values as options. `confirm` and `select` abort
  too rather than silently taking their default, which would have answered
  "yes" to questions like *write the API key into `distribution.yaml`?*
* Asking for a secret no longer fails outright where terminal echo cannot be
  switched off. Hiding the input is attempted first and, if the terminal refuses,
  the prompt warns that what is typed will be visible instead of crashing.
* **`distribute run --json` swallowed the next flag as its value.** `--json` took
  a path, so `distribute run --json --silent` wrote the report to a file literally
  named `--silent` and the run was never silenced. `--json` is now a flag that
  prints the report to stdout, and `--json-file <path>` writes it to disk. When
  the report goes to stdout the human readable log moves to stderr, so
  `distribute run --json > report.json` produces a parseable file while progress
  still shows on the terminal.
* **A mistyped configuration key was silently ignored.** `binary-typ: aab` parses
  fine and quietly builds an APK — a wrong artifact that only surfaces once it
  reaches a store. `distribute validate` now reports unknown keys at every level
  with a nearest-match suggestion. They stay warnings, not errors, so a
  configuration written for a newer CLI still runs on an older one.
* **A configuration with an `arguments:` key crashed.** The field was typed as a
  map of parsed objects while being populated with raw YAML maps, so any config
  declaring it died with a `TypeError` before anything ran. `validate` also
  points out that nothing reads the key yet.
* **`distribute` with no command exited `0`.** A script that reached this by
  mistake read it as success; it is a usage error and now exits `64`.
* A missing mandatory option exited `1`, indistinguishable from a failed build.
  The `args` package reports it as an `ArgumentError` rather than a
  `UsageException`, so it looked like a crash. It now exits `64` like every other
  usage error.
* The main example in the README declared a `workflows` entry that referenced no
  job, so the very first configuration a reader copies failed to validate.
* Pointing `--config` at a directory reported it as "not found", which sends the
  reader looking for the wrong problem. It now says what is actually wrong.
* Help text corrections: `create task` no longer describes itself as creating
  "a task or job", and `run --operation` documents the `task.job` form it
  actually accepts.
* **The global `--config` option never worked.** Every sub-command declares its
  own `--config` with a `distribution.yaml` default, and that default shadowed
  the global option on every invocation — so `distribute --config custom.yaml run`
  silently read `distribution.yaml`. A sub-command's flag now wins only when it
  was actually typed.
* A command chosen by the assistant is run with the configuration file the
  assistant was pointed at, instead of falling back to `distribution.yaml`.
* `distribute ai --setup` warns before rewriting a `distribution.yaml` that
  contains comments — re-encoding the document drops them — and offers the YAML
  to paste in by hand instead.
* An invalid `provider:` or `permission:` in the `ai:` section now names every
  place the value could have come from, rather than reporting a bare
  `Invalid argument(s)`.
* The Anthropic adapter no longer sends `output_config.effort`. It suits the
  task, but older Claude models reject it outright and the model is the user's
  choice.
* Writing the machine-wide AI store no longer fails when `chmod` is unavailable.

### Security
* **Two credentials reached the log file in the clear.** The run header masks
  credential options by name, but only matched their long spellings, so
  `publish xcrun -p <app-specific-password>` and
  `publish fastlane -J '<service-account-json>'` were written out verbatim.
  Short forms are now masked too, per sub-command — `-p` is a password under
  `xcrun` but the package name under `create job`, so the letter alone is not
  enough to decide. A test walks the real argument parsers and fails if a
  credential option grows an abbreviation that is not covered.
* **`permission: auto` is no longer honoured from `distribution.yaml`.** That
  file travels with the repository, so a cloned project could pre-authorise its
  own builds and uploads with no confirmation. The project file may still
  restrict to `manual` or `plan`; granting `auto` now requires `-p auto` or the
  machine-wide store. The demotion is announced, with the two ways to enable it.
* **The endpoint is printed, and a redirected key is flagged.** A project file
  setting `base-url` while the API key came from the machine-wide store would
  send that key wherever the repository pointed, and the URL was never shown.
  It is now part of the header, and that combination warns.
* **Project data is fenced in the model prompt.** Task and job names and
  descriptions were interpolated raw, after the tool's own rules, so a task
  description could append a section that read as new instructions and re-target
  the operation the assistant chose. Values are now flattened, capped and
  wrapped in a delimiter the prompt tells the model to treat as data.
* **Model-supplied text can no longer repaint the terminal.** Escape sequences
  were only stripped when colours were off, so a reply could erase and rewrite
  the confirmation line the user was about to answer. Everything that comes back
  over the network is stripped and truncated before it is printed.
* **A reply truncated by the token limit is refused.** Both adapters accepted a
  `tool_use` block cut short by `max_tokens` as if it were complete — a partial
  `{"command":"run"}` becomes a full-configuration run.
* Overriding `--ai-provider` no longer leaves the previous provider's key, model
  and endpoint in place, which produced a configuration nobody asked for and a
  404 blaming settings the user never touched.

## 2.6.0

### Changed
* **Redesigned the terminal output.** The `[INFO]`/`[SUCCESS]` prefixes and
  `=======` banners are gone, replaced by a symbol based, indented view
  (`▸` task, `›` job, `✓`/`✗`/`!` outcomes) with de-emphasised secondary text.
  Only what changes state is coloured, so failures actually stand out.
* **The terminal and the log file no longer share a format.** The log file now
  gets one timestamped, level prefixed line per message
  (`12:13:51.140  ERROR  ...`) and records *every* level regardless of the
  terminal verbosity - including under `--silent`.
* A job now prints the command it is about to run instead of dumping its whole
  configuration. The full config moved behind `--verbose`.
* The run summary is keyed by the operation ref (`android.publish`), so a failed
  row can be pasted straight into `distribute run -o <ref>`.
* Failures are reported once, by the runner, instead of by both the runner and
  the builder.

### Fixed
* **Every flavored Android release build failed.** Debug symbols were looked for
  at the hardcoded `merged_native_libs/release/mergeReleaseNativeLibs/`, but
  Gradle names that directory after the *variant* - `prodRelease` /
  `mergeProdReleaseNativeLibs` - and older AGP versions omit the task
  subdirectory entirely. The directory was therefore never found, and a missing
  directory returned a non-zero exit code, so a build that had already produced
  and copied its artifact was reported as failed. The layout is now discovered by
  searching, and symbol problems are warnings: they can no longer fail a build
  whose binary is already on disk. `generate-debug-symbols` defaults to `true`,
  so this affected every flavored release.
* **Debug symbols ignored the job's `output`** and were always written to
  `distribution/android/output`, while the fastlane publisher looks for
  `debug_symbols.zip` next to the binary - so a custom output silently lost them.
* **A stale binary from a previous build was copied into the output directory.**
  After a debug build followed by a release build, `app-debug.apk` was copied
  next to `app-release.apk`; the GitHub publisher uploads *every* matching file
  in that directory, so a debug binary could ship in a release. Only the
  best-matching tier is copied now (a `--split-per-abi` set still copies in
  full), and artifacts left by an earlier build are pruned.
* **The iOS bundle identifier could resolve to the unit test target.** The first
  `PRODUCT_BUNDLE_IDENTIFIER` in `project.pbxproj` was taken verbatim, so a
  reordered project yielded `...RunnerTests`, quoted values kept their quotes,
  and an unresolved `$(APP_ID)` was returned as-is - each of which becomes a
  wrong `--bundle-id` at upload time.
* `CompressFiles.compress` ignored its second parameter and always wrote
  `debug_symbols.zip`; it also failed on Windows when the archive already
  existed, and threw instead of reporting a missing archiver.
* `create job builder` / `create job publisher` without `--platform` / `--tools`
  reported a raw exception that never named the missing option.
* The notifier only bounded its receive timeout, so an unroutable webhook host
  could hold the run open for the OS-level TCP timeout after all work was done.
* **Streamed tool output broke the log format.** A child process delivers its
  output as arbitrary chunks, not lines, so every line after the first in a chunk
  was written without a timestamp, a level or an indent. Each line is now emitted
  as its own record.
* **ANSI escape codes from child processes leaked into `distribution.log`**,
  leaving it unreadable in an editor and awkward to grep. They are now stripped
  from the file (and from the terminal when colors are disabled).
* A chunk ending in a newline no longer appends a blank log record.
* `--log-file <dir>` deleted the directory and everything in it. Anything that is
  not a regular file is now refused.
* An empty `--log-file` disables file logging, as the help text already claimed.
* `--silent` is now absolute: it can no longer be overridden per logger instance.

### Added
* `-q, --quiet` - print failures only, flattened to one line each.
* `--silent` - print nothing; the exit code is the only signal. The log file is
  still written in full.
* The log file opens with a run header carrying the version, the ISO timestamp,
  the working directory and the invocation - with credential options masked,
  since the header is written before any job registers its secrets.
* `DISTRIBUTE_ASCII=1` swaps the unicode glyphs for an ASCII fallback on legacy
  consoles.

## 2.5.0

### Fixed
* **`distribute publish fastlane` crashed with `LateInitializationError`.** The
  standalone command dereferenced the enclosing job, which only exists when the
  publisher comes from `distribution.yaml`. The package name is now resolved from
  `--package-name`, then the job, then the detected `applicationId`.
* **`distribute publish firebase` crashed before doing anything**, because it read
  an option named `cli-token` that the parser never declared. It now reads
  `--token`, and also honours the mandatory `--file-path` it used to ignore.
* **`xcrun`'s `validate-app` sent `-v` to altool**, which means *verbose*, not
  *validate* — so the archive was never actually validated. Validation now runs as
  its own `--validate-app` pass before the upload, and aborts the upload on failure.
* **`fastlane`/`firebase` tool probes never drained stderr.** A tool writing more
  than the OS pipe buffer (`fastlane actions` does) would block forever. Both
  streams are now drained on every spawned process.
* `xcrun`'s `upload-package` option was accepted but silently ignored.
* `distribute create` crashed on a config without a `variables:` section, and on
  an empty YAML file.
* `distribute init` no longer calls `exit()` from inside a helper, so the exit
  code and the log file stay consistent.

### Added
* **Built-in variables** — `${{GIT_SHA}}`, `${{GIT_SHORT_SHA}}`, `${{GIT_BRANCH}}`,
  `${{GIT_TAG}}`, `${{GIT_COMMIT_COUNT}}`, `${{GIT_COMMIT_MESSAGE}}`,
  `${{GIT_AUTHOR}}`, `${{PUBSPEC_VERSION}}`, `${{PUBSPEC_VERSION_NAME}}`,
  `${{PUBSPEC_BUILD_NUMBER}}`, `${{PUBSPEC_NAME}}`, `${{ANDROID_APPLICATION_ID}}`,
  `${{IOS_BUNDLE_ID}}`, `${{BUILD_DATE}}`, `${{BUILD_TIMESTAMP}}`, `${{HOST_OS}}`.
  Auto-versioning no longer needs a wrapper script:
  `build-number: "${{GIT_COMMIT_COUNT}}"`. Resolved lazily, and overridable.
* **`distribute doctor`** — probes every external tool, the configuration and the
  credentials, and prints what the built-in variables expand to.
* **Run notifications** — a top level `notifications:` section posts the run
  summary to Slack, Discord, Telegram or a generic webhook, with
  `on: always|success|failure`. Modelled at run level so `on: failure` actually
  fires. Delivery problems never change the exit code.
* **Artifact report** — every built binary is listed with its size and SHA-256
  in the run summary.
* **`distribute run --json`** — machine readable run report on stdout, or
  `--json-file <path>` to write it to disk.
* `distribute run --no-notify` to suppress notifications for one invocation.

## 2.4.0

### Fixed
* **`distribute run` now exits with a non-zero code when a job fails.** Previously
  every run exited `0`, so CI pipelines silently reported broken builds as green.
* **`dart-defines` produced an invalid `--dart-defines` flag.** Flutter only accepts
  a repeated `--dart-define=KEY=VALUE`, so *any* configuration using dart defines
  failed with exit code 64. Values are now expanded into one flag per pair.
* **GitHub release assets were uploaded as `multipart/form-data`.** The GitHub API
  expects the raw bytes, so every uploaded APK/AAB/IPA was corrupted. Assets are
  now streamed as the raw request body with a correct content type.
* **A publish job no longer runs after its build job failed**, which used to upload
  a stale artifact from a previous build.
* Credentials (Apple password, GitHub token, Firebase CI token, Google service
  account JSON data) are no longer written to `distribution.log` or the terminal.
* `--obfuscate` now auto-supplies the `--split-debug-info` directory that Flutter
  requires, instead of failing the build with a usage error.
* GitHub releases are matched by name *and* tag, and are no longer created as
  drafts by default. The previous "fall back to the latest release" behaviour
  could attach a build to an unrelated release and has been removed.
* A missing `variables:` section no longer crashes with a `type 'Null' is not a
  subtype of type 'Map'` error; the section is optional.
* Fastlane no longer appends `debug_symbols.zip` to the caller's `mapping-paths`
  list on repeated reads.
* Debug symbols are copied into the output directory even when it does not exist yet.
* Errors are written to stderr, and colors are disabled automatically when the
  output is piped or `NO_COLOR` is set.

### Added
* `distribute validate` - parses the configuration, reports unresolved `${{VAR}}`
  placeholders and missing credential files. Use `--strict` to fail on warnings.
* `distribute run --dry-run` - prints every resolved command without executing it.
* `distribute run --list` - lists the available task and job keys.
* `distribute run --fail-fast` - stops at the first failing task.
* Per-job `continue-on-error: true` and `retry: <n>` in `distribution.yaml`.
* A run summary with per-job status, duration and attempt count.
* Global `--version`, `--log-file` and `--no-color` flags.
* `obfuscate` and `split-debug-info` are now supported for iOS builds too.
* GitHub publisher: `binary-type`, `draft`, `prerelease` and `target-commitish`.
* `distribute init` appends the generated artifacts to `.gitignore`.
* Test suite covering config validation, argument building, variables and logging.

### Changed
* **The package no longer depends on the Flutter SDK.** It never used a Flutter
  API, and the dependency made the documented `dart pub global activate
  distribute_cli` fail. Installing is now a plain Dart install.
* Configuration errors name the offending key and its position, for example
  `tasks[0].jobs[1] ('Publish') in 'distribution.yaml' is invalid: ...`.
* Duplicate task/job keys and workflow entries that reference a missing job are
  rejected at parse time rather than mid-run.
* When several artifacts match, the most recently modified one is published.
* Removed the unusable `Job.fromJson` factory, which always threw because it
  never constructed a builder or publisher.

## 2.3.5
* Fix dart-define-from-file
* Upgrade packages
* Flavor app supports

## 2.3.4
* Fix typo
* Read applicationId from gradleKts

## 2.3.3
* Distribute debug symbols and path separator fixes 

## 2.3.2
* Windows powershall validate fastlane fixes

## 2.3.1
* Enhance documentations

## 2.3.0+1
* Windows powershell support
* Enhance logger to provide more detailed information
* Enhance code and functionality for better performance

## 2.2.0
* Add `wizard` command to create a new `distribution.yaml` file interactively
* Enhance logger to provide more detailed information
* Enhance code and functionality for better performance

## 2.1.2
* Add command substitution for `distribution.yaml` variables `%{{COMMAND}}`
* Optimize the code

## 2.1.1
* Fix `distribute run -o` not working on specific jobs
* Fix wrong output for ios built

## 2.1.0
* Add output on build and publish
* Output on job's arguments
* Once build finished or publish started, binary will be copyed to the output provided
* Add `Builder.generate-debug-symbols` and `Publisher.fastlane.upload-debug-symbols` for Android
* Change `distribution.yaml` patterns
* Add `workflows` on `Task` to sort the jobs
* Add Github as a publisher
* Change publisher subcommand to directly use the publisher name
* Add `create` command to create a new task or job on distirbution.yaml
* Update documentation
* Update examples

## 2.0.1
* Add `exportOptionsPlist` and `exportMethod` to iOS build
* Solving pub.dev scores

## 2.0.0
* Refactor the code
* Refactor how to use the package
* Distribute.yaml is now used to configure the package
* Added support for `${{KEY}}` to reference environment variables or custom variables from `distribution.yaml`
* Updated `README.md`:
  - Added detailed explanation for using `${{KEY}}` in `distribution.yaml`
  - Enhanced examples for `distribution.yaml` with variables and tasks
  - Improved documentation for commands (`init`, `build`, `publish`, `run`)
  - Added a section for variable substitution in `distribution.yaml`
  - Clarified usage of environment variables and custom variables

## 1.0.4+4
* Fix Android and iOS build error logs

## 1.0.4+3
* Update code docs

## 1.0.4+2
* Update changelogs
* Update readme.md

## 1.0.4+1
* Enhance distribution.log and terminal logs
* Run firebase and fastlane same time for quick process
* Publish git logs on fastlane
* Update readme.md and add example.md

## 1.0.3+1
* Create distribution.log to record the logs
* Start distribute once task finished

## 1.0.2+1
* Builder and Publisher will be more tolerant for tools that doesn't exists
* Firebase changelogs included
* Optimize code and error appearance

## 1.0.1+1
* Add `fastlane_track` and `fastlane_promote_track_to`
* Solve `distribute build -p`
* More environment on init

## 1.0.0+2
* Add documentation on the code
* Solve pub.dev scores

## 1.0.0+1
* Add distribute executable
* Fix args not working on subCommands
* Enhance command to be more clearer

## 1.0.0
* First release, look readme.md for details
