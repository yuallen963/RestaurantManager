#!/usr/bin/env ruby

fastfile = File.read(File.expand_path("../fastlane/Fastfile", __dir__))
workflow = File.read(File.expand_path("../../../.github/workflows/ios-testflight.yml", __dir__))

abort "Fastlane must require the protected shared-test token" unless fastfile.include?('ENV.fetch("SHARED_TEST_CLIENT_TOKEN")')
abort "Native defines must use a temporary file rather than a logged command-line value" unless fastfile.include?("--dart-define-from-file=")
abort "Shared-test token must never be interpolated directly into the build command" if fastfile.include?("--dart-define=SHARED_TEST_CLIENT_TOKEN")
abort "Workflow must map the protected environment secret" unless workflow.include?('SHARED_TEST_CLIENT_TOKEN: ${{ secrets.SHARED_TEST_CLIENT_TOKEN }}')
abort "Workflow must remain protected by the TestFlight environment" unless workflow.include?("environment: testflight-production")
abort "Workflow must retain tag-only prerelease support" unless workflow.match?(/tags:\s*\n\s*-\s*"ios-v\*"/)

puts "Shared-test token release configuration OK"
