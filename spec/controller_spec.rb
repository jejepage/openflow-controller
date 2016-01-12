describe Controller do
  before(:all) do
    class MyCtl < Controller
      attr_reader :start_args

      def start(*args)
        @start_args = args
      end
    end

    @ctl = Controller.create
    Thread.new { @ctl.run('127.0.0.1', 4242, 'Hello World!', 42) }
  end

  it 'should create a subclass when inherited' do
    expect(@ctl.class).to be(MyCtl)
    expect(@ctl.logger.level).to eq(Logger::INFO)
  end

  it 'should handle start' do
    expect(@ctl.start_args).to eq(['Hello World!', 42])
  end

  it 'should start a switch when it receives a connection' do
    socket = TCPSocket.new '127.0.0.1', 4242

    # Exchange Hello messages
    socket.write Hello.new.to_binary_s
    sleep(0.001)
    msg = Parser.read socket
    expect(msg.class).to be(Hello)

    # Exchange Echo messages
    msg = Parser.read socket
    expect(msg.class).to be(EchoRequest)
    socket.write msg.to_reply.to_binary_s

    # Exchange Features messages
    msg = Parser.read socket
    expect(msg.class).to be(FeaturesRequest)
    socket.write FeaturesReply.new(datapath_id: 1).to_binary_s

    sleep(0.001)
    expect(@ctl.switches.length).to eq(1)
    expect(@ctl.switches.first.datapath_id).to eq(1)
    expect(@ctl.datapath_ids).to eq([1])
  end
end
