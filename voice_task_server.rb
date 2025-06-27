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

require 'bundler/setup'
require 'json'
require 'date'
require 'fileutils'
require 'ffi'

require_relative 'vosk_ffi'

CONFIG_PATH = 'config.json'.freeze
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

# ---------- command parser -----------------------------------------------
def parse_create_task(line, cfg)
  rx = /\b(?:add|create)\s+(?:a\s+)?task\s+to\s+['"]?([^'"]+)['"]?\s+workspace(?:[:→])?\s*(.+?)\s*(?:by\s*([a-z0-9,\s]+?))?(?:\s*\(status:\s*([^)]+)\))?\z/ix
  m = line.match(rx) or return nil
  { command: 'create_task', workspace: m[1].strip, task: m[2].strip,
    'due-date' => (m[3] && Date.parse(m[3]).to_s) || DEFAULT_CFG['due_default'],
    status: (m[4] || DEFAULT_CFG['status_default']).strip }
end

def parse_line(text, cfg)
  parse_create_task(text, cfg)
end

# ---------- Speech processing class --------------------------------------
class SpeechProcessor
  def initialize(model_glob, sample_rate)
    model_path = Dir[model_glob].first or abort 'Model not found'
    @model = Vosk.vosk_model_new(model_path)
    @rec   = Vosk.vosk_recognizer_new(@model, sample_rate)
  end

  # Feed raw PCM chunk; returns true if final result is available
  def feed(chunk)
    ptr = FFI::MemoryPointer.new(:uchar, chunk.bytesize)
    ptr.put_bytes(0, chunk)
    Vosk.vosk_recognizer_accept_waveform(@rec, ptr, chunk.bytesize)
  end

  # Get interim partial result text
  def partial
    JSON.parse(Vosk.vosk_recognizer_partial_result(@rec))['partial'] rescue ''
  end

  # Get final result text
  def final
    JSON.parse(Vosk.vosk_recognizer_result(@rec))['text'] || ''
  end

  def free
    Vosk.vosk_recognizer_free(@rec)
    Vosk.vosk_model_free(@model)
  end
end

# ---------- run_server (unchanged) ----------------------------------------
def load_config; DEFAULT_CFG.merge(JSON.parse(File.read(CONFIG_PATH))) rescue DEFAULT_CFG; end

def queue_init(path)
  FileUtils.touch(path)
  File.write(path, '[]') if File.read(path).strip.empty?
end

def queue_append(path, entry)
  data = JSON.parse(File.read(path)); data << entry; File.write(path, JSON.pretty_generate(data)); puts "🔹 queued: #{entry}"; end

require 'tty-command'

def run_server(cfg)
  cfg = load_config
  queue_init(cfg['queue_file'])
  sp = SpeechProcessor.new(cfg['model_glob'], cfg['sample_rate'])

  # last_option
  ffmpeg_cmd = cfg['ffmpeg_opts'].map{ |t|
    t == ':DEVICE' ? ":#{cfg['device_index']}" : t
  }.map{ |t|
    t == ':SAMPLE' ? "#{cfg['sample_rate']}" : t
  }
  io = IO.popen([cfg['ffmpeg_bin'], *ffmpeg_cmd], 'rb')
  puts '🎙️  Voice server ready — Ctrl-C to quit'
  while chunk = io.read(4096)
    final = sp.feed(chunk)
    text = final ? sp.final : sp.partial
    next if text.to_s.strip.empty?
    if final && (entry = parse_line(text, cfg))
      queue_append(cfg['queue_file'], entry)
    else
      print "\r…#{text.ljust(40)}"
    end
  end
  io.close
  Process.wait(io.pid)
  at_exit{ sp.free }
end

# ---------- standalone test ----------------------------------------------
if __FILE__ == $0
  if ARGV.first && File.extname(ARGV.first) == '.wav'
    sp = SpeechProcessor.new(DEFAULT_CFG['model_glob'], DEFAULT_CFG['sample_rate'])
    File.open(ARGV.first, 'rb') do |f|
      f.read(4096) until f.eof? do |chunk|
        sp.feed(chunk)
      end
    end
    text = sp.final
    puts "Transcribed: #{text}"
    p parse_line(text, load_config)
    sp.free
  else
    run_server(load_config)
  end
end
