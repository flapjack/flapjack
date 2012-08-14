require 'spec_helper'
require 'flapjack/pikelet'

describe Flapjack::Pikelet do

  context "non-evented" do

    let(:redis) { mock('Redis') }

    class Breakfast
      include Flapjack::Pikelet     
    end
      
    it "should bootstrap an including class" do
      
      ::Redis.should_receive(:new).and_return(redis)
      
      b = Breakfast.new
      b.bootstrap
      
      b.should respond_to(:persistence)
      b.persistence.should == redis
      
      # FIXME
  #    b.should_respond_to(:logger)
  #    b.logger.should == 
    end
    
  
    it "should show when it has not been bootstrapped" do
      b = Breakfast.new
      b.should_not be_bootstrapped
    end
  
    it "should show when it has been bootstrapped" do
      ::Redis.should_receive(:new).and_return(redis)
      
      b = Breakfast.new
      b.bootstrap
      b.should be_bootstrapped
    end

  end

end