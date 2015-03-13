#!/usr/bin/env ruby

require 'active_support/concern'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Helpers
        module SwaggerLinksDocs

          extend ActiveSupport::Concern

          # included do
          # end

          class_methods do

            def swagger_post_links(resource, klass, linked = {})

            end

            def swagger_get_links(resource, klass, linked = {})

            end

            def swagger_patch_links(resource, klass, linked = {})

            end

            def swagger_delete_links(resource, klass, linked = {})

            end

          end

        end
      end
    end
  end
end
