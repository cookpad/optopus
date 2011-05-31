#!/usr/bin/env ruby
require 'lib/optopus'

opts = optopus do
  desc 'program information'
  option :info, '-I'

  desc 'print lots of debugging information'
  option :debug, '-d', '--debug'

  desc 'log messages to FILE.'
  option :output_file, '-o', '--output-file FILE', :default => '/var/log/xxx.log'

  desc 'set number of retries to NUMBER (0 unlimits)'
  option :tries, '-t', '--tries NUMBER', :type => Integer, :default => 0 do
    # custom validation
    invalid_argument if @value < 0
  end

  desc 'comma-separated list of accepted extensions'
  option :accept, '-A', '--accept LIST', :type => Array, :default => []

  desc 'access timestamp'
  option :timestamp, '-T', '--timestamp TIME', :type => Time

  # read yaml config file and overwrite options
  config_file '-c', '--config-file FILE'

  after do
    # postprocessing
    # @options.each { ... }
  end

  error do |e|
    abort(e.message)
  end
end

p opts
