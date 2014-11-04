
module Factory

  def self.redis
    Sandstorm.redis
  end

  def self.contact(attrs = {})
    redis.multi
    redis.hmset("contact:#{attrs[:id]}:attrs", {'name' => attrs[:name]}.flatten)
    redis.sadd('contact::attrs:ids', attrs[:id])
    redis.exec
  end

  def self.medium(contact, attrs = {})
    redis.multi
    redis.hmset("medium:#{attrs[:id]}:attrs", {'type' => attrs[:type],
      'address' => attrs[:address],
      'initial_failure_interval' => attrs[:initial_failure_interval],
      'repeat_failure_interval' => attrs[:repeat_failure_interval],
      'rollup_threshold' => attrs[:rollup_threshold]}.flatten)
    redis.sadd('medium::attrs:ids', attrs[:id].to_s)
    # type is known not to contain unsafe chars
    redis.sadd("medium::indices:by_type:string:#{attrs[:type]}", attrs[:type])

    redis.sadd("contact:#{contact.id}:assocs:medium_ids", attrs[:id].to_s)
    redis.exec
  end

  def self.tag(attrs = {})
    redis.multi
    redis.hmset("tag:#{attrs[:id]}:attrs", {'name' => attrs[:name]}.flatten)
    redis.sadd('tag::attrs:ids', attrs[:id])
    name = attrs[:name].gsub(/%/, '%%').gsub(/ /, '%20').gsub(/:/, '%3A')
    redis.hset("tag::indices:by_name", "string:#{name}", attrs[:id])
    redis.exec
  end

  def self.check(attrs = {})
    attrs[:state] ||= 'ok'
    redis.multi
    redis.hmset("check:#{attrs[:id]}:attrs", {'name' => attrs[:name],
      'state' => attrs[:state], 'enabled' => (!!attrs[:enabled]).to_s}.flatten)
    redis.sadd('check::attrs:ids', attrs[:id])
    name = attrs[:name].gsub(/%/, '%%').gsub(/ /, '%20').gsub(/:/, '%3A')
    redis.hset("check::indices:by_name", "string:#{name}", attrs[:id])
    # state is known not to contain unsafe chars
    redis.sadd("check::indices:by_state:string:#{attrs[:state]}", attrs[:id])
    redis.sadd("check::indices:by_enabled:boolean:#{!!attrs[:enabled]}", attrs[:id])

    redis.exec
  end

end