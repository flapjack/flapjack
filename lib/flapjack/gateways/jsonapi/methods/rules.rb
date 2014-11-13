#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/contact'
require 'flapjack/data/rule'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module Rules

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Resources

            app.post '/rules' do
              rules_data, unwrap = wrapped_params('rules')

              rules = resource_post(Flapjack::Data::Rule, rules_data,
                :attributes       => ['id'],
                :singular_links   => {'contact' => Flapjack::Data::Contact},
                :collection_links => {'tags' => Flapjack::Data::Tag}
              )

              status 201
              response.headers['Location'] = "#{base_url}/rules/#{rules.map(&:id).join(',')}"
              rules_as_json = Flapjack::Data::Rule.as_jsonapi(unwrap, *rules)
              Flapjack.dump_json(:rules => rules_as_json)
            end

            app.get %r{^/rules(?:/)?([^/]+)?$} do
              requested_rules = if params[:captures] && params[:captures][0]
                params[:captures][0].split(',').uniq
              else
                nil
              end

              unwrap = !requested_rules.nil? && (requested_rules.size == 1)

              rules, meta = if requested_rules
                requested = Flapjack::Data::Rule.find_by_ids!(*requested_rules)

                if requested.empty?
                  raise Flapjack::Gateways::JSONAPI::RecordsNotFound.new(Flapjack::Data::Rule, requested_rules)
                end

                [requested, {}]
              else
                paginate_get(Flapjack::Data::Rule.sort(:id, :order => 'alpha'),
                  :total => Flapjack::Data::Rule.count, :page => params[:page],
                  :per_page => params[:per_page])
              end

              rules_as_json = Flapjack::Data::Rule.as_jsonapi(unwrap, *rules)
              Flapjack.dump_json({:rules => rules_as_json}.merge(meta))
            end

            app.put %r{^/rules/(.+)$} do
              rule_ids = params[:captures][0].split(',').uniq
              rules_data, _ = wrapped_params('rules')

              resource_put(Flapjack::Data::Rule, rule_ids, rules_data,
                :singular_links   => {'contact' => Flapjack::Data::Contact},
                :collection_links => {'tags'    => Flapjack::Data::Tag,
                                      'routes'  => Flapjack::Data::Route}
              )
              status 204
            end

            app.delete %r{^/rules/(.+)$} do
              rule_ids = params[:captures][0].split(',').uniq
              resource_delete(Flapjack::Data::Rule, rule_ids)
              status 204
            end
          end
        end
      end
    end
  end
end
