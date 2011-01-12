class flapjack::common {

  include ruby::rubygems
  include sqlite3::dev

  $version = "0.5.2"

  package { "flapjack":
    ensure   => $version,
    provider => gem,
    require  => [ Package["rubygems"],
                  Package["libsqlite3-dev"] ],
  }

  file { "/var/run/flapjack":
    ensure  => present,
    mode    => 777,
    require => [ Package["flapjack"] ],
  }

  file { "/etc/flapjack":
    ensure  => directory,
    require => [ Package["flapjack"] ],
  }

  exec { "populate-etc-flapjack":
    command => "cp $(dirname $(dirname $(dirname $(gem which flapjack/patches))))/etc/flapjack/* /etc/flapjack",
    creates => "/etc/flapjack/flapjack-notifier.conf.example",
    path    => "/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin",
    require => [ File["/etc/flapjack"],
                 Package["flapjack"] ],
  }

  exec { "populate-etc-defaults-flapjack":
    command => "cp $(dirname $(dirname $(dirname $(gem which flapjack/patches))))/etc/default/* /etc/default",
    creates => [ "/etc/default/flapjack-worker", "/etc/default/flapjack-notifier" ],
    path    => "/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin",
    require => [ Package["flapjack"] ],
  }

  exec { "populate-etc-init.d-flapjack":
    command => "cp $(dirname $(dirname $(dirname $(gem which flapjack/patches))))/etc/init.d/* /etc/init.d",
    creates => [ "/etc/init.d/flapjack-worker", "/etc/init.d/flapjack-notifier" ],
    path    => "/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin",
    require => [ Package["flapjack"] ],
  }

}
