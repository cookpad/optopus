require 'optparse'
require 'optparse/date'
require 'optparse/shellwords'
require 'optparse/time'
require 'optparse/uri'
require 'yaml'

class OptionParser
  class NotGiven < ParseError
    const_set(:Reason, 'required option was not given'.freeze)
  end
end

module Optopus
  class DefinerContext
    def self.evaluate(opts, &block)
      self.new(opts).instance_eval(&block)
    end

    def initialize(opts)
      @opts = opts
    end

    def banner=(v)         ; @opts.banner = v         ; end
    def program_name=(v)   ; @opts.program_name = v   ; end
    def summary_width=(v)  ; @opts.psummary_width = v ; end
    def summary_indent=(v) ; @opts.summary_indent = v ; end
    def default_argv=(v)   ; @opts.default_argv = v   ; end
    def version=(v)        ; @opts.version = v        ; end
    def release=(v)        ; @opts.release = v        ; end

    def desc(str)
      @desc = str
    end

    def option(name, args_hd, *args_tl, &block)
      @opts.add(name, [args_hd] + args_tl, @desc, block)
      @desc = nil
    end

    def config_file(args_hd, *args_tl)
      @desc ||= 'reading config file'
      @opts.add_file([args_hd] + args_tl, @desc)
      @desc = nil
    end

    def after(&block)
      @opts.add_after(block)
    end

    def error(&block)
      @opts.add_error(block)
    end
  end # DefinerContext

  class CheckerContext
    def self.evaluate(args, pass, &block)
      self.new(args, &block).evaluate(pass)
    end

    def initialize(value, &block)
      @args = value ? [value] : []
      (class<<self; self; end).send(:define_method, :evaluate, &block)
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

    def not_given
      raise OptionParser::NotGiven.new(*@args)
    end
  end # CheckerContext

  class Options
    def initialize
      @parser = OptionParser.new
      @opts_args = []
    end

    def banner=(v)         ; @parser.banner = v         ; end
    def program_name=(v)   ; @parser.program_name = v   ; end
    def summary_width=(v)  ; @parser.psummary_width = v ; end
    def summary_indent=(v) ; @parser.summary_indent = v ; end
    def default_argv=(v)   ; @parser.default_argv = v   ; end
    def version=(v)        ; @parser.version = v        ; end
    def release=(v)        ; @parser.release = v        ; end

    def add(name, args, desc, block)
      args, defval, required, multiple = fix_args(args, desc)
      @opts_args << [name.to_sym, args, defval, block, required, multiple]
    end

    def add_file(args, desc)
      raise 'two or more config_file is defined' if @file_args
      args, defval, required, multiple = fix_args(args, desc)
      @file_args = args
    end

    def add_after(block)
      @on_after = block
    end

    def add_error(block)
      @on_error = block
    end

    def parse!
      options = {}
      has_arg_v = false
      has_arg_h = false
      options.instance_eval("def config_file; @__config_file__; end")

      if @file_args
        @parser.on(*@file_args) do |v|
          config = YAML.load_file(v)
          options.instance_variable_set(:@__config_file__, config)

          @opts_args.each do |name, args, defval, block, required, multiple|
            if args[1].kind_of?(String) and args[1] =~ /-+([^\s=]+)/
              key = $1
            else
              key = name.to_s
            end

            value = config[key] || config[key.gsub(/[-_]/, '-')] || key.gsub(/[-_]/, '_')

            next unless value

            value = value.to_s
            type = args.find {|i| i.kind_of?(Class) }
            pat, conv =  OptionParser::DefaultList.atype[type]

            if pat and pat !~ value
              raise OptionParser::InvalidArgument.new(v, "(#{name}: #{value})")
            end

            value = conv.call(value) if conv
            
            options[name] = value
          end
        end
      end

      @opts_args.each do |name, args, defval, block, required, multiple|
        options[name] = defval unless defval.nil?
        has_arg_v = (args.first == '-v')
        has_arg_h = (args.first == '-h')

        @parser.on(*args) do |*v|
          value = v.first || true

          if multiple
            options[name] ||= []
            options[name] << value
          else
            options[name] = value
          end

          CheckerContext.evaluate(v, value, &block) if block
        end
      end

      unless has_arg_v
        @parser.on_tail('-v', '--version', 'show version') do
          v = @parser.ver or abort("#{@parser.program_name}: version unknown")
          puts v
          exit
        end
      end

      unless has_arg_h
        @parser.on_tail('-h', '--help', 'show this message') do
          puts @parser.help
          exit
        end
      end

      @parser.parse!

      @opts_args.each do |name, args, defval, block, required, multiple|
        if required and not options.has_key?(name)
          raise OptionParser::NotGiven, args.first
        end
      end

      CheckerContext.evaluate([], options, &@on_after) if @on_after

      return options
    rescue => e
      if @on_error
        @on_error.call(e)
      else
        raise e
      end
    end

    private
    def fix_args(args, desc)
      defval = nil
      required = false
      multiple = false

      if args.last.kind_of?(Hash)
        hash = args.pop
        args = (args.slice(0, 2) + [hash[:type], hash[:desc] || desc]).select {|i| i }
        defval = hash[:default]
        required = hash[:required]
        multiple = hash[:multiple]
      elsif desc
        args = args + [desc]
      end

      return [args, defval, required, multiple]
    end
  end # Options
end # Optopus

def optopus(&block)
  opts = Optopus::Options.new
  Optopus::DefinerContext.evaluate(opts, &block)
  opts.parse!
end
