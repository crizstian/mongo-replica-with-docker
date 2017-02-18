function howManyServers {
  arg=''
  c=0
  for server in manager1 worker1 worker2
  do
      cmd='docker-machine ip '$server
      arg=$arg' --add-host '${server}':'$($cmd)
  done

  echo $arg
}

function switchToServer {
  env='docker-machine env '$1
  echo '···························'
  echo '·· swtiching >>>> '$1' server ··'
  echo '···························'
  eval $($env)
}

function startReplicaSet {
  # init replica set in mongodb master
  wait_for_databases $2 "$4"
  docker exec -i $1 bash -c 'mongo --eval "rs.initiate() && rs.conf()" --port '$p' -u $MONGO_SUPER_ADMIN -p $MONGO_PASS_SUPER --authenticationDatabase="admin"'
}

function createDockerVolume {
  cmd=$(docker volume ls -q | grep $1)
  if [[ "$cmd" == $1 ]];
  then
    echo 'volume available'
  else
    cmd='docker volume create --name '$1
    eval $cmd
  fi
}

function copyFilesToContainer {
  echo '·· copying files to container >>>> '$1' ··'

  # copy necessary files
  docker cp ./admin.js $1:/data/admin/
  docker cp ./replica.js $1:/data/admin/
  docker cp ./mongo-keyfile $1:/data/keyfile/
  docker cp ./grantRole.js $1:/data/admin
  docker cp ./movies.js $1:/data/admin
}

# @params container volume
function configMongoContainer {
  echo '·· configuring container >>>> '$1' ··'

  # check if volume exists
  createDockerVolume $2

  # start container
  docker run --name $1 -v $2:/data -d mongo --smallfiles

  # create the folders necessary for the container
  docker exec -i $1 bash -c 'mkdir /data/keyfile /data/admin'

  # copy the necessary files to the container
  copyFilesToContainer $1

  # change folder owner to the current container user
  docker exec -i $1 bash -c 'chown -R mongodb:mongodb /data'
}

# @params container volume
function removeAndCreateContainer {
  echo '·· removing container >>>> '$1' ··'

  # remove container
  docker rm -f $1

  env='./env'
  serv=$(howManyServers)
  keyfile='mongo-keyfile'
  port='27017:27017'
  p='27017'
  rs='rs1'

  echo '·· recreating container >>>> '$1' ··'

  #create container with sercurity and replica configuration
  docker run --restart=unless-stopped --name $1 --hostname $1 \
  -v $2:/data \
  --env-file $env \
  $serv \
  -p $port \
  -d mongo --smallfiles \
  --keyFile /data/keyfile/$keyfile \
  --replSet $rs \
  --storageEngine wiredTiger \
  --port $p
}

# @params server container volume
function createMongoDBNode {
  # switch to corresponding server
  switchToServer $1

  echo '·· creating container >>>> '$2' ··'

  # start configuration of the container
  configMongoContainer $2 $3

  sleep 2

  #create container with sercurity and replica configuration
  removeAndCreateContainer $2 $3

  # verify if container is ready
  wait_for_databases 'manager1'

  echo '·······························'
  echo '·  CONTAINER '$1' CREATED ··'
  echo '·······························'
}

function wait_for {
  echo ">>>>>>>>>>> waiting for mongodb"
  start_ts=$(date +%s)
  while :
  do
    (echo > /dev/tcp/$1/$2) >/dev/null 2>&1
    result=$?
    if [[ $result -eq 0 ]]; then
        end_ts=$(date +%s)
        echo "<<<<< $1:$2 is available after $((end_ts - start_ts)) seconds"
        sleep 3
        break
    fi
    sleep 5
  done
}

function wait_for_databases {
  if [[ ($1 == 'manager1') ]]; then
    ip=$(docker-machine ip manager1)
  elif [[ $1 == 'worker1' ]]; then
    ip=$(docker-machine ip worker1)
  elif [[ $1 == 'worker2' ]]; then
    ip=$(docker-machine ip worker2)
  fi
  # make tcp call
  echo "IP == $ip PORT == 27017"
  wait_for "$ip" 27017
}

function createKeyFile {
  openssl rand -base64 741 > $1
  chmod 600 $1
}

# @params server primary-mongo-container
function add_replicas {
  echo '·· adding replicas >>>> '$1' ··'

  switchToServer $1
  # add nuppdb replicas
  for server in worker1 worker2
  do
    rs="rs.add('$server:27017')"
    add='mongo --eval "'$rs'" -u $MONGO_REPLICA_ADMIN -p $MONGO_PASS_REPLICA --authenticationDatabase="admin"'
    sleep 2
    wait_for_databases $server
    docker exec -i $2 bash -c "$add"
  done
}

function init_replica_set {
  docker exec -i $1 bash -c 'mongo < /data/admin/replica.js'
  sleep 2
  docker exec -i $1 bash -c 'mongo < /data/admin/admin.js'
  cmd='mongo -u $MONGO_REPLICA_ADMIN -p $MONGO_PASS_REPLICA --eval "rs.status()" --authenticationDatabase "admin"'
  sleep 2
  docker exec -i mongoNode1 bash -c "$cmd"
}

function init_mongo_primary {
  # @params name-of-keyfile
  createKeyFile mongo-keyfile
  # @params server container volume
  createMongoDBNode manager1 mongoNode1 mongo_storage
  # @params container
  init_replica_set mongoNode1
  echo '·······························'
  echo '·  REPLICA SET READY TO ADD NODES ··'
  echo '·······························'
}

function init_mongo_secondaries {
  # @Params server container volume
  createMongoDBNode worker1 mongoNode2 mongo_storage
  createMongoDBNode worker2 mongoNode3 mongo_storage
}

# @params server primary-mongo-container
function check_status {
  switchToServer $1
  cmd='mongo -u $MONGO_REPLICA_ADMIN -p $MONGO_PASS_REPLICA --eval "rs.status()" --authenticationDatabase "admin"'
  docker exec -i $2 bash -c "$cmd"
}

function add_moviesdb_test {
  docker exec -i mongoNode1 bash -c 'mongo -u $MONGO_USER_ADMIN -p $MONGO_PASS_ADMIN --authenticationDatabase "admin" < /data/admin/grantRole.js'
  sleep 1
  docker exec -i mongoNode1 bash -c 'mongo -u $MONGO_USER_ADMIN -p $MONGO_PASS_ADMIN --authenticationDatabase "admin" < /data/admin/movies.js'
}

function main {
  init_mongo_primary
  init_mongo_secondaries
  add_replicas manager1 mongoNode1
  check_status manager1 mongoNode1
  add_moviesdb_test
}

main
