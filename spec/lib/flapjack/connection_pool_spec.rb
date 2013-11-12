require 'spec_helper'

require 'flapjack/connection_pool'

describe Flapjack::ConnectionPool do

  let(:canary)   { double('canary') }

  let(:init)     { Proc.new { canary.chirp  } }
  let(:shutdown) { Proc.new { canary.expire } }

  it "initialises a defined number of connections" do
    canary.should_receive(:chirp).exactly(3).times

    Flapjack::ConnectionPool.new(:size => 3,
      :init => init, :shutdown => shutdown)
  end

  it "allows checkout/checkin of a connection" do
    birdsong_1 = double('birdsong_1')
    birdsong_2 = double('birdsong_2')
    canary.should_receive(:chirp).twice.and_return(birdsong_1, birdsong_2)

    pool = Flapjack::ConnectionPool.new(:size => 2,
      :init => init, :shutdown => shutdown)
    conn = pool.checkout
    conn.should == birdsong_2
    pool.checkin(conn)
  end

  it "wraps checkout/checkin of a connection using 'with'" do
    birdsong_1 = double('birdsong_1')
    birdsong_2 = double('birdsong_2')
    canary.should_receive(:chirp).twice.and_return(birdsong_1, birdsong_2)

    pool = Flapjack::ConnectionPool.new(:size => 2,
      :init => init, :shutdown => shutdown)
    pool.with do |conn|
      conn.should == birdsong_2
    end
  end

  it "shuts down all its connections" do
    canary.should_receive(:chirp).exactly(3).times
    canary.should_receive(:expire).exactly(3).times

    pool = Flapjack::ConnectionPool.new(:size => 3,
      :init => init, :shutdown => shutdown)
    pool.shutdown
  end

  it "adjusts the size of an initialised connection pool up" do
    canary.should_receive(:chirp).exactly(5).times

    pool = Flapjack::ConnectionPool.new(:size => 3,
      :init => init, :shutdown => shutdown)
    pool.adjust_size(5)
  end

  it "adjusts the size of an initialised connection pool down" do
    canary.should_receive(:chirp).exactly(3).times
    canary.should_receive(:expire).once

    pool = Flapjack::ConnectionPool.new(:size => 3,
      :init => init, :shutdown => shutdown)
    pool.adjust_size(2)
  end

end
