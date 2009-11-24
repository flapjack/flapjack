class Node
  include DataMapper::Resource

  has n, :checks

  property :fqdn, String, :key => true

  validates_is_unique :fqdn
  validates_format :fqdn, :with => /^[0-9|a-z|A-Z|\-|\.]*$/, 
                          :message => "not a RFC1035-formatted FQDN (see section 2.3.1)"

  def hostname
    self.fqdn.split('.').first
  end

end
