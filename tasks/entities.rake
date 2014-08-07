require 'csv'

require 'redis'

require 'flapjack/configuration'
require 'flapjack/data/entity'

FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'production'

namespace :entities do

  def redis
    @redis ||= Redis.new(@redis_config)
  end

  task :setup do
    config_file = File.join('etc', 'flapjack_config.yaml')

    config = Flapjack::Configuration.new
    config.load( config_file )

    @config_env = config.all
    @redis_config = config.for_redis

    if @config_env.nil? || @config_env.empty?
      puts "No config data for environment '#{FLAPJACK_ENV}' found in '#{config_file}'"
      exit(false)
    end
  end

  desc "lists current entity names and their ids"
  task :current => [:setup] do
    puts CSV.generate(:headers => :first_row, :write_headers => true, :row_sep => "\r\n") {|csv|
      csv << ['id', 'name']
      Flapjack::Data::Entity.all(:redis => redis).each do |entity|
        csv << [entity.id, entity.name]
      end
    }
  end

  desc "lists entities with data orphaned by entity renames prior to v1.0"
  task :orphaned => [:setup] do

    current_names = Flapjack::Data::Entity.all(:redis => redis).map(&:name)

    all_entity_names = redis.keys("check:*:*").inject([]) do |memo, ck|
      if ck =~ /^check:([^:]+):.+$/
        memo << $1
      end

      memo
    end

    orphaned = all_entity_names - current_names

    puts CSV.generate(:headers => :first_row, :write_headers => true, :row_sep => "\r\n") {|csv|
      csv << ['name']
      orphaned.each {|orp| csv << [orp]}
    }
  end

  desc "reparent entity names from a CSV file on input"
  task :reparent => [:setup] do

    # The CSV should be in the form 'id', 'name', 'old_name'
    # If more than one old name exists, another row should be used with
    # the first two values repeated. The id is there as a sanity check
    # against current data.

    entities     = {}
    old_entities = {}

    CSV.new($stdin, :headers => :first_row, :return_headers => false) {|csv|
      csv.each {|row|

        id       = row['id']
        name     = row['name']
        old_name = row['old_name']

        if entities.has_key?(id)
          unless entities[id].eql?(name)
            raise "Different names for entity id 'id': '#{name}', '#{old_name}'"
          end
        else
          entities[id] = name
        end

        old_entities[id] ||= []
        old_entities[id] << old_name
      }

      old_entities.each_pair do |id, old_entities_for_id|
        old_entities_for_id.each do |old_entity|
          puts "Re-parenting '#{old_entity}' data to '#{entities[id]}'"
          Flapjack::Data::Entity.rename(old_entity, entities[id])
        end
      end
    }

  end


end