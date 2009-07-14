__DIR__ = File.expand_path(File.join(File.dirname(__FILE__), '..', '..'))
bin_path = File.join(__DIR__, 'bin')

Given /^there are no instances of flapjack\-notifier running$/ do
  command = "#{bin_path}/flapjack-notifier-manager stop"
  silent_system(command)

  sleep 0.5 # wait for the notifier manager

  output = `ps -eo cmd |grep ^flapjack-notifier`
  output.split.size.should == 0
end

Given /^there is an instance of the flapjack\-notifier running$/ do
  command = "#{bin_path}/flapjack-notifier-manager start"
  command += " --recipients spec/fixtures/recipients.yaml --config spec/fixtures/flapjack-notifier.yaml"
  silent_system(command).should be_true
  
  sleep 0.5 # again, waiting for the notifier manager

  output = `ps -eo cmd |grep ^flapjack-notifier`
  output.split.size.should == 1
end

