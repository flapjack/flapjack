#
# Usage
# -----
#
# include flapjack-worker
#
class flapjack::worker {
  include flapjack::common

  service { "flapjack-workers":
    enable => true,
    ensure => running,
    require => [ Exec["populate-etc-flapjack"],
                 Exec["populate-etc-defaults-flapjack"],
                 Exec["populate-etc-init.d-flapjack"] ],
  }

}
