class ruby::rubygems {
  package { "rubygems": 
    ensure => present,
    tag    => "puppet"
  }

  exec { "export-rubygems-path":
    command => "echo 'export PATH=\$PATH:/var/lib/gems/1.8/bin' >> /etc/bash.bashrc",
    path    => "/bin:/usr/bin",
    unless  => "grep -c '/var/lib/gems/1.8/bin' /etc/bash.bashrc",
    require => [ Package["rubygems"] ],
    tag     => "puppet"
  }
}
