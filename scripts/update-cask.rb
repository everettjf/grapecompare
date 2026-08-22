#!/usr/bin/env ruby
require "fileutils"
require "shellwords"

version, archive, template, output = ARGV
abort "usage: update-cask.rb <version> <archive> <template> <output>" unless output
abort "archive not found: #{archive}" unless File.file?(archive)
sha256 = `shasum -a 256 #{Shellwords.escape(archive)}`.split.first
abort "could not calculate checksum" unless sha256

content = File.read(template)
content.sub!(/version "[^"]+"/, %(version "#{version.sub(/^v/, "")}"))
content.sub!(/sha256 "[^"]+"/, %(sha256 "#{sha256}"))
FileUtils.mkdir_p(File.dirname(output))
File.write(output, content)
