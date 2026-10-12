#!/usr/bin/env ruby

fastfile = File.expand_path("../fastlane/Fastfile", __dir__)
source = File.read(fastfile)

upload_block = source[/upload_to_testflight\((.*?)\n    \)/m]
abort "upload_to_testflight configuration not found" unless upload_block
abort "TestFlight upload must explicitly disable external distribution" unless upload_block.match?(/distribute_external:\s*false/)
abort "Internal-only upload must not pass a groups parameter" if upload_block.match?(/^\s*groups:/)
abort "Fastlane lane must not submit builds for external review" if source.match?(/submit_for_review:\s*true/)

puts "Internal-only TestFlight configuration OK"
