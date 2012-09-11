require 'spec_helper'
require 'flapjack/jabber'

describe Flapjack::Jabber do

  let(:config) { {'server'   => 'example.com',
                  'port'     => '5222',
                  'jabberid' => 'flapjack@example.com',
                  'password' => 'password',
                  'alias'    => 'flapjack',
                  'rooms'    => ['flapjacktest@conference.example.com']
                 }
  }

  let(:stanza) { mock('stanza') }

  it "is initialized" do
    Socket.should_receive(:gethostname).and_return('thismachine')

    fj = Flapjack::Jabber.new(:config => config)
    fj.should_not be_nil
  end

  it "joins a chat room after connecting" do
    Socket.should_receive(:gethostname).and_return('thismachine')

    fj = Flapjack::Jabber.new(:config => config)

    fj.should_receive(:write).with(an_instance_of(Blather::Stanza::Presence))
    fj.should_receive(:write).with(an_instance_of(Blather::Stanza::Message))

    fj.on_ready(stanza)
  end

  it "receives an acknowledgement message"

  it "receives a message it doesn't understand"

  it "reconnects when disconnected (if not quitting)"

  it "writes a message to the jabber connection"

  it "prompts the blocking redis connection to quit"

  it "runs a blocking loop listening for notifications"

end