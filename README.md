# Flutter Distribute CLI v2.3.0 - Comprehensive Documentation

A powerful command-line tool for automating Flutter application building and distribution workflows across multiple platforms and deployment channels.

## 🎯 Overview

Flutter Distribute CLI provides a unified, configuration-driven approach to building and distributing Flutter applications for Android and iOS platforms. With comprehensive support for multiple distribution channels, automated build processes, and flexible deployment workflows, it streamlines the entire app distribution pipeline from development to production.

## ✨ Key Features

### 🏗️ Multi-Platform Build System
- **Android Builds**: APK and AAB generation with Gradle integration
- **iOS Builds**: IPA generation with Xcode and code signing automation  
- **Custom Builds**: Flexible binary type specification for specialized workflows
- **Cross-Platform Support**: Unified build configuration across platforms

### 📦 Distribution Channels
- **Firebase App Distribution**: Beta testing and internal distribution
- **Fastlane Integration**: Automated store deployments and CI/CD workflows
- **GitHub Releases**: Version management and artifact distribution
- **App Store Connect**: Direct iOS publishing with Xcrun integration
- **Google Play Store**: Android publishing with automated metadata

### ⚙️ Advanced Configuration
- **YAML-based Configuration**: Single `distribution.yaml` file for all settings
- **Variable Substitution**: Environment and custom variable support
- **Build Modes**: Debug, profile, and release configurations
- **Flavor Support**: Product flavors and build variants
- **Custom Arguments**: User-defined build parameters and flags

## 🚀 Quick Start

### Installation
```bash
dart pub global activate distribute_cli
```

### Project Initialization
```bash
# Initialize distribution configuration
distribute init

# Create initial YAML configuration
distribute create
```

### Basic Usage
```bash
# Build Android APK
distribute build android --binary-type apk --build-mode release

# Build iOS IPA (macOS only)
distribute build ios --export-method app-store

# Custom build with specific configuration
distribute build custom --binary-type aab --flavor production

# Publish to Firebase App Distribution
distribute publish firebase --app-id your-app-id --token your-token

# Publish to GitHub Releases
distribute publish github --repo owner/repo --tag v1.0.0
```

## 📁 Project Structure

### Core Components

```
lib/
├── app_builder/              # Build system components
│   ├── build_arguments.dart  # Base build configuration
│   ├── android/              # Android-specific build tools
│   │   ├── arguments.dart    # Android build parameters
│   │   └── command.dart      # Android build command
│   ├── ios/                  # iOS-specific build tools
│   │   ├── arguments.dart    # iOS build parameters
│   │   └── command.dart      # iOS build command
│   └── custom/               # Custom build workflows
│       ├── arguments.dart    # Custom build parameters
│       └── command.dart      # Custom build command
├── app_publisher/            # Distribution system components
│   ├── publisher_arguments.dart # Base publisher configuration
│   ├── fastlane/             # Fastlane automation
│   │   ├── arguments.dart    # Fastlane parameters
│   │   └── command.dart      # Fastlane command
│   ├── firebase/             # Firebase App Distribution
│   │   ├── arguments.dart    # Firebase parameters
│   │   └── command.dart      # Firebase command
│   ├── github/               # GitHub Releases
│   │   ├── arguments.dart    # GitHub parameters
│   │   └── command.dart      # GitHub command
│   └── xcrun/                # App Store Connect
│       ├── arguments.dart    # Xcrun parameters
│       └── command.dart      # Xcrun command
└── parsers/                  # Utility and parsing components
    ├── compress_files.dart   # File compression utilities
    ├── config_parser.dart    # Configuration parsing
    ├── variables.dart        # Variable substitution
    └── ...                   # Additional utilities
```

## 🔧 Build System

### Android Build Capabilities

The Android build system provides comprehensive APK and AAB generation with full Gradle integration:

