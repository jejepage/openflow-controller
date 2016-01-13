require 'cri'
require 'openflow-controller/completion'
require 'openflow-controller/controller'

module OpenFlow
  module Controller
    class CLI
      PROMPT = '> '
      BYE_MSG = 'Bye!'

      def self.run
        create_command.run(ARGV)
      end

      private

      def self.print_error(e)
        puts "#{e.class}: #{e.message}".red
        puts e.backtrace.join("\n\t").red
      end

      def self.run_controller_on_thread(ctl, ip, port, args)
        Thread.abort_on_exception = true
        Thread.new do
          begin
            ctl.run ip, port, args
          rescue StandardError => e
            CLI.print_error e
            exit 1
          end
        end
      end

      def self.run_cli(ctl)
        loop do
          begin
            input = Readline.readline(PROMPT, true)
            if input.nil? || input == 'exit'
              puts if input.nil?
              puts BYE_MSG
              exit
            end
            output = eval(input, ctl.get_binding).inspect
            # output = ctl.eval(input).inspect
            puts " => #{output}".green
          rescue StandardError, SyntaxError => e
            print_error e
          rescue SignalException
            puts
          end
        end
      end

      def self.create_command
        Cri::Command.define do
          name        'ofctl'
          usage       'ofctl [options] [args]'
          summary     'OpenFlow Controller command-line tool'
          description 'OpenFlow Controller command-line tool'

          flag :h, :help, 'show help for this command' do |_value, cmd|
            puts cmd.help
            exit 0
          end
          flag :d, :debug, 'run controller in debug mode'

          option :i, :ip,         'IP address of the controller',  argument: :optional
          option :p, :port,       'port number of the controller', argument: :optional
          option :c, :controller, 'custom controller file',        argument: :optional

          run do |opts, args, _cmd|
            load opts[:controller] unless opts[:controller].nil?

            ctl = Controller.create
            ctl.set_debug if opts[:debug]

            init_form = ctl.logger.formatter
            ctl.logger.formatter = proc do |severity, datetime, progname, msg|
              buf = PROMPT + Readline::line_buffer
              "\r" + ' ' * buf.length + "\r" +
              init_form.call(severity, datetime, progname, msg).blue +
              buf
            end

            ip   = opts[:ip]   || Controller::DEFAULT_IP_ADDRESS
            port = opts[:port] || Controller::DEFAULT_TCP_PORT

            CLI.run_controller_on_thread ctl, ip, port, args
            CLI.run_cli ctl
          end
        end
      end
    end
  end
end
