require 'spec_helper'

describe Flapjack::Data::Tag, :redis => true do

  it "adds references to tags" do
    tags = Flapjack::Data::Tag.create('special', ['apple', 'button', 'carbon'], :redis => @redis)

    expect(tags).to include('carbon')
    expect(tags).not_to include('chocolate')

    tags.add('chocolate')
    expect(tags).to include('chocolate')
  end

  it "deletes references from tags" do
    tags = Flapjack::Data::Tag.create('special', ['apple', 'button', 'carbon'], :redis => @redis)

    expect(tags).to include('apple')
    expect(tags).to include('button')

    tags.delete('button')
    expect(tags).to include('apple')
    expect(tags).not_to include('button')
  end

  it "lists references contained in a tag" do
    t1 = Flapjack::Data::Tag.create('special', ['apple', 'button', 'carbon'], :redis => @redis)

    t2 = Flapjack::Data::Tag.find('special', :redis => @redis)
    expect(t2).to include('apple')
    expect(t2).to include('carbon')
    expect(t2).not_to include('chocolate')
  end

end