#### Features
- **Multiple Output Formats**: APK for direct installation, AAB for Play Store distribution
- **Build Mode Support**: Debug builds for development, Profile for performance testing, Release for production
- **Flavor Management**: Product flavors for different app variants (free/paid, development/staging/production)
- **Automated Signing**: Keystore management and signing configuration
- **Gradle Integration**: Direct integration with Android build tools and dependency management

#### Usage Examples
```bash
# Debug APK for development
distribute build android --binary-type apk --build-mode debug --flavor development

# Release AAB for Play Store
distribute build android --binary-type aab --build-mode release --flavor production

# Custom build with specific parameters
distribute build android --binary-type apk --flavor staging --dart-defines "API_URL=staging.api.com"
```

### iOS Build Capabilities

The iOS build system handles IPA generation with comprehensive Xcode integration and code signing:

#### Features
- **IPA Generation**: Distribution-ready iOS application packages
- **Code Signing**: Automated certificate and provisioning profile management
- **Export Methods**: App Store, Ad Hoc, Enterprise, and Development distributions
- **Xcode Integration**: Seamless workspace and project configuration
- **macOS Requirement**: Platform validation ensures proper development environment

#### Usage Examples
```bash
# App Store release build
distribute build ios --export-method app-store --build-mode release

# Ad Hoc distribution for testing
distribute build ios --export-method ad-hoc --provisioning-profile-name "AdHoc Profile"

# Development build for internal testing
distribute build ios --export-method development --team-id "TEAM123456"
```

### Custom Build System

The custom build system provides maximum flexibility for specialized requirements:

#### Features
- **Universal Binary Support**: Any output format specification (APK, AAB, IPA, Desktop apps, etc.)
- **Custom Arguments**: User-defined build parameters and flags
- **Multi-Platform Targets**: Android, iOS, Desktop, and Web builds
- **Integration Support**: Compatible with existing build systems and external tools

#### Usage Examples
```bash
# Custom Android build with specialized parameters
distribute build custom --binary-type apk --arguments "--verbose --analyze-size"

# Desktop application build
distribute build custom --binary-type macos --build-mode release

# Web application with custom optimization
distribute build custom --binary-type web --arguments "--web-renderer html"
```

## 📤 Distribution System

### Firebase App Distribution

Comprehensive beta testing and internal distribution platform:

#### Capabilities
- **Beta Distribution**: Internal and external tester management
- **Release Notes**: Automated changelog and update notifications  
- **Tester Groups**: Organized distribution to specific user groups
- **Analytics Integration**: Download and usage tracking
- **Cross-Platform**: Support for both Android and iOS distributions

#### Configuration Example
```yaml
firebase:
  app_id: "1:123456789:android:abcdef123456"
  token: "${{FIREBASE_TOKEN}}"
  groups: ["internal-testers", "beta-users"]
  release_notes: "Bug fixes and performance improvements"
```

### Fastlane Integration

Professional deployment automation for production releases:

#### Capabilities
- **Store Publishing**: Direct Google Play Store and App Store Connect uploads
- **Metadata Management**: Automated store listing updates and screenshots
- **Testing Integration**: Pre-deployment testing and validation
- **Certificate Management**: Automated signing and provisioning
- **Notification Systems**: Real-time deployment status updates

#### Configuration Example
```yaml
fastlane:
  lane: "beta"
  platform: "android"
  metadata_path: "./fastlane/metadata"
  skip_upload_metadata: false
  skip_upload_screenshots: false
```

### GitHub Releases

Version management and artifact distribution:

#### Capabilities
- **Release Management**: Automated tag creation and release publishing
- **Asset Uploads**: Binary distribution with download tracking
- **Changelog Generation**: Automated release notes from commit history
- **Version Control**: Git tag integration and semantic versioning
- **API Integration**: Full GitHub API utilization for release operations

#### Configuration Example
```yaml
github:
  repository: "owner/repository"
  tag: "v${{BUILD_NAME}}"
  token: "${{GITHUB_TOKEN}}"
  draft: false
  prerelease: false
```

