# Distribute CLI v2.7.x

Distribute CLI is a command-line tool to automate building and distributing Flutter applications for Android and iOS. It provides a unified workflow for building, publishing, and managing app distribution with a single YAML configuration file.

---

## Table of Contents
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Getting Started](#getting-started)
  - [1. Initialize Your Project](#1-initialize-your-project)
  - [2. Configure `distribution.yaml`](#2-configure-distributionyaml)
- [Commands Overview](#commands-overview)
  - [`distribute init`](#distribute-init)
  - [`distribute validate`](#distribute-validate)
  - [`distribute doctor`](#distribute-doctor)
  - [`distribute build <platform>`](#distribute-build-platform)
  - [`distribute publish <publisher>`](#distribute-publish-publisher)
  - [`distribute run`](#distribute-run)
  - [`distribute changelog`](#distribute-changelog)
  - [`distribute create`](#distribute-create)
- [AI Assistant](#ai-assistant)
- [Job Reliability Options](#job-reliability-options)
- [Variable Substitution](#variable-substitution)
- [Notifications](#notifications)
- [Exit Codes and CI](#exit-codes-and-ci)
- [Logging and Secrets](#logging-and-secrets)
- [Contributing](#contributing)
- [License](#license)

---

## Features
- Build and distribute Flutter apps for Android and iOS
- Unified configuration with `distribution.yaml`
- Supports Firebase App Distribution, Fastlane, GitHub Releases, and App Store Connect
- Built-in git and pubspec variables — auto-versioning without a wrapper script
- Configuration validation and an environment check (`validate`, `doctor`)
- Plain-language commands via `distribute ai` — any OpenAI-compatible endpoint or Claude
- Dry runs, per-job retries and `continue-on-error`
- CI-friendly exit codes, a per-job run summary and a `--json` report
- Release notes generated from the git history, optionally polished by a model
- Artifact report with size and SHA-256 for every built binary
- Slack / Discord / Telegram / webhook notifications, including on failure
- Credentials are automatically masked in the terminal and in `distribution.log`

---

## Prerequisites
- [Flutter](https://flutter.dev/docs/get-started/install) — required to build
- [Firebase CLI](https://firebase.google.com/docs/cli) — only for the `firebase` publisher
- [Fastlane](https://docs.fastlane.tools/) — only for the `fastlane` publisher
- macOS with Xcode — only for iOS builds and the `xcrun` publisher

The CLI itself is a pure Dart package and does not require the Flutter SDK to install.

---

## Installation
```zsh
dart pub global activate distribute_cli
```

Verify the installation:
```zsh
distribute --version
```

---

## Getting Started

### 1. Initialize Your Project
```zsh
distribute init
```
This command sets up the required directories and generates a starter `distribution.yaml`.

### 2. Configure `distribution.yaml`
Edit the generated `distribution.yaml` to define your build and publish tasks, jobs, and variables.

#### Example
```yaml
name: "Distribution CLI"
description: "A CLI tool to build and publish your application."
variables:
  ANDROID_PACKAGE: "com.example.app"
  IOS_PACKAGE: "com.example.app"
  APPLE_ID: "${{APPLE_ID}}"
  APPLE_APP_SPECIFIC_PASSWORD: "${{APPLE_APP_SPECIFIC_PASSWORD}}"
tasks:
  - name: "Android Build and deploy"
    key: "android"
    workflows:
      - "build"
      - "publish"
    description: "Build and deploy the Android application to playstore."
    jobs:
      - name: "Build Android"
        key: "build"
        description: "Build the Android application using Gradle."
        package_name: "${{ANDROID_PACKAGE}}"
        builder:
          android:
            binary-type: "aab"
            split-per-abi: false
            build-mode: "release"
            generate-debug-symbols: true
      - name: "Publish Android"
        key: "publish"
        description: "Publish the Android application to playstore as internal test track."
        package_name: "${{ANDROID_PACKAGE}}"
        publisher:
          fastlane:
            file-path: "distribution/android/output"
            binary-type: "aab"
            track: "production"
            metadata-path: "distribution/android/metadata"
            track-promote-to: "production"
            json-key: "distribution/google-key.json"
            skip-upload-images: true
            skip-upload-screenshots: true
            in-app-update-priority: 5
            track-promote-release-status: "completed"
            upload-debug-symbols: true
  - name: "Android Build APKs"
    key: "android_apk"
    workflows:
      - "build"
    description: "Build split APKs, without publishing them."
    jobs:
      - name: "Build Android"
        key: "build"
        description: "Build the Android application using Gradle."
        package_name: "${{ANDROID_PACKAGE}}"
        builder:
          android:
            binary-type: "apk"
            split-per-abi: true
            build-mode: "release"
            generate-debug-symbols: true
            target-platform: "android-arm"
  - name: "iOS Build and deploy"
    key: "ios"
    description: "Build and deploy the iOS application to app store."
    jobs:
      - name: "Build iOS"
        key: "build"
        description: "Build the iOS application using Xcode."
        package_name: "${{IOS_PACKAGE}}"
        builder:
          ios:
            binary-type: "ipa"
            build-mode: "release"
            pub: true
      - name: "Publish iOS"
        key: "publish"
        description: "Publish the iOS application to app store."
        package_name: "${{IOS_PACKAGE}}"
        publisher:
          xcrun:
            file-path: "distribution/ios/output"
            username: "${{APPLE_ID}}"
            password: "${{APPLE_APP_SPECIFIC_PASSWORD}}"
            binary-type: "ipa"
```

---

## Commands Overview

Every command reads `distribution.yaml` from the working directory unless
`--config` says otherwise, and every one of them is listed in the table of
contents above.

### `distribute init`
Initializes the project and creates a starter configuration.

#### Example
```zsh
distribute init
```

---

---

### `distribute validate`
Parses `distribution.yaml` and reports problems without building or uploading
anything. Ideal as the first step of a CI pipeline or as a pre-commit hook.

```zsh
distribute validate
distribute validate --strict   # treat warnings as errors
```

It reports:
- **Errors** – missing keys, duplicate task/job keys, workflows pointing at a
  job that does not exist, invalid `binary-type`. These fail the command.
- **Warnings** – unresolved `${{VAR}}` placeholders and missing credential files
  such as `json-key` or `export-options-plist`.

---

---

### `distribute doctor`
Checks that the machine can actually build and publish: probes Flutter, git,
Fastlane, the Firebase CLI, Xcode and the archiver, verifies the configuration
and credentials, and prints what the built-in variables expand to.

```zsh
distribute doctor
```

Missing *optional* tools are warnings — a project that only publishes to Firebase
has no reason to install Fastlane. The command only fails on required problems.

---

---

### `distribute build <platform>`
Builds the app for the specified platform (`android` or `ios`).

#### Example
```zsh
distribute build android
```

---

---

### `distribute publish <publisher>`
Publishes the built app using the specified publisher (e.g., `firebase`, `fastlane`).

#### Example
```zsh
distribute publish fastlane
```

---

---

### `distribute run`
Executes all tasks and jobs defined in `distribution.yaml`.

#### Example
```zsh
distribute run
```

#### Options
| Option | Description |
| --- | --- |
| `-o, --operation <key>` | Run a single task (`android`) or a single job (`android.build`) |
| `-l, --list` | Print the available task and job keys, then exit |
| `--dry-run` | Resolve and print every command without executing it |
| `--fail-fast` | Stop the run as soon as a task fails |
| `--json` | Print a machine readable run report to stdout; the log moves to stderr |
| `--json-file <path>` | Write the same report to a file |
| `--no-notify` | Skip the configured notifications for this invocation |

```zsh
# See what would happen, without building or uploading anything
distribute run --dry-run

# Run only the Android build job
distribute run -o android.build

# Capture a report for the pipeline; progress still shows on the terminal
distribute run --json > report.json
```

Jobs inside a task run in the order given by `workflows` (or in declaration order
when `workflows` is omitted). **If a job fails, the remaining jobs of that task
are skipped** so a publish step never uploads the artifact of a failed build.

At the end of the run a summary is printed:

```
✓ android.build    1m 24s
✗ android.publish  12s  exit 1

✗ 1/2 job(s) succeeded  ·  1m 36s
```

---

---

### `distribute changelog`
Turns the git history into release notes. The default range is everything since
the previous tag, which is what one release actually contains — running it on a
tagged commit describes *that* release rather than an empty range.

```zsh
distribute changelog                       # notes since the previous tag
distribute changelog --from v1.2.0         # an explicit starting point
distribute changelog -f plain              # flat list, for a store listing
distribute changelog -o RELEASE_NOTES.md   # write to a file
distribute changelog --ai                  # let the model tidy the wording
```

#### Options
| Option | Description |
| --- | --- |
| `--from <ref>` | Start of the range, exclusive. Defaults to the previous tag |
| `--to <ref>` | End of the range, inclusive. Defaults to `HEAD` |
| `-f, --format <f>` | `markdown` (grouped sections) or `plain` (flat list) |
| `--no-group` | Do not group markdown output by commit type |
| `--shas` | Append the short commit hash to every line |
| `--limit <n>` | Stop after this many commits |
| `--merges` | Include merge commits |
| `--ai` | Rewrite the notes with the configured model |
| `-o, --output <path>` | Write to a file instead of stdout |

[Conventional commit](https://www.conventionalcommits.org) prefixes are used for
grouping, but nothing requires them — a repository with ordinary commit messages
gets a flat list rather than an error:

```
### Breaking changes
- drop android 5 support

### Features
- auth: add google sign in

### Bug fixes
- crash on empty profile

### Other changes
- tidy up the build script
```

#### Using it in a publish

The generated notes are available as variables, so a publisher can fill its
release notes without a wrapper script:

| Variable | Expands to |
| --- | --- |
| `${{CHANGELOG}}` | The notes, honouring `format:`, `group:` and `shas:` |
| `${{CHANGELOG_PLAIN}}` | The notes as a flat list, whatever `format:` says |
| `${{CHANGELOG_RANGE}}` | `v1.2.0 → HEAD`, for a heading or a message |

```yaml
changelog:
  format: "markdown"     # markdown | plain
  group: true            # group markdown output by commit type
  shas: false            # append the short hash to each line
  merges: false          # include merge commits
  # from: "v1.0.0"       # pin the start; omit for "the previous tag"
  # limit: 200           # stop after this many commits
  # ai: true             # polish ${{CHANGELOG}} on every publish
  # prompt: "…"          # override the editing instruction

tasks:
  - name: "Android release"
    key: "android"
    jobs:
      - name: "Publish Android"
        key: "publish"
        description: "Upload to Firebase"
        package_name: "${{ANDROID_PACKAGE}}"
        publisher:
          firebase:
            file-path: "distribution/android/output"
            app-id: "${{FIREBASE_APP_ID}}"
            binary-type: "aab"
            release-notes: "${{CHANGELOG_PLAIN}}"
```

The history is read once per run and reused, so several publishers referencing
it cost one `git log`. When there is no git repository the placeholder is left
unresolved and `validate` reports it, rather than quietly publishing empty notes.

> `ai: true` sends your commit subjects to the configured model on **every**
> publish, so it is off by default. The instruction forbids inventing or dropping
> a change. If the request fails — no key, an unreachable endpoint, a reply cut
> off by the token limit — the job **fails**: shipping raw commit subjects when
> edited notes were asked for is the one outcome nobody wants at publish time.
>
> The endpoint is subject to the same rule as `distribute ai`: if the project
> file names a `base-url` while the key comes from your machine, it warns before
> sending anything.

`distribute changelog` warns when it is run in a shallow clone (`--depth 1`,
which is the default for most CI checkouts), because the notes would silently be
missing everything before the cut. Fetch the full history first —
`git fetch --unshallow`, or `fetch-depth: 0` on a GitHub Actions checkout.

---

---

### `distribute create`
Adds tasks and jobs to `distribution.yaml`. Every subcommand takes `-w` for an
interactive wizard, or the same values as options for scripted use.

#### The wizard

```zsh
distribute create task -w              # a new task
distribute create job builder -w       # a build job inside an existing task
distribute create job publisher -w     # an upload job inside an existing task
```

The wizard picks the task from a numbered list, suggests a key derived from the
name, offers the package name detected from the project, and shows what it is
about to write before touching the file:

```
distribute 2.7.1  ·  create builder job  ·  distribution.yaml

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

A key that is already taken is rejected at the question, not after the last one,
and answering `n` at the end writes nothing. A job key only has to be unique
within its own task, because references are `task.job`.

`create` rewrites `distribution.yaml` from scratch, which drops every comment
and reflows the formatting. It warns before doing so — as part of the review in
the wizard, and as a plain warning in the scripted form, which does not stop.

#### Without the wizard

```zsh
distribute create task -n "My Task" -k my_task -d "Description here"
distribute create job builder   -t my_task -n "Build Android"   -k build   -P android
distribute create job publisher -t my_task -n "Publish Android" -k publish -T fastlane
```

`-P` may be repeated (`-P android -P ios`), as may `-T`. Use `-c` to write to a
configuration file other than `distribution.yaml`.

> A wizard reads answers from stdin, so it works with piped input as long as
> the input supplies every answer. When the input runs out — an empty stdin, a
> CI job, Ctrl-D — it stops with exit `64` and tells you to pass the values as
> options instead. It also refuses to run under `--quiet` or `--silent`, which
> would hide the questions while still waiting for answers.

---

---

## Job Reliability Options

Two optional keys can be set on any job:

```yaml
jobs:
  - name: "Publish to Firebase"
    key: "publish_firebase"
    package_name: "${{ANDROID_PACKAGE}}"
    retry: 2                 # 2 extra attempts on failure (3 total)
    continue-on-error: true  # a failure here does not fail the run
    publisher:
      firebase:
        file-path: "distribution/android/output"
        app-id: "${{FIREBASE_APP_ID}}"
        binary-type: "aab"
```

- `retry` – how many *additional* attempts a failing job gets. Useful for
  publishers, where a throttled store API or a flaky network is transient.
- `continue-on-error` – the task keeps going and the run can still succeed. The
  job is reported as `FAILED (ignored)` in the summary.

---

## Variable Substitution
Use `${{KEY}}` in `distribution.yaml` to reference environment variables or custom variables defined in the `variables` section.

Use `%{{COMMAND}}` to substitute the output of a shell command, for example
`%{{git rev-parse --short HEAD}}` or `%{{git log --pretty=format:"%s" -n 10}}`.

Unknown placeholders are left as-is so they remain visible while debugging.
`distribute validate` flags any that survive substitution.

### Built-in variables
These are available without declaring anything. They are resolved lazily — a
config that never mentions `GIT_SHA` never spawns `git` — and are overridden by
anything you define in `variables:` or export as an environment variable.

| Variable | Value |
| --- | --- |
| `GIT_SHA` / `GIT_SHORT_SHA` | Current commit hash |
| `GIT_BRANCH` | Current branch name |
| `GIT_TAG` | Nearest tag |
| `GIT_COMMIT_COUNT` | `git rev-list --count HEAD` — a monotonic build number |
| `GIT_COMMIT_MESSAGE` / `GIT_AUTHOR` | Subject and author of `HEAD` |
| `PUBSPEC_NAME` | `name` from `pubspec.yaml` |
| `PUBSPEC_VERSION` | Full version, e.g. `1.2.3+45` |
| `PUBSPEC_VERSION_NAME` | Version without the build number, e.g. `1.2.3` |
| `PUBSPEC_BUILD_NUMBER` | Build number only, e.g. `45` |
| `ANDROID_APPLICATION_ID` / `IOS_BUNDLE_ID` | Detected from the platform files |
| `BUILD_DATE` / `BUILD_TIMESTAMP` | `2026-08-15` / ISO-8601 |
| `HOST_OS` | `macos`, `linux` or `windows` |

Auto-versioning then needs no wrapper script:

```yaml
builder:
  android:
    binary-type: "aab"
    build-name: "${{PUBSPEC_VERSION_NAME}}"
    build-number: "${{GIT_COMMIT_COUNT}}"
```

Run `distribute doctor` to see what they currently expand to.

### Dart defines
`dart-defines` takes a comma-separated list and is expanded into one
`--dart-define` flag per pair:

```yaml
builder:
  android:
    binary-type: "aab"
    dart-defines: "FLAVOR=prod,API_URL=https://api.example.com"
```
becomes `flutter build aab --dart-define=FLAVOR=prod --dart-define=API_URL=https://api.example.com`.

---

---

## AI Assistant

Ask for what you want in plain language and let a model pick the command:

```zsh
distribute ai "tolong build yang ios"
```
```
openai  ·  gpt-4o-mini  ·  permission: manual

› distribute run -o ios.build
  Builds the iOS binary only.

? Run this command? (Y/n)
```

The assistant does **not** compose a shell string. It fills in a constrained
schema whose only commands are `run`, `validate` and `doctor`, and whose
operation keys come from a generated list of the keys that exist in your
`distribution.yaml`. It cannot invent a task, and it cannot reach anything a
typed command could not — the chosen command runs through the same runner.

### Setup

```zsh
distribute ai --setup
```

An interactive wizard: pick the provider, endpoint, model, and permission mode.
Secrets are typed without echoing. It then asks whether to store the settings
machine-wide (`~/.distribute/ai.json`, written `chmod 600`) or in the project.

### Providers

| Provider | Works with |
| --- | --- |
| `openai` | OpenAI, OpenRouter, Groq, Together, DeepSeek, local Ollama — anything serving `POST {base-url}/chat/completions` |
| `anthropic` | Claude, via the Messages API |

### Permission modes

| Mode | Behaviour |
| --- | --- |
| `manual` | Show the command and ask before running it. **Default.** |
| `auto` | Run the chosen command straight away. |
| `plan` | Print the command; never execute. |

Override for one invocation with `-p`:

```zsh
distribute ai "release android" -p plan
```

### Configuration

The `ai:` section of `distribution.yaml` overrides the machine-wide store:

```yaml
ai:
  provider: "openai"          # openai | anthropic
  base-url: "https://api.openai.com/v1"
  model: "gpt-4o-mini"
  permission: "manual"        # manual | plan; see the note below about auto
  api-key: "${{OPENAI_API_KEY}}"
  max-tokens: 2048            # ceiling on the model's reply
```

> **`permission: auto` is not honoured from `distribution.yaml`.** That file
> travels with the repository, so letting it grant itself the right to build and
> publish would mean cloning a repository and running `distribute ai` could
> upload on your behalf. Set it in `~/.distribute/ai.json`, or pass `-p auto`.
> The project file may still *restrict* to `manual` or `plan`.
>
> The endpoint is printed in the header of every run. If `base-url` comes from
> the project file while the key comes from your machine, `distribute ai` warns
> before sending anything.

Settings are layered, most specific first:

1. Command line flags (`--ai-provider`, `--ai-url`, `--ai-model`, `--ai-key`, `-p`)
2. The `ai:` section of `distribution.yaml`
3. `~/.distribute/ai.json`
4. `OPENAI_API_KEY` / `ANTHROPIC_API_KEY`

> `api-key` accepts `${{VAR}}`, and the wizard writes a placeholder rather than
> the literal key by default — `distribution.yaml` is normally committed. A
> literal key works if you want one, and you'll get a warning when it is written.
> Whatever the source, the resolved key is masked in the terminal and the log.

---

## Notifications

An optional top level `notifications:` section posts the run summary once every
task has finished:

```yaml
notifications:
  - provider: slack           # slack | discord | telegram | webhook
    webhook-url: "${{SLACK_WEBHOOK}}"
    on: always                # always | success | failure
    title: "Android release"
  - provider: telegram
    webhook-url: "https://api.telegram.org/bot${{TG_TOKEN}}/sendMessage"
    chat-id: "${{TG_CHAT_ID}}"
    on: failure
```

Notifications are a run-level concept rather than a job, which is what makes
`on: failure` work — a job placed after a failing build would never be reached.
Set `message:` to replace the generated summary with your own text (variables
are substituted). A delivery failure is reported as a warning and never changes
the exit code. Use `distribute run --no-notify` to skip them for one invocation.

## Exit Codes and CI

`distribute run` returns a non-zero exit code when any job fails, so it can be
used directly in a pipeline:

```yaml
# GitHub Actions
- run: dart pub global activate distribute_cli
- run: distribute validate --strict
- run: distribute run
  env:
    APPLE_ID: ${{ secrets.APPLE_ID }}
    APPLE_APP_SPECIFIC_PASSWORD: ${{ secrets.APPLE_APP_SPECIFIC_PASSWORD }}
```

| Code | Meaning |
| --- | --- |
| `0` | Every job succeeded (or failed with `continue-on-error`) |
| `1` | At least one job failed, or the configuration is invalid |
| `64` | Usage error: unknown command or flag, a missing required option, no command at all, or a wizard with nowhere to read answers from |
| `127` | A required tool (`flutter`, `fastlane`, `firebase`) was not found in `PATH` |
| `130` | `distribute ai` proposed a command and you declined it |

`127` is returned by the standalone `distribute build` and `distribute publish`
commands. `distribute run` aggregates its jobs, so a missing tool surfaces as
`1` — the underlying `127` is still shown in the summary and recorded per job as
`exit-code` in the `--json` report.

---

## Logging and Secrets

The terminal and the log file are deliberately different. The terminal gets a
compact, symbol based view meant to be read while it scrolls:

```
distribute 2.7.1  ·  distribution.yaml  ·  2 task(s), 3 job(s)

▸ Android release
  Build and ship to the Play Store internal track.

  › Build Android  build
    $ flutter build aab --release --build-name=3.1.4 --build-number=42 --pub
    ✓ done  1m 24s
      app-release.aab  42.7 MB  9f2a1c0b3d4e

✓ android.build    1m 24s
✗ android.publish  12s  exit 1

✗ 1/2 job(s) succeeded  ·  1m 36s
```

The summary uses the same key you pass to `-o`, so a failed row can be pasted
straight back: `distribute run -o android.publish`.

### Verbosity

| Flag | Terminal shows |
| --- | --- |
| *(default)* | failures, warnings, progress |
| `-v, --verbose` | the above, plus the resolved job config and raw tool output |
| `-q, --quiet` | failures only, flattened to one line each |
| `--silent` | nothing at all; only the exit code |

**The log file always records everything**, at every verbosity — including under
`--silent`. Each line is timestamped and level prefixed so it stays greppable:

```
12:13:51.140  INFO   Build Android  build
12:13:51.141  INFO   $ flutter build aab --release --pub
12:13:51.827  ERROR  Target file "lib/main.dart" not found.
```

While a build or an upload is running the CLI animates a single line showing
the step and how long it has been going, so a long silent stage does not look
like a hang:

```
  ⠹ building aab  1m 12s
```

It is drawn only on a real terminal, and never under `--quiet`, `--silent` or
`--verbose` — piped output, CI logs and the log file are unaffected.

Use `--log-file <path>` to change its location, `--no-color` to disable ANSI
colors (also disabled automatically when the output is not a terminal or when
`NO_COLOR` is set), and set `DISTRIBUTE_ASCII=1` to swap the unicode glyphs for
an ASCII fallback on legacy consoles.

Credentials are masked with `***` in both the terminal and the log file. This
covers the values themselves, so a token echoed back by Fastlane or Firebase is
redacted too. Any option whose name contains `token`, `password`, `passwd`,
`secret`, `credential`, `api-key`, `api-issuer`, `key-data` or `ai-key` is
masked, in both its long and short forms — `publish xcrun -p <password>` and
`publish fastlane -J <json>` included.

> `distribution.log` still contains the full output of the tools it drives.
> `distribute init` adds it to `.gitignore` for you - keep it out of version control.

---

## Contributing
Contributions are welcome! Please open issues or pull requests to help improve Distribute CLI.

---

## License
MIT License. See the [LICENSE](./LICENSE) file for details.
