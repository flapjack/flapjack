class flapjack::worker {
  include flapjack::common

  service { "flapjack-workers":
    enable => true,
    ensure => running,
    require => [ Package["flapjack"],
                 Exec["populate-etc-flapjack"],
                 File["/etc/default/flapjack-workers"],
                 File["/etc/init.d/flapjack-workers"] ],
  }

}
