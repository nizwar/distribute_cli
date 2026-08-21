# Example Commands

Every command reads `distribution.yaml` from the working directory unless
`--config` says otherwise. The output below is the CLI's own help text; run
`distribute help <command>` for the current version.

## Global options

```
Run commands to distribute your app packages.

Usage: distribute <command> [arguments]

Global options:
-h, --help            Print this usage information.
-v, --[no-]verbose    Print diagnostic detail and raw tool output.
-q, --quiet           Print failures only.
    --silent          Print nothing; rely on the exit code. The log file is still written.
    --version         Print the distribute_cli version and exit.
    --[no-]color      Enable ANSI colors in the terminal output.
                      (defaults to on)
    --config          Path to the configuration file.
                      (defaults to "distribution.yaml")
    --log-file        Path to the log file. Use an empty value to disable file logging.
                      (defaults to "distribution.log")

Available commands:
  ai         Ask a model to pick the right distribute command for you.
  build      Build the application using the selected platform or custom configuration.
  clean      Clean Flutter build products and distribution output directories.
  create     Create a new task or job.
  doctor     Check that the tools, configuration and credentials are ready to use.
  init       Initialize the project with the necessary configuration files and directories.
  publish    Publish the app to the specified platform.
  run        Run the tasks and jobs declared in the configuration.
  validate   Validate the distribution configuration without running any job.
```

## A first run

```zsh
distribute init                 # scaffold distribution.yaml and the output dirs
distribute doctor               # check the toolchain and credentials
distribute validate --strict    # fail on anything suspicious
distribute run --dry-run        # print every command without executing it
distribute run                  # build and publish for real
```

## `distribute init`

```
Initialize the project with the necessary configuration files and directories.

Usage: distribute init [arguments]
-a, --android-package-name      Package name for the application.
-i, --ios-package-name          Bundle identifier for the iOS application.
-s, --[no-]skip-tools           Skip tool validation.
-g, --google-service-account    Google service for fastlane, if it validated it will be copied to the fastlane directory.

Run "distribute help" to see global options.
```

## `distribute run`

```
Run the tasks and jobs declared in the configuration.

Usage: distribute run [arguments]
-c, --config       Path to the configuration file.
                   (defaults to "distribution.yaml")
-o, --operation    Run a single task ("android") or a single job ("android.build").
                   (defaults to "")
    --dry-run      Resolve and print every command without executing it.
    --fail-fast    Stop the run as soon as a task fails.
-l, --list         List the available tasks and jobs, then exit.
    --json         Print a machine readable run report to stdout. The human readable log moves to stderr.
    --json-file    Write the machine readable run report to the given path.
-j, --jobs         Run up to this many tasks at once. 1 keeps the current sequential behaviour; "auto" uses the core count.
    --gap          Minimum gap between task starts (for example 15s or 2m).
    --on-error     Continue independent tasks or stop starting new ones.
                   [continue, stop]
    --resume       Resume the last compatible run from its state file.
    --retry-failed Resume and run failed/interrupted jobs while skipping successes.
    --state-file   Path used to persist resumable run state.
                   (defaults to ".distribute/last-run.json")
    --force-resume Resume even when the config fingerprint changed.
    --status       Print the saved run status without executing jobs.
    --no-notify    Skip the notifications declared in the configuration.

Run "distribute help" to see global options.
```

```zsh
distribute run -l                     # what can I run?
distribute run -o android             # one task
distribute run -o android.build       # one job
distribute run --json > report.json   # report on stdout, progress on stderr
distribute run -j 2                   # android and ios chains at the same time
distribute run -j auto --gap 15s      # stagger task starts
distribute run --retry-failed         # continue a saved run
```

## `distribute validate`

```
Validate the distribution configuration without running any job.

Usage: distribute validate [arguments]
-c, --config    Path to the configuration file.
                (defaults to "distribution.yaml")
    --strict    Treat warnings as errors.

Run "distribute help" to see global options.
```

Reports unknown keys, unresolved `${{VAR}}` placeholders and missing credential
files. A mistyped key is a warning rather than an error, so a configuration
written for a newer CLI still runs on an older one:

```
! android.build > builder.android has an unknown key 'binary-typ'; it is ignored — did you mean 'binary-type'?
```

## `distribute doctor`

```
Check that the tools, configuration and credentials are ready to use.

Usage: distribute doctor [arguments]
-c, --config    Path to the configuration file.
                (defaults to "distribution.yaml")

Run "distribute help" to see global options.
```

## `distribute build`

```
Build the application using the selected platform or custom configuration.

Usage: distribute build <subcommand> [arguments]
-h, --help    Print this usage information.

Available subcommands:
  android   Build an Android APK or AAB, with build modes, flavors and signing.
  custom    Build with a binary type and arguments you supply yourself.
  ios       Build a signed iOS IPA. Requires macOS with Xcode.

Run "distribute help" to see global options.
```

```zsh
distribute build android --binary-type aab --build-mode release
distribute build ios --export-method app-store
```

## `distribute publish`

