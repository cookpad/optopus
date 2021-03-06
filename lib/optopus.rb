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

    def before(&block)
      @opts.add_before(block)
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

    def parse_error(reason, *args)
      args = @args if args.empty?
      e = OptionParser::ParseError.new(*args)
      e.reason = reason
      raise e
    end

    def ambiguous_option(*args)
      args = @args if args.empty?
      raise OptionParser::AmbiguousOption.new(*args)
    end

    def needless_argument(*args)
      args = @args if args.empty?
      raise OptionParser::NeedlessArgument.new(*args)
    end

    def missing_argument(*args)
      args = @args if args.empty?
      raise OptionParser::MissingArgument.new(*args)
    end

    def invalid_option(*args)
      args = @args if args.empty?
      raise OptionParser::InvalidOption.new(*args)
    end

    def invalid_argument(*args)
      args = @args if args.empty?
      raise OptionParser::InvalidArgument.new(*args)
    end

    def ambiguous_argument(*args)
      args = @args if args.empty?
      raise OptionParser::AmbiguousArgument.new(*args)
    end

    def not_given(*args)
      args = @args if args.empty?
      raise OptionParser::NotGiven.new(*args)
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

    def add_before(block)
      @on_before = block
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

      file_args_checker = lambda do |v|
        if v.kind_of?(Hash)
          config = v
        else
          config = YAML.load_file(v)
          @on_before.call(config) if @on_before
        end

        config.keys.each do |key|
          next unless key.kind_of?(Symbol)
          config[key.to_s.gsub('_', '-')] = config[key]
        end

        options.instance_variable_set(:@__config_file__, config)

        @opts_args.each do |name, args, defval, block, required, multiple|
          if args[1].kind_of?(String) and args[1] =~ /-+([^\s=]+)/
            key = $1
          else
            key = name.to_s
          end

          value = nil

          [key, key.gsub(/[-_]/, '-'), key.gsub(/[-_]/, '_')].each do |k|
            if value = config[k]
              key = k
              break
            end
          end

          next unless value

          check_block = lambda do |unit|
            unit = orig_val = unit.to_s

            if type = args.find {|i| i.kind_of?(Class) }
              pat, conv =  OptionParser::DefaultList.atype[type]

              if pat and pat !~ unit
                raise OptionParser::InvalidArgument.new(v, "(#{key}: #{unit})")
              end

              unit = conv.call(unit) if conv
            elsif type = args.find {|i| i.kind_of?(Array) }
              unless type.map {|i| i.to_s }.include?(unit.to_s)
                raise OptionParser::InvalidArgument.new(key, unit)
              end

              unit = unit.to_s.to_sym
            end

            if unit and block
              begin
                CheckerContext.evaluate(v, unit, &block)
              rescue OptionParser::ParseError => e
                errmsg = "#{e.message}: #{key}=#{orig_val}"
                raise OptionParser::ParseError, errmsg
              end
            end

            return unit
          end

          if multiple
            value = [value] unless value.kind_of?(Array)
            options[name] = value.map {|i| check_block.call(i) }
          else
            options[name] = check_block.call(value)
          end
        end
      end # file_args_checker

      if @file_args
        @parser.on(*@file_args, &file_args_checker)
      elsif @on_before
        config = {}
        @on_before.call(config)
        file_args_checker.call(config)
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

      (options.config_file || {}).each do |key, value|
        next if key.kind_of?(Symbol)
        key = key.to_s.gsub('-', '_').to_sym
        options[key] = value unless options.has_key?(key)
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
