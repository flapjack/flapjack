#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/contact'
require 'flapjack/data/check'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module SearchMethods

        module Helpers
        end

        def self.registered(app)
          app.helpers Flapjack::Gateways::JSONAPI::Helpers
          # app.helpers Flapjack::Gateways::JSONAPI::SearchMethods::Helpers

          app.get %r{^/search/(contacts/checks/tags)$} do

            query    = params[:q]
            re_query = params[:r]

            case params[:captures][0]
            when 'contacts'
              # TODO paginate
              meta = {}

              if !query.nil? && !''.eql?(query)
                contacts = Flapjack::Data::Contact.intersect(:name => query).all
              elsif !re_query.nil? && !''.eql?(re_query)
                contacts = Flapjack::Data::Contact.intersect(:name => /#{re_query}/).all
              else
                halt(500, 'No valid query parameter')
              end

              contacts_as_json = Flapjack::Data::Contact.as_jsonapi(*contacts)
              Flapjack.dump_json({:contacts => contacts_as_json}.merge(meta))

            when 'checks'

              # TODO paginate
              meta = {}

              if !query.nil? && !''.eql?(query)
                checks = Flapjack::Data::Check.intersect(:name => query).all
              elsif !re_query.nil? && !''.eql?(re_query)
                checks = Flapjack::Data::Check.intersect(:name => /#{re_query}/).all
              else
                halt(500, 'No valid query parameter')
              end

              checks_as_json = Flapjack::Data::Check.as_jsonapi(*checks)
              Flapjack.dump_json({:checks => checks_as_json}.merge(meta))

            when 'tags'

              # TODO paginate
              meta = {}

              # normal tags endpoint is looked up by name, so no singular one here

              if !re_query.nil? && !''.eql?(re_query)
                tags = Flapjack::Data::Tag.intersect(:name => /#{re_query}/).all
              else
                halt(500, 'No valid query parameter')
              end

              tags_as_json = Flapjack::Data::Tag.as_jsonapi(*tags)
              Flapjack.dump_json({:tags => tags_as_json}.merge(meta))
            end

          end

        end

      end

    end

  end

end
