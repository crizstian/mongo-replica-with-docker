function switchToServer {
  env='docker-machine env '$1
  echo '···························'
  echo '·· swtiching >>>> '$1' server ··'
  echo '···························'
  eval $($env)
}

function removeContainer {
  switchToServer $1
  docker rm -f $2
  docker volume rm $(docker volume ls -qf dangling=true)
}

removeContainer manager1 mongoNode1
removeContainer worker1 mongoNode2
removeContainer worker2 mongoNode3
