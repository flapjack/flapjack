#!/usr/bin/env ruby

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Helpers
        module Headers

          def cors_headers
            allow_headers  = %w(* Content-Type Accept Authorization Cache-Control)
            allow_methods  = %w(GET POST PATCH DELETE OPTIONS)
            expose_headers = %w(Cache-Control Content-Language Content-Type Expires Last-Modified Pragma)
            ch   = {
              'Access-Control-Allow-Origin'   => '*',
              'Access-Control-Allow-Methods'  => allow_methods.join(', '),
              'Access-Control-Allow-Headers'  => allow_headers.join(', '),
              'Access-Control-Expose-Headers' => expose_headers.join(', '),
              'Access-Control-Max-Age'        => '1728000'
            }
            ch.each_pair {|k, v| response[k] = v}
          end

          def err(status_code, *msg)
            logger.info "Error: #{msg.inspect}"

            if 'DELETE'.eql?(request.request_method)
              # not set by default for delete, but the error structure is JSON
              response['Content-Type'] = media_type_produced(:with_charset => true)
            end

            # TODO include more relevant data
            error_data = {
              :errors => msg.collect {|m|
                {
                  :status => status_code.to_s,
                  :detail => m
                }
              }
            }

            [status_code, response.headers, Flapjack.dump_json(error_data)]
          end

          def is_jsonapi_request?
            return false if request.content_type.nil?
            Flapjack::Gateways::JSONAPI::JSONAPI_MEDIA_TYPE.eql?(request.content_type.split(/\s*[;,]\s*/, 2).first)
          end

          # def is_jsonpatch_request?
          #   return false if request.content_type.nil?
          #   'application/json-patch+json'.eql?(request.content_type.split(/\s*[;,]\s*/, 2).first)
          # end

        end
      end
    end
  end
end