# Distribute CLI

The **Distribute CLI** is a command-line tool designed to simplify the process of building and distributing Flutter applications for Android and iOS platforms. It integrates seamlessly with Firebase and Fastlane to provide a streamlined experience for app distribution.

---

## Features

- **Cross-Platform Support**: Build and distribute apps for Android and iOS.
- **Tool Integration**: Supports Firebase App Distribution and Fastlane for publishing.
- **Metadata Management**: Validate and download metadata for the Google Play Store.
- **Custom Configurations**: Define tasks and jobs in a `distribution.yaml` file.
- **Logging**: Detailed logs for debugging and tracking the build and distribution process.

---

## Prerequisites

Before using the Distribute CLI, ensure the following tools are installed:

- [Git](https://git-scm.com/)
- [Firebase CLI](https://firebase.google.com/docs/cli)
- [Fastlane](https://docs.fastlane.tools/)
- [Flutter](https://flutter.dev/docs/get-started/install)

For iOS builds, macOS is required along with Xcode.

---

## Installation

To install the Distribute CLI globally, run the following command:

```bash
dart pub global activate distribute_cli
```

---

## Commands

### `distribute init`

The `init` command initializes your project by creating the necessary configuration files and directories. It also validates the required tools and ensures your environment is ready for building and publishing.

#### Usage

```bash
distribute init --package-name=<your_package_name> [options]
```

#### Options

- `--package-name` (`-p`): **Required.** The package name of your application.
- `--skip-tools` (`-s`): Skip tool validation. Defaults to `false`.
- `--google-service-account` (`-g`): Path to the Google service account JSON file for Fastlane. If provided and valid, it will be copied to the Fastlane directory.

#### Example

```bash
distribute init -p com.example.app -g /path/to/service-account.json
```

This command will:
1. Create the necessary directories:
   - `distribution/android/output`
   - `distribution/ios/output` (on macOS)
2. Validate tools like Git, Firebase, Fastlane, and XCRun (on macOS).
3. Validate the service account JSON file if provided.
4. Generate a `distribution.yaml` file if it does not already exist.

---

### `distribution.yaml`

The `distribution.yaml` file is automatically generated during the `init` command. It defines the tasks and jobs for building and publishing your application.

#### Example Structure

```yaml
name: "Distribution CLI"
description: "A CLI tool to build and publish your application."
tasks:
  - name: "Android Build and deploy"
    key: "android"
    description: "Build and deploy the Android application to playstore."
    jobs:
      - name: "Build Android"
        key: "build"
        description: "Build the Android application using Gradle."
        package_name: "com.example.app"
        platform: "android"
        mode: "build"
        arguments:
          binary-type: "aab"
          split-per-abi: false
          build-mode: "release"
          target: null
          flavor: null
          build-name: null
          build-number: null
          pub: true
          dart-defines: null
          dart-defines-file: null
          arguments: null
      - name: "Publish Android"
        key: "publish"
        description: "Publish the Android application to playstore as internal test track."
        package_name: "com.example.app"
        platform: "android"
        mode: "publish"
        arguments:
          file-path: "distribution/android/output"
          binary-type: "aab"
          version-name: null
          version-code: null
          release-status: null
          track: "internal"
          rollout: null
          metadata-path: "distribution/android/metadata"
          json-key: "distribution/fastlane.json"
          json-key-data: null
          apk: null
          apk-paths: null
          aab: null
          aab-paths: null
          skip-upload-apk: false
          skip-upload-aab: false
          skip-upload-metadata: false
          skip-upload-changelogs: false
          skip-upload-images: true
          skip-upload-screenshots: true
          sync-image-upload: false
          track-promote-to: null
          track-promote-release-status: "completed"
          validate-only: false
          mapping: null
          mapping-paths: null
          root-url: null
          timeout: 300
          version-codes-to-retain: null
          changes-not-sent-for-review: false
          rescue-changes-not-sent-for-review: true
          in-app-update-priority: null
          obb-main-references-version: null
          obb-main-file-size: null
          obb-patch-references-version: null
          obb-patch-file-size: null
          ack-bundle-installation-warning: false
          publishers:
            - "fastlane"
  - name: "iOS Build and deploy"
    key: "ios"
    description: "Build and deploy the iOS application to app store."
    jobs:
      - name: "Build iOS"
        key: "build"
        description: "Build the iOS application using Xcode."
        package_name: "com.example.app"
        platform: "ios"
        mode: "build"
        arguments:
          binary-type: "ipa"
          build-mode: "release"
          target: null
          flavor: null
          dart-defines: null
          dart-defines-file: null
          build-name: null
          build-number: null
          pub: true
      - name: "Publish iOS"
        key: "publish"
        description: "Publish the iOS application to app store."
        package_name: "com.example.app"
        platform: "ios"
        mode: "publish"
        arguments:
          file-path: "distribution/ios/output"
          username: "your-apple-id"
          password: "your-app-specific-password"
          binary-type: "ipa"
          api-key: null
          api-issuer: null
          apple-id: null
          bundle-version: null
          bundle-short-version-string: null
          asc-public-id: null
          type: null
          validate-app: false
          upload-package: null
          bundle-id: null
          product-id: null
          sku: null
          output-format: null
          publishers:
            - "xcrun"
```

#### Explanation

- **Tasks**: High-level operations like building or publishing the app.
- **Jobs**: Subtasks within a task, such as building for Android or publishing to the Play Store.
- **Arguments**: Configuration details for each job, such as build modes or credentials.

#### Customization

You can modify the `distribution.yaml` file to suit your project's requirements. For example, you can add new tasks, change build modes, or update credentials.

---

### `distribute build`

The `build` command compiles your Flutter application for the specified platform (Android or iOS) and generates the necessary binary files.

#### Usage

```bash
distribute build android
distribute build ios
```

#### Options

Use the `-h` flag to view detailed options for each platform.

---

### `distribute publish`

The `publish` command uploads the generated binary files to the specified distribution platform (Firebase or Fastlane) and handles the necessary metadata.

#### Usage

```bash
distribute publish android fastlane
distribute publish android firebase
distribute publish ios
```

#### Options

Use the `-h` flag to view detailed options for each platform.

---

### `distribute run`

The `run` command executes the tasks defined in the `distribution.yaml` file. It allows you to build and publish your application in one go.

#### Usage

```bash
distribute run
```

#### Options

- `--config` (`-c`): Path to the configuration file. Defaults to `distribution.yaml`.
- `--operation` (`-o`): Key of the operation to run. Use `TaskKey.JobKey` to run a specific job.

---

## Logs

All logs are saved to `distribution.log` in the root directory. Use this file to debug issues or review the build and distribution process.

---

## Contributing

Contributions are welcome! Feel free to submit issues or pull requests to improve the tool.

---

## License

This project is licensed under the MIT License. See the [LICENSE](../LICENSE) file for details.
