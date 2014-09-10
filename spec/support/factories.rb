
module Factory

  def self.redis
    Sandstorm.redis
  end

  def self.contact(attrs = {})
    redis.multi
    redis.hmset("contact:#{attrs[:id]}:attrs", {'first_name' => attrs[:first_name],
      'last_name' => attrs[:last_name], 'email' => attrs[:email]}.flatten)
    redis.sadd('contact::attrs:ids', attrs[:id])
    redis.exec
  end

  def self.medium(contact, attrs = {})
    redis.multi
    redis.hmset("medium:#{attrs[:id]}:attrs", {'type' => attrs[:type],
      'address' => attrs[:address], 'interval' => attrs[:interval],
      'rollup_threshold' => attrs[:rollup_threshold]}.flatten)
    redis.sadd('medium::attrs:ids', attrs[:id].to_s)
    redis.sadd("medium::indices:by_type:#{attrs[:type]}", attrs[:type])

    redis.sadd("contact:#{contact.id}:assocs:medium_ids", attrs[:id].to_s)
    redis.exec
  end

  def self.entity(attrs = {})
    redis.multi
    redis.hmset("entity:#{attrs[:id]}:attrs", {'name' => attrs[:name]}.flatten)
    redis.sadd('entity::attrs:ids', attrs[:id])
    redis.hset("entity::indices:by_name", attrs[:name], attrs[:id])
    redis.exec
  end

  def self.check(entity, attrs = {})
    attrs[:state] ||= 'ok'
    redis.multi
    redis.hmset("check:#{attrs[:id]}:attrs", {'name' => attrs[:name],
      'state' => attrs[:state], 'enabled' => (!!attrs[:enabled]).to_s}.flatten)
    redis.sadd('check::attrs:ids', attrs[:id])
    redis.sadd("check::indices:by_name:#{attrs[:name]}", attrs[:id])
    redis.sadd("check::indices:by_state:#{attrs[:state]}", attrs[:id])
    redis.sadd("check::indices:by_enabled:#{!!attrs[:enabled]}", attrs[:id])

    redis.hset("check:#{attrs[:id]}:assocs:belongs_to", 'entity_id', entity.id)
    redis.sadd("entity:#{entity.id}:assocs:checks_ids", attrs[:id].to_s)
    redis.exec
  end

end