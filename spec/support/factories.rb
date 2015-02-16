require 'securerandom'

module Factory

  def self.redis
    Zermelo.redis
  end

  def self.contact(attrs = {})
    redis.multi do |r|
      attrs[:id] ||= SecureRandom.uuid
      r.hmset("contact:#{attrs[:id]}:attrs", {'name' => attrs[:name]}.flatten)
      r.sadd('contact::attrs:ids', attrs[:id])
      name = attrs[:name].gsub(/%/, '%%').gsub(/ /, '%20').gsub(/:/, '%3A')
      r.sadd("contact::indices:by_name:string:#{name}", attrs[:id])
    end
  end

  def self.medium(contact, attrs = {})
    redis.multi do |r|
      attrs[:id] ||= SecureRandom.uuid
      r.hmset("medium:#{attrs[:id]}:attrs", {'transport' => attrs[:transport],
        'address' => attrs[:address], 'interval' => attrs[:interval],
        'rollup_threshold' => attrs[:rollup_threshold]}.flatten)
      r.sadd('medium::attrs:ids', attrs[:id].to_s)
      # transport is known not to contain unsafe chars
      r.sadd("medium::indices:by_transport:string:#{attrs[:transport]}", attrs[:id])

      r.sadd("contact:#{contact.id}:assocs:medium_ids", attrs[:id].to_s)
    end
  end

  def self.tag(attrs = {})
    redis.multi do |r|
      attrs[:id] ||= SecureRandom.uuid
      r.hmset("tag:#{attrs[:id]}:attrs", {'name' => attrs[:name]}.flatten)
      r.sadd('tag::attrs:ids', attrs[:id])
      name = attrs[:name].gsub(/%/, '%%').gsub(/ /, '%20').gsub(/:/, '%3A')
      r.hset("tag::indices:by_name", "string:#{name}", attrs[:id])
    end
  end

  def self.check(attrs = {})
    attrs[:state] ||= 'ok'
    redis.multi do |r|
      attrs[:id] ||= SecureRandom.uuid
      r.hmset("check:#{attrs[:id]}:attrs", {'name' => attrs[:name],
        'state' => attrs[:state], 'enabled' => (!!attrs[:enabled]).to_s}.flatten)
      r.sadd('check::attrs:ids', attrs[:id])
      name = attrs[:name].gsub(/%/, '%%').gsub(/ /, '%20').gsub(/:/, '%3A')
      r.hset("check::indices:by_name", "string:#{name}", attrs[:id])
      # state is known not to contain unsafe chars
      r.sadd("check::indices:by_state:string:#{attrs[:state]}", attrs[:id])
      r.sadd("check::indices:by_enabled:boolean:#{!!attrs[:enabled]}", attrs[:id])
    end
  end

end