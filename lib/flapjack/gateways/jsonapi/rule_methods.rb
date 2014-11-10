#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/contact'
require 'flapjack/data/rule'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module RuleMethods

        # module Helpers
        # end

        def self.registered(app)
          app.helpers Flapjack::Gateways::JSONAPI::Helpers
          # app.helpers Flapjack::Gateways::JSONAPI::RuleMethods::Helpers

          # Creates a rule or rules for a contact
          app.post '/contacts/:contact_id/rules' do
            rules_data, unwrap = wrapped_params('rules')

            rules_err = nil
            rule_ids = nil
            rules = nil

            Flapjack::Data::Contact.lock(Flapjack::Data::Rule) do

              contact = Flapjack::Data::Contact.find_by_id(params[:contact_id])

              if contact.nil?
                rules_err = "Contact with id '#{params[:contact_id]}' could not be loaded"
              else
                rules = rules_data.collect do |rule_data|
                  Flapjack::Data::Rule.new(:id => rule_data['id'],
                    :is_specific => false)
                end

                if invalid = rules.detect {|nr| nr.invalid? }
                  rules_err = "Notification rule validation failed, " + invalid.errors.full_messages.join(', ')
                else
                  rule_ids = rules.collect {|nr|
                    nr.save
                    contact.rules << nr
                    nr.id
                  }
                end

              end
            end

            halt err(403, rules_err) unless rules_err.nil?

            status 201
            response.headers['Location'] = "#{base_url}/rules/#{rule_ids.join(',')}"
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

          app.patch '/rules/:id' do
            Flapjack::Data::Rule.find_by_ids!(*params[:id].split(',')).each do |rule|
              apply_json_patch('rules') do |op, property, linked, value|
                case op
                when 'replace'
                  if ['time_restrictions'].include?(property)
                    rule.send("#{property}=".to_sym, value)
                  end
                when 'add'
                  case linked
                  when 'tags'
                    Flapjack::Data::Rule.lock(Flapjack::Data::Tag) do
                      add_tag = proc {|tag_name|
                        tag = Flapjack::Data::Tag.intersect(:name => tag_name).all.first
                        if tag.nil?
                          tag = Flapjack::Data::Tag.new(:name => tag_name)
                          tag.save
                        end
                        tag
                      }

                      tags = if value.respond_to?(:each)
                        value.collect {|tag_name| add_tag.call(tag_name) }
                      else
                        [add_tag.call(tag_name)]
                      end
                      unless tags.empty?
                        # TODO association callbacks, which would lock around things
                        rule.tags << tag
                        rule.is_specific = true
                      end
                    end
                  end
                when 'remove'
                  case linked
                  when 'tags'
                    Flapjack::Data::Rule.lock(Flapjack::Data::Tag) do
                      tags = rule.tags.intersect(:name => value).all
                      unless tags.empty?
                        rule.tags.delete(*tags)
                        if rule.tags.empty?
                          rule.is_specific = false
                        end
                        tags.each do |tag|
                          if tag.checks.empty? && tag.rules.empty?
                            tag.destroy
                          end
                        end
                      end
                    end
                  end
                end
              end
              rule.save # no-op if the record hasn't changed
            end

            status 204
          end

          app.delete '/rules/:id' do
            rule_ids = params[:id].split(',')
            rules = Flapjack::Data::Rule.intersect(:id => rule_ids)
            missing_ids = rule_ids - rules.ids

            unless missing_ids.empty?
              raise Sandstorm::Records::Errors::RecordsNotFound.new(Flapjack::Data::Rule, missing_ids)
            end

            rules.destroy_all
            status 204
          end

        end

      end

    end

  end

end
