#!/bin/bash

MANAGER_NUM=1
WORKER_NUM=3
MACHINE_NAME_PREFIX="node"


SWARM_MANAGER_TOKEN=""
SWARM_WORKER_TOKEN=""
SWARM_JOIN_ADDRESS=""

RUNNING_TASKS=""

NFS_SERVER_IP="192.168.99.1"
HOST_DATA_PATH=${HOME}/data
GUEST_DATA_PATH=/data

syncTasks() {
  echo "Waiting for pids ${RUNNING_TASKS}"

  for PID in ${RUNNING_TASKS}
  do
    if wait $PID; then
      echo "Process ${PID} ended successfuly"
    else
      echo "Process ${PID} failed"
    fi
  done

  RUNNING_TASKS=""
}

createMachines() {
  for MACHINE_ID in $(seq 1 "${1}")
  do
    MACHINE_NAME="${MACHINE_NAME_PREFIX}-${MACHINE_ID}"
    ( docker-machine create ${MACHINE_NAME} --engine-opt dns=8.8.8.8 --virtualbox-no-share)&
    RUNNING_TASKS+=" $!"
  done

  syncTasks
}

initManagers() {
  echo "Init managers for node-1 to node-${1}"
  for MANAGER_ID in $(seq 1 "${1}")
  do
    MACHINE_NAME="${MACHINE_NAME_PREFIX}-${MANAGER_ID}"
    eval "$(docker-machine env ${MACHINE_NAME})"

    if [ "${MANAGER_ID}" -eq 1 ]
    then
      docker swarm init --advertise-addr=eth1
      SWARM_JOIN_ADDRESS="$(docker swarm join-token manager | grep 2377 | awk '{print $1}')"
      SWARM_MANAGER_TOKEN="$(docker swarm join-token manager -q)"
      SWARM_WORKER_TOKEN="$(docker swarm join-token worker -q)"
      export SWARM_MANAGER_TOKEN SWARM_WORKER_TOKEN SWARM_JOIN_ADDRESS
    else
      docker swarm join --token "${SWARM_MANAGER_TOKEN}" "${SWARM_JOIN_ADDRESS}"
    fi
  done
}

initWorkers() {
  echo "Init workers for node-${1} to node-${2}"

  for WORKER_ID in $(seq "${1}" "${2}")
  do
    MACHINE_NAME="${MACHINE_NAME_PREFIX}-${WORKER_ID}"
    docker-machine ssh ${MACHINE_NAME} "docker swarm join --token ${SWARM_WORKER_TOKEN} ${SWARM_JOIN_ADDRESS}"
  done
}

startCluster() {
  echo "Starting cluster"

  for MACHINE_ID in $(seq 1 "${1}")
  do
    MACHINE_NAME="${MACHINE_NAME_PREFIX}-${MACHINE_ID}"

    (docker-machine start ${MACHINE_NAME})&

    RUNNING_TASKS+=" $!"
  done

  syncTasks
}

stopCluster() {
  echo "Stopping cluster"
  for MACHINE_ID in $(seq 1 "${1}")
  do
    MACHINE_NAME="${MACHINE_NAME_PREFIX}-${MACHINE_ID}"

    (docker-machine stop ${MACHINE_NAME})&

    RUNNING_TASKS+=" $!"
  done

  syncTasks
}

cleanupCluster() {
  for MACHINE_ID in $(seq 1 "${1}")
  do
    MACHINE_NAME="${MACHINE_NAME_PREFIX}-${MACHINE_ID}"

    (docker-machine rm -y ${MACHINE_NAME})&

    RUNNING_TASKS+=" $!"
  done

  syncTasks
}

mountNFS() {
  echo "Mounting NFS share from machine ${MACHINE_NAME_PREFIX}-${1} to ${MACHINE_NAME_PREFIX}-${2}"
  for MACHINE_ID in $(seq "${1}" "${2}")
  do
    MACHINE_NAME="${MACHINE_NAME_PREFIX}-${MACHINE_ID}"
    docker-machine ssh ${MACHINE_NAME} "sudo mkdir -p ${GUEST_DATA_PATH} && \
      sudo /usr/local/etc/init.d/nfs-client start && \
      sudo mount ${NFS_SERVER_IP}:${HOST_DATA_PATH} ${GUEST_DATA_PATH} -o rw,async,noatime,rsize=32768,wsize=32768,proto=tcp"
  done
}

umountNFS() {
  echo "Unmounting NFS share from machine ${MACHINE_NAME_PREFIX}-${1} to ${MACHINE_NAME_PREFIX}-${2}"
  for MACHINE_ID in $(seq "${1}" "${2}")
  do
    MACHINE_NAME="${MACHINE_NAME_PREFIX}-${MACHINE_ID}"
    docker-machine ssh ${MACHINE_NAME} "sudo umount ${GUEST_DATA_PATH}"
  done

}

startNFS() {
  echo "Starting NFS Server..."
  sudo systemctl start nfs-server
}

stopNFS() {
  echo "Stopping NFS Server..."
  sudo systemctl stop nfs-server
}

printSummary() {
    docker-machine ls
    eval "$(docker-machine env ${MACHINE_NAME_PREFIX}-1)"
    docker node ls
}

TOTAL_MACHINES=`expr ${MANAGER_NUM} + ${WORKER_NUM}`

case $1 in
  init)
    startNFS
    createMachines ${TOTAL_MACHINES}
    initManagers ${MANAGER_NUM}
    initWorkers `expr ${MANAGER_NUM} + 1` ${TOTAL_MACHINES}

    mountNFS `expr ${MANAGER_NUM} + 1` ${TOTAL_MACHINES}

    printSummary
  ;;
  start)
    startNFS
    startCluster ${TOTAL_MACHINES}

    mountNFS `expr ${MANAGER_NUM} + 1` ${TOTAL_MACHINES}
  ;;
  remount)
    umountNFS `expr ${MANAGER_NUM} + 1` ${TOTAL_MACHINES}
    mountNFS `expr ${MANAGER_NUM} + 1` ${TOTAL_MACHINES}
  ;;
  stop)
    umountNFS `expr ${MANAGER_NUM} + 1` ${TOTAL_MACHINES}
    stopCluster ${TOTAL_MACHINES}
    stopNFS
  ;;
  clean)
    umountNFS `expr ${MANAGER_NUM} + 1` ${TOTAL_MACHINES}
    stopCluster ${TOTAL_MACHINES}
    cleanupCluster ${TOTAL_MACHINES}
    stopNFS
  ;;
  **)
    echo "Usage: ./swarm.sh [init|start|remount|stop|clean]"
  ;;
esac
