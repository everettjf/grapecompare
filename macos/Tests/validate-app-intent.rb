#!/usr/bin/env ruby
require "json"

app = ARGV.fetch(0)
metadata = File.join(app, "Contents/Resources/Metadata.appintents/extract.actionsdata")
document = JSON.parse(File.read(metadata))
action = document.dig("actions", "CompareFilesIntent") or abort("CompareFilesIntent missing")
parameter = action.fetch("parameters").find { |item| item["name"] == "files" } or abort("files parameter missing")
metadata = parameter.fetch("typeSpecificMetadata")
size_index = metadata.index("LNValueTypeMetadataKeyCollectionSizes") or abort("collection size metadata missing")
sizes = metadata.dig(size_index + 1, "collectionSizes", "sizes", "*")
abort("Finder action must require exactly two files") unless sizes == { "max" => 2, "min" => 2 }
abort("Finder action must open the app") unless action["openAppWhenRun"] == true
abort("Compare Files app shortcut missing") unless document.fetch("autoShortcuts").any? { |item| item["actionIdentifier"] == "CompareFilesIntent" }
puts "PASS: built app exposes an exact-two-file Finder-compatible App Intent"
