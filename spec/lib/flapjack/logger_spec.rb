require 'spec_helper'
require 'flapjack/pikelet'

describe Flapjack::Logger do

  # let(:logger)     { mock(Log4r::Logger) }
  # let(:stdout_out) { mock('stdout_out') }
  # let(:syslog_out) { mock('syslog_out') }

  it "creates a log4r logger"

  it "changes the logging level via config hash"

  it "passes a log command to its log4r logger"

  # def setup_logger(type)
  #   formatter = mock('Formatter')
  #   Log4r::PatternFormatter.should_receive(:new).with(
  #     :pattern => "[%l] %d :: #{type} :: %m",
  #     :date_pattern => "%Y-%m-%dT%H:%M:%S%z").and_return(formatter)

  #   stdout_out.should_receive(:formatter=).with(formatter)
  #   syslog_out.should_receive(:formatter=).with(formatter)

  #   Log4r::StdoutOutputter.should_receive(:new).and_return(stdout_out)
  #   Log4r::SyslogOutputter.should_receive(:new).and_return(syslog_out)
  #   logger.should_receive(:add).with(stdout_out)
  #   logger.should_receive(:add).with(syslog_out)
  #   Log4r::Logger.should_receive(:new).and_return(logger)
  # end

end