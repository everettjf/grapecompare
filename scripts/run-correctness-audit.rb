#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "time"

root = File.expand_path("..", __dir__)
output = File.expand_path(ARGV.fetch(0, File.join(root, ".audit", "correctness-report.json")))

checks = [
  ["core", ["bash", "macos/Tests/run-tests.sh"]],
  ["cli", ["bash", "macos/CLI/run-tests.sh"]],
  ["localizations", ["ruby", "macos/Tests/validate-localizations.rb"]]
].map do |name, command|
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  stdout, stderr, status = Open3.capture3(*command, chdir: root)
  $stdout.write(stdout)
  $stderr.write(stderr)
  {
    "name" => name,
    "command" => command.join(" "),
    "passed" => status.success?,
    "exitStatus" => status.exitstatus,
    "durationSeconds" => (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3),
    "outputTail" => (stdout + stderr).lines.last(20).join
  }
end

screenshots = Dir.glob(File.join(root, "docs/assets/*.{png,jpg,jpeg}"), File::FNM_EXTGLOB).sort.map do |path|
  details, status = Open3.capture2("sips", "-g", "pixelWidth", "-g", "pixelHeight", path)
  width = details[/pixelWidth:\s+(\d+)/, 1]&.to_i
  height = details[/pixelHeight:\s+(\d+)/, 1]&.to_i
  valid = status.success? && width.to_i >= 800 && height.to_i >= 500
  {
    "path" => path.delete_prefix(root + "/"),
    "width" => width,
    "height" => height,
    "sha256" => Digest::SHA256.file(path).hexdigest,
    "passed" => valid
  }
end

revision, = Open3.capture2("git", "rev-parse", "HEAD", chdir: root)
passed = checks.all? { |check| check["passed"] } &&
         !screenshots.empty? && screenshots.all? { |screenshot| screenshot["passed"] }
report = {
  "schemaVersion" => 1,
  "generatedAt" => Time.now.utc.iso8601,
  "revision" => revision.strip,
  "passed" => passed,
  "checks" => checks,
  "screenshots" => screenshots
}

FileUtils.mkdir_p(File.dirname(output))
File.write(output, JSON.pretty_generate(report) + "\n")
puts "Correctness audit #{passed ? 'passed' : 'failed'}: #{output}"
exit(passed ? 0 : 1)
