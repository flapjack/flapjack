require 'spec_helper'

describe Flapjack::Data::Tag, :redis => true do

  it "adds references to tags" do
    tags = Flapjack::Data::Tag.create('special', ['apple', 'button', 'carbon'])

    tags.should include('carbon')
    tags.should_not include('chocolate')

    tags.add('chocolate')
    tags.should include('chocolate')
  end

  it "deletes references from tags" do
    tags = Flapjack::Data::Tag.create('special', ['apple', 'button', 'carbon'])

    tags.should include('apple')
    tags.should include('button')

    tags.delete('button')
    tags.should include('apple')
    tags.should_not include('button')
  end

  it "lists references contained in a tag" do
    t1 = Flapjack::Data::Tag.create('special', ['apple', 'button', 'carbon'])

    t2 = Flapjack::Data::Tag.find('special')
    t2.should include('apple')
    t2.should include('carbon')
    t2.should_not include('chocolate')
  end

end
