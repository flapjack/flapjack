require 'spec_helper'
require 'flapjack/logger'

describe Flapjack::Logger do

  let(:logger)     { double(::Logger) }

  let(:sys_logger) { double(::Logger) }
  let(:syslog)     { double(Syslog) }

  it "creates a logger logging to STDOUT and syslog" do
    logger.should_receive(:formatter=).with(an_instance_of(Proc))
    logger.should_receive(:level=).and_return(Logger::DEBUG)
    logger.should_receive(:add).with(2, nil, "Yowza!")
    ::Logger.should_receive(:new).with(STDOUT).and_return(logger)

    Syslog.should_receive(:open).with('flapjack',
      (Syslog::Constants::LOG_PID | Syslog::Constants::LOG_CONS),
       Syslog::Constants::LOG_USER).and_return(syslog)
    Syslog.should_receive(:mask=).with(Syslog::LOG_UPTO(Syslog::Constants::LOG_ERR))
    Syslog.should_receive(:log).with(Syslog::Constants::LOG_WARNING, /\[WARN\] :: spec :: %s/, "Yowza!")
    Syslog.should_receive(:close)

    flogger = Flapjack::Logger.new('spec', 'level' => 'debug', 'syslog_errors' => 'true')
    flogger.warn "Yowza!"
  end

  it 'defaults to not logging via syslog' do
    logger.should_receive(:formatter=).with(an_instance_of(Proc))
    logger.should_receive(:level=).and_return(Logger::DEBUG)
    logger.should_receive(:add).with(2, nil, "Yowza!")
    ::Logger.should_receive(:new).with(STDOUT).and_return(logger)

    Syslog.should_not_receive(:open)

    flogger = Flapjack::Logger.new('spec', 'level' => 'debug')
    flogger.warn "Yowza!"
  end

end
