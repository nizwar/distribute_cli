import 'dart:io';

class Files {
  static final File androidChangeLogs = File("distribution/android/output/changelogs.log");
  static final File fastlaneJson = File("distribution/fastlane.json");
  static final Directory androidDistributionDir = Directory("distribution/android");
  static final Directory androidOutputAppbundles = Directory("build/app/outputs/bundle");

  static Directory get androidDistributionOutputDir => Directory("${androidDistributionDir.path}/output");
  static Directory get androidDistributionMetadataDir => Directory("${androidDistributionDir.path}/metadata");

  static final Directory iosDistributionDir = Directory("distribution/ios");
  static final Directory iosOutputIPA = Directory("build/ios/ipa");

  static Directory get iosDistributionOutputDir => Directory("${iosDistributionDir.path}/output");
  static Directory get iosDistributionMetadataDir => Directory("${iosDistributionDir.path}/metadata");
}
