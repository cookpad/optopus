require 'optparse'
require 'optparse/date'
require 'optparse/shellwords'
require 'optparse/time'
require 'optparse/uri'
require 'yaml'

module Optopus
  class DefinerContext
    def self.evaluate(opts, &block)
      self.new(opts).instance_eval(&block)
    end

    def initialize(opts)
      @opts = opts
    end

    def desc(str)
      @desc = str
    end

    def option(name, args_hd, *args_tl, &block)
      @opts.add(name, [args_hd] + args_tl, @desc, block)
      @desc = nil
    end

    def file(args_hd, *args_tl)
      @desc ||= 'reading config file'
      @opts.add_file([args_hd] + args_tl, @desc)
      @desc = nil
    end

    def after(&block)
      @opts.add_after(block)
    end

    def exception(&block)
      @opts.add_exception(block)
    end
  end # DefinerContext

  class CheckerContext
    def self.evaluate(args, vars = {}, &block)
      self.new(args, vars).instance_eval(&block)
    end

    def initialize(value, vars = {})
      @args = value ? [value] : []

      vars.each do |name, value|
        instance_variable_set("@#{name}", value)
      end
    end

    def parse_error(reason)
      e = OptionParser::ParseError.new(*@args)
      e.reason = reason
      raise e
    end

    def ambiguous_option
      raise OptionParser::AmbiguousOption.new(*@args)
    end

    def needless_argument
      raise OptionParser::NeedlessArgument.new(*@args)
    end

    def missing_argument
      raise OptionParser::MissingArgument.new(*@args)
    end

    def invalid_option
      raise OptionParser::InvalidOption.new(*@args)
    end

    def invalid_argument
      raise OptionParser::InvalidArgument.new(*@args)
    end

    def ambiguous_argument
      raise OptionParser::AmbiguousArgument.new(*@args)
    end
  end # CheckerContext

  class Options
    def initialize
      @opts_args = []
    end

    def add(name, args, desc, block)
      args, defval = fix_args(args, desc)
      @opts_args << [name.to_sym, args, defval, block]
    end

    def add_file(args, desc)
      args, defval = fix_args(args, desc)
      @file_args = args
    end

    def add_after(block)
      @on_after = block
    end

    def add_exception(block)
      @on_exception = block
    end

    def parse!
      parser = OptionParser.new
      options = {}
      has_arg_h = false

      @opts_args.each do |name, args, defval, block|
        options[name] = defval
        has_arg_h = (args.first == '-h')

        parser.on(*args) do |*v|
          value = v.first || true
          options[name] = value
          CheckerContext.evaluate(v, {:value => value}, &block) if block
        end
      end

      if @file_args
        parser.on(*@file_args) do |v|
          config = YAML.load_file(v)

          @opts_args.each do |name, args, defval, block|
            value = config[name] || config[name.to_s]
            options[name] = value if value
          end
        end
      end

      unless has_arg_h
        parser.on_tail('-h', '--help', 'Show this message') do
          puts parser.help
          exit
        end
      end

      parser.parse!(ARGV)
      CheckerContext.evaluate([], {:options => options},&@on_after) if @on_after

      return options
    rescue => e
      if @on_exception
        @on_exception.call(e)
      else
        raise e
      end
    end

    private
    def fix_args(args, desc)
      defval = nil

      if args.last.kind_of?(Hash)
        hash = args.pop
        args = (args.slice(0, 2) + [hash[:type], hash[:desc] || desc]).select {|i| i }
        defval = hash[:default]
      elsif desc
        args = args + [desc]
      end

      return [args, defval]
    end
  end # Options
end # Optopus

def optopus(&block)
  opts = Optopus::Options.new
  Optopus::DefinerContext.evaluate(opts, &block)
  opts.parse!
end
