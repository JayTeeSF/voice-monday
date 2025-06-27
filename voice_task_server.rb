#!/usr/bin/env ruby
# voice_task_server.rb  — mic → JSON queue
# ---------------------------------------------------------------------------
# ❶ CONFIG
#    • Values come from DEFAULT_CFG and can be overridden in ./config.json
# ❷ QUEUE OPS
#    • queue_init / queue_append
# ❸ PARSING
#    • create_task  (due-date optional → defaults to coming Friday)
# ❹ MAIN LOOP
#    • sets up Vosk + FFmpeg, streams audio, enqueues commands
# ---------------------------------------------------------------------------

require 'json'
require 'date'
require 'fileutils'
require 'vosk'
require 'vosk/model'    # <= explicit load (newer gem versions need this)
require 'tty/command'

CONFIG_PATH  = 'config.json'.freeze

DEFAULT_CFG = {
  'queue_file'     => 'queue.json',
  'model_glob'     => 'models/vosk-model-small-en-us*',
  'sample_rate'    => 16_000,
  'device_index'   => 0,                         # avfoundation mic index
  'status_default' => 'todo',
  'ffmpeg_bin'     => 'ffmpeg',
  'ffmpeg_opts'    => %w[-hide_banner -loglevel panic -f avfoundation -i :DEVICE
                         -ac 1 -ar :SAMPLE -f s16le -],
  'due_default'    => 'next_friday'             # or 'none'
}.freeze

# ---------------------------------------------------------------------------

# ---------- helpers (config / queue) ---------------------------------------
def load_config
  user_cfg = File.exist?(CONFIG_PATH) ? JSON.parse(File.read(CONFIG_PATH)) : {}
  DEFAULT_CFG.merge(user_cfg)                       # shallow merge
end

def queue_init(path)
  FileUtils.touch(path)
  File.write(path, '[]') if File.read(path).strip.empty?
end

def queue_append(path, entry)
  data = JSON.parse(File.read(path))
  data << entry
  File.write(path, JSON.pretty_generate(data))
  puts "🔹 queued: #{entry.to_json}"
end

# ---------- date utilities --------------------------------------------------
def next_friday(from = Date.today)
  days_ahead = (5 - from.wday) % 7
  days_ahead = 7 if days_ahead.zero?              # always a future Friday
  from + days_ahead
end

def normalize_date(raw)
  return next_friday.to_s if raw.nil? || raw.empty?
  Date.parse(raw).yield_self { |d|
    raw =~ /\d{4}/ ? d : Date.new(Date.today.year, d.month, d.day)
  }.to_s
rescue ArgumentError
  next_friday.to_s
end

# ---------- command parser --------------------------------------------------
def parse_create_task(line, cfg)
  rx = /
    \b(?:add|create)\s+(?:a\s+)?task\s+to\s+
    ['"]?([^'"]+)['"]?\s+workspace\s*(?:[:→])?\s*
    (.+?)                                   # task (lazy) …
    (?:\s+by\s+([a-z0-9,\s]+?))?            #  … optional due date
    (?:\s*\(status:\s*([^)]+)\))?           #  … optional status
    \s*\z
  /ix
  m = line.match(rx) or return nil

  {
    command:   'create_task',
    workspace: m[1].strip,
    task:      m[2].strip,
    'due-date': normalize_date(m[3]),
    status:    (m[4] || cfg['status_default']).strip
  }
end

def parse_line(line, cfg)
  parse_create_task(line, cfg)
end

# ---------- voicestream → recogniser loop -----------------------------------
def run_server(cfg)
  model_path = Dir[cfg['model_glob']].first or
               abort 'Vosk model not found — run setup.sh'

  queue_init(cfg['queue_file'])

  model = Vosk::Model.new(model_path)
  rec   = Vosk::Recognizer.new(model, cfg['sample_rate'])
  cmd   = TTY::Command.new

  ffmpeg_cmd = cfg['ffmpeg_opts']
                .map { |t| t == ':DEVICE' ? ":#{cfg['device_index']}" : t }
                .map { |t| t == ':SAMPLE' ? cfg['sample_rate'].to_s : t }

  ffmpeg = cmd.popen([cfg['ffmpeg_bin'], *ffmpeg_cmd])

  puts '🎙️  Voice server ready — Ctrl-C to quit'
  ffmpeg.each(4096) do |chunk|
    next unless rec.accept_waveform(chunk)
    spoken = JSON.parse(rec.result)['text']
    next if spoken.empty?

    if (entry = parse_line(spoken, cfg))
      queue_append(cfg['queue_file'], entry)
    else
      puts "⚠️  Unrecognised: #{spoken.inspect}"
    end
  end
end

# ---------- entrypoint -------------------------------------------------------
run_server(load_config)
