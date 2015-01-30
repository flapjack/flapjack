#!/usr/bin/env ruby

require 'redis'

require 'flapjack/configuration'
require 'flapjack/data/contact'

module Flapjack
  module CLI
    class Import

      def initialize(global_options, options)
        @global_options = global_options
        @options = options

        config = Flapjack::Configuration.new
        config.load(global_options[:config])
        @config_env = config.all

        if @config_env.nil? || @config_env.empty?
          exit_now! "No config data found in '#{global_options[:config]}'"
        end

        Flapjack::RedisProxy.config = config.for_redis
        Zermelo.redis = Flapjack.redis
      end

      # TODO should these be similar to JSONAPI structures? e.g.
      # {'contacts' => [CONTACT_HASH, ...]}

      def contacts
        conts = JSON.load(File.new(@options[:from]))

        if conts && conts.is_a?(Enumerable) && conts.any? {|e| !e['id'].nil?}
          conts.each do |contact_data|
            unless contact_data['id']
              puts "Contact not imported as it has no id: " + contact_data.inspect
              next
            end
            media_data = contact_data.delete('media')
            contact = Flapjack::Data::Contact.new(contact_data)
            contact.save

            unless media_data.nil? || media_data.empty?
              media_data.each_pair do |transport, medium_data|

                itv = medium_data['interval'].to_i
                itv = nil unless itv >= 0

                rut = medium_data['rollup_threshold'].to_i
                rut = nil unless rut > 0

                medium = Flapjack::Data::Medium.new(:transport => transport,
                  :address => medium_data['address'],
                  :interval => itv, :rollup_threshold => rut)
                medium.save
                contact.media << medium
              end
            end
          end
        end

      end

      private

      def redis
        @redis ||= Redis.new(@redis_options.merge(:driver => :ruby))
      end

    end
  end
end

desc 'Bulk import data from an external source, reading from JSON formatted data files'
command :import do |import|

  import.desc 'Import contacts'
  import.command :contacts do |contacts|

    contacts.flag [:f, 'from'],     :desc => 'PATH of the contacts JSON file to import',
      :required => true

    contacts.action do |global_options,options,args|
      import = Flapjack::CLI::Import.new(global_options, options)
      import.contacts
    end
  end

end
