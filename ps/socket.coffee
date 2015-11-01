uuid = require 'uuid'
couchbase = require 'couchbase'
Message = (new couchbase.Cluster('couchbase://81.181.8.153')).openBucket 'test1', 'kochetov'
N1QL = require('couchbase').N1qlQuery
dateFormat = require '../public/coffee/date.format'
jsonfile = require 'jsonfile'
config = jsonfile.readFileSync 'config.json'
mongo = require 'mongodb'
mongoose = require 'mongoose'
mongoose.connect 'mongodb://kochetov_dd:ms17081981ntv@ds035633.mongolab.com:35633/chatio'
redis =
  pub: require('../redis')()
  sub: require('../redis')()

Room = require '../models/room'
Stats = require '../models/stats'
User = require '../models/user'

PORT = process.env.PORT or parseInt process.argv[2]
server = require('http').createServer().listen PORT
# return new port to main app
redis.sub.publish 'port', JSON.stringify
  ps: 'socket'
  old: parseInt process.argv[2]
  new: PORT

require('../console')
  ps: 'socket'
  port: PORT
  redis: redis.pub

redis.sub.subscribe 'exit'

redis.sub.on 'message', (ch, data)->
  data = JSON.parse data
  switch ch

    when 'exit' then process.exit 0


sockjs = require('sockjs').createServer sockjs_url: 'javascripts/source/sockjs.min.js'
connections = []
sockjs.installHandlers server, prefix: '/sockjs'

users = []
rooms = []

emit = (socket, event, data)->
  res = JSON.stringify
    event: event
    data: data
  #console.log(event, data);
  socket.write res

emitRoom = (room, event, data)->
  for id of rooms[room]
    emit users[rooms[room][id]].socket, event, data

broadcast = (event, data)->
  for sockid of connections
    emit connections[sockid], event, data
