#!/usr/bin/env bash
set -euo pipefail

profile_path="${1:?Provisioning profile path is required}"
team_id="${2:?Apple team ID is required}"
bundle_id="${3:?Bundle identifier is required}"
entitlements_path="${4:?App entitlements path is required}"

fail() {
  echo "iOS signing preflight failed: $1" >&2
  exit 1
}

[[ -f "$profile_path" ]] || fail "provisioning profile was not installed"
[[ -f "$entitlements_path" ]] || fail "app entitlements file is missing"

profile_plist="$(mktemp)"
certificate_plist="$(mktemp)"
trap 'rm -f "$profile_plist" "$certificate_plist"' EXIT

security cms -D -i "$profile_path" -o "$profile_plist" \
  || fail "provisioning profile could not be decoded"

plistbuddy=/usr/libexec/PlistBuddy
profile_uuid="$($plistbuddy -c 'Print :UUID' "$profile_plist")"
profile_name="$($plistbuddy -c 'Print :Name' "$profile_plist")"
profile_team="$($plistbuddy -c 'Print :TeamIdentifier:0' "$profile_plist")"
application_identifier="$($plistbuddy -c 'Print :Entitlements:application-identifier' "$profile_plist")"
expiration_date="$($plistbuddy -c 'Print :ExpirationDate' "$profile_plist")"
get_task_allow="$($plistbuddy -c 'Print :Entitlements:get-task-allow' "$profile_plist" 2>/dev/null || echo false)"

[[ "$profile_team" == "$team_id" ]] || fail "provisioning profile belongs to a different Apple team"
[[ "$application_identifier" == "$team_id.$bundle_id" ]] \
  || fail "provisioning profile does not match the FundWell bundle identifier"
[[ "$get_task_allow" != "true" ]] || fail "a development provisioning profile was installed instead of an App Store profile"

ruby -rtime -e 'exit(Time.parse(ARGV[0]) > Time.now ? 0 : 1)' "$expiration_date" \
  || fail "provisioning profile is expired"

app_domains="$($plistbuddy -c 'Print :com.apple.developer.associated-domains' "$entitlements_path" 2>/dev/null || true)"
profile_domains="$($plistbuddy -c 'Print :Entitlements:com.apple.developer.associated-domains' "$profile_plist" 2>/dev/null || true)"
[[ -n "$app_domains" ]] || fail "FundWell Associated Domains entitlement is missing"
[[ -n "$profile_domains" ]] || fail "provisioning profile does not permit Associated Domains"

identity_line="$(security find-identity -v -p codesigning | grep 'Apple Distribution' | grep "($team_id)" | head -n 1 || true)"
[[ -n "$identity_line" ]] || fail "valid Apple Distribution identity with private key was not found"
identity_fingerprint="$(awk '{print $2}' <<<"$identity_line")"

plutil -extract DeveloperCertificates xml1 -o "$certificate_plist" "$profile_plist" \
  || fail "provisioning profile certificates could not be read"
profile_fingerprints="$(ruby -rbase64 -ropenssl -rrexml/document -e '
  document = REXML::Document.new(File.read(ARGV[0]))
  REXML::XPath.each(document, "//data") do |node|
    certificate = OpenSSL::X509::Certificate.new(Base64.decode64(node.texts.join))
    puts OpenSSL::Digest::SHA1.hexdigest(certificate.to_der).upcase
  end
' "$certificate_plist")"
grep -qx "$identity_fingerprint" <<<"$profile_fingerprints" \
  || fail "installed Apple Distribution certificate is not included in the provisioning profile"

[[ "$profile_name" != *$'\n'* && "$profile_uuid" != *$'\n'* ]] \
  || fail "provisioning profile metadata is malformed"

printf 'IOS_PROVISIONING_PROFILE_NAME=%s\n' "$profile_name"
printf 'IOS_PROVISIONING_PROFILE_UUID=%s\n' "$profile_uuid"
