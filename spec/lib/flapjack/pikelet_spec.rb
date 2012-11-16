require 'spec_helper'
require 'flapjack/pikelet'

describe Flapjack::Pikelet do

  let(:stdout) { mock('StdoutOutputter') }
  let(:syslogout) { mock('SyslogOutputter') }
  let(:logger) { mock('Logger') }

  class Breakfast
    include Flapjack::Pikelet
  end

  it "should bootstrap an including class" do

    formatter = mock('Formatter')
    Log4r::PatternFormatter.should_receive(:new).with(
      :pattern => "[%l] %d :: breakfast :: %m",
      :date_pattern => "%Y-%m-%dT%H:%M:%S%z").and_return(formatter)

    stdout.should_receive(:formatter=).with(formatter)
    syslogout.should_receive(:formatter=).with(formatter)

    Log4r::StdoutOutputter.should_receive(:new).and_return(stdout)
    Log4r::SyslogOutputter.should_receive(:new).and_return(syslogout)
    logger.should_receive(:add).with(stdout)
    logger.should_receive(:add).with(syslogout)
    Log4r::Logger.should_receive(:new).and_return(logger)

    b = Breakfast.new
    b.bootstrap

    b.should respond_to(:logger)
    b.logger.should equal(logger)
  end

end