### App Store Connect (Xcrun)

Direct iOS publishing with comprehensive store integration:

#### Capabilities
- **Store Uploads**: Direct IPA submission to App Store Connect
- **Metadata Management**: App information and store listing updates
- **TestFlight Integration**: Beta distribution through Apple's platform
- **Review Management**: Automated submission and review tracking
- **Platform Validation**: macOS-specific toolchain requirements

#### Configuration Example
```yaml
xcrun:
  username: "${{APPLE_ID}}"
  password: "${{APPLE_APP_SPECIFIC_PASSWORD}}"
  ipa_path: "./build/ios/ipa/app.ipa"
  skip_waiting_for_build_processing: false
```

## 🛠️ Configuration System

### YAML Configuration Structure

The `distribution.yaml` file provides centralized configuration for all build and distribution operations:

```yaml
name: "My Flutter App"
description: "Production-ready mobile application"

# Global variables for reuse across tasks
variables:
  APP_NAME: "MyApp"
  ANDROID_PACKAGE: "com.company.myapp" 
  IOS_BUNDLE_ID: "com.company.myapp"
  BUILD_NUMBER: "${{CI_BUILD_NUMBER}}"
  
# Build task definitions
tasks:
  build_android_release:
    builder: "android"
    arguments:
      binary-type: "aab"
      build-mode: "release"
      flavor: "production"
      
  build_ios_release:
    builder: "ios"
    arguments:
      export-method: "app-store"
      build-mode: "release"
      
# Distribution job definitions      
jobs:
  deploy_production:
    tasks: ["build_android_release", "build_ios_release"]
    publishers:
      - fastlane:
          lane: "release"
          platform: "android"
      - xcrun:
          username: "${{APPLE_ID}}"
          password: "${{APPLE_APP_SPECIFIC_PASSWORD}}"
```

### Variable Substitution

The system supports comprehensive variable substitution for flexible configuration:

#### Variable Types
- **Environment Variables**: `${{ENV_VAR_NAME}}`
- **Configuration Variables**: `${{CONFIG_VAR}}`
- **System Variables**: `${{SYSTEM_INFO}}`
- **Build Context**: `${{BUILD_NUMBER}}`, `${{BUILD_NAME}}`

#### Usage Examples
```yaml
variables:
  API_URL: "${{ENVIRONMENT}}.api.company.com"
  BUILD_VERSION: "${{BUILD_NAME}}+${{BUILD_NUMBER}}"
  SIGNING_KEY: "${{HOME}}/.android/release.keystore"
```

## 🔍 Utility Components

### File Compression System

Cross-platform file compression with native tool integration:

#### Features
- **Platform Detection**: Automatic tool selection (PowerShell on Windows, zip on Unix)
- **Tool Validation**: Pre-compression availability checking
- **Batch Processing**: Directory-level compression operations
- **Error Handling**: Comprehensive failure detection and reporting

### Configuration Parsing

Robust YAML configuration processing with validation:

#### Features
- **Schema Validation**: Configuration structure verification
- **Type Safety**: Parameter type checking and conversion
- **Error Reporting**: Detailed validation error messages
- **Default Values**: Automatic fallback configuration

### Build Information Processing

Comprehensive build metadata management:

#### Features
- **Version Management**: Semantic versioning support
- **Build Context**: Environment and system information collection
- **Metadata Generation**: Automated build information compilation
- **Cross-Platform**: Unified information gathering across platforms

## 🎨 Command-Line Interface

### Build Commands

