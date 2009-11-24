class RelatedCheck
  include DataMapper::Resource
 
  belongs_to :parent_check, :class_name => "Check", :child_key => [:parent_id]
  belongs_to :child_check, :class_name => "Check", :child_key => [:child_id]

  property :id,        Serial, :key => true
  #property :parent_check_id, Integer, :nullable => false
  #property :child_check_id,  Integer, :nullable => false



end
