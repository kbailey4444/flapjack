#!/usr/bin/env ruby

require 'zermelo/records/redis_record'

require 'flapjack/data/validators/id_validator'

require 'flapjack/data/alert'
require 'flapjack/data/check'

module Flapjack

  module Data

    class Medium

      include Zermelo::Records::RedisRecord
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false

      TRANSPORTS = ['email', 'sms', 'jabber', 'pagerduty', 'sns', 'sms_twilio']

      define_attributes :transport               => :string,
                        :address                 => :string,
                        :interval                => :integer,
                        :rollup_threshold        => :integer,
                        :last_rollup_type        => :string

      belongs_to :contact, :class_name => 'Flapjack::Data::Contact',
        :inverse_of => :media

      has_and_belongs_to_many :rules, :class_name => 'Flapjack::Data::Rule',
        :inverse_of => :media

      has_many :alerts, :class_name => 'Flapjack::Data::Alert', :inverse_of => :medium

      belongs_to :last_entry, :class_name => 'Flapjack::Data::Entry',
        :inverse_of => :latest_media

      index_by :transport

      validates :transport, :presence => true,
        :inclusion => {:in => Flapjack::Data::Medium::TRANSPORTS }

      validates :address, :presence => true

      validates :interval, :presence => true,
        :numericality => {:greater_than_or_equal_to => 0, :only_integer => true},
        :unless => proc {|m| 'pagerduty'.eql?(m.transport) }

      validates :rollup_threshold, :allow_nil => true,
        :numericality => {:greater_than => 0, :only_integer => true},
        :unless => proc {|m| 'pagerduty'.eql?(m.transport) }

      validates_each :interval, :rollup_threshold,
        :if =>  proc {|m| 'pagerduty'.eql?(m.transport) } do |record, att, value|

        record.errors.add(att, 'must be nil') unless value.nil?
      end

      validates_with Flapjack::Data::Validators::IdValidator

      def alerting_checks
        route_ids_by_rule_id = self.rules.associated_ids_for(:routes)
        route_ids = route_ids_by_rule_id.values.reduce(&:|)

        check_ids = Flapjack::Data::Route.intersect(:id => route_ids,
          :is_alerting => true).associated_ids_for(:checks).values.reduce(:|)

        # scheduled maintenance may have occurred without the routes being updated
        Flapjack::Data::Check.intersect(:id => check_ids).all.each_with_object([]) do |check, memo|
          memo << check unless check.in_scheduled_maintenance?
        end
      end

      def self.jsonapi_attributes
        [:transport, :address, :interval, :rollup_threshold]
      end

      def self.jsonapi_singular_associations
        [:contact]
      end

      def self.jsonapi_multiple_associations
        [:rules]
      end
    end
  end
end