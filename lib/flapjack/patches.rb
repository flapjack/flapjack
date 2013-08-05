#!/usr/bin/env ruby

require 'logger'
require 'redis'
# require 'xmpp4r'

# bugfix for webrick's assuming 1.8.7 Logger syntax
class ::Logger; alias_method :write, :<<; end

# As Redis::Future objects inherit from BasicObject, it's difficult to
# distinguish between them and other objects in collected data from
# pipelined queries.
#
# (One alternative would be to put other values in Futures ourselves, and
#  evaluate everything...)
class Redis::Future; def class; ::Redis::Future; end; end

# # Unfortunately we have to override/repeat the join method in order to add
# # the directive that will disable the history being sent.
# module Jabber
#   module MUC
#     class MUCClient

#       def join(jid, password=nil)
#         if active?
#           raise "MUCClient already active"
#         end

#         @jid = (jid.kind_of?(JID) ? jid : JID.new(jid))
#         activate

#         # Joining
#         pres = Presence.new
#         pres.to = @jid
#         pres.from = @my_jid
#         xmuc = XMUC.new
#         xmuc.password = password
#         pres.add(xmuc)

#         # NOTE: Adding 'maxstanzas="0"' to 'history' subelement of xmuc nixes
#         # the history being sent to us when we join.
#         history = XMPPElement.new('history')
#         history.add_attributes({'maxstanzas' => '0'})
#         xmuc.add(history)

#         # We don't use Stream#send_with_id here as it's unknown
#         # if the MUC component *always* uses our stanza id.
#         error = nil
#         @stream.send(pres) { |r|
#           if from_room?(r.from) and r.kind_of?(Presence) and r.type == :error
#             # Error from room
#             error = r.error
#             true
#             # type='unavailable' may occur when the MUC kills our previous instance,
#             # but all join-failures should be type='error'
#           elsif r.from == jid and r.kind_of?(Presence) and r.type != :unavailable
#             # Our own presence reflected back - success
#             if r.x(XMUCUser) and (i = r.x(XMUCUser).items.first)
#               @affiliation = i.affiliation  # we're interested in if it's :owner
#               @role = i.role                # :moderator ?
#             end

#             handle_presence(r, false)
#             true
#           else
#             # Everything else
#             false
#           end
#         }

#         if error
#           deactivate
#           raise ServerError.new(error)
#         end

#         self
#       end

#     end
#   end
# end
