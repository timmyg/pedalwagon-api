express = require 'express'
stylus = require 'stylus'
assets = require 'connect-assets'
mongoose = require 'mongoose'
session = require('express-session')
cookieParser = require('cookie-parser')
bodyParser = require("body-parser")

#### Basic application initialization
# Create app instance.
app = express()

# Define Port & Environment
app.port = process.env.PORT or process.env.VMC_APP_PORT or 3000
env = process.env.NODE_ENV or "development"

# Config module exports has `setEnvironment` function that sets app settings depending on environment.
config = require "./config"
config.setEnvironment env

# db_config = "mongodb://#{config.DB_USER}:#{config.DB_PASS}@#{config.DB_HOST}:#{config.DB_PORT}/#{config.DB_NAME}"
# mongoose.connect db_config
if env != 'production'
  mongoose.connect 'mongodb://localhost/example'
else
  console.log('If you are running in production, you may want to modify the mongoose connect path')

#### View initialization 
# Add Connect Assets.
app.use assets()
# Set the public folder as static assets.
app.use express.static(process.cwd() + '/public')
# app.use express.static(path.join(process.env.PWD, 'public'))
# process.env.PWD = process.cwd()
# app.use(express.static(process.env.PWD + '/public'));
# app.use( '/public/forms', express.static(__dirname + '/public/forms') );

app.use (req, res, next) ->
	res.header 'Access-Control-Allow-Origin', '*'
	res.header 'Access-Control-Allow-Headers', 'Origin, X-Requested-With, X-File-Name, Content-Type, Accept, Cache-Control, lifecycle-api-key'
	res.header 'Access-Control-Allow-Methods', 'PUT, POST, GET, OPTIONS'
	next()

# Express Session
console.log "setting session/cookie"
app.use cookieParser()
app.use session(
  secret: "keyboard cat"
  key: "sid"
  cookie:
    secure: true
)

# Set View Engine.
app.set 'view engine', 'jade'

# [Body parser middleware](http://www.senchalabs.org/connect/middleware-bodyParser.html) parses JSON or XML bodies into `req.body` object
app.use bodyParser()


#### Finalization
# Initialize routes
routes = require './routes'
routes(app)

if !process.env.STRIPE_API_KEY or !process.env.MANDRILL_API_KEY or !process.env.LOB_API_KEY or !process.env.XOLA_API_KEY
  console.log "/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\"
  console.log "/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\"
  console.log "/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\"
  console.log "All environment variables are not set!!"
  console.log "/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\"
  console.log "/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\"
  console.log "/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\/\\"
else
  console.log "all environment variables are good to go!"


# Export application object
module.exports = app

