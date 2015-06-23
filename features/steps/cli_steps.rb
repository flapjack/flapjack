
Given /^PENDING/ do
  pending
end

Given /^a file named "([^"]*)" with:$/ do |file_name, file_content|
  write_file(file_name, file_content)
end

Given /^a fifo named "([^"]*)" exists$/ do |fifo_name|
  create_fifo(fifo_name)
end

When /^I ((?:re)?start|stop) (\S+)( \(via bundle exec\))? with `(.+)`$/ do |start_stop_restart, exe,  bundle_exec, cmd|
  @daemons_output      ||= []
  @daemons_exit_status ||= []

  @root = Pathname.new(File.dirname(__FILE__)).parent.parent.expand_path
  command = "#{bundle_exec ? 'bundle exec ' : ''}#{@root.join('bin')}/#{cmd}"

  # # enable debugging output from spawn_process etc
  # @debug = true

  case start_stop_restart
  when 'start'
    @process_h = spawn_process(command)
  when 'stop', 'restart'
    @daemons_output << `#{command}`
    @daemons_exit_status << $?
  end
  puts "output: #{@daemons_output.join(', ')}, exit statuses: #{@daemons_exit_status}" if @debug
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
  max_attempts = seconds.to_i * 10

  if @debug
    puts "should #{start_stop_restart} within #{seconds} seconds..."
    puts "pid:  #{pid}, max_attempts: #{max_attempts}"
  end

  case start_stop_restart
  when 'start'
    begin
      Process.kill(0, pid)
      running = true
    rescue Errno::EINVAL, Errno::ESRCH, RangeError, Errno::EPERM => e
      puts "rescued error from kill: #{e.class} - #{e.message}" if @debug
      attempts += 1; sleep 0.1; retry if attempts < max_attempts
      running = false
    end
    expect(running).to be true
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
    expect(running).to be false
  when 'restart'
    read_pid = nil
    while attempts < max_attempts
      time_and_pid = time_and_pid_from_file("tmp/cucumber_cli/#{exe}.pid")
      read_pid = time_and_pid.last
      break if read_pid != pid
      attempts += 1; sleep 0.1
    end
    expect(read_pid).not_to eq(pid)
  end

end