```bash
# Android builds
distribute build android [options]
  --binary-type        Output format (apk, aab)
  --build-mode         Build optimization (debug, profile, release)
  --flavor            Product flavor specification
  --signing-key       Keystore file path
  --key-alias         Signing key alias
  
# iOS builds  
distribute build ios [options]
  --export-method     Distribution type (app-store, ad-hoc, enterprise, development)
  --provisioning-profile  Provisioning profile name or path
  --team-id           Developer team identifier
  --certificate       Code signing certificate
  
# Custom builds
distribute build custom [options]
  --binary-type       Any output format specification
  --arguments         Custom build parameters
  --target           Entry point file specification
  --output           Custom output directory
```

### Publishing Commands

```bash
# Firebase App Distribution
distribute publish firebase [options]
  --app-id           Firebase app identifier
  --token            Authentication token
  --groups           Tester group names
  --release-notes    Update description
  
# GitHub Releases
distribute publish github [options]
  --repository       Repository in owner/repo format
  --tag              Release tag name
  --token            GitHub API token
  --draft            Create as draft release
  
# Fastlane automation
distribute publish fastlane [options]
  --lane             Fastlane lane to execute
  --platform         Target platform (android, ios)
  --env              Environment variables
  
# App Store Connect
distribute publish xcrun [options]
  --username         Apple ID username
  --password         App-specific password
  --ipa-path         IPA file location
  --skip-waiting     Skip build processing wait
```

## 🔒 Security and Authentication

### Credential Management

The CLI supports multiple authentication methods for secure distribution:

#### Environment Variables
```bash
export FIREBASE_TOKEN="your-firebase-token"
export GITHUB_TOKEN="your-github-token"  
export APPLE_ID="your-apple-id"
export APPLE_APP_SPECIFIC_PASSWORD="your-app-password"
```

#### Configuration File Security
- **Token Substitution**: Credentials referenced via variables
- **File Permissions**: Secure configuration file handling
- **Key Management**: External keystore and certificate management

### Code Signing

Comprehensive signing support for production distributions:

#### Android Signing
- **Keystore Management**: Automated keystore configuration
- **Key Alias**: Signing key specification
- **Password Handling**: Secure credential management

#### iOS Signing  
- **Certificate Management**: Automated certificate selection
- **Provisioning Profiles**: Profile matching and validation
- **Team Management**: Developer team identifier handling

## 📊 Logging and Monitoring

### Comprehensive Logging

Detailed logging system for build and distribution tracking:

#### Log Levels
- **Info**: General operation information
- **Warning**: Non-critical issues and recommendations
- **Error**: Critical failures and error conditions
- **Debug**: Detailed diagnostic information

#### Log Output
- **Console Output**: Real-time operation feedback
- **File Logging**: Persistent log file generation (`distribution.log`)
- **Structured Data**: JSON-formatted log entries for automation

### Progress Tracking

Real-time operation monitoring:

#### Build Progress
- **Phase Tracking**: Individual build step monitoring
- **Time Estimation**: Completion time predictions
- **Resource Usage**: CPU and memory utilization

#### Distribution Progress
- **Upload Tracking**: File transfer progress monitoring
- **API Operations**: Remote service interaction logging
- **Success Metrics**: Completion statistics and performance data

## 🤝 Integration Patterns

### CI/CD Integration

Seamless integration with continuous integration systems:

#### GitHub Actions
```yaml
- name: Build and Distribute
  run: |
    distribute run production_deploy
  env:
    FIREBASE_TOKEN: ${{ secrets.FIREBASE_TOKEN }}
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

#### GitLab CI
```yaml
distribute_app:
  script:
    - distribute run production_deploy
  variables:
    FIREBASE_TOKEN: $FIREBASE_TOKEN
    APPLE_ID: $APPLE_ID
```

### Custom Workflows

Flexible workflow definitions for complex deployment scenarios:

#### Multi-Environment Deployment
```yaml
jobs:
  staging_deployment:
    tasks: ["build_staging"]
    publishers: ["firebase"]
    
  production_deployment:
    tasks: ["build_production"]
    publishers: ["fastlane", "github"]
    depends_on: ["staging_deployment"]
