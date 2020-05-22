import asyncdispatch
import db_postgres
import jester
import json
import os
import sequtils
import strutils

import ws, ws/jester_extra

import ./db
import ./deprecations
import ./logs
import ./misc
import ./models/person
import ./models/status
import ./views/index
import ./statics

let db_open = open_pg

let settings = newSettings()
if existsEnv("PORT"):
  settings.port = Port(parseInt(getEnv("PORT")))

logs.setupWeb()

info "version:  ", pkgVersion
info "revision: ", pkgRevision

var websockets : seq[WebSocket] = @[]

proc wsRefresh(): Future[void] {.async.} =
  # TODO: Also clean up Closed ones
  for ws in websockets:
    if ws.readyState == Open:
      await ws.send "REFRESH"

proc updateStatus(person: Person) =
  let query = sql dedent """
    UPDATE people
    SET is_on_call = $1
    WHERE name = $2;"""
  db_open.use conn:
    debug query.string
    let prepared = conn.prepare("update_status", query, 2)
    conn.exec prepared, $person.isOnCall(), person.name

proc nameExists(name: string): bool =
  let query = sql dedent """
    SELECT name
    FROM people
    WHERE name = $1
    LIMIT 1;"""
  db_open.use conn:
    debug query.string
    let prepared = conn.prepare("check_name", query, 1)
    conn.getValue(prepared, name) == name

proc getPeople(): seq[Person] =
  let query = sql dedent """
    SELECT
      name
    , is_on_call
    FROM people
    WHERE name IN ($1, $2)
    ORDER BY name;"""
  let rows = db_open.use conn:
    debug query.string
    let prepared = conn.prepare("get_people", query, 2)
    conn.getAllrows prepared, "D", "N"

  rows.map fromPgRow

router api:
  # DEPRECATED
  get "/status":
    deprecations.ApiStatusEndpoints.check(supported, logProc):
      logProc()
      if not supported: halt Http404

    redirect "/api/people"

  get "/people": resp %*getPeople()

  # DEPRECATED
  post "/status":
    deprecations.ApiStatusEndpoints.check(supported, logProc):
      logProc()
      if not supported: halt Http404

    let jsonNode = parseJson request.body
    debug jsonNode
    updateStatus person.fromJson(jsonNode)
    discard wsRefresh()
    resp Http204

  put "/person/@name":
    let rawName: TaintedString = @"name"
    if not nameExists(rawName.string): halt Http404

    let jsonNode = parseJson request.body
    debug jsonNode

    let person = person.fromJson jsonNode
    if not(person.name == rawName.string): halt Http422

    updateStatus person
    discard wsRefresh()
    resp Http204

router web:
  get "/":
    let forms = getPeople().map(renderPerson)
    resp renderIndex(forms[0], forms[1])

  get "/ws":
    let ws = await newWebSocket(request)
    websockets.add ws
    discard ws.send("Hello from Websocket server")
    resp Http101

  # I'd like for this to be PUT, but browser forms are GET and POST only
  post "/person/@name":
    let status = status.fromIsOnCall parseBool(request.params["is_on_call"])
    let person = Person(name: @"name", status: status)
    updateStatus person
    discard wsRefresh()
    redirect "/"

routes:
  extend web, ""
  extend api, "/api"

runForever()
