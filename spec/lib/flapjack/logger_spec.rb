require 'spec_helper'

describe Flapjack::Logger do

  let(:logger)     { mock(::Logger) }

  let(:sys_logger) { mock(::Logger) }
  let(:syslog)     { mock(Syslog) }

  it "creates a logger logging to STDOUT and syslog" do
    logger.should_receive(:formatter=).with(an_instance_of(Proc))
    logger.should_receive(:level=).and_return(Logger::DEBUG)
    logger.should_receive(:warn).with("Yowza!")
    ::Logger.should_receive(:new).with(STDOUT).and_return(logger)

    if Syslog.const_defined?('Logger', false)
      sys_logger.should_receive(:formatter=).with(an_instance_of(Proc))
      sys_logger.should_receive(:level=).with(Logger::DEBUG)
      sys_logger.should_receive(:warn).with("Yowza!")
      Syslog.const_get('Logger', false).should_receive(:new).with('flapjack').and_return(sys_logger)
    else
      syslog.should_receive(:log).with(Syslog::Constants::LOG_WARNING, /\[WARN\] :: spec :: %s/, "Yowza!")
      Syslog.should_receive(:"opened?").and_return(false)
      Syslog.should_receive(:open).with('flapjack',
        (Syslog::Constants::LOG_PID | Syslog::Constants::LOG_CONS),
         Syslog::Constants::LOG_USER).and_return(syslog)
      Syslog.should_receive(:mask=).with(Syslog::LOG_UPTO(Syslog::Constants::LOG_DEBUG))
    end

    flogger = Flapjack::Logger.new('spec', 'level' => 'debug')
    flogger.warn "Yowza!"
  end

end
