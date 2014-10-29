#!/usr/bin/env ruby

require 'sinatra/base'

# NB: documentation changes required, this now uses individual check ids rather
# than v1's 'entity_name:check_name' pseudo-id

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module TagMethods

        # module Helpers
        # end

        def self.registered(app)
          app.helpers Flapjack::Gateways::JSONAPI::Helpers
          # app.helpers Flapjack::Gateways::JSONAPI::TagMethods::Helpers

          app.post '/tags' do
            tags_data = wrapped_params('tags')

            tag_err   = nil
            tag_names = nil
            tags      = nil

            data_names = tags_data.inject([]) do |memo, t|
              memo << t['name'].to_s unless t['name'].nil?
              memo
            end

            Flapjack::Data::Tag.lock do
              conflicted_names = Flapjack::Data::Tag.intersect(:name => data_names).map(&:name)

              if conflicted_names.length > 0
                tag_err = "Tags already exist with the following names: " +
                              conflicted_names.join(', ')
              else
                tags = tags_data.collect do |td|
                  Flapjack::Data::Tag.new(:id => td['id'], :name => td['name'])
                end
              end

              if invalid = tags.detect {|t| t.invalid? }
                check_err = "Tag validation failed, " + invalid.errors.full_messages.join(', ')
              else
                tag_names = tags.collect {|t| t.save; t.name }
              end
            end

            halt err(403, tag_err) unless tag_err.nil?

            status 201
            response.headers['Location'] = "#{base_url}/tags/#{tag_names.join(',')}"
            Flapjack.dump_json(tag_names)
          end

          app.get %r{^/tags(?:/)?(.+)?$} do
            requested_tags = if params[:captures] && params[:captures][0]
              params[:captures][0].split(',').uniq
            else
              nil
            end

            tags, meta = if requested_tags
              requested = Flapjack::Data::Tag.intersect(:name => requested_tags).all

              if requested.empty?
                raise Flapjack::Gateways::JSONAPI::RecordsNotFound.new(Flapjack::Data::Tag, requested_tags)
              end

              [requested, {}]
            else
              paginate_get(Flapjack::Data::Tag.sort(:name, :order => 'alpha'),
                :total => Flapjack::Data::Tag.count, :page => params[:page],
                :per_page => params[:per_page])
            end

            tags_as_json = if tags.empty?
              []
            else
              tag_ids = tags.map(&:id)
              linked_check_ids = Flapjack::Data::Tag.intersect(:id => tag_ids).
                associated_ids_for(:checks)
              linked_rule_ids = Flapjack::Data::Tag.intersect(:id => tag_ids).
                associated_ids_for(:rules)

              tags.collect {|tag|
                tag.as_json(:check_ids => linked_check_ids[tag.id],
                            :rule_ids => linked_rule_ids[tag.id])
              }
            end

            Flapjack.dump_json({:tags => tags_as_json}.merge(meta))
          end

          app.patch %r{^/tags/(.+)$} do
            requested_tags = params[:captures][0].split(',').uniq
            tags = Flapjack::Data::Tag.intersect(:name => requested_tags).all
            if tags.empty?
              raise Flapjack::Gateways::JSONAPI::RecordsNotFound.new(Flapjack::Data::Tag, requested_tags)
            end

            tags.each do |tag|
              apply_json_patch('tags') do |op, property, linked, value|
                case op
                # # NB tag names are not editable, to make querying by name viable
                # when 'replace'
                #   case property
                #   end
                when 'add'
                  case linked
                  when 'checks'
                    check = Flapjack::Data::Check.find_by_id(value)
                    tag.checks << check unless check.nil?
                  when 'notification_rules'
                    Flapjack::Data::Rule.lock(Flapjack::Data::Tag) do
                      rule = Flapjack::Data::Rule.find_by_id(value)
                      unless rule.nil?
                        tag.rules << rule
                        rule.is_specific = false
                        rule.save
                      end
                    end
                  end
                when 'remove'
                  case linked
                  when 'checks'
                    check = Flapjack::Data::Check.find_by_id(value)
                    tag.checks.delete(check) unless check.nil?
                  when 'notification_rules'
                    Flapjack::Data::Rule.lock(Flapjack::Data::Tag) do
                      rule = Flapjack::Data::Rule.find_by_id(value)
                      unless rule.nil?
                        tag.rules.delete(rule)
                        if rule.tags.empty?
                          rule.is_specific = false
                          rule.save
                        end
                      end
                    end
                  end
                end
              end
            end

            status 204
          end

          app.delete '/tags/:name' do
            tag_names = params[:name].split(',')
            tags = Flapjack::Data::Tag.intersect(:name => tag_names)
            missing_names = tag_names - tags.map(&:name)

            unless missing_names.empty?
              raise Sandstorm::Records::Errors::RecordsNotFound.new(Flapjack::Data::Tag, missing_names)
            end

            tags.destroy_all
            status 204
          end

        end

      end

    end

  end

end
