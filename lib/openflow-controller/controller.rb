require 'socket'
require 'logger'
require 'openflow-controller/switch'

class Numeric
  def sec; self end
end

module OpenFlow
  module Controller
    class Controller
      include Protocol
      include PacketProtocols

      DEFAULT_IP_ADDRESS = '0.0.0.0'
      DEFAULT_TCP_PORT   = 6633

      def self.inherited(subclass)
        @controller_class = subclass
      end

      def self.create
        @instance = (@controller_class || self).new
      end

      def self.instance
        @instance
      end

      def self.timer_event(handler, options)
        @timer_handlers ||= {}
        @timer_handlers[handler] = options.fetch(:interval)
      end

      def self.timer_handlers
        @timer_handlers || {}
      end

      attr_reader :logger

      def initialize
        @switches = {}
        @messages = {}
        @logger = Logger.new($stdout).tap do |logger|
          logger.formatter = proc do |severity, datetime, _progname, msg|
            "#{datetime} (#{severity}) -- #{msg}\n"
          end
          logger.level = Logger::INFO
        end
      end

      def set_debug
        @logger.level = Logger::DEBUG
      end

      def get_binding
        binding
      end

      def run(ip = DEFAULT_IP_ADDRESS, port = DEFAULT_TCP_PORT, *args)
        maybe_send_handler :start, *args
        socket = TCPServer.open(ip, port)
        socket.setsockopt(:SOCKET, :REUSEADDR, true)
        logger.info "Controller running on #{ip}:#{port}."
        start_timers
        loop { start_switch_thread socket.accept }
      end

      def datapath_ids
        @switches.keys.map(&:to_i)
      end

      def switches
        @switches.values
      end

      def send_message(datapath_id, msg = nil)
        if msg.nil?
          msg         = datapath_id
          datapath_id = datapath_ids.first
        end
        @switches.fetch(datapath_id.to_s).send(msg)
      end

      def broadcast(msg)
        datapath_ids.each { |did| send_message did, msg }
      end

      def messages_for(datapath_id)
        @messages.fetch(datapath_id.to_s)
      end

      def last_message_for(datapath_id)
        messages_for(datapath_id).last
      end

      def messages
        messages_for datapath_ids.first
      end

      def last_message
        messages.last
      end

      def start(*_args) end
      def switch_ready(_datapath_id) end
      def message_received(_datapath_id, _msg) end
      def error(_datapath_id, _msg) end
      def echo_request(datapath_id, msg)
        send_message datapath_id, EchoReply.new(xid: msg.xid)
      end
      def packet_in(_datapath_id, _msg) end
      def port_add(_datapath_id, _msg) end
      def port_delete(_datapath_id, _msg) end
      def port_modify(_datapath_id, _msg) end
      def flow_removed(_datapath_id, _msg) end

      private

      def maybe_send_handler(handler, *args)
        @handler_mutex ||= Mutex.new
        @handler_mutex.synchronize do
          __send__(handler, *args) if respond_to?(handler)
        end
      end

      def start_timers
        self.class.timer_handlers.each do |handler, interval|
          Thread.new do
            loop do
              maybe_send_handler handler
              sleep interval
            end
          end
        end
      end

      def start_switch_thread(socket)
        logger.debug 'Socket accepted.'
        Thread.new do
          switch = create_and_register_new_switch(socket)
          start_switch_main(switch.datapath_id)
        end
      end

      def create_and_register_new_switch(socket)
        switch = Switch.new(self, socket)
        @messages[switch.datapath_id.to_s] = []
        @switches[switch.datapath_id.to_s] = switch
      end

      def start_switch_main(datapath_id)
        logger.info "Switch #{datapath_id} is ready."
        maybe_send_handler :switch_ready, datapath_id
        loop { handle_openflow_message(datapath_id) }
      rescue => exception
        logger.debug "Switch #{datapath_id} error: #{exception}."
        logger.debug exception.backtrace
        unregister_switch(datapath_id)
      end

      def unregister_switch(datapath_id)
        @messages.delete(datapath_id.to_s)
        @switches.delete(datapath_id.to_s)
        logger.info "Switch #{datapath_id} is disconnected."
        maybe_send_handler :switch_disconnected, datapath_id
      end

      def handle_openflow_message(datapath_id)
        msg = @switches.fetch(datapath_id.to_s).receive

        unless msg.class == EchoRequest
          logger.debug "Switch #{datapath_id} received #{msg.type} message."
          @messages[datapath_id.to_s] << msg
          maybe_send_handler :message_received, datapath_id, msg
        end

        case msg
        when Error
          maybe_send_handler :error, datapath_id, msg
        when EchoRequest
          maybe_send_handler :echo_request, datapath_id, msg
        when FeaturesReply
          maybe_send_handler :features_reply, datapath_id, msg
        when PacketIn
          maybe_send_handler :packet_in, datapath_id, msg
        when PortStatus
          case msg.reason
          when :add
            maybe_send_handler :port_add, datapath_id, msg
          when :delete
            maybe_send_handler :port_delete, datapath_id, msg
          when :modify
            maybe_send_handler :port_modify, datapath_id, msg
          # else
          end
        when FlowRemoved
          maybe_send_handler :flow_removed, datapath_id, msg
        # else
        end
      end
    end
  end
end
