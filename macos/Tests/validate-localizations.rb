#!/usr/bin/env ruby
require "json"

catalog = JSON.parse(File.read(File.expand_path("../GrapeCompare/Localizable.xcstrings", __dir__)))
catalog_keys = catalog.fetch("strings").keys
missing = catalog.fetch("strings").map do |key, entry|
  next if key.empty?
  unit = entry.dig("localizations", "zh-Hans", "stringUnit")
  key unless unit && unit["state"] == "translated" && unit["value"]
end.compact
abort("Missing Simplified Chinese translations:\n#{missing.join("\n")}") unless missing.empty?
if ARGV[0]
  extracted = Dir.glob(File.join(ARGV[0], "*.stringsdata")).flat_map do |path|
    JSON.parse(File.read(path)).fetch("tables", {}).fetch("Localizable", []).map { |item| item["key"] }
  end.compact.uniq
  absent = extracted - catalog_keys
  abort("Strings extracted from source but absent from catalog:\n#{absent.join("\n")}") unless absent.empty?
end
puts "PASS: every catalog string has a Simplified Chinese translation"
