# Distribute CLI v2.3.x

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
  - [`distribute build <platform>`](#distribute-build-platform)
  - [`distribute publish <publisher>`](#distribute-publish-publisher)
  - [`distribute run`](#distribute-run)
  - [`distribute create`](#distribute-create)
- [Variable Substitution](#variable-substitution)
- [Logging](#logging)
- [Contributing](#contributing)
- [License](#license)

---

## Features
- Build and distribute Flutter apps for Android and iOS
- Unified configuration with `distribution.yaml`
- Supports Firebase App Distribution, Fastlane, and more
- Variable substitution for environment and custom variables
- Detailed logging to `distribution.log`
- Customizable tasks and jobs for flexible workflows

---

## Prerequisites
- [Flutter](https://flutter.dev/docs/get-started/install)
- [Firebase CLI](https://firebase.google.com/docs/cli)
- [Fastlane](https://docs.fastlane.tools/)
- macOS with Xcode (for iOS builds)

---

## Installation
```zsh
dart pub global activate distribute_cli
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
            json-key: "distribution/fastlane.json"
            skip-upload-images: true
            skip-upload-screenshots: true
            in-app-update-priority: 5
            track-promote-release-status: "completed"
            upload-debug-symbols: true
  - name: "Android Build APKs and deploy"
    key: "android_apk"
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
The Distribute CLI provides several commands to manage your app distribution process.

- [distribute init](#distribute-init)
- [distribute build](#distribute-build)
- [distribute publish](#distribute-publish)
- [distribute run](#distribute-run)
- [distribute create](#distribute-create)

### `distribute init`
Initializes the project and creates a starter configuration.

#### Example
```zsh
distribute init
```

---

### `distribute build <platform>`
Builds the app for the specified platform (`android` or `ios`).

#### Example
```zsh
distribute build android
```

---

### `distribute publish <publisher>`
Publishes the built app using the specified publisher (e.g., `firebase`, `fastlane`).

#### Example
```zsh
distribute publish fastlane
```

---

### `distribute run`
Executes all tasks and jobs defined in `distribution.yaml`.

#### Example
```zsh
distribute run
```

---

### `distribute create`
Creates new tasks or jobs in `distribution.yaml`.

#### Example: Create a Task
This command facilitates the creation of new tasks. Tasks can be defined with a name, key, and description.
For an interactive task creation process, use the `--wizard` (or `-w`) option:

```zsh
distribute create task builder -w
```

Alternatively, tasks can be created directly by providing all necessary arguments:
```zsh
distribute create task --name="My Task" --key=my_task --description="Description here"
```

#### Example: Create a Builder Job
This command is used to create builder jobs for Android or iOS platforms.
The `--wizard` (or `-w`) option enables an interactive job creation mode:
```zsh
distribute create job builder -w
```

Alternatively, builder jobs can be created directly:
```zsh
distribute create job builder -t my_task -n "Build Android" -k build_android -P android
```

#### Example: Create a Publisher Job
This command allows for the creation of publisher jobs, supporting Fastlane and other configured publishers.
Utilize the `--wizard` (or `-w`) option for an interactive setup:
```zsh
distribute create job publisher -w
```

Alternatively, create publisher jobs directly by specifying the parameters:
```zsh
distribute create job publisher -t my_task -n "Publish Android" -k publish_android -T fastlane
```

---

## Variable Substitution
Use `${{KEY}}` in `distribution.yaml` to reference environment variables or custom variables defined in the `variables` section.

Use `%{{KEY}}` to reference command calls that will result strings like `${{echo "Some Strings"}}` or `${{git log --pretty=format:\"%s%d\" -n 10}}`.

---

## Logging
All logs are saved to `distribution.log` in the project root for troubleshooting and auditing.

---

## Contributing
Contributions are welcome! Please open issues or pull requests to help improve Distribute CLI.

---

## License
MIT License. See the [LICENSE](./LICENSE) file for details.
