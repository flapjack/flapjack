require 'spec_helper'
require 'flapjack/data/semaphore'

describe 'Flapjack::Data::Semaphore', :redis => true do

  it "obtains a lock that locks" do
    options = {:expiry => 60}
    lock_1 = Flapjack::Data::Semaphore.new('fooey', options)
    expect(lock_1.class).to eq(Flapjack::Data::Semaphore)
    expect{Flapjack::Data::Semaphore.new('fooey', options)}.to raise_error(Flapjack::Data::Semaphore::ResourceLocked)
  end

  it "releases a lock" do
    options = {:expiry => 60}
    lock_1 = Flapjack::Data::Semaphore.new('fooey', options)
    expect(lock_1.class).to eq(Flapjack::Data::Semaphore)
    lock_1.release

    lock_2 = Flapjack::Data::Semaphore.new('fooey', options)
    expect(lock_2.class).to eq(Flapjack::Data::Semaphore)
  end

end

