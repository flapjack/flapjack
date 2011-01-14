class flapjack::notifier {
  include flapjack::common

  service { "flapjack-notifier":
    enable => true,
    ensure => running,
    require => [ Package["flapjack"],
                 Exec["populate-etc-flapjack"],
                 File["/etc/default/flapjack-notifier"],
                 File["/etc/init.d/flapjack-notifier"] ],
  }

}
