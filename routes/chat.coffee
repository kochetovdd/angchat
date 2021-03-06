require 'coffee-script'
conn = require('../mongoose')()

jsonfile = require 'jsonfile'
config = jsonfile.readFileSync 'config.json'

express = require 'express'
router = express.Router()

User = require('../models/user')
  conn: conn
Room = require('../models/room')
  conn: conn
Stats = require('../models/stats')
  conn: conn

router.get '/', (req, res, next) ->
  res.render 'chat/default', config: config

router.get '/rooms', (req, res, next) ->
  res.render 'chat/rooms', config: config

router.get '/createroom', (req, res, next) ->
  res.render 'chat/createroom', config: config

router.post '/createroom', (req, res, next) ->

  sockets = require('../sockets')(req.app.locals.io)

  name = req.body.name
  description = req.body.description
  protect = req.body.protect
  if protect then password = req.body.password

  req.checkBody('name', 'Name field is empty!').notEmpty()
  if protect then req.checkBody('password', 'Password field is empty!').notEmpty()

  errors = req.validationErrors()

  if errors then return res.end JSON.stringify
      status: 'error'
      errors: errors

  Room.findOne {name: name}, (err, room) ->
    if err then return next(err)
    if room then return res.end(JSON.stringify(
        status: 'error'
        errors: [{msg: 'Room with this name already exists!'}]))
    else
      room = new Room(
        name: name
        description: description
        protect: protect
        password: password
        owner: req.user._id
        users: JSON.parse('{"' + req.user._id + '": 4}'))
      room.save (err) ->
        if err then return next(err)
        sockets.updateRooms()
        Room.findOne {name: name}, (err, room) ->
          if err then next err
          Stats.inc ['rooms', 'created']
          res.end JSON.stringify(
            status: 'success'
            id: room._id)

router.get '/myrooms', (req, res, next) ->
  res.render 'chat/myrooms', config: config

router.get '/room/:room', (req, res, next) ->
  Room.findById req.params.room, (err, room) ->
    if err or !room
      res.end 'Error: no such room'
    else
      res.render 'chat/room', config: config

router.get '/user/:user', (req, res, next) ->
  User.findById req.params.user, (err, user) ->
    if err or !user then return res.redirect('/rooms')

  res.render 'chat/room', config: config

module.exports = router