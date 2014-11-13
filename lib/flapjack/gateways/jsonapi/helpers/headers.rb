#!/usr/bin/env ruby

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Helpers
        module Headers

          def cors_headers
            allow_headers  = %w(* Content-Type Accept AUTHORIZATION Cache-Control)
            allow_methods  = %w(GET POST PUT PATCH DELETE OPTIONS)
            expose_headers = %w(Cache-Control Content-Language Content-Type Expires Last-Modified Pragma)
            cors_headers   = {
              'Access-Control-Allow-Origin'   => '*',
              'Access-Control-Allow-Methods'  => allow_methods.join(', '),
              'Access-Control-Allow-Headers'  => allow_headers.join(', '),
              'Access-Control-Expose-Headers' => expose_headers.join(', '),
              'Access-Control-Max-Age'        => '1728000'
            }
            headers(cors_headers)
          end

          def err(status, *msg)
            logger.info "Error: #{msg}"

            headers = if 'DELETE'.eql?(request.request_method)
              # not set by default for delete, but the error structure is JSON
              {'Content-Type' => JSONAPI_MEDIA_TYPE}
            else
              {}
            end

            [status, headers, Flapjack.dump_json({:errors => msg})]
          end

          def is_json_request?
            Flapjack::Gateways::JSONAPI::JSON_REQUEST_MIME_TYPES.include?(request.content_type.split(/\s*[;,]\s*/, 2).first)
          end

          def is_jsonapi_request?
            return false if request.content_type.nil?
            'application/vnd.api+json'.eql?(request.content_type.split(/\s*[;,]\s*/, 2).first)
          end

          def is_jsonpatch_request?
            return false if request.content_type.nil?
            'application/json-patch+json'.eql?(request.content_type.split(/\s*[;,]\s*/, 2).first)
          end

        end
      end
    end
  end
end