```
Publish the app to the specified platform.

Usage: distribute publish <subcommand> [arguments]
-h, --help    Print this usage information.

Available subcommands:
  fastlane   Publish to the Play Store using Fastlane supply.
  firebase   Publish to Firebase App Distribution.
  github     Publish the artifacts as a GitHub release.
  huawei     Upload an APK/AAB and optionally submit it to Huawei AppGallery.
  xcrun      Publish to App Store Connect using xcrun altool.

Run "distribute help" to see global options.
```

## `distribute create`

```
Create a new task or job.

Usage: distribute create <subcommand> [arguments]
-h, --help    Print this usage information.

Available subcommands:
  job    Create a new job.
  task   Create a new task in the configuration.

Run "distribute help" to see global options.
```

Every `create` subcommand takes `-c/--config`, `-w/--wizard`, `-n/--name`,
`-k/--key` and `-d/--description`. Job subcommands add `-t/--task-key`,
`-p/--package-name`, and the repeatable `-P/--platform` (builder) or
`-T/--tools` (publisher).

```zsh
distribute create task -n "Android" -k android -d "Build and ship Android"
distribute create job builder -t android -n "Build" -k build -P android -P ios
distribute create job publisher -t android -n "Publish" -k publish -T firebase -T github
```

`-P` and `-T` may be repeated. Pass `-w` instead to fill the same fields
interactively — the wizard picks the task from a numbered list, suggests a key
from the name, and shows what it will write before touching the file:

```
? Which task does this job belong to?
  › 1) Android release  android  build, publish
    2) iOS release  ios  no jobs yet
  1-2 (1) 2

? Job name (Build) Build iOS
? Job key (build_ios) build
? Description Archive and sign
? Package name (com.acme.myapp)

? Which platforms should this job build?
  › 1) android  APK or AAB via Gradle
    2) ios  IPA via Xcode
  1-2 or "all" (1) 2

  task         ios
  name         Build iOS
  key          build
  description  Archive and sign
  package      com.acme.myapp
  platforms    ios
  reference    ios.build

? Add this job to distribution.yaml? (Y/n)
✓ added ios.build to distribution.yaml
  run it with `distribute run -o ios.build`
```

A wizard reads its answers from stdin. When the input runs out — a CI job, an
empty stdin, Ctrl-D — it exits `64` rather than hanging. It also refuses to run
under `--quiet` or `--silent`.

## Wildcard paths

Any `file-path` accepts `*`, `?`, `[abc]` and `**`:

```yaml
publisher:
  fastlane:
    file-path: "distribution/android/output/*.aab"
  github:
    file-path: "distribution/android/output/*.apk"   # every split APK
  xcrun:
    file-path: "build/ios/ipa/*.ipa"
```

## `distribute changelog`

```
Generate release notes from the git history.

Usage: distribute changelog [arguments]
-c, --config            Path to the configuration file.
                        (defaults to "distribution.yaml")
    --from              Start of the range, exclusive. Defaults to the previous tag.
    --to                End of the range, inclusive.
                        (defaults to "HEAD")
-f, --format            How to render the notes.

          [markdown]    Headed sections and bullets, for a GitHub release.
          [plain]       A flat bullet list, for stores that show plain text.

    --[no-]group        Group markdown output by conventional commit type.
                        (defaults to on)
    --shas              Append the short commit hash to every line.
    --limit             Stop after this many commits.
    --merges            Include merge commits.
    --ai                Rewrite the notes with the configured model before printing.
-o, --output            Write to this file instead of stdout.

Run "distribute help" to see global options.
```

```zsh
distribute changelog                      # since the previous tag
distribute changelog --from v1.2.0        # explicit range
distribute changelog -f plain             # flat list, for a store listing
distribute changelog -o RELEASE_NOTES.md  # write to a file
distribute changelog --ai                 # let the model tidy the wording
```

Reference the result from a publisher instead of copying it by hand:

```yaml
changelog:
  format: markdown

tasks:
  - name: Ship
    key: ship
    jobs:
      - name: Firebase
        key: fb
        description: Upload the build
        package_name: com.example.app
        publisher:
          firebase:
            file-path: distribution/android/output
            app-id: "1:2:android:3"
            binary-type: aab
            release-notes: "${{CHANGELOG_PLAIN}}"
```

## `distribute ai`

```
Ask a model to pick the right distribute command for you.

Usage: distribute ai [arguments]
-c, --config          Path to the configuration file.
                      (defaults to "distribution.yaml")
    --setup           Run the interactive setup wizard instead of asking a question.
    --ai-provider     Override the provider for this run (openai, anthropic).
    --ai-url          Override the endpoint base URL for this run.
    --ai-key          Override the API key for this run.
    --ai-model        Override the model for this run.
-p, --permission      Override how much the assistant may do on its own.

          [manual]    Show the command and ask before running it.
          [auto]      Run the chosen command without asking.
          [plan]      Print the command; never execute.

Run "distribute help" to see global options.
```

```zsh
distribute ai --setup                       # store provider, model and key
distribute ai "build the iOS app"           # ask, then confirm before running
distribute ai -p plan "ship to Firebase"    # print the command, never run it
```

## Exit codes

```zsh
distribute run || echo "failed with $?"
```

`0` success, `1` a job failed or the configuration is invalid, `64` a usage
error, `127` a required tool is missing from `PATH`.
