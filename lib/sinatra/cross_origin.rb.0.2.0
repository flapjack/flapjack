require 'sinatra/base'

# Helper to enable cross origin requests.
# More on Cross Origin Resource Sharing here:
#   https://developer.mozilla.org/En/HTTP_access_control
#
# To enable cross origin requests for all routes:
#   configure do
#     enable :cross_origin
#     ...
#
# To enable cross origin requests for a single domain:
#   get '/' do
#     cross_origin
#     ...
#
# More info at:
#   http://github.com/britg/sinatra-cross_origin
#

module Sinatra
  module CrossOrigin
    module Helpers

      # Apply cross origin headers either
      # from global config or custom config passed
      # as a hash
      def cross_origin(hash=nil)
        return unless request.env['HTTP_ORIGIN']
        settings.set hash if hash

        origin = settings.allow_origin == :any ? request.env['HTTP_ORIGIN'] : settings.allow_origin
        methods = settings.allow_methods.map{ |m| m.to_s.upcase! }.join(', ')

        headers 'Access-Control-Allow-Origin' => origin,
          'Access-Control-Allow-Methods' => methods,
          'Access-Control-Allow-Credentials' => settings.allow_credentials.to_s,
          'Access-Control-Max-Age' => settings.max_age.to_s 
      end
    end

    def self.registered(app)

      app.helpers CrossOrigin::Helpers

      app.set :cross_origin, false 
      app.set :allow_origin, :any
      app.set :allow_methods, [:post, :get, :options]
      app.set :allow_credentials, true
      app.set :max_age, 1728000


      app.before do 
        cross_origin if settings.cross_origin
      end

    end
  end

  register CrossOrigin

end