sockjs.on 'connection', (socket)->

  console.log 'new connection'
  connections.push socket

  socket.on 'data', (e)->
    e = JSON.parse e
    event = e.event
    data = e.data

    switch event
      when config.events['new user']
        if typeof data is 'string' then data = JSON.parse(data)
        if !rooms[data.room._id] then rooms[data.room._id] = []
        f = true
        for i of rooms[data.room._id]
          if rooms[data.room._id][i] is socket.id
            f = false
            break
        if f then rooms[data.room._id].push socket.id
        if !users[socket.id]
          users[socket.id] =
            socket: socket
            rooms: [ data.room._id ]
            user: data.user
        else
          users[socket.id].rooms.push data.room._id
        updateUsers data.room._id
        updateRooms()

        Room.findById data.room._id, (err, room)->
          if err then throw err
          if room then console.log 'User "' + data.user.username + '" joined the room "' + room.name + '".'
          else
            User.findById data.room._id, (err, user)->
              if err then throw err
              if user then console.log 'User "' + data.user.username + '" joined the private chat with "' + user.username + '".' 

      #Update usernames list
      when config.events['update users'] then updateUsers data

      #Returns messages list
      when config.events['get history']
        if typeof data is 'string' then data = JSON.parse data
        getHistory data, (messages)->
          emit socket, config.events['history'],
            id: data.roomid
            data: messages

      when config.events['get private history']
        if typeof data is 'string' then data = JSON.parse data
        getPrivateHistory data.id1, data.id2, data.skip, (messages)->
          emit socket, config.events['private history'],
            from: data.id1
            to: data.id2
            data: messages

      #Send message
      when config.events['send message']
        if typeof data is 'string' then data = JSON.parse data
        Stats.inc ['messages', 'public']
        msg = 
          text: data.msg
          room: data.roomid
          time: Date.now()
          username: users[socket.id].user.username
        addMessage msg, ->
          emitRoom data.roomid, config.events['new message'], msg
          emitRoom 'listeners', config.events['new message'], msg

      when config.events['send private message']
        if typeof data is 'string' then data = JSON.parse(data)
        Stats.inc ['messages', 'private']
        msg = 
          text: data.msg
          private: true
          from: users[socket.id].user._id
          to: data.to
          username: users[socket.id].user.username
          time: Date.now()
        addMessage msg, ->
          for i of users
            if users[i].user._id is msg.to
              emit users[i].socket, config.events['new private message'], msg
          emit socket, config.events['new private message'], msg
          broadcast config.events['listener event'], msg

      when config.events['clear history']
        clearHistory data, users[socket.id].user._id, ->
          updateHistory data

      when config.events['get room']
        Room.findById data, (err, room)->
          if err then throw err
          unless room? then room = '404'
          emit socket, config.events['room'], room

      when config.events['get rooms'] then updateRooms()

      when config.events['delete room']
        if typeof data is 'string' then data = JSON.parse(data)
        Stats.inc ['rooms', 'deleted']
        Room.findById(data.roomid).remove (err)->
          if err then throw err
          updateRooms()
          Message.query N1QL.fromString 'delete from `test1` where room = "' + data.roomid + '"'
          if err then throw err

      when config.events['admin:delete room']
        Stats.inc ['rooms', 'deleted']
        Room.findById(data).remove ->
          broadcast config.events['kick'], data
          updateRooms()
          Message.query N1QL.fromString 'delete from `test1` where room = "' + data + '"'

      when config.events['comment'] then console.log data

      when config.events['get friends'] then updateFriends socket, data

      when config.events['add friend']
        if typeof data is 'string' then data = JSON.parse(data)
        User.findById data.userid, (err, user)->
          if err then throw err
          user.friends.push data.friendid if user
          user.save (err)->
            if err then throw err
            updateFriends socket, data.userid

      when config.events['remove friend']
        if typeof data is 'string' then data = JSON.parse(data)
        User.findById data.userid, (err, user)->
          if err then throw err
          user.friends.splice(user.friends.indexOf(data.friendid), 1) if user
            user.save (err)->
              if err then throw err
              updateFriends socket, data.userid

      when config.events['get user']
        User.findById data, (err, user)->
          if err then throw err
          unless user? then user = '404'
          emit socket, config.events['user'], user

      when config.events['admin:get users']
        if typeof data is 'string' then data = JSON.parse(data)
        getUsers socket, data

      when config.events['set rank']
        if typeof data is 'string' then data = JSON.parse data
        User.update {_id: data.user._id}, {rank: data.rank}, ->
          getUsers()

      when config.events['admin:delete user']
        if typeof data is 'string' then data = JSON.parse(data)
        User.findById(data).remove ->
          getUsers socket

      when config.events['leave room'] then leaveRoom socket, data

      when config.events['admin:get stats']
        Stats.model.findOrCreate {date: data}, (err, today, created)->
          Stats.model.aggregate [
            {$group:
              _id: 0
              roomsCreated:
                $sum: '$rooms.created'
              roomsDeleted:
                $sum: '$rooms.deleted'
              messagesPublic:
                $sum: '$messages.public'
              messagesPrivate:
                $sum: '$messages.private'
              usersSignedUp:
                $sum: '$users.signedUp'
              usersSignedIn:
                $sum: '$users.signedIn'
            },
            {
              $project:
                _id: 0
                rooms:
                  created: '$roomsCreated'
                  deleted: '$roomsDeleted'
                messages:
                  public: '$messagesPublic'
                  private: '$messagesPrivate'
                users:
                  signedUp: '$usersSignedUp'
                  signedIn: '$usersSignedIn'
            }
          ], (err, all)->
            emit socket, config.events['admin:stats'], {today: today, all: all[0]}

      when config.events['autoLogin'] then broadcast config.events['autoLogin'], data

      when config.events['autoLogout'] then broadcast config.events['autoLogout'], data

  #Disconnect
  socket.on 'close', ->
    disconnect socket
    for i of users
      if users[i].socket.id is socket.id
        users.splice i, 1
    for i of connections
      if connections[i].id is socket.id
        connections.splice i, 1

getUsers = (socket, data = {})->
  User.find {}, (err, users)->
    unless users? then users = '404'
    unless socket?
      broadcast config.events['admin:users'], users
    else
      emit socket, config.events['admin:users'], users

