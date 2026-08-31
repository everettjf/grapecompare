#!/usr/bin/env ruby
# frozen_string_literal: true

require "English"
require "shellwords"

root = File.expand_path("..", __dir__)
metadata_path = File.join(root, "docs/app-store-metadata.md")
metadata = File.read(metadata_path, encoding: "UTF-8")

def fail_check(message)
  warn "App Store metadata validation failed: #{message}"
  exit 1
end

def section(document, heading, next_heading)
  match = document.match(/^## #{Regexp.escape(heading)}\n(.*?)(?=^## #{Regexp.escape(next_heading)}\n)/m)
  fail_check("missing #{heading} section") unless match
  match[1]
end

def field(block, name)
  match = block.match(/^- #{Regexp.escape(name)}: `([^`]*)`$/)
  fail_check("missing #{name}") unless match
  match[1]
end

def fenced_field(block, name)
  match = block.match(/^- #{Regexp.escape(name)}:\n\n  ```text\n(.*?)\n  ```/m)
  fail_check("missing #{name}") unless match
  match[1].gsub(/^  /, "")
end

def inline_paragraph_field(block, name)
  match = block.match(/^- #{Regexp.escape(name)}:\n\n  `([^`]*)`$/)
  fail_check("missing #{name}") unless match
  match[1]
end

english = section(metadata, "English (U.S.)", "Simplified Chinese")
chinese = section(metadata, "Simplified Chinese", "App Review information")

[["English", english], ["Simplified Chinese", chinese]].each do |locale, block|
  subtitle = field(block, "Subtitle")
  keywords = field(block, "Keywords")
  promotional_text = inline_paragraph_field(block, "Promotional text")
  description = fenced_field(block, "Description")

  fail_check("#{locale} subtitle exceeds 30 characters") if subtitle.length > 30
  fail_check("#{locale} keywords exceed 100 UTF-8 bytes") if keywords.bytesize > 100
  fail_check("#{locale} promotional text is missing") unless promotional_text
  fail_check("#{locale} promotional text exceeds 170 characters") if promotional_text.length > 170
  fail_check("#{locale} description exceeds 4,000 characters") if description.length > 4_000
end

screenshots = Dir.glob(File.join(root, "app-store/screenshots/en-US/*.{jpg,jpeg,png}"), File::FNM_EXTGLOB).sort
fail_check("one to ten screenshots are required") unless (1..10).cover?(screenshots.length)

screenshots.each do |path|
  properties = `sips -g pixelWidth -g pixelHeight -g hasAlpha #{Shellwords.escape(path)} 2>/dev/null`
  fail_check("cannot inspect #{path}") unless $CHILD_STATUS.success?
  width = properties[/pixelWidth: (\d+)/, 1].to_i
  height = properties[/pixelHeight: (\d+)/, 1].to_i
  alpha = properties[/hasAlpha: (\w+)/, 1]
  supported = [[1280, 800], [1440, 900], [2560, 1600], [2880, 1800]].include?([width, height])
  fail_check("unsupported dimensions for #{path}: #{width}x#{height}") unless supported
  fail_check("screenshot has an alpha channel: #{path}") unless alpha == "no"
end

puts "Validated App Store metadata and #{screenshots.length} screenshots."
