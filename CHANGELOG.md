## Flapjack Changelog

# 0.7.13 - 2013-06-18
- Bug: test notifications are blocked by notification rules gh-188 (@jessereynolds)
- Bug: unscheduled maintenances does not prevent alerts for checks with colons in their name gh-208 (@jessereynolds)

# 0.7.12 - 2013-06-12
- Feature: auto-generate a general notification rule for contacts that don't have any gh-199 (@ali-graham)
- Bug: no recovery for unknown for contact with notification rules gh-203 (@jessereynolds)
- Bug: UNKNOWN -> OK (brief) -> [any problem state] alert is masked by notification interval gh-204 (@jessereynolds)

# 0.7.11 - 2013-06-11
- Bug: unknown events not fully treated as problems - no notification delay blocking (second swing) gh-154 (@jessereynolds)
- Bug: correct jabber alias in example acknowledgement strings (second swing) gh-189 (@jessereynolds)

# 0.7.10 - 2013-06-05
- Bug: unknown events not fully treated as problems - no notification delay blocking gh-154 (@jessereynolds)

# 0.7.9 - 2013-06-04
- Feature: Include summary and details in the /status API call gh-179 (@ali-graham)

# 0.7.8 - 2013-05-30
- Feature: support multiline check output (thanks @bs-github) gh-100 (@jessereynolds)
- Bug: notification rule with no entities or entity tags not being allowed gh-193 (@jessereynolds)
- Bug: correct jabber alias in example acknowledgement strings gh-189 (@jessereynolds)
- Bug: entity lists in Web UI should be sorted alphabetically gh-195 (@jessereynolds)

# 0.7.7 - 2013-05-22
- Bug: relax notification rule validations somewhat gh-185 (@jessereynolds)
- Chore: log notification rule validation errors from api gh-183 (@jessereynolds)

# 0.7.6 - 2013-05-20
- Bug: Problems with email notifications (no name, text part missing fields) gh-158 (@ali-graham)

# 0.7.5 - 2013-05-20
- Bug: Removal of contact media via POST /contacts is not working gh-175 (@ali-graham)

# 0.7.4 - 2013-05-16
- Bug: Event counter values are strings, not integers gh-173 (@auxesis)

# 0.7.3 - 2013-05-14
- Bug: Web and api gateways have configuable http timeout gh-170 (@jessereynolds)
- Bug: Support POSTs to API larger than ~112 KB gh-169 (@jessereynolds)
- Bug: Validate notification rules before adding, updating gh-146 (@ali-graham)
- Bug: Web UI very slow with large number of keys gh-164 (@jessereynolds)
- Bug: crash in executive should exit flapjack gh-143 (@ali-graham)

# 0.7.2 - 2013-05-06
- Feature: executive instance keys now expire after 7 days, touched every event gh-111 (@jessereynolds)
- Feature: slightly less sucky looking web UI, also now includes entity listing screens (@jessereynolds)
- Feature: expose notification rules and intervals via the Web UI gh-150, gh-151 (@jessereynolds)
- Feature: command line - support "--version", "help" etc gh-134 (@jessereynolds)
- Feature: replay events from another flapjack gh-138 (@jessereynolds)
- Bug: recovery is not resetting notification intervals gh-136 (@jessereynolds)
- Bug: recoveries are blocked for users with notification rules gh-148 (@jessereynolds)
- Bug: jabber gateway now uses configured alias for commands gh-138 (@jessereynolds)
- Bug: jabber gateway was crashing on querying entities with invalid regex gh-147 (@jessereynolds)
- Bug: handle media addresses correctly when adding contacts and generating messages gh-145 (@jessereynolds)

# 0.7.1 - 2013-04-24
- Feature: archive incoming events in a sliding window gh-127 (@jessereynolds)
- Bug: Unable to retrieve status of a check containing non word characters via the API gh-117 (@ali-graham)
- Bug: Disable Thin's loading of Daemons gh-133 (@jessereynolds, thanks @johnf)

# 0.7.0 - 2013-04-18
- Feature: Introduce Notification Rules gh-55 (@jessereynolds)
- Feature: Tagging on contacts and entities, expose via API gh-125 (@ali-graham)
- Feature: API improvements (notification rules, contact's timezone and notification intervals per media, tags) (@ali-graham, @jessereynolds)
- Feature: Contact mass update (rather than drop all then import) gh-124 (@ali-graham)
- Feature: Improve error handling (log file paths, permissions), expose internal stats as json gh-122 (@auxesis)
- Incompatable Change: POST /contacts in the API now includes intervals per media and is incompatible with previous versions

# 0.6.61 - 2013-01-11
- todo (and previous versions)
