## Flapjack Changelog

# 0.7.28 - 2013-10-21
- Feature: Per contact media rollup (summary) notifications - foundation (data, api, web UI etc) gh-291 (@jessereynolds)
- Feature: flapper takes an IP to bind to gh-98 (@ali-graham)
- Feature: tests for bin scripts gh-289 (@ali-graham)
- Feature: Entity / check query function via jabber gh-77 (@ali-graham)
- Chore: Make production the default environment gh-331 (@jessereynolds)
- Chore: Look in /etc/flapjack/flapjack_config.yaml for config by default gh-332 (@jessereynolds)
- Bug: --version should not depend on a config file being found gh-316 (@ali-graham)

# 0.7.27 - 2013-09-19
- Feature: Treat UNKNOWN separately to CRITICAL in notification rules gh-295 (@jessereynolds)
- Bug: License missing from gemspec gh-313 (@jessereynolds)
- Bug: fix ack after ack deletion gh-308 (@ali-graham)

# 0.7.26 - 2013-09-16
- Bug: last critical notification is empty in web UI gh-306 (@ali-graham)
- Bug: Ending unscheduled maintenance in Web UI is broken gh-307 (@jessereynolds)
- Bug: Acknowledgement jabber message shows incorrect duration gh-309 (@jessereynolds)
- Bug: Details showing up in email alerts when "empty" gh-310 (@jessereynolds)
- Bug: Only show Previous State and Summary when current state != previous unique state gh-311 (@jessereynolds)

# 0.7.25 - 2013-09-13
- Bug: EntityCheck last_update= isn't being called for update_state since refactoring gh-303 (@ali-graham)
- Bug: flapjack-nagios-receiver is double-escaping its JSON data gh-304 (@jessereynolds)

# 0.7.24 - 2013-09-12
- Bug: gem install of flapjack 0.7.23 fails with tzinfo-data dependency error gh-302 (@jessereynolds)

# 0.7.23 - 2013-09-12
- Bug: Quick ok -> warning -> ok -> warning triggers too many recovery notifications gh-119 (@jessereynolds)
- Bug: Blackhole notification rule doesn't block recovery notifications gh-282 (@jessereynolds)
- Chore: Shorten SMS messages to 159 chars on the Messagenet gateway gh-278 (@ali-graham)
- Chore: flapjack-nagios-receiver should use Event#add gh-275 (@ali-graham)
- Chore: Non-zero exit code after receiving SIGINT gh-266 (@ali-graham)
- Bug: Email notifications - remove "(about a minute ago)" and fix previous state fields gh-258 (@ali-graham)
- Chore: refactor delays filter, remove mass client failures filter gh-293 (@jessereynolds)
- Bug: creation of scheduled maintenance fails from web UI gh-296 (@ali-graham)
- Feature: flapjack UI needs a favicon gh-297 (@jessereynolds)
- Chore: email notification styling gh-298 (@jessereynolds)

# 0.7.22 - 2013-08-08
- Bug: fix potential exception in json serialisation of tags in notifications gh-281 (@jessereynolds)

# 0.7.21 - 2013-08-08
- Feature: make entity search scopable by tags gh-89 (@jessereynolds)
- Feature: add benchmark rake task gh-259 (@jessereynolds)
- Feature: make tags more general in notification rules gh-269 (@jessereynolds)
- Feature: ephemeral tag generation on events gh-268 (@jessereynolds)
- Bug: fix syslog output levels gh-260 (@ali-graham)
- Bug: Ruby 2 shutdown error gh-261 (@ali-graham)
- Bug: Email and SMS problem and recovery notifications failing (@jessereynolds)
- Bug: Links to contacts from the check detail page are broken (@jessereynolds)

# 0.7.20 - 2013-07-17
- Bug: flapjack-nagios-receiver failing after json library change gh-257 (@jessereynolds)
- Bug: email gateway partial conversion to erb sending haml source code gh-256 (@ali-graham)

# 0.7.19 - 2013-07-17
- Feature: Removed log4r and YAJL dependencies gh-25 (@ali-graham)
- Feature: Made jabber entity status messages more verbose gh-245 (@ali-graham)
- Feature: Split executive pikelet into two parts (processor and notifier) gh-247 (@ali-graham)
- Feature: marking entities and entity_checks as disabled / inactive gh-104 (@jessereynolds)
- Feature: include check summary when listing checks (all, failing, and per entity) gh-255 (@jessereynolds)

# 0.7.18 - 2013-07-05
- Feature: delete currently active scheduled maintenance via api should truncate from Time.now gh-242 (@ali-graham)

# 0.7.17 - 2013-07-04
- Feature: split API methods into two separate files, also specs gh-215 (@ali-graham)
- Feature: unlock ruby version, build with Ruby 2 in travis gh-237 (@ali-graham)
- Feature: include notification rule validation error details in api add, update functions gh-184 (@ali-graham)
- Feature: API: delete scheduled maintenance should return an error if no start_time parameter is passed gh-240 (@ali-graham)
- Bug: entity name in bulk status api response is incorrect gh-233 (@jessereynolds)
- Bug: non-changing checks creating state-change records gh-235 (@ali-graham)
- Bug: posting scheduled maintenance in new api format throwing 500 gh-239 (@jessereynolds)

# 0.7.16 - 2013-06-27
- Bug: errors accessing API gh-231 (@ali-graham)

# 0.7.15 - 2013-06-27
- Feature: Show acknowledgement duration on web interface, queryable via jabber gh-159 (@ali-graham)
- Feature: More info on check state in email gh-207 (@ali-graham)
- Feature: Bulk API operations gh-123 (@ali-graham)
- Bug: You can't remove an interval from a contact's media once it has one gh-153 (@ali-graham)
- Bug: Fix jabber identify boot time gh-172 (@ali-graham)
- Bug: Don't pluralise singular time periods in jabber messages gh-209 (@ali-graham)
- Bug: PUT /contacts/ID/media/MEDIA returns previous value for address gh-152 (@ali-graham)
- Bug: 'last update' shows large numbers of seconds gh-157 (@ali-graham)

# 0.7.14 - 2013-06-19
- Bug: Display of checks on web ui with a colon in their name is screwed gh-213 (@jessereynolds)
- Bug: show last critical, warning, unknown notificaiton times in web ui gh-211 (@jessereynolds)

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
