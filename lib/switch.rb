require 'openflow-protocol'

class OFSwitch
  attr_reader :controller, :features_reply

  def initialize(controller, socket)
    @controller = controller
    @socket     = socket
    begin
      exchange_hello_messages
      exchange_echo_messages
      exchange_features_messages
    rescue => exception
      controller.logger.debug "Switch error: #{exception}."
      raise exception
    end
  end

  def send(msg)
    @socket.write msg.to_binary_s
  end

  def receive
    OFParser.read @socket
  end

  def datapath_id
    @features_reply.datapath_id
  end

  private

  def exchange_hello_messages
    controller.logger.debug 'Wait OFPT_HELLO.'
    fail unless receive.is_a?(OFHello)
    send OFHello.new
  end

  def exchange_echo_messages
    send OFEchoRequest.new
    controller.logger.debug 'Wait OFPT_ECHO_REPLY.'
    fail unless receive.is_a?(OFEchoReply)
  end

  def exchange_features_messages
    send OFFeaturesRequest.new
    controller.logger.debug 'Wait OFPT_FEATURES_REPLY.'
    @features_reply = receive
    controller.logger.debug "OFPT_FEATURES_REPLY.datapath_id: #{datapath_id}."
    fail unless @features_reply.is_a?(OFFeaturesReply)
  end
end
