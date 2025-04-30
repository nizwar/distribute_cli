# Distribute CLI

The **Distribute CLI** is a command-line tool designed to streamline the process of building and distributing Flutter applications for Android and iOS platforms. It supports integration with Firebase and Fastlane for seamless app distribution.

## Features

- Build Android and iOS apps with custom configurations.
- Distribute apps using Firebase App Distribution or Fastlane.
- Automatically generate changelogs based on Git commits.
- Validate and download metadata for Android Play Store.
- Cross-platform support (macOS required for iOS builds).

## Prerequisites

Before using the Distribute CLI, ensure the following tools are installed:

- [Git](https://git-scm.com/)
- [Firebase CLI](https://firebase.google.com/docs/cli)
- [Fastlane](https://docs.fastlane.tools/)
- [Flutter](https://flutter.dev/docs/get-started/install)

For iOS builds, you must use macOS and have Xcode installed.

## Installation

Execute the following command to globally activate `distribute_cli`:
```bash
dart pub global activate distribute_cli
```

Run the following command to initialize the environment:

```bash
distribute init
```

This will create the necessary directories and validate the required tools.

## Usage

### Build Apps

To build Android and iOS apps, use the `build` command:

```bash
distribute build --android --ios
```

#### Options

- `-p, --[no-]publish`: Automatically distribute Android builds.
- `--[no]-android`: Build Android (enabled by default).
- `--[no]-ios`: Build iOS (enabled by default).
- `--android_binary`: Specify the Android binary type (`aab` or `apk`).
- `--android_args`: Specify additional arguments for Android builds.
- `--ios_args`: Specify additional arguments for iOS builds.
- `--custom_args=<macos:macos,windows:windows,ios:ipa,android_apk:apk>`: Provide custom arguments in the format `key:args,key:args`. These will be executed as `flutter build <args>`.

### Distribute Apps

To distribute apps, use the `publish` command:

```bash
distribute publish --android --firebase
```

#### Options

- `--[no]-android`: Build and distribute Android (enabled by default).
- `--[no]-ios`: Build and distribute iOS (enabled by default).
- `--[no]-firebase`: Use Firebase for distribution.
- `--[no]-fastlane`: Use Fastlane for distribution (enabled by default).
- `--fastlane_track`: Specify the Play Store track (e.g., `internal`, `production`).
- `--fastlane_promote_track_to`: Specify the track to promote to after distribution.

### Example Commands

#### Build and Distribute Android App

```bash
distribute build --no-ios --android --publish --android_binary=aab
```

#### Distribute iOS App

```bash
distribute publish --ios --no-android
```

#### Build with Custom Arguments

```bash
distribute build --custom_args="macos:macos,windows:windows"
```

## Configuration

The tool uses a `.distribution.env` file for configuration. This file is created during initialization and contains the following settings:

```env
ANDROID_BUILD=true
ANDROID_DISTRIBUTE=true
ANDROID_PLAYSTORE_TRACK=internal
ANDROID_PLAYSTORE_TRACK_PROMOTE_TO=production
ANDROID_PACKAGE_NAME=com.example.app
ANDROID_FIREBASE_APP_ID=your-firebase-app-id
ANDROID_FIREBASE_GROUPS=testers
ANDROID_BINARY=appbundle

IOS_BUILD=true
IOS_DISTRIBUTE=true
IOS_DISTRIBUTION_USER=your-apple-id
IOS_DISTRIBUTION_PASSWORD=your-app-specific-password

USE_FASTLANE=true
USE_FIREBASE=false
```


### Populating the `.distribution.env` File

1. **ANDROID_BUILD**:  
   Set to `true` to enable Android builds.

2. **ANDROID_DISTRIBUTE**:  
   Set to `true` to enable Android distribution after building.

3. **ANDROID_PACKAGE_NAME**:  
   Specify your app's package name (e.g., `com.example.app`).

4. **ANDROID_PLAYSTORE_TRACK**:  
   Specify the Play Store track for Android distribution (e.g., `internal`, `alpha`, `beta`, `production`). Defaults to `internal`.

5. **ANDROID_PLAYSTORE_TRACK_PROMOTE_TO**:  
   Specify the Play Store track to promote the build to after distribution (e.g., `production`). Defaults to `production`.

6. **ANDROID_BINARY**:  
   Specify the Android binary type for builds (`apk` or `appbundle`). Defaults to `appbundle`.

7. **ANDROID_FIREBASE_APP_ID**:  
   Provide your Firebase App ID if using Firebase App Distribution. Leave blank otherwise.

8. **ANDROID_FIREBASE_GROUPS**:  
   List Firebase tester groups (comma-separated) for distribution. Leave blank if not applicable.

9. **IOS_BUILD**:  
   Set to `true` to enable iOS builds.

10. **IOS_DISTRIBUTE**:  
    Set to `true` to enable iOS distribution after building.

11. **IOS_DISTRIBUTION_USER**:  
    Provide your Apple ID for App Store distribution.

12. **IOS_DISTRIBUTION_PASSWORD**:  
    Provide your app-specific password for App Store distribution. You can generate it from [Apple ID settings](https://support.apple.com/en-us/HT204397).

13. **USE_FASTLANE**:  
    Set to `true` to enable Fastlane for Android distribution.

14. **USE_FIREBASE**:  
    Set to `true` to enable Firebase App Distribution.

### Adding the `distribution/fastlane.json` File

1. Visit the [Google Cloud Console](https://console.cloud.google.com/).
2. Navigate to **IAM & Admin > Service Accounts**.
3. Select or create a service account with **Editor** or **Release Manager** permissions for your Play Store project.
4. Generate a JSON key for the service account and download it.
5. Place the JSON key file in the `distribution` directory and name it `fastlane.json`.

Ensure your project directory is structured as follows:

```
your_project_directory
  ├── lib
  ├── distribution
      ├── fastlane.json
```

## Logs

All logs are saved to `distribution.log` in the root directory. Use this file to debug issues or review the build and distribution process.

## Contributing

Contributions are welcome! Feel free to submit issues or pull requests to improve the tool.

## License

This project is licensed under the MIT License. See the [LICENSE](../LICENSE) file for details.
