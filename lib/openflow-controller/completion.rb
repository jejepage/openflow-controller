require 'readline'
require 'openflow-controller/controller'

module OpenFlow
  module Controller
    module Completion
      # Set of reserved words used by Ruby, you should not use these for
      # constants or variables
      RESERVED_WORDS = %w[
        BEGIN END
        alias and
        begin break
        case class
        def defined do
        else elsif end ensure
        false for
        if in
        module
        next nil not
        or
        redo rescue retry return
        self super
        then true
        undef unless until
        when while
        yield
      ]

      Proc = proc do |input|
        bind = Controller.instance.get_binding

        case input
        when /^((["'`]).*\2)\.([^.]*)$/
          # String
          receiver = $1
          message = Regexp.quote($3)

          candidates = String.instance_methods.map(&:to_s)
          select_message(receiver, message, candidates)

        when /^(\/[^\/]*\/)\.([^.]*)$/
          # Regexp
          receiver = $1
          message = Regexp.quote($2)

          candidates = Regexp.instance_methods.map(&:to_s)
          select_message(receiver, message, candidates)

        when /^([^\]]*\])\.([^.]*)$/
          # Array
          receiver = $1
          message = Regexp.quote($2)

          candidates = Array.instance_methods.map(&:to_s)
          select_message(receiver, message, candidates)

        when /^([^\}]*\})\.([^.]*)$/
          # Proc or Hash
          receiver = $1
          message = Regexp.quote($2)

          candidates = Proc.instance_methods.map(&:to_s)
          candidates |= Hash.instance_methods.map(&:to_s)
          select_message(receiver, message, candidates)

        when /^(:[^:.]*)$/
          # Symbol
          if Symbol.respond_to?(:all_symbols)
            sym = $1
            candidates = Symbol.all_symbols.map { |s| ':' + s.id2name }
            candidates.grep(/^#{Regexp.quote(sym)}/)
          else
            []
          end

        when /^::([A-Z][^:\.\(]*)$/
          # Absolute Constant or class methods
          receiver = $1
          candidates = Object.constants.map(&:to_s)
          candidates.grep(/^#{receiver}/).map { |s| '::' + s }

        when /^([A-Z].*)::([^:.]*)$/
          # Constant or class methods
          receiver = $1
          message = Regexp.quote($2)
          begin
            candidates = eval("#{receiver}.constants.map(&:to_s)", bind)
            candidates |= eval("#{receiver}.methods.map(&:to_s)", bind)
          rescue Exception
            candidates = []
          end
          select_message(receiver, message, candidates, '::')

        when /^(:[^:.]+)(\.|::)([^.]*)$/
          # Symbol
          receiver = $1
          sep = $2
          message = Regexp.quote($3)

          candidates = Symbol.instance_methods.map(&:to_s)
          select_message(receiver, message, candidates, sep)

        when /^(-?(0[dbo])?[0-9_]+(\.[0-9_]+)?([eE]-?[0-9]+)?)(\.|::)([^.]*)$/
          # Numeric
          receiver = $1
          sep = $5
          message = Regexp.quote($6)

          begin
            candidates = eval(receiver, bind).methods.map(&:to_s)
          rescue Exception
            candidates = []
          end
          select_message(receiver, message, candidates, sep)

        when /^(-?0x[0-9a-fA-F_]+)(\.|::)([^.]*)$/
          # Numeric(0xFFFF)
          receiver = $1
          sep = $2
          message = Regexp.quote($3)

          begin
            candidates = eval(receiver, bind).methods.map(&:to_s)
          rescue Exception
            candidates = []
          end
          select_message(receiver, message, candidates, sep)

        when /^(\$[^.]*)$/
          # global var
          regmessage = Regexp.new(Regexp.quote($1))
          candidates = global_variables.map(&:to_s).grep(regmessage)

        when /^([^."].*)(\.|::)([^.]*)$/
          # variable.func or func.func
          receiver = $1
          sep = $2
          message = Regexp.quote($3)

          gv = eval('global_variables', bind).map(&:to_s)
          lv = eval('local_variables', bind).map(&:to_s)
          iv = eval('instance_variables', bind).map(&:to_s)
          cv = eval('self.class.constants', bind).map(&:to_s)

          if (gv | lv | iv | cv).include?(receiver) or /^[A-Z]/ =~ receiver && /\./ !~ receiver
            # foo.func and foo is var. OR
            # foo::func and foo is var. OR
            # foo::Const and foo is var. OR
            # Foo::Bar.func
            begin
              candidates = []
              rec = eval(receiver, bind)
              if sep == '::' and rec.kind_of?(Module)
                candidates = rec.constants.map(&:to_s)
              end
              candidates |= rec.methods.map(&:to_s)
            rescue Exception
              candidates = []
            end
          else
            # func1.func2
            candidates = []
            ObjectSpace.each_object(Module) do |m|
              begin
                name = m.name
              rescue Exception
                name = ''
              end
              begin
                next if name != "IRB::Context" and
                  /^(IRB|SLex|RubyLex|RubyToken)/ =~ name
              rescue Exception
                next
              end
              candidates.concat m.instance_methods(false).map(&:to_s)
            end
            candidates.sort!
            candidates.uniq!
          end
          select_message(receiver, message, candidates, sep)

        when /^\.([^.]*)$/
          # unknown(maybe String)
          receiver = ''
          message = Regexp.quote($1)

          candidates = String.instance_methods(true).map(&:to_s)
          select_message(receiver, message, candidates)

        else
          candidates = eval('methods | private_methods | local_variables | instance_variables | self.class.constants | Object.constants | OpenFlow.constants | OpenFlow::Controller.constants', bind).map(&:to_s)

          (candidates | RESERVED_WORDS).grep(/^#{Regexp.quote(input)}/)
        end
      end

      # Set of available operators in Ruby
      OPERATORS = %w[% & * ** + - / < << <= <=> == === =~ > >= >> [] []= ^ ! != !~]

      def self.select_message(receiver, message, candidates, sep = '.')
        candidates.grep(/^#{message}/).map do |e|
          case e
          when /^[a-zA-Z_]/
            receiver + sep + e
          when /^[0-9]/
          when *OPERATORS
            #receiver + " " + e
          end
        end
      end
    end
  end
end

if Readline.respond_to?('basic_word_break_characters=')
  Readline.basic_word_break_characters = " \t\n`><=;|&{("
end
Readline.completion_append_character = nil
Readline.completion_proc = OpenFlow::Controller::Completion::Proc
