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
