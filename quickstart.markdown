---
title: Quickstart | Flapjack
layout: default
---

# Quickstart

This quickstart guide will get you [Flapjack](http://flapjack.io/) running in a VM locally using Vagrant and VirtualBox.

You'll also learn the basics of how to:

- Configure Flapjack
- Simulate a failure of a monitored service
- Integrate Flapjack with Nagios (or Icinga), so Flapjack takes over alerting

To skip this tutorial and jump straight to the code, view the project on [GitHub](https://github.com/flapjack/flapjack).

## Getting Flapjack running

### Dependencies

- [Vagrant](http://vagrantup.com/) 1.2+
- [VirtualBox](https://www.virtualbox.org/wiki/Downloads) 4.2+
  (or an alternative provider such as [VMware Fusion](http://www.vmware.com/au/products/fusion/)
  and the [Vagrant plugin](http://www.vagrantup.com/vmware))

### Setup

Get the repo, and build your Vagrant box:

```
git clone https://github.com/flapjack/vagrant-flapjack.git
cd vagrant-flapjack
vagrant up
```

For an alternative provider to VirtualBox (e.g. VMware Fusion), you can specify the provider when running `vagrant up`:

```
vagrant up --provider=vmware_fusion
```

<div class="alert alert-info">
<strong>More information:</strong>
Check out the <a class="alert-link" href="https://github.com/flapjack/vagrant-flapjack">vagrant-flapjack</a> project on GitHub.
</div>

### Verify

Visit [http://localhost:3080](http://localhost:3080) from your host workstation.
You should see the Flapjack Web UI:

![Screenshot of the Flapjack Web UI](/images/quickstart/web-ui.png)

You should also find Icinga and Nagios UIs running at:


<table class="table table-striped table-hover">
  <tr>
    <th>URL</th>
    <th>Username</th>
    <th>Password</th>
  </tr>
  <tr>
    <td>
      <a href="http://localhost:3083/nagios3">
      http://localhost:3083/nagios3
      </a>
    </td>
    <td>nagiosadmin</td>
    <td>nagios</td>
  </tr>
  <tr>
    <td>
      <a href="http://localhost:3083/icinga">
      http://localhost:3083/icinga
      </a>
    </td>
    <td>icingaadmin</td>
    <td>icinga</td>
  </tr>
</table>

## Get comfortable with the Flapjack CLI

SSH into the VM:

``` bash
vagrant ssh
```

Have a look at the commands under `/opt/flapjack/bin`:

```text
export PATH=$PATH:/opt/flapjack/bin
# ...
flapjack --help
# ...
simulate-failed-check --help
# ...
```

<div class="alert alert-info">
Details of these commands are available <a class="alert-link" href="https://github.com/flapjack/flapjack/wiki/USING#running">on the Flapjack wiki</a>.
</div>

![CLI](/images/quickstart/term-flapjack-help.png)

## Simulate a check failure

Run something like:

``` bash
simulate-failed-check fail-and-recover \
  --entity foo-app-01.example.com \
  --check Sausage \
  --time 3
```

This will send a stream of critical events for 3 minutes, and send one ok event at the end. If you want the last event to be a failure as well, use the `fail` command instead of `fail-and-recover`.

### Verify

Reload the Flapjack Web UI and you should now be able to see the status of the check you're simulating, e.g. at:

<pre>
<a href="http://localhost:3080/check?entity=foo-app-01.example.com&check=Sausage">http://localhost:3080/check?entity=foo-app-01.example.com&check=Sausage</a>
</pre>

## Integrate Flapjack with Nagios (and Icinga)

Both Nagios and Icinga are configured already to append check output data to the following named pipe: `/var/cache/icinga/event_stream.fifo`.

`flapjack-nagios receiver` takes check output data from Nagios and turns it into events that Flapjack understands:

![Flapjack's architecture](/images/quickstart/architecture.png)

All that remains is to configure `flapjack-nagios-receiver` to read from this named pipe, configure its Redis connection, and start it up.

- Edit the Flapjack config file at `/etc/flapjack/flapjack_config.yaml`
- Find the `nagios-receiver` section under `production` and change the `fifo: ` to be `/var/cache/icinga/event_stream.fifo`
- Start it up with:

``` bash
sudo /etc/init.d/flapjack-nagios-receiver start
```

More details on configuration are available [on the wiki](https://github.com/flapjack/flapjack/wiki/USING#configuring-components).

### Verify

Reload the Flapjack web interface and you should now see the checks from Icinga and/or Nagios appearing there.

![Checks](/images/quickstart/checks-from-nagios.png)

## Create some contacts and Entities

Currently Flapjack does not include a friendly web interface for managing contacts and entities, so for now we use json, curl, and the [Flapjack API](https://github.com/flapjack/flapjack/wiki/API).

The vagrant-flapjack project ships with [example json files](https://github.com/flapjack/vagrant-flapjack/tree/master/examples) that you can use in this tutorial, or you can copy and paste the longform curl commands below that include the json.

### Create Contacts Ada and Charles

We'll be using the [POST /contacts](https://github.com/flapjack/flapjack/wiki/API#wiki-post_contacts) API call to create two contacts.

Run the following from your workstation, cd'd into the vagrant-flapjack directory:

```
curl -w 'response: %{http_code} \n' -X POST -H "Content-type: application/json" \
  -d @examples/contacts_ada_and_charles.json \
  http://localhost:3081/contacts
```

Or alternatively, copy and paste the following. This does the same thing, but includes the json data inline.

```
curl -w 'response: %{http_code} \n' -X POST -H "Content-type: application/json" -d \
 '{
    "contacts": [
      {
        "id": "21",
        "first_name": "Ada",
        "last_name": "Lovelace",
        "email": "ada@example.com",
        "media": {
          "sms": {
            "address": "+61412345678",
            "interval": "3600",
            "rollup_threshold": "5"
          },
          "email": {
            "address": "ada@example.com",
            "interval": "7200",
            "rollup_threshold": null
          }
        },
        "tags": [
          "legend",
          "first computer programmer"
        ]
      },
      {
        "id": "22",
        "first_name": "Charles",
        "last_name": "Babbage",
        "email": "charles@example.com",
        "media": {
          "sms": {
            "address": "+61412345679",
            "interval": "3600",
            "rollup_threshold": "5"
          },
          "email": {
            "address": "charles@example.com",
            "interval": "7200",
            "rollup_threshold": null
          }
        },
        "tags": [
          "legend",
          "polymath"
        ]
      }
    ]
  }' \
 http://localhost:3081/contacts
```

Navigate to [Contacts](http://localhost:3080/contacts) in the Flapjack web UI and you should see Ada Lovelace and Charles Babbage listed:

![Contacts - List](/images/quickstart/contacts-ada-and-charles.png)

Selecting [Ada](http://localhost:3080/contacts/21) should give you something like:

![Contact - Ada Lovelace](/images/quickstart/contact-ada.png)

### Create entities foo-app-01 and foo-db-01 (.example.com)

We'll be using the [POST /entities](https://github.com/flapjack/flapjack/wiki/API#wiki-post_entities) api call to create two entities.

We're going to assign both Ada and Charles to foo-app-01, and just Ada to foo-db-01.

```
curl -w 'response: %{http_code} \n' -X POST -H "Content-type: application/json" \
  -d @examples/entities_my-app-01_and_my-db-01.json \
  http://localhost:3081/entities
```

Or with json inline if you prefer:

```
curl -w 'response: %{http_code} \n' -X POST -H "Content-type: application/json" -d \
 '{
    "entities": [
      {
        "id": "801",
        "name": "my-app-01.example.com",
        "contacts": [
          "21",
          "22"
        ],
        "tags": [
          "my",
          "app"
        ]
      },
      {
        "id": "802",
        "name": "my-db-01.example.com",
        "contacts": [
          "21"
        ],
        "tags": [
          "my",
          "db"
        ]
      }

    ]
  }' \
 http://localhost:3081/entities
```

#### Verify

Visit [my-app-01](http://localhost:3080/entity/my-app-01.example.com) in the web UI and you should see something like:

![Entity - my-app-01.example.com](/images/quickstart/entity-my-app-01-no-checks.png)

## Feedback?

Found an error in the above? Please [submit a bug report](https://github.com/flapjack/flapjack/issues/new) and/or a pull request against the [gh-pages branch](https://github.com/flapjack/flapjack/tree/gh-pages) with the fix.

Something not clear? That's a bug too!

Got questions? Suggestions? Talk to us via irc, mailing list, or twitter. See [Support](/support) for details.

## Coming soon

Stay tuned for more info on how to configure:

- notification rules
- intervals
- summary thresholds

In the mean time, check out:

 - [Documentation](https://github.com/flapjack/flapjack/wiki/IMPORTING) on **how to import contacts and entities**
 - **[JSONAPI documentation](/docs/jsonapi)** for working with individual contacts and entities
