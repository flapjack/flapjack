#
# Usage
# -----
#
# include flapjack::notifier
#
class flapjack::notifier {
  include flapjack::common

  service { "flapjack-notifier":
    enable => true,
    ensure => running,
    require => [ Exec["populate-etc-flapjack"],
                 Exec["populate-etc-defaults-flapjack"],
                 Exec["populate-etc-init.d-flapjack"] ]
  }

}
