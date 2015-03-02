module JsonapiHelper

  shared_context "jsonapi" do

    def app
      Flapjack::Gateways::JSONAPI
    end

    let(:contact)      { double(Flapjack::Data::Contact, :id => '21') }
    let(:contact_core) {
      {'id'         => contact.id,
       'first_name' => "Ada",
       'last_name'  => "Lovelace",
       'email'      => "ada@example.com",
       'tags'       => ["legend", "first computer programmer"]
      }
    }

    let(:redis)           { double(::Redis) }

    let(:semaphore) {
      double(Flapjack::Data::Semaphore, :resource => 'folly',
             :key => 'semaphores:folly', :expiry => 30, :token => 'spatulas-R-us')
    }

    let(:jsonapi_post_env) {
      {'CONTENT_TYPE' => 'application/json',
       'HTTP_ACCEPT'  => 'application/json; q=0.8, application/vnd.api+json'}
    }

    let(:jsonapi_patch_env) {
      {'CONTENT_TYPE' => 'application/json-patch+json',
       'HTTP_ACCEPT'  => 'application/json; q=0.8, application/vnd.api+json'}
    }

    before(:all) do
      Flapjack::Gateways::JSONAPI.class_eval {
        set :raise_errors, true
      }
    end

    before(:each) do
      expect(Flapjack::RedisPool).to receive(:new).and_return(redis)
      Flapjack::Gateways::JSONAPI.instance_variable_set('@config', {})
      Flapjack::Gateways::JSONAPI.instance_variable_set('@logger', @logger)
      Flapjack::Gateways::JSONAPI.start
    end

    after(:each) do
      if last_response.status >= 200 && last_response.status < 300
        expect(last_response.headers.keys).to include('Access-Control-Allow-Methods')
        expect(last_response.headers['Access-Control-Allow-Origin']).to eq("*")
        unless last_response.status == 204
          expect(Flapjack.load_json(last_response.body)).to be_a(Enumerable)
          ct = "#{Flapjack::Gateways::JSONAPI::JSONAPI_MEDIA_TYPE}; charset=UTF-8"
          expect(last_response.headers['Content-Type']).to eq(ct)
        end
      end
    end

  end

end