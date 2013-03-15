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
        env['rack.request.form_hash'] = data.empty?? {} : JSON.parse(data)
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

      set :show_exceptions, false

      if defined?(FLAPJACK_ENV) && 'test'.eql?(FLAPJACK_ENV)
        # expose test errors properly
        set :raise_errors, true
      else
        # doesn't work with Rack::Test unless we wrap tests in EM.synchrony blocks
        rescue_exception = Proc.new { |env, exception|
          @logger.error exception.message
          @logger.error exception.backtrace.join("\n")
          [503, {}, {:errors => [exception.message]}.to_json]
        }

        use Rack::FiberPool, :size => 25, :rescue_exception => rescue_exception
      end
      use Rack::MethodOverride
      use Rack::JsonParamsParser

      class << self
        def start
          @redis = Flapjack::RedisPool.new(:config => @redis_config, :size => 1)
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
          {'id' => e.id, 'name' => e.name,
           'checks' => e.check_list.sort.collect {|c|
                         entity_check_status(e, c)
                       }
          }
        }
        ret.to_json
      end

      get '/checks/:entity' do
        content_type :json
        entity = Flapjack::Data::Entity.find_by_name(params[:entity], :redis => redis)
        if entity.nil?
          status 404
          return
        end
        entity.check_list.to_json
      end

      get %r{/status/([a-zA-Z0-9][a-zA-Z0-9\.\-]*[a-zA-Z0-9])(?:/(\w+))?} do
        content_type :json

        entity_name = params[:captures][0]
        check = params[:captures][1]

        entity = Flapjack::Data::Entity.find_by_name(entity_name, :redis => redis)
        if entity.nil?
          status 404
          return
        end

        ret = if check
          entity_check_status(entity, check)
        else
          entity.check_list.sort.collect {|c|
            entity_check_status(entity, c)
          }
        end
        ret.to_json
      end

      # the first capture group in the regex checks for acceptable
      # characters in a domain name -- this will also match strings
      # that aren't acceptable domain names as well, of course.
      get %r{/outages/([a-zA-Z0-9][a-zA-Z0-9\.\-]*[a-zA-Z0-9])(?:/(\w+))?} do
        content_type :json

        entity_name = params[:captures][0]
        check = params[:captures][1]

        entity = entity = Flapjack::Data::Entity.find_by_name(entity_name, :redis => redis)
        if entity.nil?
          status 404
          return
        end

        start_time = validate_and_parsetime(params[:start_time])
        end_time   = validate_and_parsetime(params[:end_time])

        presenter = if check
          entity_check = Flapjack::Data::EntityCheck.for_entity(entity,
            check, :redis => redis)
          Flapjack::Gateways::API::EntityCheckPresenter.new(entity_check)
        else
          Flapjack::Gateways::API::EntityPresenter.new(entity, :redis => redis)
        end

        presenter.outages(start_time, end_time).to_json
      end

      get %r{/unscheduled_maintenances/([a-zA-Z0-9][a-zA-Z0-9\.\-]*[a-zA-Z0-9])(?:/(\w+))?} do
        content_type :json

        entity_name = params[:captures][0]
        check = params[:captures][1]

        entity = Flapjack::Data::Entity.find_by_name(entity_name, :redis => redis)
        if entity.nil?
          status 404
          return
        end

        start_time = validate_and_parsetime(params[:start_time])
        end_time   = validate_and_parsetime(params[:end_time])

        presenter = if check
          entity_check = Flapjack::Data::EntityCheck.for_entity(entity,
            check, :redis => redis)
          Flapjack::Gateways::API::EntityCheckPresenter.new(entity_check)
        else
          Flapjack::Gateways::API::EntityPresenter.new(entity, :redis => redis)
        end

        presenter.unscheduled_maintenance(start_time, end_time).to_json
      end

      get %r{/scheduled_maintenances/([a-zA-Z0-9][a-zA-Z0-9\.\-]*[a-zA-Z0-9])(?:/(\w+))?} do
        content_type :json

        entity_name = params[:captures][0]
        check = params[:captures][1]

        entity = Flapjack::Data::Entity.find_by_name(entity_name, :redis => redis)
        if entity.nil?
          status 404
          return
        end

        start_time = validate_and_parsetime(params[:start_time])
        end_time   = validate_and_parsetime(params[:end_time])

        presenter = if check
          entity_check = Flapjack::Data::EntityCheck.for_entity(entity,
            check, :redis => redis)
          Flapjack::Gateways::API::EntityCheckPresenter.new(entity_check)
        else
          Flapjack::Gateways::API::EntityPresenter.new(entity, :redis => redis)
        end
        presenter.scheduled_maintenance(start_time, end_time).to_json
      end

      get %r{/downtime/([a-zA-Z0-9][a-zA-Z0-9\.\-]*[a-zA-Z0-9])(?:/(\w+))?} do
        content_type :json

        entity_name = params[:captures][0]
        check = params[:captures][1]

        entity = Flapjack::Data::Entity.find_by_name(entity_name, :redis => redis)
        if entity.nil?
          status 404
          return
        end

        start_time = validate_and_parsetime(params[:start_time])
        end_time   = validate_and_parsetime(params[:end_time])

        presenter = if check
          entity_check = Flapjack::Data::EntityCheck.for_entity(entity,
            check, :redis => redis)
          Flapjack::Gateways::API::EntityCheckPresenter.new(entity_check)
        else
          Flapjack::Gateways::API::EntityPresenter.new(entity, :redis => redis)
        end

        presenter.downtime(start_time, end_time).to_json
      end

      # create a scheduled maintenance period for a service on an entity
      post '/scheduled_maintenances/:entity/:check' do
        content_type :json
        entity = Flapjack::Data::Entity.find_by_name(params[:entity], :redis => redis)
        if entity.nil?
          status 404
          return
        end
        entity_check = Flapjack::Data::EntityCheck.for_entity(entity,
          params[:check], :redis => redis)
        entity_check.create_scheduled_maintenance(:start_time => params[:start_time],
          :duration => params[:duration], :summary => params[:summary])
        status 204
      end

      # create an acknowledgement for a service on an entity
      # NB currently, this does not acknowledge a specific failure event, just
      # the entity-check as a whole
      post '/acknowledgements/:entity/:check' do
        content_type :json
        entity = Flapjack::Data::Entity.find_by_name(params[:entity], :redis => redis)
        if entity.nil?
          status 404
          return
        end

        dur = params[:duration] ? params[:duration].to_i : nil
        duration = (dur.nil? || (dur <= 0)) ? (4 * 60 * 60) : dur

        entity_check = Flapjack::Data::EntityCheck.for_entity(entity,
          params[:check], :redis => redis)
        entity_check.create_acknowledgement('summary' => params[:summary],
          'duration' => duration)
        status 204
      end

      post '/test_notifications/:entity/:check' do
        content_type :json
        entity = Flapjack::Data::Entity.find_by_name(params[:entity], :redis => redis)
        if entity.nil?
          status 404
          return
        end

        summary = params[:summary] || "Testing notifications to all contacts interested in entity #{entity.name}"

        entity_check = Flapjack::Data::EntityCheck.for_entity(entity,
          params[:check], :redis => redis)
        entity_check.test_notifications('summary' => summary)
        status 204
      end

      post '/entities' do
        pass unless 'application/json'.eql?(request.content_type)
        content_type :json

        errors = []
        ret = nil

        entities = params[:entities]
        if entities && entities.is_a?(Enumerable) && entities.any? {|e| !e['id'].nil?}
          entities.each do |entity|
            unless entity['id']
              errors << "Entity not imported as it has no id: #{entity.inspect}"
              next
            end
            Flapjack::Data::Entity.add(entity, :redis => redis)
          end
          ret = 200
        else
          ret = 403
          errors << "No valid entities were submitted"
        end
        errors.empty? ? ret : [ret, {}, {:errors => [errors]}.to_json]
      end

      post '/contacts' do
        pass unless 'application/json'.eql?(request.content_type)
        content_type :json

        errors = []
        ret = nil

        contacts = params[:contacts]
        if contacts && contacts.is_a?(Enumerable) && contacts.any? {|c| !c['id'].nil?}
          Flapjack::Data::Contact.delete_all(:redis => redis)
          contacts.each do |contact|
            unless contact['id']
              logger.warn "Contact not imported as it has no id: #{contact.inspect}"
              next
            end
            Flapjack::Data::Contact.add(contact, :redis => redis)
          end
          ret = 200
        else
          ret = 403
          errors << "No valid contacts were submitted"
        end
        errors.empty? ? ret : [ret, {}, {:errors => [errors]}.to_json]
      end

      # Returns all the contacts
      # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts
      get '/contacts' do
        content_type :json
        output = '[ '
        output += Flapjack::Data::Contact.all(:redis => redis).map {|contact|
          contact.as_json
        }.join(', ')
        output += ' ]'
        output
      end

      # Returns the core information about the specified contact
      # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts_id
      get '/contacts/:contact_id' do
        content_type :json
        contact = Flapjack::Data::Contact.find_by_id(params[:contact_id], :redis => redis)
        if contact.nil?
          status 404
          return
        end
        contact.as_json
      end

      # Lists the IDs of this contact's notification rules
      # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts_id_notification_rules
      get '/contacts/:contact_id/notification_rules' do
        content_type :json
        contact = Flapjack::Data::Contact.find_by_id(params[:contact_id], :redis => redis)
        if contact.nil?
          status 404
          return
        end
        notification_rules = contact.notification_rules
        notification_rules.collect {|r| r.id}.to_json
      end

      # Get the specified notification rule for this user
      # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts_id_notification_rules_id
      get '/notification_rules/:rule_id' do
        content_type :json

        rule = Flapjack::Data::NotificationRule.find_by_id(params[:rule_id], :redis => redis)
        if rule.nil?
          logger.warn("Unable to find a notification rule with id [#{params[:rule_id]}]")
          status 404
          return
        end
        rule.as_json
      end

      # Creates a notification rule for a contact
      # https://github.com/flpjck/flapjack/wiki/API#wiki-post_contacts_id_notification_rules
      post '/notification_rules' do
        pass unless 'application/json'.eql?(request.content_type)
        content_type :json

        errors = []
        ret = nil
        rule_data = {}

        contact = Flapjack::Data::Contact.find_by_id(params[:contact_id], :redis => redis)
        if contact.nil?
          logger.warn "contact not found with id #{params[:contact_id]}"
          status 404
          return
        end
        if params[:id]
          logger.warn "post cannot be used for update, do a put instead"
          status 403
          return
        end
        rule_data = {:contact_id         => params[:contact_id],
                     :entities           => params[:entities],
                     :entity_tags        => params[:entity_tags],
                     :warning_media      => params[:warning_media],
                     :critical_media     => params[:critical_media],
                     :time_restrictions  => params[:time_restrictions],
                     :warning_blackhole  => params[:warning_blackhole],
                     :critical_blackhole => params[:critical_blackhole] }
        rule = Flapjack::Data::NotificationRule.new(rule_data, :redis => redis)

        errors.empty? ? rule.as_json : [ret, {}, {:errors => [errors]}.to_json]
      end

      # Updates a notification rule
      # https://github.com/flpjck/flapjack/wiki/API#wiki-put_notification_rules_id
      put('/notification_rules/:rule_id') do
        pass unless 'application/json'.eql?(request.content_type)
        content_type :json

        errors = []
        ret = nil

        rule = Flapjack::Data::NotificationRule.find_by_id(params[:rule_id], :redis => redis)
        if not rule
          status 404
          return
        end
        contact = Flapjack::Data::Contact.find_by_id(params[:contact_id], :redis => redis)
        if contact.nil?
          logger.warn "contact not found with id #{params[:contact_id]}"
          status 403
          return
        end
        rule.contact_id         = params[:contact_id]
        rule.entities           = params[:entities]
        rule.entity_tags        = params[:entity_tags]
        rule.warning_media      = params[:warning_media]
        rule.critical_media     = params[:critical_media]
        rule.time_restrictions  = params[:time_restrictions]
        rule.warning_blackhole  = params[:warning_blackhole]
        rule.critical_blackhole = params[:critical_blackhole]
        rule.save!

        errors.empty? ? rule.as_json : [ret, {}, {:errors => [errors]}.to_json]
      end

      # Deletes a notification rule
      # https://github.com/flpjck/flapjack/wiki/API#wiki-put_notification_rules_id
      delete('/notification_rules/:rule_id') do
        rule = Flapjack::Data::NotificationRule.find_by_id(params[:rule_id], :redis => redis)
        if not rule
          status 404
          return
        end
        rule.delete!
        status 204
      end

      # Returns the media of a contact
      # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts_id_media
      get '/contacts/:contact_id/media' do
        content_type :json
        contact = Flapjack::Data::Contact.find_by_id(params[:contact_id], :redis => redis)
        if contact.nil?
          status 404
          return
        end
        contact.media_list.to_json
      end

      # Returns the specified media of a contact
      # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts_id_media_media
      get('/contacts/:contact_id/media/:media_id') do
        status 405
        return
      end

      # Create or updates a media of a contact
      # https://github.com/flpjck/flapjack/wiki/API#wiki-put_contacts_id_media_media
      put('/contacts/:contact_id/media/:media_id') do
        status 405
        return
      end

      # delete a media of a contact
      delete('/contacts/:contact_id/media/:media_id') do
        status 405
        return
      end

      # Returns the timezone of a contact
      # https://github.com/flpjck/flapjack/wiki/API#wiki-get_contacts_id_timezone
      get('/contacts/:contact_id/timezone') do
        contact = Flapjack::Data::Contact.find_by_id(params[:contact_id], :redis => redis)
        if contact.nil?
          status 404
          return
        end
        contact.timezone
      end

      # Sets the timezone of a contact
      # https://github.com/flpjck/flapjack/wiki/API#wiki-put_contacts_id_timezone
      put('/contacts/:contact_id/timezone') do
        contact = Flapjack::Data::Contact.find_by_id(params[:contact_id], :redis => redis)
        if contact.nil?
          status 404
          return
        end
        contact.set_timezone(params[:timezone])
      end

      # Removes the timezone of a contact
      # https://github.com/flpjck/flapjack/wiki/API#wiki-put_contacts_id_timezone
      delete('/contacts/:contact_id/timezone') do
        contact = Flapjack::Data::Contact.find_by_id(params[:contact_id], :redis => redis)
        if contact.nil?
          status 404
          return
        end
        contact.remove_timezone
      end

      not_found do
        [404, {}, {:errors => ["Not found"]}.to_json]
      end

      private

      def entity_check_status(entity, check)
        entity_check = Flapjack::Data::EntityCheck.for_entity(entity,
          check, :redis => redis)
        return if entity_check.nil?
        { 'name'                                => check,
          'state'                               => entity_check.state,
          'in_unscheduled_maintenance'          => entity_check.in_unscheduled_maintenance?,
          'in_scheduled_maintenance'            => entity_check.in_scheduled_maintenance?,
          'last_update'                         => entity_check.last_update,
          'last_problem_notification'           => entity_check.last_problem_notification,
          'last_recovery_notification'          => entity_check.last_recovery_notification,
          'last_acknowledgement_notification'   => entity_check.last_acknowledgement_notification
        }
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
