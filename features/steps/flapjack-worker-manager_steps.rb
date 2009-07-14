__DIR__ = File.expand_path(File.join(File.dirname(__FILE__), '..', '..'))
bin_path = File.join(__DIR__, 'bin')

Given /^the (.+) is on my path$/ do |command|
  silent_system("test -e #{bin_path}/#{command}").should be_true
end

When /^I run "([^\"]*)"$/ do |cmd|
  command = "#{bin_path}/#{cmd}"
  silent_system(command).should be_true
end

Then /^(\d+) instances of "([^\"]*)" should be running$/ do |number, command|
  output = `ps -eo cmd |grep ^#{command}`
  output.split.size.should >= number.to_i
end

Given /^there are (\d+) instances of the flapjack\-worker running$/ do |number|
  command = "#{bin_path}/flapjack-worker-manager start --workers=5"
  silent_system(command).should be_true
end
