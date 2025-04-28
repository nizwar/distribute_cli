# Distribute CLI

`distribute_cli` is a command-line utility designed to streamline the process of building and distributing your Flutter applications.

## Installation

To install `distribute_cli`, please follow these steps:

* **Activate the CLI**  
   Execute the following command to globally activate `distribute_cli`:
   ```bash
   dart pub global activate distribute_cli
   ```

## Prerequisites

Ensure the following tools are installed before proceeding:

- **Fastlane (for Android distribution)**:  
  Follow the installation guide available at [fastlane.tools](https://fastlane.tools).

- **Firebase CLI (optional, for Firebase App Distribution)**:  
  Install Firebase CLI by running:  
  ```bash
  npm install -g firebase-tools
  ```

- **Xcode Command Line Tools (for iOS builds)**:  
  Install Xcode and verify that `xcrun` is accessible.

- **Git**:  
  Ensure Git is installed and configured for generating changelogs.

- **Google Cloud Service Account Key (for Fastlane)**:  
  Obtain the JSON key file for your Google Cloud service account. This is required for Fastlane to upload Android builds to the Play Store.

## Environment Configuration

When you run `distribute init`, a `.distribution.env` file will be automatically generated with the following structure:

```env
# Android Configuration
ANDROID_BUILD=true
ANDROID_DISTRIBUTE=true
ANDROID_PACKAGE_NAME=
ANDROID_FIREBASE_APP_ID=
ANDROID_FIREBASE_GROUPS=

# iOS Configuration
IOS_BUILD=true
IOS_DISTRIBUTE=true
IOS_DISTRIBUTION_USER=
IOS_DISTRIBUTION_PASSWORD=

# Distribution Options
USE_FASTLANE=true
USE_FIREBASE=false
```

Additionally, a `distribution` directory will be created.  
It is recommended to add both `.distribution.env` and the `distribution` directory to your `.gitignore` file to prevent committing sensitive information:

```gitignore
.distribution.env
distribution/
```

### Populating the `.distribution.env` File

1. **ANDROID_BUILD**:  
   Set to `true` to enable Android builds.

2. **ANDROID_DISTRIBUTE**:  
   Set to `true` to enable Android distribution after building.

3. **ANDROID_PACKAGE_NAME**:  
   Specify your app's package name (e.g., `com.example.app`).

4. **ANDROID_FIREBASE_APP_ID**:  
   Provide your Firebase App ID if using Firebase App Distribution. Leave blank otherwise.

5. **ANDROID_FIREBASE_GROUPS**:  
   List Firebase tester groups (comma-separated) for distribution. Leave blank if not applicable.

6. **IOS_BUILD**:  
   Set to `true` to enable iOS builds.

7. **IOS_DISTRIBUTE**:  
   Set to `true` to enable iOS distribution after building.

8. **IOS_DISTRIBUTION_USER**:  
   Provide your Apple ID for App Store distribution.

9. **IOS_DISTRIBUTION_PASSWORD**:  
   Provide your app-specific password for App Store distribution. You can generate it from [Apple ID settings](https://support.apple.com/en-us/HT204397).

10. **USE_FASTLANE**:  
    Set to `true` to enable Fastlane for Android distribution.

11. **USE_FIREBASE**:  
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

## Usage Instructions

1. **Install the CLI**  
   Run the following command to globally install `distribute_cli`:
   ```bash
   dart pub global activate distribute_cli
   ```

2. **Initialize Distribution**  
   Execute this command in your project directory to set up the distribution environment:
   ```bash
   distribute init
   ```

3. **Build Your Project**  
   Use the following command to build your project. Include the `-p` flag to automatically upload the build:
   ```bash
   distribute build -p
   ```

4. **Publish Your Project**  
   To publish your project without building, run:
   ```bash
   distribute publish
   ```

For additional arguments and details, refer to the sections below.

## Command Reference

Run commands to build and distribute your app packages:

```bash
distribute <command> [arguments]
```

### Global Options

- `-h, --help`  
  Display usage information.
  
- `--config_path`  
  Specify the path to the configuration file.  
  *(defaults to `.distribution.env`)*

- `-v, --[no-]verbose`  
  Enable verbose output.

- `-l, --[no-]process_logs`  
  Enable process logs.

### Available Commands

#### `init`

Initialize the distribution tool:

```bash
distribute init
```

#### `build`

Build the application:

```bash
distribute build [arguments]
```

**Options:**

- `-p, --[no-]publish`  
  Automatically distribute Android builds.

- `--[no]-android`  
  Build Android.  
  *(enabled by default)*

- `--[no]-ios`  
  Build iOS.  
  *(enabled by default)*

- `--android_args`  
  Specify additional arguments for Android builds.  
  *(defaults to `""`)*

- `--ios_args`  
  Specify additional arguments for iOS builds.  
  *(defaults to `""`)*

- `--custom_args=<macos:macos,windows:windows,ios:ipa,android_apk:apk>`  
  Provide custom arguments in the format `key:args,key:args`. These will be executed as `flutter build <args>`.  
  *(defaults to `""`)*

#### `publish`

Distribute the application:

```bash
distribute publish [arguments]
```

**Options:**

- `--[no-]android`  
  Build and distribute Android.  
  *(enabled by default)*

- `--[no-]ios`  
  Build and distribute iOS.  
  *(enabled by default)*

- `--[no-]firebase`  
  Use Firebase for distribution.

- `--[no-]fastlane`  
  Use Fastlane for distribution.  
  *(enabled by default)*

## License

This project is licensed under the MIT License. For more details, refer to the LICENSE file.
