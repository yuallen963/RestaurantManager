#!/usr/bin/env ruby

require "open3"

ipa_directory = File.expand_path(ARGV.fetch(0))
expected_bundle_id = ARGV.fetch(1)

def fail_check(message)
  warn "IPA discovery failed: #{message}"
  exit 1
end

ipa_files = Dir.glob(File.join(ipa_directory, "*.ipa")).select { |path| File.file?(path) }
fail_check("no IPA files found in #{ipa_directory}") if ipa_files.empty?
fail_check("expected exactly one IPA, found #{ipa_files.length}: #{ipa_files.map { |path| File.basename(path) }.join(', ')}") unless ipa_files.length == 1

ipa_path = ipa_files.first
entries, unzip_status = Open3.capture2("unzip", "-Z1", ipa_path)
fail_check("could not inspect #{File.basename(ipa_path)}") unless unzip_status.success?

info_plists = entries.lines.map(&:strip).grep(%r{\APayload/[^/]+\.app/Info\.plist\z})
fail_check("#{File.basename(ipa_path)} has no application Info.plist") unless info_plists.length == 1

info_data, unzip_status = Open3.capture2("unzip", "-p", ipa_path, info_plists.first)
fail_check("could not read the application Info.plist") unless unzip_status.success?

bundle_id, plutil_status = Open3.capture2("plutil", "-extract", "CFBundleIdentifier", "raw", "-o", "-", "-", stdin_data: info_data)
fail_check("application bundle identifier could not be read") unless plutil_status.success?
bundle_id = bundle_id.strip
fail_check("bundle identifier #{bundle_id.inspect} does not match #{expected_bundle_id.inspect}") unless bundle_id == expected_bundle_id

puts File.expand_path(ipa_path)
