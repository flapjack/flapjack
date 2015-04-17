module ProviderSupport

  def default_tear_down
    Flapjack.logger.messages.clear
    Flapjack.redis.flushdb
  end

end