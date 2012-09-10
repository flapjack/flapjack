require 'spec_helper'
require 'flapjack/jabber'

describe Flapjack::Jabber do

  let(:stanza) { mock('stanza') }

  it "is initialized"

  it "joins a chat room after connecting"

  it "receives an acknowledgement message"

  it "receives a message it doesn't understand"

  it "reconnects when disconnected (if not quitting)"

  it "writes a message to the jabber connection"

  it "prmopts the blocking redis connection to quit"

  it "runs a blocking loop listening for notifications"

end