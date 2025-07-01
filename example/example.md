
# Example Commands

By default, these commands use the `.distribution.env` file for configuration. You may need to modify this file to try the example commands below.

## Build and Distribute Android App only

```bash
distribute build --no-ios --android --publish --android_binary=aab
```

## Distribute iOS App only

```bash
distribute publish --ios --no-android
```

## Build with Custom Arguments

```bash
distribute build --custom_args="macos:macos,windows:windows"
```
