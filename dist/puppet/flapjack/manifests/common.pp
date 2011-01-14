class flapjack::common {

  include ruby::rubygems
  include sqlite3::dev

  $version = "0.5.3"

  package { "flapjack":
    ensure   => $version,
    provider => gem,
    require  => [ Package["rubygems"],
                  Package["libsqlite3-dev"] ],
  }

  file { "/var/run/flapjack":
    ensure  => directory,
    mode    => 777,
    require => [ Package["flapjack"] ],
  }

  file { "/etc/flapjack":
    ensure  => directory,
    require => [ Package["flapjack"] ],
  }

  exec { "symlink-latest-flapjack-gem":
    command => "ln -sf $(dirname $(dirname $(dirname $(gem which flapjack/patches)))) /usr/lib/flapjack",
    path    => "/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin",
    unless  => "readlink /usr/lib/flapjack |grep -E '$version$'",
    require => [ Package["flapjack"] ]
  }

  exec { "populate-etc-flapjack":
    command => "cp $(dirname $(dirname $(dirname $(gem which flapjack))))/dist/etc/flapjack/* /etc/flapjack",
    creates => [ "/etc/flapjack/flapjack-notifier.conf.example", "/etc/flapjack/recipients.conf.example" ],
    path    => "/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin",
    require => [ File["/etc/flapjack"],
                 Package["flapjack"] ],
  }

  file { "/etc/default/flapjack-workers":
    source  => "/usr/lib/flapjack/dist/etc/default/flapjack-workers",
    require => [ Exec["symlink-latest-flapjack-gem"] ],
  }

  file { "/etc/default/flapjack-notifier":
    source  => "/usr/lib/flapjack/dist/etc/default/flapjack-notifier",
    require => [ Exec["symlink-latest-flapjack-gem"] ],
  }

  file { "/etc/init.d/flapjack-workers":
    source  => "/usr/lib/flapjack/dist/etc/init.d/flapjack-workers",
    require => [ Exec["symlink-latest-flapjack-gem"] ],
  }

  file { "/etc/init.d/flapjack-notifier":
    source  => "/usr/lib/flapjack/dist/etc/init.d/flapjack-notifier",
    require => [ Exec["symlink-latest-flapjack-gem"] ],
  }

}
