module.exports = (opts)->

  mongoose = require 'mongoose'
  RoomSchema = new mongoose.Schema
    name:
      type: String
      unique: true
      index: true
    description:
      type: String
      default: ''
    protect: Boolean
    password: String
    owner: String
    users:
      type: mongoose.Schema.Types.Mixed
      default: {}
    online:
      type: Number
      default: 0

  RoomSchema.plugin require 'mongoose-findorcreate'

  Room = opts.conn.model 'rooms', RoomSchema

  Room