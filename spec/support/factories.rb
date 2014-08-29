
module Factory

  def self.redis
    Sandstorm.redis
  end

  def self.contact(attrs = {})
    redis.multi
    redis.hmset("contact:#{attrs[:id]}:attrs", {'first_name' => attrs[:first_name],
      'last_name' => attrs[:last_name], 'email' => attrs[:email]}.flatten)
    redis.sadd('contact::ids', attrs[:id])
    redis.exec
  end

  def self.medium(contact, attrs = {})
    redis.multi
    redis.hmset("medium:#{attrs[:id]}:attrs", {'type' => attrs[:type],
      'address' => attrs[:address], 'interval' => attrs[:interval],
      'rollup_threshold' => attrs[:rollup_threshold]}.flatten)
    redis.sadd('medium::ids', attrs[:id].to_s)
    redis.sadd("medium::by_type:#{attrs[:type]}", attrs[:type])

    redis.sadd("contact:#{contact.id}:medium_ids", attrs[:id].to_s)
    redis.exec
  end

  def self.tag(attrs = {})
    redis.multi
    redis.hmset("tag:#{attrs[:id]}:attrs", {'name' => attrs[:name]}.flatten)
    redis.sadd('tag::ids', attrs[:id])
    redis.hset("tag::by_name", attrs[:name], attrs[:id])

    redis.exec
  end

  def self.check(attrs = {})
    attrs[:state] ||= 'ok'
    redis.multi
    redis.hmset("check:#{attrs[:id]}:attrs", {'name' => attrs[:name],
      'state' => attrs[:state], 'enabled' => (!!attrs[:enabled]).to_s}.flatten)
    redis.sadd('check::ids', attrs[:id])
    redis.hset("check::by_name", attrs[:name], attrs[:id])
    redis.sadd("check::by_state:#{attrs[:state]}", attrs[:id])
    redis.sadd("check::by_enabled:#{!!attrs[:enabled]}", attrs[:id])

    redis.exec
  end

end