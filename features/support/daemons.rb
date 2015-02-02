#!/usr/bin/env ruby

def red(text);    "\e[0;31;49m#{text}\e[0m"; end
def yellow(text); "\e[0;33;49m#{text}\e[0m"; end
def green(text);  "\e[0;32;49m#{text}\e[0m"; end
def blue(text);   "\e[0;34;49m#{text}\e[0m"; end

After('@process') do
  kill_lingering_processes
end

PROCESSES = []

def current_dir
  File.join(*dirs)
end

def dirs
  @dirs ||= ['tmp', 'cucumber_cli']
end

def write_file(file_name, file_content)
  _create_file(file_name, file_content, false)
end

def create_fifo(fifo_name)
  unless File.pipe?(fifo_name)
    system("mkfifo #{fifo_name}")
  end
end

def _create_file(file_name, file_content, check_presence)
  in_current_dir do
    raise "expected #{file_name} to be present" if check_presence && !File.file?(file_name)
    _mkdir(File.dirname(file_name))
    File.open(file_name, 'w') { |f| f << file_content }
  end
end

def in_current_dir(&block)
  _mkdir(current_dir)
  Dir.chdir(current_dir, &block)
end

def _mkdir(dir_name)
  FileUtils.mkdir_p(dir_name) unless File.directory?(dir_name)
end

def kill_lingering_processes
  PROCESSES && PROCESSES.each do |process_h|
    process = process_h[:process]
    pid     = process ? process.pid : process_h[:pid]
    command = process_h[:command]

    begin
      puts yellow("Killing process #{pid}") if @debug
      Process.kill("KILL", pid)
    rescue Errno::ESRCH
      puts green("Process #{pid} has already exited.") if @debug
    end

    if @debug && !process.nil?
      puts blue("Output from #{pid} #{command}\n")
      puts process.read + "\n"
    end
  end
  puts yellow("Done killing processes") if @debug
  PROCESSES.clear
end

def time_and_pid_from_file(pid_file, cutoff_time = nil)
  return unless File.exists?(pid_file)
  file_time = File.mtime(pid_file)
  return unless cutoff_time.nil? || (file_time.to_i >= cutoff_time.to_i)
  [file_time, File.read(pid_file).strip.to_i]
end

def spawn_process(command, opts={})
  puts yellow("Running: #{command}") if @debug

  process_h = nil

  file = opts[:daemon_pidfile]

  process = IO.popen(command)
  pid = process.pid
  process_h = {:process => process, :command => command}

  raise "failed to spawn process #{command}" if process_h.nil?

  PROCESSES << process_h

  process_h
end

at_exit do
  kill_lingering_processes
end
