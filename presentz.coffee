express = require "express"
routes = require "./routes"
orient = require "orientdb"

server = new orient.Server
  host: "localhost"
  port: 2424

db = new orient.Db "presentz", server,
  user_name: "admin"
  user_password: "admin"

db.open ->
  console.log("DB connection open")

app = express.createServer()

config = require "./config.#{app.settings.env}"
everyauth = require "everyauth"

everyauth.everymodule.findUserById (userId, callback) ->
  db.loadRecord userId, callback

everyauth.facebook.appId(config.auth.facebook.app_id).appSecret(config.auth.facebook.app_secret).findOrCreateUser(
  (session, accessToken, accessTokenExtra, fb_user) ->
    promise = @Promise()

    db.command "SELECT FROM User where email = '#{fb_user.email}'", (err, results) ->
      if results.length isnt 0
        promise.fulfill
          id: results[0]["@rid"]
      else
        create_or_update_user session, fb_user, merge_facebook_user_data, promise

    return promise
).redirectPath("/")
everyauth.facebook.scope("email")

everyauth.twitter.consumerKey(config.auth.twitter.consumer_key).consumerSecret(config.auth.twitter.consumer_secret).findOrCreateUser(
  (session, accessToken, accessSecret, twitter_user) ->
    promise = @Promise()

    db.command "SELECT @rid FROM User where twitter_id = '#{twitter_user.id}'", (err, results) ->
      if results.length isnt 0
        promise.fulfill
          id: results[0].rid
      else
        create_or_update_user session, twitter_user, merge_twitter_user_data, promise

    return promise
).redirectPath("/")

merge_facebook_user_data = (user, fb_user) ->
  user.name ?= fb_user.name
  user.email ?= fb_user.email
  user.link ?= fb_user.link

merge_twitter_user_data = (user, twitter_user) ->
  user.name ?= twitter_user.name || twitter_user.screen_name
  user.twitter_id ?= twitter_user.id
  user.link ?= "https://twitter.com/#{twitter_user.screen_name}"

create_or_update_user = (session, user_data, merge, promise) ->
  save = (doc) ->
    db.save doc, (err, document) ->
      promise.fail(err) if err?
      promise.fulfill
        id: document["@rid"]

  if session.auth? && session.auth.userId?
    db.loadRecord session.auth.userId, (err, user) ->
      merge user, user_data
      save user
  else
    user =
      "@class": "User"
    merge user, user_data
    save user

app.configure ->
  app.set "views", "#{__dirname}/views"
  app.set "view engine", "jade"
  app.use express.logger()
  app.use express.bodyParser()
  app.use express.cookieParser()
  app.use express.session
    secret: config.presentz.session_secret
  app.use express.methodOverride()
  #  app.use routes.catalog_name_by_third_domain()
  app.use everyauth.middleware()
  app.use app.router
  app.use express.static "#{__dirname}/public"
  app.use routes.redirect_to "/"

app.configure "development", ->
  app.use express.errorHandler({ dumpExceptions: true, showStack: true })

app.configure "production", ->
  app.use express.errorHandler()

app.get "/", routes.static "index"
app.get "/r/index.html", routes.static "index"
app.get "/r/about.html", routes.static "about"
app.get "/r/tos.html", routes.static "tos"
app.get "/p.html", routes.redirect_to_presentation_from_p_html
app.get "/:catalog_name/p.html", routes.redirect_to_presentation_from_p_html
app.get "/:catalog_name/catalog.html", routes.show_catalog
app.get "/:catalog_name/catalog", routes.show_catalog
app.get "/:catalog_name/index.html", routes.show_catalog
app.get "/:catalog_name/:presentation.html", routes.redirect_to_presentation_from_html
app.get "/:catalog_name/:presentation.json", routes.raw_presentation
app.get "/:catalog_name/:presentation", routes.show_presentation
app.get "/:catalog_name", routes.show_catalog

everyauth.helpExpress(app)

app.listen 3000
console.log "Express server listening on port %d in %s mode", app.address().port, app.settings.env

subdomain = express.createServer()

subdomain.configure ->
  subdomain.use express.logger()
  subdomain.use express.methodOverride()
  subdomain.use routes.redirect_to_catalog_if_subdomain()
  subdomain.use routes.redirect_to "http://presentz.org/"

subdomain.configure "development", ->
  subdomain.use express.errorHandler({ dumpExceptions: true, showStack: true })

subdomain.configure "production", ->
  subdomain.use express.errorHandler()

subdomain.listen 3001
console.log "Express server listening on port %d in %s mode", subdomain.address().port, subdomain.settings.env 
