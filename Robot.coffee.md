Robot Party!
============

Robot Party is a place for code. That code takes the form of robots -
self-contained pieces of code that listen for and respond to messages with other
messages. Robots can be pulled and pushed around, and attached to other robots.

As much as possible, Robot Party is designed to be agnostic to
communication protocols and network topologies, because experimentation is fun!

It has a few simple architectural pillars:

- A robot can run other robots, these robots are called its children.
- Robots distribute messages to and from their children.
- Child robots can have their own children, making one giant tree of robo-glory.
- A robot is, conceptually, not just the top-level robot but all its descendents as well.
- But each descendent is also a robot in its own right. This is known as the great robo-paradox.

Code in Robot Party is designed to be mobile and tangible above everything else.
You can grab a robot from one parent and move it to another one. You can clone a
robot to your local collection of robots, edit it for your use, and the person
who wrote it can copy it back.

Robots are written in CoffeeScript. It'd be nice if we could be language
agnostic, but every robot needs to be able to run every other robot's code.
CoffeeScript has a number of features that makes it attractive to robots though:
it is concise but powerful, it can run on a server via Node.js or in a web
browser, and its parser is available (and also written in CoffeeScript) in case
we want to do any neat meta-trickery.

    coffeescript = window?.CoffeeScript or require 'coffee-script'
    _ = window?._ or require 'underscore'
    nextTick = process?.nextTick || (fn) -> setTimeout fn, 0


Robot
-----

The robot constructor makes a new robot.

    class Robot

      constructor: (@parent, @code) ->
        [@code, @parent] = [@parent] unless @code?

        @defaults = {transmit: {}, listen: {}}
        @info = {}
        @id = _.randomId()
        @children = []
        @listeners = {}
        @listenerId = 0
        @addRobotAPI()

A robot can be a single string of code, or a nested object including child
robots as follows:

```
  {
    code: "code"
    children: [
      {
        code: "code"
        children: ...
      }
    ]
  }
```

        if typeof @code is 'object'
          {@code, children} = @code
        else
          children = []

        fn = eval "(function(_){" + coffeescript.compile(@code, bare: true) + "})"
        fn.call this, _

        console.log "added", @name, "with", children.length, "children"

        nextTick =>
          for child in children
            @add child, (err) =>
              console.log "error", child, err if err
              @transmit "error", {message: err.message, stack: err.stack, type: err.type} if err

The first line of a robot is always its `@robot` directive. This specifies
details about a robot like its name and an object with arbitrary information.

One not-so-arbitrary bit of information is whether the robot is "local", which
means it doesn't generally interact with messages that are non-local. It's up
to you how that's defined (see Messaging below).

      robot: (@name, info) ->
        @info = info or {}
        @info.root = true if !@parent
        if @info.local
          @defaults.listen.local = true
          @defaults.transmit.local = true



Messaging API
-------------

Robots talk by passing messages around. By convention, messages look like this:
```
{
  id: 'msgid1234', re: 'msgid1233' # Message id can be used for message replies
  from: 'roboid1', to: 'roboid2' # Source and destination robot ids
  local: true, trusted: true # Flags for trust and local messages

  howcold: "ice cold" # Whatever other metadata you like

  type: "neatmessage" # Type is used for filtering
  data: "This is a pretty neat message" # Payload/data goes here
}
```
The above conventions are obeyed by the *high-level messaging API*, which is as follows:

**@transmit**: sends a message in one of the following ways:

  * `@transmit 'type', 'data', (msg, reply, done) -> ...`
  * `@transmit {type: 'type', data: 'data', howcold: 'ice cold'}, (msg, reply, done) -> ...`

The callback and data are optional.

`from` and `id` fields will be filled in automatically.

The callback will be called if you receive a message with a `re` field that
matches your message's id. You can call `done()` to say you don't want any
more replies.

