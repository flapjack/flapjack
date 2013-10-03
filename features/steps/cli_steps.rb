
Given /^PENDING/ do
  pending
end

Given /^flapjack is( not)? running( \(restarted\))?$/ do |not_run, restart|
  output = `ps -e -o command |grep "^ruby.*flapjack.*#{restart ? 'restart' : 'start'}.*$"`
  if not_run
    output.size.should == 0
  else
    output.size.should be > 0
  end
end

When /^I (?:re)?start a daemon with `(.+)`$/ do |cmd|
  @root = Pathname.new(File.dirname(__FILE__)).parent.parent.expand_path
  command = "#{@root.join('bin')}/#{cmd}"

  @pipe = spawn_daemon(command)
end

When /^I send a SIG(\w+) to the flapjack process$/ do |signal|
  kill_latest_daemon(signal)
end

When /^I wait until flapjack is( not)? running( \(restarted\))?, for a maximum of (\d+) seconds$/ do |stopping, restart, seconds|
  Timeout::timeout(exit_timeout) do
    loop do
      output = if restart
        `ps -e -o command |grep "^ruby.*flapjack.*restart.*$"`
      else
        `ps -e -o command |grep "^ruby.*flapjack.*start.*$"`
      end
      break if (stopping ? (output.size == 0) : (output.size > 0))
      sleep 0.1
    end
  end
end

Then /^flapjack should( not)? be running( \(restarted\))?$/ do |not_run, restart|
  step "flapjack is#{not_run ? ' not' : ''} running#{restart ? ' (restarted)' : ''}"
end
