require 'spec_helper'
require 'flapjack/logger'

describe Flapjack::Logger do

  let(:logger)     { double(::Logger) }

  let(:sys_logger) { double(::Logger) }
  let(:syslog)     { double(Syslog) }

  it "creates a logger logging to STDOUT and syslog" do
    expect(logger).to receive(:formatter=).with(an_instance_of(Proc))
    expect(logger).to receive(:level=).and_return(Logger::DEBUG)
    expect(logger).to receive(:add).with(2, nil, "Yowza!")
    expect(::Logger).to receive(:new).with(STDOUT).and_return(logger)

    expect(Syslog).to receive(:open).with('flapjack',
      (Syslog::Constants::LOG_PID | Syslog::Constants::LOG_CONS),
       Syslog::Constants::LOG_USER).and_return(syslog)
    expect(Syslog).to receive(:mask=).with(Syslog::LOG_UPTO(Syslog::Constants::LOG_ERR))
    expect(Syslog).to receive(:log).with(Syslog::Constants::LOG_WARNING, /\[WARN\] :: spec :: %s/, "Yowza!")
    expect(Syslog).to receive(:close)

    flogger = Flapjack::Logger.new('spec', 'level' => 'debug', 'syslog_errors' => 'true')
    flogger.warn "Yowza!"
  end

  it 'defaults to not logging via syslog' do
    expect(logger).to receive(:formatter=).with(an_instance_of(Proc))
    expect(logger).to receive(:level=).and_return(Logger::DEBUG)
    expect(logger).to receive(:add).with(2, nil, "Yowza!")
    expect(::Logger).to receive(:new).with(STDOUT).and_return(logger)

    expect(Syslog).not_to receive(:open)

    flogger = Flapjack::Logger.new('spec', 'level' => 'debug')
    flogger.warn "Yowza!"
  end

end
