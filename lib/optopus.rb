require 'optparse'
require 'yaml'

module Optopus
  class DefinerContext
    def initialize(opts)
      @opts = opts
    end

    def desc(text)
      @desc = text
    end

    def option(name, hd, *tl, &checker)
      @opts.add(name, [hd] + tl, @desc, checker)
      @desc = nil
    end

    def file(hd, *tl)
      @desc ||= 'reading config file'
      @opts.file = [[hd] + tl, @desc]
      @desc = nil
    end

    def after(&block)
      @opts.after = block
    end
  end

  class CheckerContext
    def initialize(args, vars = {})
      @args = args

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
  end

  class Options
    attr_accessor :file
    attr_accessor :after

    def initialize
      @opts = {}
    end

    def add(name, args, desc, checker)
      @opts[name.to_sym] = [args, desc, checker]
    end

    def parse!
      parsed_options = {}
      parser = OptionParser.new
      has_h = false

      @opts.each do |name, values|
        args, desc, checker = values

        if args.last.kind_of?(Hash)
          hash = args.pop
          args = (args.slice(0, 2) + [hash[:type], hash[:desc] || desc]).select {|i| i }
          parsed_options[name] = hash[:default]
        elsif desc
          args = args + [desc]
        end

        has_h = (args.first == '-h')

        parser.on(*args) do |*v|
          value = v.first || true
          parsed_options[name] = value

          if checker
            CheckerContext.new(v.select {|i| i }, :value => value).instance_eval(&checker)
          end
        end
      end

      if file
        args, desc = file

        if args.last.kind_of?(Hash)
          hash = args.pop
          args = (args.slice(0, 2) + [hash[:type], hash[:desc] || desc]).select {|i| i }
          parsed_options[name] = hash[:default]
        elsif desc
          args = args + [desc]
        end

        parser.on(*args) do |v|
          YAML.load_file(v).each do |k, v|
            parsed_options[k.to_sym] = v
          end
        end
      end

      unless has_h
        parser.on_tail('-h', '--help', 'Show this message') do
          puts parser.help
          exit
        end
      end

      parser.parse!(ARGV)

      if after
        CheckerContext.new([], :options => parsed_options).instance_eval(&after)
      end

      return parsed_options
    rescue RuntimeError => e
      $stderr.puts e.message
      exit 1
    end
  end
end

def optopus(&block)
  opts = Optopus::Options.new
  Optopus::DefinerContext.new(opts).instance_eval(&block)
  opts.parse!
end
