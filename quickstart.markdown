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

## Getting Flapjack running

### Dependencies

- [Vagrant](http://vagrantup.com/) 1.2+
- [VirtualBox](https://www.virtualbox.org/wiki/Downloads) 4.2+
  (or an alternative provider such as [VMware Fusion](http://www.vmware.com/au/products/fusion/)
  and the [Vagrant plugin](http://www.vagrantup.com/vmware))

### Setup

Get the repo, and build your Vagrant box:

```
git clone https://github.com/flpjck/vagrant-flapjack.git
cd vagrant-flapjack
vagrant up
```

For an alternative provider to VirtualBox (e.g. VMware Fusion), you can specify the provider when running `vagrant up`:

```
vagrant up --provider=vmware_fusion
```

<div class="alert alert-info">
<strong>More information:</strong>
Check out the <a class="alert-link" href="https://github.com/flpjck/vagrant-flapjack">vagrant-flapjack</a> project on GitHub.
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

Have a look at the commands:

```text
export PATH=$PATH:/opt/flapjack/bin
# ...
flapjack --help
# ...
simulate-failed-check --help
# ...
```

Have a look at the commands under `/opt/flapjack/bin`.

<div class="alert alert-info">
Details of these commands are available <a class="alert-link" href="https://github.com/flpjck/flapjack/wiki/USING#running">on the Flapjack wiki</a>.
</div>

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

More details on configuration are avilable [on the wiki](https://github.com/flpjck/flapjack/wiki/USING#configuring-components).

### Verify

Reload the Flapjack web interface and you should now see the checks from Icinga and/or Nagios appearing there.

![Checks](/images/quickstart/checks-from-nagios.png)


## Coming soon

<div class="alert alert-danger">
<p>
<strong>Work in progress.</strong>
</p>
</div>

Stay tuned for more info on how to:

- Import contacts and entities.
- Configure notification rules, intervals, and summary thresholds.

In the mean time, **check out the [API documentation](https://github.com/flpjck/flapjack/wiki/IMPORTING) on how to import contacts and entities**.

