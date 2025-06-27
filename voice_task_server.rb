#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Continuously transcribes the macOS default microphone (via ffmpeg/avfoundation),
# parses recognised sentences into structured commands, and appends them
# to queue.json (a JSON array on disk).

require "json"
require "open3"
require "vosk"
require "tty/command"
require "fileutils"

QUEUE_FILE = "queue.json"
MODEL_PATH = Dir["models/vosk-model-small-en-us*"].first or
             abort "Vosk model not found – run ./setup.sh"

FileUtils.touch(QUEUE_FILE)
File.write(QUEUE_FILE, "[]") if File.read(QUEUE_FILE).strip.empty?

# ---------- helpers ----------
def load_queue
  JSON.parse(File.read(QUEUE_FILE))
end

def save_queue(arr)
  File.write(QUEUE_FILE, JSON.pretty_generate(arr))
end

def append_task(hash)
  q = load_queue
  q << hash
  save_queue(q)
  puts "🔹 queued: #{hash}"
end

def parse_sentence(text)
  text.downcase!
  create_re = /
    (?:add|create)\s+a?\s*task\s+to\s+
    ['"]?([^'"]+)['"]?\s+workspace\s*[:→]?\s*
    (.+?)\s+by\s+([a-z0-9\s]+?)        # task + due-date
    (?:\s*\(status:\s*([^)]+)\))?      # optional status
  /ix

  if (m = text.match(create_re))
    {
      command:   "create_task",
      workspace: m[1].strip,
      task:      m[2].strip,
      "due-date": m[3].strip,
      status:    (m[4] || "todo").strip
    }
  else
    nil
  end
end

# ---------- speech recogniser ----------
model  = Vosk::Model.new(MODEL_PATH)
rec    = Vosk::Recognizer.new(model, 16000.0)
cmd    = TTY::Command.new
ffmpeg = cmd.popen(%w[
  ffmpeg -hide_banner -loglevel panic
  -f avfoundation -i :0
  -ac 1 -ar 16000 -f s16le -
])

puts "🎙  Voice server running…  (Ctrl-C to quit)"

ffmpeg.each(4096) do |chunk|
  next unless rec.accept_waveform(chunk)

  result = JSON.parse(rec.result)["text"]
  next if result.strip.empty?

  if (parsed = parse_sentence(result))
    append_task(parsed)
  else
    puts "⚠️  Unrecognised: #{result.inspect}"
  end
end
