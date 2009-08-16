class Event
  include DataMapper::Resource

  timestamps :at

  belongs_to :check

  property :id, Serial, :key => true
  property :check_id, Integer, :nullable => false

  # dm-timestamps
  property :created_at, DateTime
  property :updated_at, DateTime
  property :deleted_at, ParanoidDateTime

end
