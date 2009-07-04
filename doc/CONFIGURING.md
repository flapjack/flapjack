### Configuring ###

You can configure who receives notifications from `flapjack-notifier` 
in `/etc/flapjack/recipients.yaml`:

    ---
    - :name: Jane Doe
      :email: "jane@doe.com"
      :phone: "+61 444 222 111"
      :pager: "61444222111"
      :jid: "jane@doe.com"

Then you can configure how people are notified in `/etc/flapjack/flapjack-notifier.yaml`: 

    --- 
    :notifiers: 
      :mailer: 
        :from_address: notifications@my-domain.com
      :xmpp: 
        :jid: notifications@my-domain.com
        :password: foo
    :database_uri: "sqlite3:///var/lib/flapjack/flapjack.db"

Currently there are email and XMPP notifiers. 

The `database_uri` setting must point to the database `flapjack-admin` backs 
onto. This can be SQLite3, MySQL, or PostgreSQL:

    :database_uri: "mysql://user:password@localhost/flapjack_production"
    # or
    :database_uri: "postgres://me:spoons@db.mydomain.com/flapjack_production"
    
Now you need to restart the notifier: 

    flapjack-notifier-manager restart --recipients /etc/flapjack/recipients.yaml \
                                      --config /etc/flapjack/flapjack-notifier.yaml


