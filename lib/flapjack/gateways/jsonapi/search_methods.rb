#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/contact'
require 'flapjack/data/check'
require 'flapjack/data/tag'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module SearchMethods

        module Helpers
        end

        def self.registered(app)
          app.helpers Flapjack::Gateways::JSONAPI::Helpers
          # app.helpers Flapjack::Gateways::JSONAPI::SearchMethods::Helpers

          app.get %r{^/search/(contacts|checks|tags)$} do

            resource = params[:captures][0]

            klass, string_params, boolean_params = case resource
            when 'contacts'
              [Flapjack::Data::Contact, [:id, :name], []]
            when 'checks'
              [Flapjack::Data::Check, [:id, :name, :state, :ack_hash], [:enabled]]
            when 'tags'
              [Flapjack::Data::Tag, [:id, :name], []]
            end

            opts = string_params.each_with_object({}) do |sp, memo|
              next unless params.has_key?(sp.to_s)
              memo[sp] = Regexp.new(params[sp.to_s])
            end

            bool_opts = boolean_params.each_with_object({}) do |sp, memo|
              next unless params.has_key?(sp.to_s)
              memo[sp] = case params[sp.to_s].downcase
              when '0', 'f', 'false', 'n', 'no'
                false
              when '1', 't', 'true', 'y', 'yes'
                true
              else
                nil
              end
            end

            opts.update(bool_opts)

            records, meta = paginate_get(klass.intersect(opts).sort(:name, :order => 'alpha'),
              :total => klass.intersect(opts).count, :page => params[:page],
              :per_page => params[:per_page])

            records_as_json = klass.as_jsonapi(*records)
            Flapjack.dump_json({resource.to_sym => records_as_json}.merge(meta))
          end

        end

      end

    end

  end

end
