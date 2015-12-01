require 'redis'
require 'securerandom'

namespace :documentation do

  require 'flapjack'
  require 'flapjack/configuration'

  require 'flapjack/data/check'
  require 'flapjack/data/contact'
  require 'flapjack/data/medium'
  require 'flapjack/data/notification'
  require 'flapjack/data/rule'
  require 'flapjack/data/scheduled_maintenance'
  require 'flapjack/data/state'
  require 'flapjack/data/statistic'
  require 'flapjack/data/tag'
  require 'flapjack/data/unscheduled_maintenance'

  task :dump_keys do

    puts "Generated using `rake documentation:dump_keys` in the Flapjack codebase.\n\n---\n\n\n"

    redis_klasses = [
      Flapjack::Data::Check,
      Flapjack::Data::Contact,
      Flapjack::Data::Medium,
      Flapjack::Data::Notification,
      Flapjack::Data::Rule,
      Flapjack::Data::ScheduledMaintenance,
      Flapjack::Data::State,
      Flapjack::Data::Statistic,
      Flapjack::Data::Tag,
      Flapjack::Data::UnscheduledMaintenance
    ]

    redis_klasses.each do |rk|
      uuid = SecureRandom.uuid
      klass_keys = rk.key_dump
      instance_keys = rk.new(:id => uuid).key_dump

      puts "# #{rk.short_model_name.human}\n\n"

      unless klass_keys.empty?
        puts "## global\n\n```"
        klass_keys.keys.sort.each do |kk|
          puts "#{kk} (#{klass_keys[kk].type})"
        end
      end

      puts "```\n\n"

      unless instance_keys.empty?
        puts "## instance\n\n```"
        attr_types = rk.attribute_types
        unless attr_types.empty?
          attrs_key = instance_keys.keys.detect {|ik| ik =~ /#{uuid}:attrs\z/}
          attr_out = attrs_key.sub(/#{uuid}/, '[UUID]')
          puts "#{attr_out} (hash)"
          puts "  {\n"
          complex_attrs = {}
          attr_types.each_pair do |name, type|
            if Zermelo::COLLECTION_TYPES.keys.include?(type)
              complex_attrs[name] = type
              next
            end
            puts "    :#{name}  => :#{type}"
          end
          puts "  }\n"
        end
        complex_attrs.each_pair do |name, type|
          puts "#{attr_out}:#{name} (:#{type})"
        end
        instance_keys.keys.reject {|ik| ik.eql?(attrs_key)}.sort.each do |k|
          puts "#{k.sub(/#{uuid}/, '[UUID]')} (#{instance_keys[k].type}) "
        end
      end

      puts "```\n\n"
    end
  end
end
