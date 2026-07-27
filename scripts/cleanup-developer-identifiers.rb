#!/usr/bin/env ruby
# List or delete stale Apple Developer Portal App IDs via fastlane spaceship.
#
# Usage:
#   bundle exec ruby scripts/cleanup-developer-identifiers.rb list
#   bundle exec ruby scripts/cleanup-developer-identifiers.rb plan
#   bundle exec ruby scripts/cleanup-developer-identifiers.rb delete --confirm
#
# Requires Apple ID login (2FA) — uses Spaceship Developer Portal, not API key.

require "spaceship"

KEEP = [
  "com.calarmapp.calarm",
  "com.calarmapp.calarm.CalarmWidgetExtension",
  "*" # wildcard dev profile
].freeze

# Old Xcode auto-IDs and superseded CALarm bundle — safe to remove if delete succeeds.
CANDIDATE_DELETE = [
  "pchandak.calarm",
  "pchandak.CalendarTags",
  "pchandak.caltags",
  "com.pchandak.calendar-tags-app",
  "com.pchandak.liveactivitycountdown",
  "test.cal-tag-app",
  "test.cal-tag-appUITests",
  "com.calendar-tags",
  "com.parthchandak.caltagapp"
].freeze

# Review manually before deleting — may be another shipped or in-progress app.
REVIEW_BEFORE_DELETE = [
  "cal.tag.app",
  "cal.tag.app.OneSignalNotificationServiceExtension"
].freeze

def usage!
  warn <<~HELP
    Usage:
      bundle exec ruby scripts/cleanup-developer-identifiers.rb list
      bundle exec ruby scripts/cleanup-developer-identifiers.rb plan
      bundle exec ruby scripts/cleanup-developer-identifiers.rb delete --confirm

    list   — all App IDs on your team
    plan   — what we'd try to delete vs keep
    delete — remove CANDIDATE_DELETE IDs (skips failures)
  HELP
  exit 1
end

command = ARGV[0] || "list"
usage! unless %w[list plan delete].include?(command)
abort "Pass --confirm to delete" if command == "delete" && !ARGV.include?("--confirm")

puts "Logging in to Apple Developer Portal (Apple ID + 2FA)..."
Spaceship.login
Spaceship.select_team

apps = Spaceship.app.all
by_bundle = apps.index_by { |a| a.bundle_id.downcase }

puts "\n=== All App IDs (#{apps.size}) ==="
apps.sort_by(&:bundle_id).each do |app|
  tag = if KEEP.include?(app.bundle_id)
          "KEEP"
        elsif CANDIDATE_DELETE.include?(app.bundle_id)
          "DELETE?"
        elsif REVIEW_BEFORE_DELETE.include?(app.bundle_id)
          "REVIEW"
        else
          "—"
        end
  puts format("  [%<tag>-6s] %<bundle>s  (%<name>s)", tag: tag, bundle: app.bundle_id, name: app.name)
end

if command == "list"
  puts "\nDone. Run `plan` to see cleanup intent, or delete old CALarm/Xcode IDs with `delete --confirm`."
  exit 0
end

to_delete = CANDIDATE_DELETE.select { |bid| by_bundle.key?(bid.downcase) }
missing = CANDIDATE_DELETE - to_delete

puts "\n=== Plan ==="
puts "Will KEEP: #{KEEP.join(', ')}"
puts "Will try DELETE (#{to_delete.size}):"
to_delete.each { |bid| puts "  - #{bid}" }
puts "Not found (already gone?): #{missing.join(', ')}" unless missing.empty?
puts "Manual REVIEW (not auto-deleted): #{REVIEW_BEFORE_DELETE.join(', ')}"

exit 0 unless command == "delete"

puts "\n=== Deleting ==="
to_delete.each do |bid|
  app = Spaceship.app.find(bid)
  unless app
    puts "  skip #{bid} (not found)"
    next
  end
  begin
    app.delete!
    puts "  deleted #{bid}"
  rescue StandardError => e
    puts "  FAILED #{bid}: #{e.message}"
    puts "    → Remove linked provisioning profiles in developer.apple.com → Profiles first"
  end
end

puts "\nFinished. Re-run `list` to verify."