```

## 🚨 Error Handling and Troubleshooting

### Common Issues and Solutions

#### Build Failures
- **Android SDK Issues**: SDK path and version validation
- **iOS Certificate Problems**: Signing configuration troubleshooting
- **Dependency Conflicts**: Package resolution guidance

#### Distribution Failures
- **Authentication Errors**: Token and credential validation
- **Network Issues**: Connectivity and timeout handling
- **API Limitations**: Rate limiting and quota management

### Diagnostic Tools

Built-in troubleshooting capabilities:

#### System Validation
```bash
# Check system requirements
distribute doctor

# Validate configuration
distribute validate

# Test authentication
distribute auth test
```

## 📈 Performance Optimization

### Build Performance

Optimization strategies for faster build times:

#### Caching
- **Build Cache**: Gradle and Xcode build cache utilization
- **Dependency Cache**: Package and library caching
- **Artifact Cache**: Build output reuse

#### Parallel Processing
- **Multi-Platform Builds**: Concurrent Android and iOS builds
- **Task Parallelization**: Independent task execution
- **Resource Management**: Optimal CPU and memory utilization

### Distribution Performance

Efficient distribution workflows:

#### Upload Optimization
- **Compression**: Automatic file compression before upload
- **Delta Updates**: Incremental update distribution
- **CDN Integration**: Content delivery network utilization

## 🔄 Version Management

### Semantic Versioning

Comprehensive version control integration:

#### Version Schemes
- **Semantic Versioning**: MAJOR.MINOR.PATCH format
- **Build Numbers**: Incremental build identification
- **Git Integration**: Tag-based version management

#### Automated Versioning
```yaml
variables:
  BUILD_NAME: "${{GIT_TAG}}"
  BUILD_NUMBER: "${{GIT_COMMIT_COUNT}}"
  VERSION_CODE: "${{TIMESTAMP}}"
```

## 🎯 Best Practices

### Configuration Management
- **Environment Separation**: Distinct configurations for dev/staging/production
- **Secret Management**: Secure credential handling and rotation
- **Version Control**: Configuration file versioning and change tracking

### Build Management
- **Clean Builds**: Regular clean build execution for consistency
- **Artifact Management**: Organized build output storage and archival
- **Testing Integration**: Automated testing before distribution

### Distribution Management
- **Gradual Rollouts**: Phased release deployment strategies
- **Rollback Procedures**: Quick rollback mechanisms for failed releases
- **Monitoring**: Post-deployment monitoring and analytics

## 📚 Advanced Configuration Examples

### Complex Multi-Environment Setup

```yaml
name: "Enterprise Mobile App"
description: "Multi-environment Flutter application with comprehensive CI/CD"

variables:
  # Environment-specific variables
  DEV_API_URL: "dev-api.company.com"
  STAGING_API_URL: "staging-api.company.com"
  PROD_API_URL: "api.company.com"
  
  # Build configuration
  APP_NAME: "Enterprise App"
  ANDROID_PACKAGE: "com.company.enterprise"
  IOS_BUNDLE_ID: "com.company.enterprise"
  
  # Version management
  VERSION_NAME: "${{GIT_TAG}}"
  VERSION_CODE: "${{BUILD_NUMBER}}"

# Development environment tasks
tasks:
  build_android_dev:
    builder: "android"
    arguments:
      binary-type: "apk"
      build-mode: "debug"
      flavor: "development"
      dart-defines: "API_URL=${{DEV_API_URL}},ENVIRONMENT=development"
      
  build_ios_dev:
    builder: "ios"
    arguments:
      export-method: "development"
      build-mode: "debug"
      provisioning-profile-name: "Development Profile"

