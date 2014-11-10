#!/usr/bin/env ruby

require 'sandstorm/records/redis_record'

require 'flapjack/data/validators/id_validator'

module Flapjack

  module Data

    class PagerdutyCredentials

      include Sandstorm::Records::RedisRecord
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false

      define_attributes :service_key  => :string,
                        :subdomain    => :string,
                        :username     => :string,
                        :password     => :string

      belongs_to :contact, :class_name => 'Flapjack::Data::Contact', :inverse_of => :pagerduty_credentials

      validates :service_key, :presence => true
      validates :subdomain, :presence => true
      validates :username, :presence => true
      validates :password, :presence => true

      validates_with Flapjack::Data::Validators::IdValidator

      # def as_json(opts = {})
      #   super.as_json(opts).merge(
      #     [:id, :service_key, :subdomain, :username, :password].inject({}) {|memo, k|
      #       memo[k] = self.send(k)
      #       memo
      #     }
      #   )
      # end

      def self.as_jsonapi(unwrap, *pagerduty_credentials)
        return [] if pagerduty_credentials.empty?
        pagerduty_credentials_ids = pagerduty_credentials.map(&:id)

        # contact_ids = Flapjack::Data::PagerdutyCredentials.
        #   intersect(:id => pagerduty_credentials_ids).associated_ids_for(:contact)

        data = pagerduty_credentials.collect do |pdc|
          pdc.as_json
          # (:contact_ids => [linked_contact_ids[pdc.id]])
          # }
        end
        return data unless (data.size == 1) && unwrap
        data.first
      end

    end

  end

end