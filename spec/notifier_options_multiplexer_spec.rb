require File.join(File.dirname(__FILE__), '..', 'lib', 'flapjack', 'cli', 'notifier')

describe "notifier options multiplexer" do 

  before(:all) do
    @config_filename     = File.join(File.dirname(__FILE__), 'configs', 'flapjack-notifier.ini')
    @recipients_filename = File.join(File.dirname(__FILE__), 'configs', 'recipients.ini')
    
    @couchdb_config_filename = File.join(File.dirname(__FILE__), 'configs', 'flapjack-notifier-couchdb.ini')
  end

  it "should setup notifier options from specified config file" do 
    args = ["-c", @config_filename, "-r", @recipients_filename]
    config = Flapjack::Notifier::Options.parse(args)
    config.notifiers.each do |notifier|
      %w(mailer xmpp).include?(notifier.keys.first)
    end

    config.notifier_directories.each do |dir|
      %w(/usr/lib/flapjack/notifiers/ /path/to/my/notifiers).include?(dir)
    end
  end

  it "should setup beanstalkd transport options from specified config file" do 
    args = ["-c", @config_filename, "-r", @recipients_filename]
    config = Flapjack::Notifier::Options.parse(args)
    config.transport.backend.should == "beanstalkd"
    config.transport.host.should == "localhost"
    config.transport.port.should == "11300"
  end

  it "should setup datamapper persistence options from specified config file" do 
    args = ["-c", @config_filename, "-r", @recipients_filename]
    config = Flapjack::Notifier::Options.parse(args)
    config.persistence.backend.should == "datamapper"
    config.persistence.uri.should == "sqlite3:///tmp/flapjack.db"
  end

  it "should setup couchdb persistence backend from specified config file" do 
    args = [ "-c", @couchdb_config_filename, "-r", @recipients_filename ]
    config = Flapjack::Notifier::Options.parse(args)
    config.persistence.backend.should == "couchdb"
    config.persistence.host.should == "localhost"
    config.persistence.port.should == "5984"
    config.persistence.username.should == "spoons"
    config.persistence.password.should == "doom"
  end

end


