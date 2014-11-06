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

      def as_json(opts = {})
        super.as_json(opts).merge(
          [:id, :service_key, :subdomain, :username, :password].inject({}) {|memo, k|
            memo[k] = self.send(k)
            memo
          }
        )
      end

    end

  end

end