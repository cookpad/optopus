#!/usr/bin/env ruby
require 'lib/optopus'

opts = optopus do
  before do |option|
    option[:protocol] = 'ftp'
    option[:undifeind_option3] = {:a => :b}
  end

  option :info, '-I', :desc => 'program information'

  desc 'print lots of debugging information'
  option :debug, '-d', '--debug'

  desc 'log messages to FILE.'
  option :output_file, '-o', '--output-file FILE', :default => '/var/log/xxx.log'

  desc 'set number of retries to NUMBER (0 unlimits)'
  option :tries, '-t', '--tries NUMBER', :type => Integer, :default => 0 do |value|
    # custom validation
    invalid_argument if value < 0
  end

  desc 'comma-separated list of accepted extensions'
  option :accept, '-A', '--accept LIST', :type => Array, :default => []

  desc 'access protocol'
  option :protocol, '-P', '--protocol PROTO', :type => [:http, :ftp]

  desc 'access timestamp'
  option :timestamp, '-T', '--timestamp TIME', :type => Time, :required => true

  desc 'resource record'
  option :record, '-R', '--record RECORD', :type => Array, :multiple => true

  # read yaml config file and overwrite options
  config_file '-c', '--config-file FILE'

  after do |options|
    # postprocessing
    # options.each { ... }
  end

  error do |e|
    abort(e.message)
  end
end

p opts
p opts.config_file
