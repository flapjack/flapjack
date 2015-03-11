module JsonapiHelper

  shared_context "jsonapi" do

    def app
      Flapjack::Gateways::JSONAPI
    end

    let(:redis)           { double(::Redis) }

    let(:jsonapi_post_env) {
      {'CONTENT_TYPE' => 'application/vnd.api+json; ext=bulk; charset=UTF-8',
       'HTTP_ACCEPT'  => 'application/vnd.api+json'}
    }

    let(:jsonapi_put_env) {
      {'CONTENT_TYPE' => 'application/vnd.api+json; ext=bulk; charset=UTF-8',
       'HTTP_ACCEPT'  => 'application/vnd.api+json'}
    }

    # let(:jsonapi_patch_env) {
    #   {'CONTENT_TYPE' => 'application/json-patch+json',
    #    'HTTP_ACCEPT'  => 'application/json; q=0.8, application/vnd.api+json'}
    # }

    before(:all) do
      Flapjack::Gateways::JSONAPI.class_eval {
        set :raise_errors, true
      }
    end

    before(:each) do
      allow(Flapjack).to receive(:redis).and_return(redis)
      Flapjack::Gateways::JSONAPI.instance_variable_set('@config', {})
      Flapjack::Gateways::JSONAPI.start
    end

    after(:each) do
      lr = nil
      begin
        lr = last_response
      rescue Rack::Test::Error
        lr = nil
      end
      if !lr.nil? && (last_response.status >= 200) && (last_response.status < 300)
        expect(last_response.headers.keys).to include('Access-Control-Allow-Methods')
        expect(last_response.headers['Access-Control-Allow-Origin']).to eq("*")
        unless last_response.status == 204
          expect(Flapjack.load_json(last_response.body)).to be_a(Enumerable)
          expect(last_response.headers['Content-Type']).to eq(Flapjack::Gateways::JSONAPI::JSONAPI_MEDIA_TYPE)
        end
      end
    end

  end

end