The done parameter is optional. If you don't include it then it'll be called
automatically (you'll only receive the first reply to your message).

      transmit: (metadata, data, callback, defaults=@defaults) ->
        metadata = {type: metadata} if typeof metadata is 'string'
        [callback, data] = [data] if typeof data is 'function'
        msg = _.extend {}, defaults.transmit, {data, id: _.randomId(), from: @id, robot: @name}, metadata

        if callback?
          #console.warn "metadata", metadata, "data", data, "callback", callback, "msgid", msg.id
          lid = @listen {re: msg.id}, (msg) =>
            callback.call this, msg, @makeReply(msg)
            @unlisten lid
          , defaults

        #console.warn "sendRaw", msg.data.message if msg.data.message
        #console.warn "sendRaw", msg
        @distribute msg, this

**@listen**: listens for a message. It can be called:

  * With a simple type:

  `@listen 'type', (msg, reply) -> ...`

  * With an object which will be recursively matched against the message:

  `@listen {type: 'type', local: true}, (msg, reply) -> ...`

  * With a function that will be called with the message and tested for truthiness:

  `@listen ((msg) -> msg.type is 'type'), (msg, reply) -> ...`

  * With just a callback, in which case it listens for everything:

  `@listen (msg, reply) -> ...`

The reply callback is a version of the @transmit function that will
automatically set the `re` field to the message id of the received message.

      listen: (matcher, callback, defaults=@defaults) ->
        [callback, matcher] = [matcher] if not callback?
        ok = (msg, src) => callback.call this, msg, @makeReply(msg, defaults), src

        matcher = {} if !matcher?
        matcher = {type: matcher} if typeof matcher is 'string'
        if typeof matcher is 'object'
          matcher[k] = v for k, v of defaults.listen when k not of matcher

        @listeners[@listenerId] = (msg, src) ->
          return ok(msg, src) if typeof matcher is 'function' and matcher(msg)
          return ok(msg, src) if typeof matcher is 'object' and _.matchQuery(msg, matcher)

        return @listenerId++

      makeReply: (msg, defaults) ->
        (metadata, data, callback) =>
          metadata = {type:metadata} if typeof metadata is 'string'
          metadata.re ?= msg.id
          @transmit metadata, data, callback, defaults

      withDefaults: (newDefaults, f) ->
        [oldDefaults, @defaults] = [@defaults, newDefaults]
        f.call(this)
        @defaults = oldDefaults

      noDefaults: (f) -> @withDefaults {transmit: {}, listen: {}}, f

      cleanup: =>
        @unlistenAll()

      unlisten: (id) ->
        delete @listeners[id]

      unlistenAll: (id) ->
        @listeners = {}

Despite the convention, a message can really look like whatever you want. What
is accepted as a message is defined by your robots, not by any higher authority.

Intercept function
------------------

Sometimes you'll want to go deeper. Various parts of how robots work internally
can be overridden. One way to do that is to just override functions with
whatever you want, but to make things easier you can use the *intercept
function*. It works like this

```
  @intercept 'add', (code, cb, add) ->
    code = "@robot 'Robert Paulson'"
    add code, cb
```

Which will replace the `@add` function of your robot with a version that calls
your code first (in this case, turning all child robots into Robert Paulson),
and then calls the default code when you call add().

You can also use this to intercept callbacks, so if you wanted to make a version
of the previous intercept that just replaced the name (as opposed to the whole
robot), you could do something like this:

```
  @intercept 'add', (code, cb, add) ->
    add code, (err, robot) ->
      robot?.name = "Robert Paulson"
      cb err, robot
```

You can call intercept multiple times, and it'll work more or less like you
expect; the functions are called starting with the most recent `@intercept()`
and finishing with the original function.

      intercept: (fname, cb) ->
        orig = this[fname]
        this[fname] = ->
          arguments[arguments.length++] = _.bind(orig, this)
          cb.apply this, arguments


Low-level messaging API
-----------------------

The actual passing of messages between robots constitutes the **low-level
messaging API**.

**@distribute** passes a message around. Depending on the source of the
message, it'll be distributed to the robot itself, parents or children.

      distribute: (msg, source) ->
        nextTick =>
          @receive msg unless this is source
          @distributeUp msg, source unless @parent is source
          @distributeDown msg, source

**@distributeUp** passes a message to the robot's parent.

      distributeUp: (msg, source) ->
        @parent?.distribute msg, this unless @parent is source

**@distributeDown** passes a message to the robot's children.

      distributeDown: (msg, source) ->
        child.distribute msg, this for child in @children when child isnt source

**@receive**: this function is called when a robot receives a message, and
calls all that robot's listeners.

      receive: (msg) ->
        listener.call(this, msg) for own id, listener of @listeners

When a message is sent with `@transmit`, it is passed to that robot's
`@distribute`, which will pass it to parents and children via `@distributeUp`
and `@distrubuteDown`. These functions call `@distribute` again and thus the
message propagates out to the `@receive` functions of all robots in the tree.


Robot API
---------

Each Robot (probably) obeys the Robot API. This API is bilingual: you can call
it from your own code, but it is also made available via robot messages.

The API provides the following methods:

**@add**/**"add robot"** adds a new child to this robot

      add: (code, cb=->) ->
        try
          robot = new Robot this, code
          console.log "robot", robot
          @children.push robot
          cb null, robot

        catch e
          cb e

**@remove**/**"remove robot"** removes a child from this robot

      remove: (id, cb=->) ->
        console.log "removing id", id
        child = null; i = null
        [child, i] = [_child, _i] for _child, _i in @children when id is _child.id
        return cb new Error "no such robot" unless child

        console.log "child", child, i
        child.cleanup()
        @children.splice(i, 1)
        cb null

**@get**/**"get robot"** returns the code for a robot. The result will either be
a simple string if the robot has no children, or a nested object that can be
passed back into `@add`

      get: (cb=->) ->
        code = @code
        return cb null, code if @children.length is 0
        result = {code, children: []}
        done = _.after @children.length, ->
          cb null, result

        for child in @children then do (child) ->
          child.get (err, childcode) ->
            return cb err if err
            result.children.push childcode
            done()

**@list**/**"list robots"** lists robots that this robot knows about. Usually
that means its children, but if those children would not be able to respond on
their own it should include their grandchildren and so on. Similarly, robots
with no parents should add themselves to this list.

      list: (cb=->) ->
        robots = ({id, name, info, parent: @id} for {id, name, info} in @children)
        robots.push {@id, @name, @info, parent: null} if !@parent
        cb null, robots

Finally we expose all these functions via robot messages.

      addRobotAPI: ->
        @noDefaults ->
          @listen type: "add robot", to: @id, trusted: true, ({data: code}, reply) ->
            @add code, (err, robot) ->
              if err
                reply "error", {message: err.message, stack: err.stack, type: err.type}
              else
                reply "robot added", {id: robot.id, name: robot.name, info: robot.info}

          @listen type: "remove robot", to: @id, trusted: true, ({data: id}, reply) ->
            @remove id, (err) ->
              if err
                reply "error", {message: err.message, stack: err.stack, type: err.type}
              else
                reply "robot removed", id

          @listen type: "get robot", to: @id, (msg, reply) ->
            @get (err, robot) ->
              if err
                reply "error", {message: err.message, stack: err.stack, type: err.type}
              else
                reply type: "code for robot", data: robot, local: msg.local

          @listen type: "list robots", ({data: id, to}, reply) ->
            @list (err, robots) =>
              if err
                reply "error", {message: err.message, stack: err.stack, type: err.type}
              else
                #console.log "robots robots", robots if (to and to is @id) or robots.length > 0
                reply "I have robots", robots if (to and to is @id) or robots.length > 0


These functions can be overridden in interesting ways. For example, the
library robot (robrary) will only store a child, not run it, when you call
"add robot". This means you can interact with it like any other robot even
though it acts slightly differently.

`add` and `remove` will only accept messages with `trusted: true` in their
metadata. It's up to you to define what messages are trusted. By default, the
network robot (netwerk) will remove the trusted flag from anything coming over
the network.


Helpers
-------

Robots are given access to the underscore utility library, with a few extra
useful functions added in.

    _.mixin {

**_.randomId** is used for generating message and robot ids.

      randomId: (length = 10) ->
        chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-="
        (chars[Math.floor(Math.random() * chars.length)] for x in [0...length]).join('')

**_.intercept** lets you intercept a function.

      intercept: (fn, cb) -> (args...) -> cb args..., fn

**_.matchQuery** tests if an object's fields match those in another "query"
object, recursing if necessary. We use this for message matching in `@listen`.

      matchQuery: (obj, query) ->
        if typeof obj is 'object' and typeof query is 'object'
          for key, val of query when val isnt undefined
            return false unless _.matchQuery obj[key], val
          return true
        return obj == query

**_.inspectRobot** gives us the name and info of a robot by executing it and
returning immediately after the `@robot` call via some try/catch trickery.
This can't be run on untrusted code, although a version that used the
coffeescript parser to pull out the values without evaluating them might be.

      inspectRobot: (code) ->
        exc = new Error()
        dummy =
          robot: (@name, @info={}) ->
            throw exc

        # Handle robots in recursive object form.
        code = code.code if typeof code is 'object'

        try
          fn = eval "(function(_){" + coffeescript.compile(code, bare: true) + "})"
          fn.call dummy, _
        catch e
          if e is exc
            return {name: dummy.name, info: dummy.info}
          else
            return null
        return null

    }


    if window?
      window.Robot = Robot
    else
      module.exports = Robot
