#!/usr/bin/env ruby

# A HTTP-based API server, which provides queries to determine the status of
# entities and the checks that are reported against them.
#
# There's a matching flapjack-diner gem at https://github.com/flpjck/flapjack-diner
# which consumes data from this API.

require 'time'

require 'rack/fiber_pool'
require 'sinatra/base'

require 'flapjack/data/contact'
require 'flapjack/data/entity'
require 'flapjack/data/entity_check'

require 'flapjack/gateways/api/entity_presenter'
require 'flapjack/rack_logger'
require 'flapjack/redis_pool'

# from https://github.com/sinatra/sinatra/issues/501
# TODO move to its own file
module Rack
  class JsonParamsParser < Struct.new(:app)
    def call(env)
      if env['rack.input'] and not input_parsed?(env) and type_match?(env)
        env['rack.request.form_input'] = env['rack.input']
        data = env['rack.input'].read
        env['rack.input'].rewind
        env['rack.request.form_hash'] = data.empty? ? {} : JSON.parse(data)
      end
      app.call(env)
    end

    def input_parsed? env
      env['rack.request.form_input'].eql? env['rack.input']
    end

    def type_match? env
      type = env['CONTENT_TYPE'] and
        type.split(/\s*[;,]\s*/, 2).first.downcase == 'application/json'
    end
  end
end

