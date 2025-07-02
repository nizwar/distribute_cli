
# Example Commands

By default, these commands use the `distribution.yaml` file for configuration.

## Available Commands
```bash
Run commands to distribute your app packages.

Usage: distribute <command> [arguments]

Global options:
-h, --help            Print this usage information.
-v, --[no-]verbose    Enable verbose output.
    --config          Path to the configuration file.
                      (defaults to "distribution.yaml")

Available commands:
  build     Build the application using the selected platform or custom configuration.
  create    Create a new task or job.
  init      Initialize the project with the necessary configuration files and directories.
  publish   Publish the app to the specified platform.
  run       Command to run the application using the selected platform or custom configuration. 

```

### Build the application using CLI
```bash
Build the application using the selected platform or custom configuration.

Usage: distribute build <subcommand> [arguments]
-h, --help    Print this usage information.

Available subcommands:
  android   Build an Android application using the specified configuration and options provided in the arguments. 
  custom    Build a custom application by selecting specific configurations and options tailored to your requirements. 
  ios       Build an iOS application using the specified configuration and parameters provided in the command-line arguments. 

Run "distribute help" to see global options.
```

### Create tasks or jobs using CLI

```bash
Create a new task or job.

Usage: distribute create <subcommand> [arguments]
-h, --help    Print this usage information.

Available subcommands:
  job    Create a new job.
  task   Create a new task or job.

Run "distribute create --help" to see global options.
``` 

### Initialize project arguments

```bash
Initialize the project with the necessary configuration files and directories.

Usage: distribute init [arguments]
-a, --android-package-name      Package name for the application.
-i, --ios-package-name          Bundle identifier for the iOS application.
-s, --[no-]skip-tools           Skip tool validation.
-g, --google-service-account    Google service for fastlane, if it validated it will be copied to the fastlane directory.

Run "distribute init --help" to see global options.
```

### Publish with CLI
```bash
Publish the app to the specified platform.

Usage: distribute publish <subcommand> [arguments]
-h, --help    Print this usage information.

Available subcommands:
  fastlane   Publish an Android application using Fastlane.
  firebase   Publish an Android application to Firebase App Distribution.
  github     Publish app to GitHub.
  xcrun      Publish an iOS application using the XCrun tool.

Run "distribute help" to see global options.
```

### Run distribute process

```bash
Command to run the application using the selected platform or custom configuration. 

Usage: distribute run [arguments]
-c, --config       Path to the configuration file.
                   (defaults to "distribution.yaml")
-o, --operation    Key of the operation to run, use OperationKey.JobKey to run spesifict job.
                   (defaults to "")

Run "distribute run --help" to see global options.
```
