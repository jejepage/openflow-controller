class FDB
  class Entry
    DEFAULT_AGE_MAX = 300

    attr_reader :mac, :port_no

    def initialize(mac, port_no, age_max = DEFAULT_AGE_MAX)
      @mac     = mac
      @age_max = age_max
      update port_no
    end

    def update(port_no)
      @port_no     = port_no
      @last_update = Time.now
    end

    def aged_out?
      Time.now - @last_update > @age_max
    end
  end

  def initialize
    @db = {}
  end

  def lookup(mac)
    entry = @db[mac]
    entry && entry.port_no
  end

  def learn(mac, port_no)
    entry = @db[mac]
    if entry
      entry.update port_no
    else
      @db[mac] = Entry.new(mac, port_no)
    end
  end

  def age
    @db.delete_if { |_mac, entry| entry.aged_out? }
  end
end

class LearningSwitch < OFController
  timer_event :age_fdb, interval: 5.sec

  def start(_argv)
    @fdb = FDB.new
  end

  def packet_in(datapath_id, msg)
    @fdb.learn(msg.parsed_data.mac_source, msg.in_port)
    logger.debug "Learned #{msg.parsed_data.mac_source} on #{msg.in_port}."
    flow_mod_and_packet_out(datapath_id, msg)
  end

  def flow_removed(datapath_id, msg)
    logger.info "Flow #{datapath_id} removed (#{msg.reason})."
  end

  def age_fdb
    @fdb.age
  end

  private

  def flow_mod(datapath_id, msg, port_no)
    logger.debug "FlowMod add #{datapath_id} on #{port_no}."
    send_message datapath_id, OFFlowMod.new(
      xid: msg.xid,
      match: {
        wildcards: [
          :in_port,
          :mac_protocol,
          :mac_source,
          :vlan_id,
          :vlan_pcp,
          :ip_tos,
          :ip_protocol,
          :ip_source_all,
          :ip_destination_all,
          :source_port,
          :destination_port
        ],
        mac_destination: msg.parsed_data.mac_destination
      },
      idle_timeout: 100,
      priority: 0x6000,
      buffer_id: msg.buffer_id,
      flags: [:send_flow_removed],
      actions: [OFActionOutput.new(port: port_no)]
    )
  end

  def packet_out(datapath_id, msg, port_no)
    logger.debug "PacketOut #{datapath_id} on #{port_no}."
    send_message datapath_id, OFPacketOut.new(
      xid: msg.xid,
      buffer_id: msg.buffer_id,
      in_port: msg.in_port,
      actions: [OFActionOutput.new(port: port_no)]
    )
  end

  def flow_mod_and_packet_out(datapath_id, msg)
    port_no = @fdb.lookup(msg.parsed_data.mac_destination)
    if port_no
      flow_mod(datapath_id, msg, port_no)
    else
      packet_out(datapath_id, msg, :flood)
    end
  end
end
