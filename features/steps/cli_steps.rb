
Given /^PENDING/ do
  pending
end

Given /^a file named "([^"]*)" with:$/ do |file_name, file_content|
  write_file(file_name, file_content)
end

When /^I ((?:re)?start|stop) (\S+)( \(daemonised\))? with `(.+)`$/ do |start_stop_restart, exe, daemonise, cmd|
  @root = Pathname.new(File.dirname(__FILE__)).parent.parent.expand_path
  command = "#{@root.join('bin')}/#{cmd}"

  case start_stop_restart
  when 'start'
    @process_h = spawn_process(command,
                  :daemon_pidfile => (daemonise.nil? || daemonise.empty?) ? nil : "tmp/cucumber_cli/#{exe}_d.pid")
  when 'stop', 'restart'
    `#{command}`
  end
end

When /^I send a SIG(\w+) to the (?:\S+) process$/ do |signal|
  process = @process_h[:process]
  pid     = process ? process.pid : @process_h[:pid]
  Process.kill(signal, pid)
end

Then /^(\S+) should ((?:re)?start|stop) within (\d+) seconds$/ do |exe, start_stop_restart, seconds|
  process = @process_h[:process]
  pid     = process ? process.pid : @process_h[:pid]
  running = nil
  attempts = 0
  max_attempts = seconds.to_i * 200

  case start_stop_restart
  when 'start'
    begin
      Process.kill(0, pid)
      running = true
    rescue Errno::EINVAL, Errno::ESRCH, RangeError, Errno::EPERM => e
      attempts += 1; sleep 0.1; retry if attempts < max_attempts
      running = false
    end
    running.should be_true
  when 'stop'
    if process
      # it's a child process, so we can use waitpid
      begin
        Timeout::timeout(seconds.to_i) do
          Process.waitpid(pid)
          running = false
        end
      rescue Timeout::Error
        running = true
      end
    else
      # started via dante, so we'll need to monitor externally
      while (running != false) && (attempts < max_attempts)
        begin
          Process.kill(0, pid)
          attempts += 1; sleep 0.1
          running = true
        rescue Errno::EINVAL, Errno::ESRCH, RangeError, Errno::EPERM => e
          running = false
        end
      end
    end
    running.should be_false
  when 'restart'
    read_pid = nil
    while attempts < max_attempts
      time_and_pid = time_and_pid_from_file("tmp/cucumber_cli/#{exe}_d.pid")
      read_pid = time_and_pid.last
      break if read_pid != pid
      attempts += 1; sleep 0.1
    end
    read_pid.should_not == pid
  end

end