module Flapjack

  module Gateways

    class API < Sinatra::Base

      class EntityCheckNotFound < RuntimeError
        attr_reader :entity, :check
        def initialize(entity, check)
          @entity = entity
          @check = check
        end
      end

      class EntityNotFound < RuntimeError
        attr_reader :entity
        def initialize(entity)
          @entity = entity
        end
      end

      class ContactNotFound < RuntimeError
        attr_reader :contact_id
        def initialize(contact_id)
          @contact_id = contact_id
        end
      end

      class NotificationRuleNotFound < RuntimeError
        attr_reader :rule_id
        def initialize(rule_id)
          @rule_id = rule_id
        end
      end

      include Flapjack::Utility

      set :show_exceptions, false

      rescue_exception = Proc.new { |env, exception|
        @logger.error exception.message
        @logger.error exception.backtrace.join("\n")
        [503, {}, {:errors => [exception.message]}.to_json]
      }
      use Rack::FiberPool, :size => 25, :rescue_exception => rescue_exception

      use Rack::MethodOverride
      use Rack::JsonParamsParser

      class << self
        def start
          @redis = Flapjack::RedisPool.new(:config => @redis_config, :size => 1)

          @logger.info "starting api - class"

          if @config && @config['access_log']
            access_logger = Flapjack::AsyncLogger.new(@config['access_log'])
            use Flapjack::CommonLogger, access_logger
          end
        end
      end

      def redis
        self.class.instance_variable_get('@redis')
      end

      def logger
        self.class.instance_variable_get('@logger')
      end

      get '/entities' do
        content_type :json
        ret = Flapjack::Data::Entity.all(:redis => redis).sort_by(&:name).collect {|e|
          presenter = Flapjack::Gateways::API::EntityPresenter.new(e, :redis => redis)
          {'id' => e.id, 'name' => e.name, 'checks' => presenter.status }
        }
        ret.to_json
      end

      get '/checks/:entity' do
        content_type :json
        entity = find_entity(params[:entity])
        entity.check_list.to_json
      end

      get '/status' do
        entities = params[:entity]
        halt err(403, "no entities") if entities.nil? || entities.empty?
        entities = [entities] unless entities.is_a?(Array)

        present_api_results(entities, 'status') {|presenter|
          presenter.status
        }
      end

      get '/outages' do
        start_time = validate_and_parsetime(params[:start_time])
        end_time   = validate_and_parsetime(params[:end_time])

        entities = params[:entity]
        halt err(403, "no entities") if entities.nil? || entities.empty?
        entities = [entities] unless entities.is_a?(Array)

        present_api_results(entities, 'outages') {|presenter|
          presenter.outages(start_time, end_time)
        }
      end

      get '/unscheduled_maintenances' do
        start_time = validate_and_parsetime(params[:start_time])
        end_time   = validate_and_parsetime(params[:end_time])

        entities = params[:entity]
        halt err(403, "no entities") if entities.nil? || entities.empty?
        entities = [entities] unless entities.is_a?(Array)

        present_api_results(entities, 'unscheduled_maintenances') {|presenter|
          presenter.unscheduled_maintenance(start_time, end_time)
        }
      end

      get '/scheduled_maintenances' do
        start_time = validate_and_parsetime(params[:start_time])
        end_time   = validate_and_parsetime(params[:end_time])

        entities = params[:entity]
        halt err(403, "no entities") if entities.nil? || entities.empty?
        entities = [entities] unless entities.is_a?(Array)

        present_api_results(entities, 'scheduled_maintenances') {|presenter|
          presenter.scheduled_maintenance(start_time, end_time)
        }
      end

      get '/downtime' do
        start_time = validate_and_parsetime(params[:start_time])
        end_time   = validate_and_parsetime(params[:end_time])

        entities = params[:entity]
        halt err(403, "no entities") if entities.nil? || entities.empty?
        entities = [entities] unless entities.is_a?(Array)

        present_api_results(entities, 'downtime') {|presenter|
          presenter.downtime(start_time, end_time)
        }
      end

      # create a scheduled maintenance period for a check on an entity
      post '/scheduled_maintenances/:entity/:check' do
        content_type :json

        start_time = validate_and_parsetime(params[:start_time])

        entity = find_entity(params[:entity])
        entity_check = find_entity_check(entity, params[:check])
        entity_check.create_scheduled_maintenance(:start_time => start_time,
          :duration => params[:duration].to_i, :summary => params[:summary])
        status 204
      end

      # create an acknowledgement for a service on an entity
      # NB currently, this does not acknowledge a specific failure event, just
      # the entity-check as a whole
      post '/acknowledgements/:entity/:check' do
        content_type :json

        dur = params[:duration] ? params[:duration].to_i : nil
        duration = (dur.nil? || (dur <= 0)) ? (4 * 60 * 60) : dur
        entity = find_entity(params[:entity])
        entity_check = find_entity_check(entity, params[:check])

        entity_check.create_acknowledgement('summary' => params[:summary],
          'duration' => duration)
        status 204
      end

      post '/test_notifications/:entity/:check' do
        content_type :json

        entity = find_entity(params[:entity])
        entity_check = find_entity_check(entity, params[:check])
        summary = params[:summary] || "Testing notifications to all contacts interested in entity #{entity.name}"

        entity_check.test_notifications('summary' => summary)
        status 204
      end

      post '/entities' do
        pass unless 'application/json'.eql?(request.content_type)
        content_type :json

        errors = []
        ret = nil

        # FIXME should scan for invalid records before making any changes, fail early

        entities = params[:entities]
        unless entities
          logger.debug("no entities object found in the following supplied JSON:")
          logger.debug(request.body)
          return err(403, "No entities object received")
        end
        return err(403, "The received entities object is not an Enumerable") unless entities.is_a?(Enumerable)
        return err(403, "Entity with a nil id detected") unless entities.any? {|e| !e['id'].nil?}

        entities.each do |entity|
          unless entity['id']
            errors << "Entity not imported as it has no id: #{entity.inspect}"
            next
          end
          Flapjack::Data::Entity.add(entity, :redis => redis)
        end
        errors.empty? ? 204 : err(403, *errors)
      end

      post '/contacts' do
        pass unless 'application/json'.eql?(request.content_type)
        content_type :json

        errors = []

        contacts_data = params[:contacts]
        if contacts_data.nil? || !contacts_data.is_a?(Enumerable)
          errors << "No valid contacts were submitted"
        else
          # stringifying as integer string params are automatically integered,
          # but our redis ids are strings
          contacts_data_ids = contacts_data.reject {|c| c['id'].nil? }.
            map {|co| co['id'].to_s }

          if contacts_data_ids.empty?
            errors << "No contacts with IDs were submitted"
          else
            contacts = Flapjack::Data::Contact.all(:redis => redis)
            contacts_h = hashify(*contacts) {|c| [c.id, c] }
            contacts_ids = contacts_h.keys

            # delete contacts not found in the bulk list
            (contacts_ids - contacts_data_ids).each do |contact_to_delete_id|
              contact_to_delete = contacts.detect {|c| c.id == contact_to_delete_id }
              contact_to_delete.delete!
            end

            # add or update contacts found in the bulk list
            contacts_data.reject {|cd| cd['id'].nil? }.each do |contact_data|
              if contacts_ids.include?(contact_data['id'].to_s)
                contacts_h[contact_data['id'].to_s].update(contact_data)
              else
                Flapjack::Data::Contact.add(contact_data, :redis => redis)
              end
            end
          end
        end
        errors.empty? ? 204 : err(403, *errors)
      end

      # Returns all the contacts
      # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts
      get '/contacts' do
        content_type :json

        Flapjack::Data::Contact.all(:redis => redis).to_json
      end

      # Returns the core information about the specified contact
      # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts_id
      get '/contacts/:contact_id' do
        content_type :json

        contact = find_contact(params[:contact_id])
        contact.to_json
      end

      # Lists this contact's notification rules
      # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts_id_notification_rules
      get '/contacts/:contact_id/notification_rules' do
        content_type :json

        contact = find_contact(params[:contact_id])
        contact.notification_rules.to_json
      end

      # Get the specified notification rule for this user
      # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts_id_notification_rules_id
      get '/notification_rules/:id' do
        content_type :json

        rule = find_rule(params[:id])
        rule.to_json
      end

      # Creates a notification rule for a contact
      # https://github.com/flpjck/flapjack/wiki/API#wiki-post_contacts_id_notification_rules
      post '/notification_rules' do
        content_type :json

        if params[:id]
          halt err(403, "post cannot be used for update, do a put instead")
        end

        logger.debug("post /notification_rules data: ")
        logger.debug(params.inspect)

        contact = find_contact(params[:contact_id])

        rule_data = hashify(:entities, :entity_tags,
          :warning_media, :critical_media, :time_restrictions,
          :warning_blackhole, :critical_blackhole) {|k| [k, params[k]]}

        unless rule = contact.add_notification_rule(rule_data, :logger => logger)
          halt err(403, "invalid notification rule data")
        end
        rule.to_json
      end

      # Updates a notification rule
      # https://github.com/flpjck/flapjack/wiki/API#wiki-put_notification_rules_id
      put('/notification_rules/:id') do
        content_type :json

        logger.debug("put /notification_rules/#{params[:id]} data: ")
        logger.debug(params.inspect)

        rule = find_rule(params[:id])
        contact = find_contact(rule.contact_id)

        rule_data = hashify(:entities, :entity_tags,
          :warning_media, :critical_media, :time_restrictions,
          :warning_blackhole, :critical_blackhole) {|k| [k, params[k]]}

        unless rule.update(rule_data, :logger => logger)
          halt err(403, "invalid notification rule data")
        end
        rule.to_json
      end

      # Deletes a notification rule
      # https://github.com/flpjck/flapjack/wiki/API#wiki-put_notification_rules_id
      delete('/notification_rules/:id') do
        logger.debug("delete /notification_rules/#{params[:id]}")
        rule = find_rule(params[:id])
        logger.debug("rule to delete: #{rule.inspect}, contact_id: #{rule.contact_id}")
        contact = find_contact(rule.contact_id)
        contact.delete_notification_rule(rule)
        status 204
      end

      # Returns the media of a contact
      # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts_id_media
      get '/contacts/:contact_id/media' do
        content_type :json

        contact = find_contact(params[:contact_id])

        media = contact.media
        media_intervals = contact.media_intervals
        media_addr_int = hashify(*media.keys) {|k|
          [k, {'address'  => media[k],
               'interval' => media_intervals[k] }]
        }
        media_addr_int.to_json
      end

      # Returns the specified media of a contact
      # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts_id_media_media
      get('/contacts/:contact_id/media/:id') do
        content_type :json

        contact = find_contact(params[:contact_id])
        media = contact.media[params[:id]]
        if media.nil?
          halt err(403, "no #{params[:id]} for contact '#{params[:contact_id]}'")
        end
        interval = contact.media_intervals[params[:id]]
        if interval.nil?
          halt err(403, "no #{params[:id]} interval for contact '#{params[:contact_id]}'")
        end
        {'address'  => media,
         'interval' => interval}.to_json
      end

      # Creates or updates a media of a contact
      # https://github.com/flpjck/flapjack/wiki/API#wiki-put_contacts_id_media_media
      put('/contacts/:contact_id/media/:id') do
        content_type :json

        contact = find_contact(params[:contact_id])
        errors = []
        if params[:address].nil?
          errors << "no address for '#{params[:id]}' media"
        end
        if params[:interval].nil?
          errors << "no interval for '#{params[:id]}' media"
        end

        halt err(403, *errors) unless errors.empty?

        contact.set_address_for_media(params[:id], params[:address])
        contact.set_interval_for_media(params[:id], params[:interval])

        {'address'  => contact.media[params[:id]],
         'interval' => contact.media_intervals[params[:id]]}.to_json
      end

      # delete a media of a contact
      delete('/contacts/:contact_id/media/:id') do
        contact = find_contact(params[:contact_id])
        contact.remove_media(params[:id])
        status 204
      end

      # Returns the timezone of a contact
      # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts_id_timezone
      get('/contacts/:contact_id/timezone') do
        content_type :json

        contact = find_contact(params[:contact_id])
        contact.timezone.name.to_json
      end

      # Sets the timezone of a contact
      # https://github.com/flpjck/flapjack/wiki/API#wiki-put_contacts_id_timezone
      put('/contacts/:contact_id/timezone') do
        content_type :json

        contact = find_contact(params[:contact_id])
        contact.timezone = params[:timezone]
        contact.timezone.name.to_json
      end

      # Removes the timezone of a contact
      # https://github.com/flpjck/flapjack/wiki/API#wiki-put_contacts_id_timezone
      delete('/contacts/:contact_id/timezone') do
        contact = find_contact(params[:contact_id])
        contact.timezone = nil
        status 204
      end

      post '/contacts/:contact_id/tags' do
        content_type :json

        tags = find_tags(params[:tag])
        contact = find_contact(params[:contact_id])
        contact.add_tags(*tags)
        contact.tags.to_json
      end

      post '/contacts/:contact_id/entity_tags' do
        content_type :json
        contact = find_contact(params[:contact_id])
        contact.entities.map {|e| e[:entity]}.each do |entity|
          next unless tags = params[:entity][entity.name]
          entity.add_tags(*tags)
        end
        contact_ent_tag = hashify(*contact.entities(:tags => true)) {|et|
          [et[:entity].name, et[:tags]]
        }
        contact_ent_tag.to_json
      end

      delete '/contacts/:contact_id/tags' do
        tags = find_tags(params[:tag])
        contact = find_contact(params[:contact_id])
        contact.delete_tags(*tags)
        status 204
      end

      delete '/contacts/:contact_id/entity_tags' do
        contact = find_contact(params[:contact_id])
        contact.entities.map {|e| e[:entity]}.each do |entity|
          next unless tags = params[:entity][entity.name]
          entity.delete_tags(*tags)
        end
        status 204
      end

      get '/contacts/:contact_id/tags' do
        content_type :json

        contact = find_contact(params[:contact_id])
        contact.tags.to_json
      end

      get '/contacts/:contact_id/entity_tags' do
        content_type :json

        contact = find_contact(params[:contact_id])
        contact_ent_tag = hashify(*contact.entities(:tags => true)) {|et|
          [et[:entity].name, et[:tags]]
        }
        contact_ent_tag.to_json
      end

      post '/entities/:entity/tags' do
        content_type :json

        tags = find_tags(params[:tag])
        entity = find_entity(params[:entity])
        entity.add_tags(*tags)
        entity.tags.to_json
      end

      delete '/entities/:entity/tags' do
        tags = find_tags(params[:tag])
        entity = find_entity(params[:entity])
        entity.delete_tags(*tags)
        status 204
      end

      get '/entities/:entity/tags' do
        content_type :json

        entity = find_entity(params[:entity])
        entity.tags.to_json
      end

      not_found do
        logger.debug("in not_found :-(")
        err(404, "not routable")
      end

      error Flapjack::Gateways::API::ContactNotFound do
        e = env['sinatra.error']
        err(403, "could not find contact '#{e.contact_id}'")
      end

      error Flapjack::Gateways::API::NotificationRuleNotFound do
        e = env['sinatra.error']
        err(403, "could not find notification rule '#{e.rule_id}'")
      end

      error Flapjack::Gateways::API::EntityNotFound do
        e = env['sinatra.error']
        err(403, "could not find entity '#{e.entity}'")
      end

      error Flapjack::Gateways::API::EntityCheckNotFound do
        e = env['sinatra.error']
        err(403, "could not find entity check '#{e.check}'")
      end

      private

      def err(status, *msg)
        msg_str = msg.join(", ")
        logger.info "Error: #{msg_str}"
        [status, {}, {:errors => msg}.to_json]
      end

      def find_contact(contact_id)
        contact = Flapjack::Data::Contact.find_by_id(contact_id, :logger => logger, :redis => redis)
        raise Flapjack::Gateways::API::ContactNotFound.new(contact_id) if contact.nil?
        contact
      end

      def find_rule(rule_id)
        rule = Flapjack::Data::NotificationRule.find_by_id(rule_id, :logger => logger, :redis => redis)
        raise Flapjack::Gateways::API::NotificationRuleNotFound.new(rule_id) if rule.nil?
        rule
      end

      def find_entity(entity_name)
        entity = Flapjack::Data::Entity.find_by_name(entity_name, :redis => redis)
        raise Flapjack::Gateways::API::EntityNotFound.new(entity_name) if entity.nil?
        entity
      end

      def find_entity_check(entity, check)
        entity_check = Flapjack::Data::EntityCheck.for_entity(entity,
          check, :redis => redis)
        raise Flapjack::Gateways::API::EntityCheckNotFound.new(entity, check) if entity_check.nil?
        entity_check
      end

      def present_api_results(entities, result_type, &block)
        entities.collect {|entity_name_or_hash|
          # hash of {entity_name => 'check', entity_name_2 => ['check_2', 'check_3']}
          if entity_name_or_hash.is_a?(Hash)
            # is there a simpler way to express this?
            entity_name_or_hash.keys.collect {|entity_name|
              checks = entity_name_or_hash[entity_name]
              checks = [checks] unless checks.is_a?(Array)
              entity = find_entity(entity_name)
              checks.collect {|check|
                entity_check = find_entity_check(entity, check)
                {:entity => entity_name,
                 :check => check,
                 result_type => yield(Flapjack::Gateways::API::EntityCheckPresenter.new(entity_check, :redis => redis))
                }
              }
            }.flatten(1)
          else
            # entity name string, so get results for all checks for that entity
            entity_name = entity_name_or_hash
            entity = find_entity(entity_name)
            yield(Flapjack::Gateways::API::EntityPresenter.new(entity, :redis => redis))
          end
        }.flatten(1).to_json
      end

      def find_tags(tags)
        halt err(403, "no tags") if tags.nil? || tags.empty?
        tags
      end

      # NB: casts to UTC before converting to a timestamp
      def validate_and_parsetime(value)
        return unless value
        Time.iso8601(value).getutc.to_i
      rescue ArgumentError => e
        logger.error "Couldn't parse time from '#{value}'"
        nil
      end

    end

  end

end
