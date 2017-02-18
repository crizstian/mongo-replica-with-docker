admin = db.getSiblingDB("admin")

admin.grantRolesToUser( "cristian", [ "root" , { role: "root", db: "admin" } ] )
