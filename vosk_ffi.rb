require 'ffi'
require 'rubygems'

module Vosk
  extend FFI::Library
  
  # Locate the Vosk gem and its native library
  spec = Gem.loaded_specs['vosk'] || Gem::Specification.find_by_name('vosk') rescue nil
  abort '❌ Vosk gem not found — add `gem "vosk"` to your Gemfile and run `bundle install`' unless spec

  # Possible library locations: ENV override, gem directory, project lib/vosk
  candidates = []
  candidates << ENV['VOSK_LIBRARY_PATH'] if ENV['VOSK_LIBRARY_PATH']
  candidates.concat Dir.glob(File.join(spec.full_gem_path, '**', '*.dylib'))
  # include project-local native library under lib/vosk/**
  candidates.concat Dir.glob(File.join(Dir.pwd, 'lib', 'vosk', '**', '*.dylib'))
  lib_path = candidates.compact.find { |p| File.basename(p).downcase.include?('vosk') }
  abort "❌ Vosk native library not found; searched: #{candidates.join(', ')}" unless lib_path

  ffi_lib lib_path

  # Model bindings
  attach_function :vosk_model_new, [:string], :pointer
  attach_function :vosk_model_free, [:pointer], :void

  # Recognizer bindings
  attach_function :vosk_recognizer_new, [:pointer, :int], :pointer
  attach_function :vosk_recognizer_free, [:pointer], :void
  attach_function :vosk_recognizer_accept_waveform, [:pointer, :pointer, :int], :bool
  attach_function :vosk_recognizer_result, [:pointer], :string
  attach_function :vosk_recognizer_final_result, [:pointer], :string
end