# Staging environment tasks      
  build_android_staging:
    builder: "android"
    arguments:
      binary-type: "aab"
      build-mode: "release"
      flavor: "staging"
      dart-defines: "API_URL=${{STAGING_API_URL}},ENVIRONMENT=staging"
      signing-key: "${{ANDROID_KEYSTORE_PATH}}"
      key-alias: "staging"
      
  build_ios_staging:
    builder: "ios"
    arguments:
      export-method: "ad-hoc"
      build-mode: "release"
      provisioning-profile-name: "Staging AdHoc Profile"

# Production environment tasks
  build_android_production:
    builder: "android"
    arguments:
      binary-type: "aab"
      build-mode: "release"
      flavor: "production"
      dart-defines: "API_URL=${{PROD_API_URL}},ENVIRONMENT=production"
      signing-key: "${{ANDROID_KEYSTORE_PATH}}"
      key-alias: "production"
      
  build_ios_production:
    builder: "ios"
    arguments:
      export-method: "app-store"
      build-mode: "release"
      provisioning-profile-name: "App Store Profile"

# Distribution jobs
jobs:
  development_deploy:
    description: "Deploy to development environment for internal testing"
    tasks: ["build_android_dev", "build_ios_dev"]
    publishers:
      - firebase:
          app-id: "${{FIREBASE_DEV_APP_ID}}"
          token: "${{FIREBASE_TOKEN}}"
          groups: ["internal-developers"]
          release-notes: "Development build - ${{GIT_COMMIT_MESSAGE}}"
          
  staging_deploy:
    description: "Deploy to staging environment for QA testing"
    tasks: ["build_android_staging", "build_ios_staging"]
    publishers:
      - firebase:
          app-id: "${{FIREBASE_STAGING_APP_ID}}"
          token: "${{FIREBASE_TOKEN}}"
          groups: ["qa-testers", "stakeholders"]
          release-notes: "Staging build - ${{VERSION_NAME}}"
      - github:
          repository: "company/enterprise-app"
          tag: "staging-${{VERSION_NAME}}"
          token: "${{GITHUB_TOKEN}}"
          prerelease: true
          
  production_deploy:
    description: "Deploy to production stores"
    tasks: ["build_android_production", "build_ios_production"]
    publishers:
      - fastlane:
          lane: "release"
          platform: "android"
          metadata-path: "./fastlane/metadata/android"
      - xcrun:
          username: "${{APPLE_ID}}"
          password: "${{APPLE_APP_SPECIFIC_PASSWORD}}"
          ipa-path: "./build/ios/ipa/Runner.ipa"
          skip-waiting-for-build-processing: false
      - github:
          repository: "company/enterprise-app"
          tag: "v${{VERSION_NAME}}"
          token: "${{GITHUB_TOKEN}}"
          draft: false
          prerelease: false
```

## 🌟 Conclusion

Flutter Distribute CLI provides a comprehensive, professional-grade solution for automating Flutter application building and distribution. With its flexible configuration system, multi-platform support, and extensive integration capabilities, it streamlines the entire app distribution pipeline from development to production.

The tool's architecture supports both simple single-platform deployments and complex multi-environment CI/CD workflows, making it suitable for individual developers, small teams, and large enterprise organizations. Its extensive documentation, error handling, and monitoring capabilities ensure reliable and maintainable distribution processes.

Whether you're distributing beta builds to testers, deploying to app stores, or managing complex release workflows, Flutter Distribute CLI provides the tools and flexibility needed to automate and optimize your app distribution strategy.

---

## 📞 Support and Resources

- **GitHub Repository**: [nizwar/distribute_cli](https://github.com/nizwar/distribute_cli)
- **Dart Package**: [distribute_cli on pub.dev](https://pub.dev/packages/distribute_cli)
- **Documentation**: Comprehensive inline documentation in all source files
- **Issues**: GitHub Issues for bug reports and feature requests
- **Community**: Discussions and community support through GitHub

---

*This documentation reflects the comprehensive enhancement of all Dart files in the Flutter Distribute CLI project, providing detailed explanations, usage examples, and best practices for effective app distribution automation.*
