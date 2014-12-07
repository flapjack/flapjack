require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::Checks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:check) { double(Flapjack::Data::Check, :id => check_data[:id]) }
  let(:tag)   { double(Flapjack::Data::Tag, :id => tag_data[:name]) }

  let(:check_presenter) { double(Flapjack::Gateways::JSONAPI::Helpers::CheckPresenter) }

  it "creates a check" do
    expect(Flapjack::Data::Check).to receive(:lock).
      with(Flapjack::Data::State, Flapjack::Data::Tag).and_yield

    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    full_ids = double('full_ids')
    expect(full_ids).to receive(:associated_ids_for).with(:state).and_return({check.id => nil})
    expect(full_ids).to receive(:associated_ids_for).with(:tags).and_return({check.id => []})
    expect(Flapjack::Data::Check).to receive(:intersect).
      with(:id => [check_data[:id]]).exactly(3).times.and_return(empty_ids, full_ids)

    expect(check).to receive(:invalid?).and_return(false)
    expect(check).to receive(:save).and_return(true)
    expect(Flapjack::Data::Check).to receive(:new).with(check_data).
      and_return(check)

    expect(check).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(check_data)

    post "/checks", Flapjack.dump_json(:checks => check_data), jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json(:checks => check_data.merge(:links =>
      {:state => nil,
       :tags => []}
    )))
  end

  it "creates a check with a linked tag" do
    expect(Flapjack::Data::Check).to receive(:lock).
      with(Flapjack::Data::State, Flapjack::Data::Tag).and_yield
    empty_ids = double('empty_ids')
    expect(empty_ids).to receive(:ids).and_return([])
    full_ids = double('full_ids')
    expect(full_ids).to receive(:associated_ids_for).with(:state).and_return({check.id => nil})
    expect(full_ids).to receive(:associated_ids_for).with(:tags).and_return({check.id => [tag.id]})
    expect(Flapjack::Data::Check).to receive(:intersect).
      with(:id => [check_data[:id]]).exactly(3).times.and_return(empty_ids, full_ids)

    expect(check).to receive(:invalid?).and_return(false)
    expect(check).to receive(:save).and_return(true)
    expect(Flapjack::Data::Check).to receive(:new).with(check_data).
      and_return(check)

    expect(Flapjack::Data::Tag).to receive(:find_by_ids!).with(tag.id).
      and_return([tag])
    check_tags = double('check_tags')
    expect(check_tags).to receive(:add).with(tag)
    expect(check).to receive(:tags).and_return(check_tags)

    expect(check).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(check_data)

    post "/checks", Flapjack.dump_json(:checks => check_data.merge(:links =>
      {:tags => [tag.id]})), jsonapi_post_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq(Flapjack.dump_json(:links => {
        'checks.tags' => 'http://example.org/tags/{checks.tags}',
      },
      :checks => check_data.merge(:links =>
      {:state => nil,
       :tags => [tag.id]}
    )))
  end

  it "retrieves paginated checks" do
    meta = {
      :pagination => {
        :page        => 1,
        :per_page    => 20,
        :total_pages => 1,
        :total_count => 1
      }
    }

    expect(Flapjack::Data::Check).to receive(:count).and_return(1)

    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).
      and_return([check])
    expect(Flapjack::Data::Check).to receive(:sort).
      with(:name).and_return(sorted)

    full_ids = double('full_ids')
    expect(full_ids).to receive(:associated_ids_for).with(:state).and_return({check.id => nil})
    expect(full_ids).to receive(:associated_ids_for).with(:tags).and_return({check.id => []})
    expect(Flapjack::Data::Check).to receive(:intersect).
      with(:id => [check_data[:id]]).twice.and_return(full_ids)

    expect(check).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(check_data)

    get '/checks'
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:checks => [check_data.merge(:links => {
      :state => nil,
      :tags => []})], :meta => meta))
  end

  it "retrieves one check" do
    expect(Flapjack::Data::Check).to receive(:find_by_id!).
      with(check.id).and_return(check)

    full_ids = double('full_ids')
    expect(full_ids).to receive(:associated_ids_for).with(:state).and_return({check.id => nil})
    expect(full_ids).to receive(:associated_ids_for).with(:tags).and_return({check.id => []})
    expect(Flapjack::Data::Check).to receive(:intersect).
      with(:id => [check_data[:id]]).twice.and_return(full_ids)

    expect(check).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(check_data)

    get "/checks/#{check.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:checks => check_data.merge(:links =>
      {:state => nil,
       :tags => []}
    )))
  end

  it "retrieves one check with a subset of fields" do
    expect(Flapjack::Data::Check).to receive(:find_by_id!).
      with(check.id).and_return(check)

    full_ids = double('full_ids')
    expect(full_ids).to receive(:associated_ids_for).with(:state).and_return({check.id => nil})
    expect(full_ids).to receive(:associated_ids_for).with(:tags).and_return({check.id => []})
    expect(Flapjack::Data::Check).to receive(:intersect).
      with(:id => [check_data[:id]]).twice.and_return(full_ids)

    expect(check).to receive(:as_json).with(:only => [:name, :enabled, :id]).
      and_return(check_data)

    get "/checks/#{check.id}?fields=name,enabled"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:checks => check_data.merge(:links =>
        {:state => nil, :tags => []})))
  end

  it "retrieves one check and all its linked tag records" do
    expect(Flapjack::Data::Check).to receive(:find_by_id!).
      with(check.id).and_return(check)

    checks = double('checks')
    expect(checks).to receive(:associated_ids_for).with(:state).and_return({check.id => nil})
    expect(checks).to receive(:associated_ids_for).with(:tags).
      and_return(check.id => [tag.id])
    expect(Flapjack::Data::Check).to receive(:intersect).
      with(:id => [check.id]).twice.and_return(checks)

    expect(Flapjack::Data::Tag).to receive(:find_by_ids!).
      with(tag.id).and_return([tag])

    full_tag_ids = double('full_tag_ids')
    expect(full_tag_ids).to receive(:associated_ids_for).with(:checks).and_return({tag.id => [check.id]})
    expect(full_tag_ids).to receive(:associated_ids_for).with(:rules).and_return({tag.id => []})
    expect(Flapjack::Data::Tag).to receive(:intersect).
      with(:id => [tag.id]).twice.and_return(full_tag_ids)

    full_check_ids = double('full_check_ids')
    expect(full_check_ids).to receive(:associated_ids_for).with(:tags).and_return({check.id => [tag.id]})
    expect(Flapjack::Data::Check).to receive(:intersect).
      with(:id => [check.id]).and_return(full_check_ids)

    expect(tag).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(tag_data)

    expect(check).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(check_data)

    get "/checks/#{check.id}?include=tags"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:links => {
      'checks.tags' => 'http://example.org/tags/{checks.tags}',
      'tags.checks' => 'http://example.org/checks/{tags.checks}',
      },
      :checks => check_data.merge(:links => {:state => nil, :tags => [tag.id]}),
      :linked => {:tags => [tag_data.merge(:links => {
        :checks => [check.id],
        :rules => []
      })]}))
  end

  it "retrieves several checks" do
    check_2 = double(Flapjack::Data::Check, :id => check_2_data[:id])

    sorted = double('sorted')
    expect(sorted).to receive(:find_by_ids!).
      with(check.id, check_2.id).and_return([check, check_2])
    expect(Flapjack::Data::Check).to receive(:sort).with(:name).and_return(sorted)

    full_ids = double('full_ids')
    expect(full_ids).to receive(:associated_ids_for).with(:state).and_return({check.id => nil, check_2.id => nil})
    expect(full_ids).to receive(:associated_ids_for).with(:tags).and_return({check.id => [], check_2.id => []})
    expect(Flapjack::Data::Check).to receive(:intersect).
      with(:id => [check.id, check_2.id]).twice.and_return(full_ids)

    expect(check).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(check_data)

    expect(check_2).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(check_2_data)

    get "/checks/#{check.id},#{check_2.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(:checks => [
      check_data.merge(:links => {:state => nil, :tags => []}),
      check_2_data.merge(:links => {:state => nil, :tags => []})
    ]))
  end

  it 'disables a check' do
    expect(Flapjack::Data::Check).to receive(:find_by_ids!).
      with(check.id).and_return([check])

    expect(check).to receive(:enabled=).with(false)
    expect(check).to receive(:invalid?).and_return(false)
    expect(check).to receive(:save).and_return(true)

    put "/checks/#{check.id}",
      Flapjack.dump_json(:checks => {:id => check.id, :enabled => false}),
      jsonapi_put_env
    expect(last_response.status).to eq(204)
  end

end