updateRooms = ->
  Room.find {}, (err, found)->
    if err then throw err
    for cur of found
      id = found[cur]._id
      arr = []
      for i of rooms[id]
        f = true
        for k of arr
          if users[arr[k]].user._id is users[rooms[id][i]].user._id
            f = false
            break
        if f
          arr.push rooms[id][i]
      found[cur].online = arr.length
    broadcast config.events['rooms'], found
    
leaveRoom = (socket, id)->
  if rooms[id]? and rooms[id].length > 0
    len = rooms[id].length
    cur = 0
    while cur < len
      if rooms[id][cur] is socket.id
        rooms[id].splice cur, 1
      else
        ++cur
  if users[socket.id]?
    for cur of users[socket.id].rooms
      if users[socket.id].rooms[cur] is id
        users[socket.id].rooms.splice cur, 1
        break
  updateRooms()
  updateUsers id

disconnect = (socket)->
  console.log 'disconnected'
  return if !users[socket.id]?
  len = users[socket.id].rooms.length
  i = 0
  while i < len
    cur = users[socket.id].rooms[0]
    leaveRoom socket, cur
    Room.findById cur, (err, room)->
      if err then throw err
      if room then console.log "User '#{users[socket.id].user.username}' disconnected from the room '#{room.name}'."
      else
        User.findById cur, (err, user)->
          if err then throw err
          if user then console.log "User '#{users[socket.id].user.username}' disconnected from the private chat with '#{user.username}'."
    ++i

updateUsers = (roomid)->
  roomid = roomid.toString()
  res = []
  for cur of rooms[roomid]
    f = true
    for id of res
      if res[id]._id is users[rooms[roomid][cur]].user._id
        f = false
        break
    if f then res.push users[rooms[roomid][cur]].user
  emitRoom roomid, config.events['users'], res

updateHistory = (roomid)->
  getHistory roomid, (messages)->
    emitRoom roomid, config.events['history'],
      id: roomid
      data: messages

getHistory = (data, callback)->
  data.skip ?= 0
  condition = "`room` = '#{data.roomid}'"
  query = "select * from `test1` where #{condition} order by `time` desc limit 50 offset #{data.skip}"
  Message.query N1QL.fromString(query), (err, messages)->
    Message.query N1QL.fromString("select count(*) as `count` from `test1` where #{condition}"),
    (err, count)->
      if err then throw err
      if not messages? then return
      for id, message of messages
        messages[id] = message.test1
      callback {messages: messages.reverse(), count: count[0].count}

getPrivateHistory = (id1, id2, skip = 0, callback)->
  condition = "(`from` = '#{id1}' and `to` = '#{id2}') or (`from` = '#{id2}' and `to` = '#{id1}')"
  query = "select * from `test1` where #{condition} order by `time` desc limit 50 offset #{skip}"
  Message.query N1QL.fromString(query), (err, messages)->
    if err then throw err
    Message.query N1QL.fromString("select count(*) as `count` from `test1` where #{condition}"),
    (err, count)->
      if err then throw err
      if not messages? then return
      for id, message of messages
        messages[id] = message.test1
      callback {messages: messages.reverse(), count: count[0].count}

addMessage = (msg, callback)->
  Message.insert uuid.v4(), msg, (err, res)->
    callback()

clearHistory = (roomid, userid, callback)->
  User.findById userid, (err, user)->
    if err then throw err
    rank = user.rank
    Room.findById roomid, (err, room)->
      if err then throw err
      if room and room.users[user._id]
        rank = Math.max rank, room.users[user._id]
      if rank < 3 then return console.log "#{user.username} tried to clear history but had no permission"
      Message.query N1QL.fromString("delete from `test1` where room = '#{roomid}'"), (err, res)->
        console.log 'history cleared'
        callback()

updateFriends = (socket, userid)->
  User.findById userid, (err, user)->
    if err then throw err
    if user?
      User.find { _id: $in: user.friends }, (err, friends)->
        if err then throw err
        if friends? then emit socket, config.events['friends'], friends