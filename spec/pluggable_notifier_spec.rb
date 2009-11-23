require File.join(File.dirname(__FILE__), '..', 'lib', 'flapjack', 'applications', 'notifier')
require File.join(File.dirname(__FILE__), 'helpers')

describe "notifier application" do 

  it "should have a simple interface to start the notifier" do 
    options = {:notifiers => {}}
    app = Flapjack::Notifier::Application.run(options)
  end

  it "should log when loading a notifier" do 
    options = { :notifiers => {:mailer => {}}, 
                :logger => MockLogger.new,
                :notifier_directories => [File.join(File.dirname(__FILE__),'notifier-directories', 'spoons')]}
    app = Flapjack::Notifier::Application.run(options)
    app.log.messages.find {|msg| msg =~ /loading the mailer notifier/i}.should_not be_nil
  end

  it "should warn if a specified notifier doesn't exist" do 
    options = { :notifiers => {:nonexistant => {}}, 
                :logger => MockLogger.new }
    app = Flapjack::Notifier::Application.run(options)
    app.log.messages.find {|msg| msg =~ /Flapjack::Notifiers::Nonexistant doesn't exist/}.should_not be_nil
  end

  it "should give precedence to notifiers in user-specified notifier directories" do 
    options = { :notifiers => {:mailer => {}}, 
                :logger => MockLogger.new,
                :notifier_directories => [File.join(File.dirname(__FILE__),'notifier-directories', 'spoons')]}
    app = Flapjack::Notifier::Application.run(options)
    app.log.messages.find {|msg| msg =~ /spoons/i}.should_not be_nil
    # this will raise an exception if the notifier directory isn't specified,
    # as the mailer notifier requires several arguments anyhow
  end

  it "should pass global notifier config options to each notifier"

  it "should merge recipients from a file and a specified list of recipients" do
    options = { :notifiers => {:mailer => {}}, 
                :logger => MockLogger.new,
                :notifier_directories => [File.join(File.dirname(__FILE__),'notifier-directories', 'spoons')],
                :recipients => {:filename => File.join(File.dirname(__FILE__), 'fixtures', 'recipients.yaml'),
                                :list => [{:name => "Spoons McDoom"}]}}
    app = Flapjack::Notifier::Application.run(options)
    app.log.messages.find {|msg| msg =~ /fixtures\/recipients\.yaml/i}.should_not be_nil
    # should have one specified in options[:recipients][:list], and some from specified recipients.yaml
    app.recipients.size.should > 1
  end


end

def puts(*args) ; end
