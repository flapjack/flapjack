#!/usr/bin/env ruby

require 'sandstorm/records/redis_record'

module Flapjack

  module Data

    class PagerdutyCredentials

      include Sandstorm::Records::RedisRecord

       define_attributes :service_key  => :string,
                         :subdomain    => :string,
                         :username     => :string,
                         :password     => :string

      belongs_to :contact, :class_name => 'Flapjack::Data::Contact', :inverse_of => :pagerduty_credentials

      validates :service_key, :presence => true
      validates :subdomain, :presence => true
      validates :username, :presence => true
      validates :password, :presence => true

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