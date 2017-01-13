admin = db.getSiblingDB("admin")
admin.createUser(
  {
    user: "cristian",
    pwd: "cristianPassword2017",
    roles: [ { role: "userAdminAnyDatabase", db: "admin" } ]
  }
)

db.getSiblingDB("admin").auth("cristian", "cristianPassword2017" )

db.getSiblingDB("admin").createUser(
  {
    "user" : "replicaAdmin",
    "pwd" : "replicaAdminPassword2017",
    roles: [ { "role" : "clusterAdmin", "db" : "admin" } ]
  }
)
