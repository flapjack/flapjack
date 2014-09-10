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

    end

  end

end