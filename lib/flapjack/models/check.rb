class Check
  include DataMapper::Resource

  timestamps :at

  has n, :related_checks, :child_key => [:child_id, :parent_id]

  #has n, :parent_checks, :through => :related_checks, 
  #       :child_key => :child_id,  :class_name => "Check"
  #has n, :child_checks,  :through => :related_checks, 
  #       :child_key => :parent_id, :class_name => "Check"

  belongs_to :node
  belongs_to :check_template

  property :id, Serial, :key => true
  property :command, Text, :nullable => false
  property :params, Yaml
  property :name, String, :nullable => false
  property :enabled, Boolean, :default => false
  property :status, Integer, :default => 0

  # dm-timestamps
  property :created_at, DateTime
  property :updated_at, DateTime
  property :deleted_at, ParanoidDateTime

  # copy command onto check
  before :valid? do 
    if self.check_template && self.command.blank?
      self.command = self.check_template.command
      self.name = self.check_template.name
      self.params = (self.check_template.params || {})
    end
  end

  def parameters_and_values
    names = parameter_names_from_command
    hash = {}
    names.each { |name| hash[name] = params ? params[name] : "" }
    hash["$FQDN"] = self.node_fqdn # pkey of node check belongs to
    hash
  end

  def parameter_names_from_command
    self.command.split.grep(/\$\w/)
  end

  def executed_command
    c = self.command
    parameters_and_values.each_pair do |param, value|
      value = value.to_s
      c.gsub!(param, value)
    end
    return c
  end

  # FIXME: this should work through related checks association, but doesn't
  def parent_checks
    RelatedCheck.all(:child_id => self.id).map {|rc| rc.parent_check}
  end

  def child_checks
    RelatedCheck.all(:parent_id => self.id).map {|rc| rc.child_check}
  end

  def worst_parent_status
    if parent_checks.size > 0
      self.parent_checks.map { |parent| parent.status }.sort.pop
    else
      0
    end
  end


  GOOD = 0
  BAD  = 1
  UGLY = 2
  
  def pretty_print_status
    case self.status
    when GOOD
      "good"
    when BAD
      "bad"
    when UGLY
      "ugly"
    end
  end

end
