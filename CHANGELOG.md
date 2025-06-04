
## 2.3.0+1

### 🚀 New Features
* **Windows CLI Support**: Full Windows PowerShell compatibility with native command execution
* **Comprehensive Documentation Overhaul**: Complete rewrite of all Dart file documentation
  - Added detailed library-level documentation for all modules
  - Enhanced class documentation with comprehensive capability descriptions
  - Improved method documentation with parameter details, return values, and workflow explanations
  - Added extensive property documentation with usage patterns and examples
  - Implemented consistent formatting using backticks instead of brackets
  - Added practical usage examples throughout the codebase

### 📚 Documentation Enhancements
* **Build System Documentation**: 
  - Complete Android build documentation with APK/AAB generation workflows
  - Comprehensive iOS build documentation with IPA generation and code signing
  - Custom build system documentation with flexible binary type support
* **Publisher Documentation**:
  - Detailed Firebase App Distribution integration documentation
  - Comprehensive Fastlane automation documentation with CI/CD workflows
  - Complete GitHub Releases documentation with version management
  - Extensive App Store Connect (Xcrun) documentation with store integration
* **Utility Documentation**:
  - Cross-platform file compression utility documentation
  - Configuration parsing and validation documentation
  - Variable substitution system documentation

### 🔧 Code Quality Improvements
* **Enhanced Logger**: More detailed information and structured output for better debugging
* **Performance Optimizations**: Improved code efficiency and functionality across all modules
* **Error Handling**: Better error messages and troubleshooting guidance
* **Type Safety**: Enhanced parameter validation and type checking

### 📖 New Documentation Files
* **Comprehensive README**: Created detailed `new_readme.md` with complete feature overview
* **Architecture Documentation**: Added project structure and component explanations
* **Usage Examples**: Extensive CLI command examples and configuration patterns
* **Best Practices**: Guidelines for multi-environment setups and CI/CD integration

### 🛠️ Development Experience
* **IntelliSense Support**: Improved code completion with detailed documentation
* **IDE Integration**: Better hover information and parameter hints
* **Code Navigation**: Enhanced cross-references between related components
* **Maintainability**: Consistent documentation patterns across all files

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
